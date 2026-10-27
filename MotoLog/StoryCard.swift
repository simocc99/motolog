import SwiftUI
import CoreLocation
import MapKit
import Network

/// Mappa scaricata da Apple Maps con il percorso già proiettato sui pixel della storia (360×640).
struct MapBackdrop {
    let image: UIImage
    let points: [CGPoint]
}

enum StoryMap {
    static func online() async -> Bool {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            var done = false
            monitor.pathUpdateHandler = { path in
                guard !done else { return }
                done = true
                monitor.cancel()
                cont.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "motolog.net"))
        }
    }

    /// nil se offline o se la mappa non si riesce a scaricare: la storia usa allora lo sfondo scuro.
    static func backdrop(for ride: Ride) async -> MapBackdrop? {
        guard ride.points.count > 1 else { return nil }
        if let hit = cached(ride) { return hit }
        guard await online() else { return nil }
        let coords = ride.points.map(\.coordinate)
        let mp = coords.map { MKMapPoint($0) }
        guard let minX = mp.map(\.x).min(), let maxX = mp.map(\.x).max(),
              let minY = mp.map(\.y).min(), let maxY = mp.map(\.y).max() else { return nil }

        // Il percorso deve occupare la fascia centrale dell'immagine (x 40…320, y 130…400).
        let minExtent = 400 * MKMapPointsPerMeterAtLatitude(coords[0].latitude)
        let s = max((maxX - minX) / 280, (maxY - minY) / 235, minExtent / 280)
        let rect = MKMapRect(x: (minX + maxX) / 2 - 180 * s,
                             y: (minY + maxY) / 2 - 250 * s,
                             width: 360 * s, height: 640 * s)

        let o = MKMapSnapshotter.Options()
        o.mapRect = rect
        o.size = CGSize(width: 360, height: 640)
        o.scale = 3
        o.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        o.pointOfInterestFilter = .excludingAll
        o.showsBuildings = false

        guard let snap = try? await MKMapSnapshotter(options: o).start() else { return nil }
        let step = max(1, coords.count / 200)
        var idx = Array(stride(from: 0, to: coords.count, by: step))
        if idx.last != coords.count - 1 { idx.append(coords.count - 1) }
        let backdrop = MapBackdrop(image: snap.image, points: idx.map { snap.point(for: coords[$0]) })
        store(backdrop, for: ride)
        return backdrop
    }

    // Cache su disco: la mappa di un giro non cambia, quindi si scarica una volta sola e poi vale anche offline.
    private static func cacheURL(_ ride: Ride, _ ext: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("story-\(ride.id.uuidString).\(ext)")
    }

    private static func cached(_ ride: Ride) -> MapBackdrop? {
        guard let img = UIImage(contentsOfFile: cacheURL(ride, "png").path),
              let data = try? Data(contentsOf: cacheURL(ride, "json")),
              let pts = try? JSONDecoder().decode([[Double]].self, from: data) else { return nil }
        return MapBackdrop(image: img, points: pts.map { CGPoint(x: $0[0], y: $0[1]) })
    }

    private static func store(_ b: MapBackdrop, for ride: Ride) {
        try? b.image.pngData()?.write(to: cacheURL(ride, "png"), options: .atomic)
        try? JSONEncoder().encode(b.points.map { [Double($0.x), Double($0.y)] }).write(to: cacheURL(ride, "json"), options: .atomic)
    }
}

struct PointsShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (i, p) in points.enumerated() {
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

/// Immagine 9:16 (1080×1920 a scala 3) pronta per le storie di Instagram.
struct StoryCard: View {
    let ride: Ride
    let bikeName: String?
    var backdrop: MapBackdrop? = nil

    private var route: [CLLocationCoordinate2D] {
        let step = max(1, ride.points.count / 160)
        return stride(from: 0, to: ride.points.count, by: step).map { ride.points[$0].coordinate }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.high")
                    Text("MOTOLOG").tracking(5)
                }
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(backdrop == nil ? Theme.dim : .white.opacity(0.8))
                .padding(.top, 34)

                VStack(spacing: 4) {
                    Text(ride.name)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(ride.start.shortDate)" + (bikeName.map { " · \($0)" } ?? ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.top, 22)

                if backdrop == nil {
                    ZStack {
                        RouteShape(pts: route)
                            .stroke(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                            .blur(radius: 9)
                        RouteShape(pts: route)
                            .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .frame(height: 270)
                } else {
                    Color.clear.frame(height: 270)   // il percorso è disegnato sopra la mappa
                }

                VStack(spacing: -4) {
                    Text(Fmt.distText(ride.distance))
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.gradient)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(Fmt.distUnit.uppercased())
                        .font(.system(size: 14, weight: .bold)).tracking(4)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.top, 4)

                Spacer(minLength: 12)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    cell("Durata", Fmt.duration(ride.elapsed), "")
                    cell("Media", Fmt.speedText(ride.avgSpeed), Fmt.speedUnit)
                    cell("Massima", Fmt.speedText(ride.maxSpeed), Fmt.speedUnit)
                    cell("Piega max", String(format: "%.0f", ride.maxLean), "°")
                    cell("Dislivello", Fmt.altText(ride.elevationGain), Fmt.altUnit)
                    cell("G max", String(format: "%.1f", ride.maxG), "G")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 360, height: 640)
    }

    @ViewBuilder
    private var background: some View {
        if let b = backdrop {
            Image(uiImage: b.image)
                .resizable()
                .frame(width: 360, height: 640)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.88), location: 0),
                .init(color: .black.opacity(0.55), location: 0.26),
                .init(color: .black.opacity(0.05), location: 0.38),
                .init(color: .black.opacity(0.05), location: 0.52),
                .init(color: .black.opacity(0.88), location: 0.64),
                .init(color: .black.opacity(0.96), location: 0.80)
            ], startPoint: .top, endPoint: .bottom)
            ZStack {
                PointsShape(points: b.points)
                    .stroke(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                    .blur(radius: 8)
                PointsShape(points: b.points)
                    .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                if let first = b.points.first {
                    Circle().fill(Color.green).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(first)
                }
                if let last = b.points.last {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(last)
                }
            }
            .frame(width: 360, height: 640)
        } else {
            Theme.storyBg
            RadialGradient(colors: [Theme.accent.opacity(0.38), .clear], center: .top, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Theme.accent2.opacity(0.18), .clear], center: .bottom, startRadius: 10, endRadius: 420)
        }
    }

    private func cell(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)) }
            }
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(backdrop == nil ? Color.white.opacity(0.07) : Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Genera l'immagine finale 1080×1920.
    @MainActor
    static func render(ride: Ride, bikeName: String?, backdrop: MapBackdrop?) -> UIImage? {
        let renderer = ImageRenderer(content: StoryCard(ride: ride, bikeName: bikeName, backdrop: backdrop)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        return renderer.uiImage
    }
}

struct StoryItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct StoryPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.3), radius: 20)
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("Storia MotoLog", image: Image(uiImage: image))) {
                    Label("Condividi storia", systemImage: "square.and.arrow.up")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.gradient, in: Capsule())
                }
                Text("Scegli Instagram › Storie dal menu. Da lì puoi metterla sopra una tua foto.")
                    .font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }
            .padding(20)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Chiudi") { dismiss() } }
            }
        }
    }
}
