import SwiftUI
import UIKit
import Vision
import CoreImage

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
            IconBadge(icon: "scooter", size: size)
        }
    }
}

// MARK: Autonomia

extension DataStore {
    /// Km percorribili con un pieno (serve serbatoio e almeno due rifornimenti).
    func autonomy(for bike: Bike) -> Double? {
        guard let tank = bike.tankLiters, tank > 0, let c = consumption(for: bike), c > 0 else { return nil }
        return tank / c * 100
    }

    /// Km stimati prima di restare a secco, contando anche il giro in corso.
    func remainingRange(for bike: Bike, extraKm: Double = 0) -> Double? {
        guard let full = autonomy(for: bike),
              let last = fuel.filter({ $0.bikeID == bike.id }).max(by: { $0.date < $1.date }) else { return nil }
        let since = max(0, odometer(of: bike) + extraKm - last.odometerKm)
        return full - since
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
