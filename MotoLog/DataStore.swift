import Foundation
import UserNotifications

final class DataStore: ObservableObject {
    @Published var rides: [Ride] = [] { didSet { save(rides, "rides") } }
    @Published var bikes: [Bike] = [] { didSet { save(bikes, "bikes") } }
    @Published var maintenance: [MaintenanceItem] = [] { didSet { save(maintenance, "maintenance") } }
    @Published var fuel: [FuelEntry] = [] { didSet { save(fuel, "fuel") } }
    @Published var deadlines: [Deadline] = [] { didSet { save(deadlines, "deadlines") } }
    @Published var draft: Ride?

    private let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let queue = DispatchQueue(label: "motolog.store", qos: .utility)
    private var pending: [String: DispatchWorkItem] = [:]

    init() {
        rides = load("rides") ?? []
        bikes = load("bikes") ?? []
        maintenance = load("maintenance") ?? []
        fuel = load("fuel") ?? []
        deadlines = load("deadlines") ?? []
        draft = load("draft")
        rides.sort { $0.start > $1.start }
        // Una bozza di un giro già salvato non va riproposta.
        if let d = draft, rides.contains(where: { $0.start == d.start }) { saveDraft(nil) }
    }

    // MARK: Persistenza

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name + ".json") }

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        pending[name]?.cancel()
        let target = url(name)
        let item = DispatchWorkItem {
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            if let data = try? e.encode(value) {
                try? data.write(to: target, options: .atomic)
            }
        }
        pending[name] = item
        queue.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func saveDraft(_ ride: Ride?) {
        draft = ride
        if let ride {
            save(ride, "draft")
        } else {
            pending["draft"]?.cancel()
            let target = url("draft")
            queue.async { try? FileManager.default.removeItem(at: target) }
        }
    }

    func resetAll() {
        rides = []; bikes = []; maintenance = []; fuel = []; deadlines = []
        saveDraft(nil)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: Utilità

    func bike(_ id: UUID?) -> Bike? { bikes.first { $0.id == id } }

    func odometer(of bike: Bike) -> Double {
        bike.initialKm + rides.filter { $0.bikeID == bike.id }.reduce(0) { $0 + $1.distance } / 1000
    }

    func addRide(_ ride: Ride) {
        rides.append(ride)
        rides.sort { $0.start > $1.start }
    }

    func deleteBike(_ bike: Bike) {
        for i in rides.indices where rides[i].bikeID == bike.id { rides[i].bikeID = nil }
        maintenance.removeAll { $0.bikeID == bike.id }
        fuel.removeAll { $0.bikeID == bike.id }
        deadlines.filter { $0.bikeID == bike.id }.forEach { Notifier.cancel($0) }
        deadlines.removeAll { $0.bikeID == bike.id }
        bikes.removeAll { $0.id == bike.id }
        BikePhotos.delete(bike.id)
    }

    /// Consumo medio in L/100km tra i pieni registrati (nil se dati insufficienti).
    func consumption(for bike: Bike) -> Double? {
        let entries = fuel.filter { $0.bikeID == bike.id && $0.isFull != false }.sorted { $0.odometerKm < $1.odometerKm }
        guard entries.count >= 2, let first = entries.first, let last = entries.last else { return nil }
        let km = last.odometerKm - first.odometerKm
        guard km > 0 else { return nil }
        let liters = entries.dropFirst().reduce(0) { $0 + $1.liters }
        return liters / km * 100
    }
}

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule(_ deadline: Deadline) {
        requestAuthorization()
        cancel(deadline)
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        let offsets = [(7, "tra 7 giorni"), (0, "oggi")]
        for (days, label) in offsets {
            guard let day = cal.date(byAdding: .day, value: -days, to: deadline.date) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 9
            guard let fire = cal.date(from: comps), fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Scadenza moto"
            content.body = "\(deadline.title): \(label)"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(deadline.id.uuidString)-\(days)", content: content, trigger: trigger))
        }
    }

    static func cancel(_ deadline: Deadline) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["\(deadline.id.uuidString)-7", "\(deadline.id.uuidString)-0"])
    }
}
