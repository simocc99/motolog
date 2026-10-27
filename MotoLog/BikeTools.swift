import SwiftUI
import UIKit
import Vision
import CoreImage
import CoreLocation

// MARK: Foto della moto

enum BikePhotos {
    private static let cache = NSCache<NSString, UIImage>()

    private static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bikes", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func url(_ id: UUID) -> URL { dir.appendingPathComponent(id.uuidString + ".png") }

    static func image(for bike: Bike) -> UIImage? {
        guard bike.hasPhoto == true else { return nil }
        let key = "\(bike.id.uuidString)-\(bike.photoRev ?? 0)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = UIImage(contentsOfFile: url(bike.id).path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    static func save(_ image: UIImage, for id: UUID) {
        try? image.pngData()?.write(to: url(id), options: .atomic)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
    }
}

enum Cutout {
    /// Ridimensiona e raddrizza la foto (EXIF) prima dell'analisi.
    static func normalized(_ image: UIImage, maxSide: CGFloat = 1400) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let k = min(1, maxSide / longest)
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Isola il soggetto principale con Vision (iOS 17). nil se il dispositivo non riesce.
    static func subject(of image: UIImage) async -> UIImage? {
        let source = normalized(image)
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let cg = source.cgImage else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg)
            do {
                try handler.perform([request])
                guard let obs = request.results?.first, !obs.allInstances.isEmpty else { return nil }
                let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
                let ci = CIImage(cvPixelBuffer: buffer)
                guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
                return UIImage(cgImage: out)
            } catch {
                return nil
            }
        }.value
    }
}

/// Foto ritagliata della moto, oppure l'icona se non c'è.
struct BikeThumb: View {
    let bike: Bike
    var size: CGFloat = 52

    var body: some View {
        if let img = BikePhotos.image(for: bike) {
            Image(uiImage: img)
                .resizable().scaledToFit()
                .frame(width: size * 1.5, height: size)
        } else {
            IconBadge(icon: Theme.bikeSymbol, size: size)
        }
    }
}

// MARK: Autonomia

struct FuelState {
    let liters: Double
    let range: Double
    let tank: Double
    let learned: Bool   // false = consumo non ancora noto, uso un valore standard
    var low: Bool { liters < tank * 0.2 }
}

extension Theme {
    /// SF Symbol "motorcycle" esiste solo dalle versioni recenti di iOS.
    static var bikeSymbol: String { UIImage(systemName: "motorcycle") != nil ? "motorcycle" : "bicycle" }
}

extension DataStore {
    /// Km percorribili con un pieno (serve serbatoio e almeno due rifornimenti).
    func autonomy(for bike: Bike) -> Double? {
        guard let tank = bike.tankLiters, tank > 0, let c = consumption(for: bike), c > 0 else { return nil }
        return tank / c * 100
    }

    /// Benzina stimata nel serbatoio e km rimasti.
    /// Parte dall'ultimo pieno, toglie il consumo dei km fatti (più alto oltre i ~80 km/h) e somma i rifornimenti parziali.
    func fuelState(for bike: Bike, live: [TrackPoint] = []) -> FuelState? {
        guard let tank = bike.tankLiters, tank > 0 else { return nil }
        let learned = consumption(for: bike)
        let cons = learned ?? 5.5
        var level: Double?
        var last: Date?
        for e in fuel.filter({ $0.bikeID == bike.id }).sorted(by: { $0.date < $1.date }) {
            if let l = level, let ld = last {
                level = max(0, l - usedKm(bike.id, from: ld, to: e.date, live: []) * cons / 100)
            }
            if e.isFull != false { level = tank } else if let l = level { level = min(tank, l + e.liters) }
            last = e.date
        }
        guard let l0 = level, let ld = last else { return nil }
        let liters = max(0, l0 - usedKm(bike.id, from: ld, to: Date(), live: live) * cons / 100)
        return FuelState(liters: liters, range: liters / cons * 100, tank: tank, learned: learned != nil)
    }

    func remainingRange(for bike: Bike) -> Double? { fuelState(for: bike)?.range }

    /// Consumo "pesato": i km veloci contano di più, quelli lenti di meno.
    private static func speedFactor(_ ms: Double) -> Double {
        min(max(1 + 0.004 * (ms * 3.6 - 80), 0.85), 1.5)
    }

    private func weightedKm(_ points: [TrackPoint], from: Date, to: Date) -> Double {
        guard points.count > 1 else { return 0 }
        var sum = 0.0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            guard b.time > from, b.time <= to else { continue }
            let gap = b.time.timeIntervalSince(a.time)
            let d = CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
            guard gap > 0, d / gap < 120 else { continue }
            sum += d / 1000 * Self.speedFactor((a.speed + b.speed) / 2)
        }
        return sum
    }

    private func usedKm(_ id: UUID, from: Date, to: Date, live: [TrackPoint]) -> Double {
        rides.filter { $0.bikeID == id && $0.end > from && $0.start < to }
            .reduce(0) { $0 + weightedKm($1.points, from: from, to: to) } + weightedKm(live, from: from, to: to)
    }

    /// Velocità media in movimento sui tuoi giri con questa moto (nil se meno di 3 giri utili).
    func typicalSpeed(bikeID: UUID?) -> Double? {
        let pool = rides.filter { $0.distance > 2000 && $0.movingTime > 0 && (bikeID == nil || $0.bikeID == bikeID) }
        guard pool.count >= 3 else { return nil }
        return pool.reduce(0) { $0 + $1.distance } / pool.reduce(0) { $0 + $1.movingTime }
    }

    func deletePhoto(of bike: Bike) {
        BikePhotos.delete(bike.id)
        if let i = bikes.firstIndex(where: { $0.id == bike.id }) { bikes[i].hasPhoto = false }
    }
}
