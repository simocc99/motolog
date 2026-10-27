import Foundation

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let progress: Double     // 0...1
    var unlocked: Bool { progress >= 1 }
}

/// Livello del motociclista in base ai chilometri totali.
struct RiderLevel {
    let name: String
    let progress: Double      // 0...1 verso il livello successivo
    let next: String?
    let nextKm: Double?

    static let tiers: [(name: String, km: Double)] = [
        ("Novizio", 0), ("Apprendista", 100), ("Biker", 500),
        ("Motociclista", 1500), ("Veterano", 5000), ("Leggenda", 15000)
    ]

    static func level(forKm km: Double) -> RiderLevel {
        var idx = 0
        for (i, t) in tiers.enumerated() where km >= t.km { idx = i }
        guard idx + 1 < tiers.count else { return RiderLevel(name: tiers[idx].name, progress: 1, next: nil, nextKm: nil) }
        let lo = tiers[idx].km, hi = tiers[idx + 1].km
        return RiderLevel(name: tiers[idx].name, progress: (km - lo) / (hi - lo), next: tiers[idx + 1].name, nextKm: hi)
    }

    /// Settimane consecutive con almeno un giro (la settimana corrente conta se hai già guidato).
    static func weekStreak(_ rides: [Ride]) -> Int {
        let cal = Calendar.current
        let weeks = Set(rides.compactMap { cal.dateInterval(of: .weekOfYear, for: $0.start)?.start })
        guard var cursor = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        if !weeks.contains(cursor), let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) { cursor = prev }
        var n = 0
        while weeks.contains(cursor) {
            n += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }
}

enum Achievements {
    static func compute(_ rides: [Ride]) -> [Achievement] {
        let totalKm = rides.reduce(0) { $0 + $1.distance } / 1000
        let longestKm = (rides.map(\.distance).max() ?? 0) / 1000
        let topKmh = (rides.map(\.maxSpeed).max() ?? 0) * 3.6
        let lean = rides.map(\.maxLean).max() ?? 0
        let climb = rides.reduce(0) { $0 + $1.elevationGain }
        let hours = rides.reduce(0) { $0 + $1.elapsed } / 3600
        let night = rides.contains { r in
            let h = Calendar.current.component(.hour, from: r.start)
            return (h >= 22 || h < 5) && r.distance > 5000
        }
        let days = Set(rides.map { Calendar.current.startOfDay(for: $0.start) })

        func p(_ v: Double, _ goal: Double) -> Double { min(v / goal, 1) }

        return [
            Achievement(id: "first", title: "Prima uscita", detail: "Registra il tuo primo giro", icon: "flag.checkered", progress: p(Double(rides.count), 1)),
            Achievement(id: "rides10", title: "Habitué", detail: "10 giri registrati", icon: "repeat", progress: p(Double(rides.count), 10)),
            Achievement(id: "rides50", title: "Motociclista vero", detail: "50 giri registrati", icon: "star.fill", progress: p(Double(rides.count), 50)),
            Achievement(id: "km100", title: "Cento chilometri", detail: "100 km totali", icon: "road.lanes", progress: p(totalKm, 100)),
            Achievement(id: "km1000", title: "Mille e non più mille", detail: "1.000 km totali", icon: "map.fill", progress: p(totalKm, 1000)),
            Achievement(id: "km10000", title: "Giro del mondo (quasi)", detail: "10.000 km totali", icon: "globe.europe.africa.fill", progress: p(totalKm, 10000)),
            Achievement(id: "long100", title: "Gran fondista", detail: "100 km in un solo giro", icon: "arrow.triangle.swap", progress: p(longestKm, 100)),
            Achievement(id: "long300", title: "Iron Butt", detail: "300 km in un solo giro", icon: "bolt.fill", progress: p(longestKm, 300)),
            Achievement(id: "speed100", title: "Ritmo autostradale", detail: "Raggiungi 100 km/h", icon: "speedometer", progress: p(topKmh, 100)),
            Achievement(id: "speed150", title: "Velocista", detail: "Raggiungi 150 km/h", icon: "gauge.high", progress: p(topKmh, 150)),
            Achievement(id: "lean30", title: "Ginocchio a terra?", detail: "30° di piega", icon: "angle", progress: p(lean, 30)),
            Achievement(id: "lean45", title: "Piega estrema", detail: "45° di piega", icon: "rotate.right.fill", progress: p(lean, 45)),
            Achievement(id: "climb1000", title: "Cacciatore di passi", detail: "1.000 m di dislivello totale", icon: "mountain.2.fill", progress: p(climb, 1000)),
            Achievement(id: "climb10000", title: "Everest in moto", detail: "10.000 m di dislivello totale", icon: "mountain.2", progress: p(climb, 10000)),
            Achievement(id: "hours24", title: "Un giorno in sella", detail: "24 ore totali in moto", icon: "clock.fill", progress: p(hours, 24)),
            Achievement(id: "night", title: "Gufo notturno", detail: "Un giro dopo le 22", icon: "moon.stars.fill", progress: night ? 1 : 0),
            Achievement(id: "days10", title: "Costanza", detail: "Esci in 10 giorni diversi", icon: "calendar", progress: p(Double(days.count), 10)),
        ]
    }
}
