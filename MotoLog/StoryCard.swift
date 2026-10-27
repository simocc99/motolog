import SwiftUI
import CoreLocation

/// Immagine 9:16 (1080×1920 a scala 3) pronta per le storie di Instagram.
struct StoryCard: View {
    let ride: Ride
    let bikeName: String?

    private var route: [CLLocationCoordinate2D] {
        let step = max(1, ride.points.count / 160)
        return stride(from: 0, to: ride.points.count, by: step).map { ride.points[$0].coordinate }
    }

    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.accent.opacity(0.38), .clear], center: .top, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Theme.accent2.opacity(0.18), .clear], center: .bottom, startRadius: 10, endRadius: 420)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.high")
                    Text("MOTOLOG").tracking(5)
                }
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.dim)
                .padding(.top, 34)

                VStack(spacing: 4) {
                    Text(ride.name)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(ride.start.shortDate)" + (bikeName.map { " · \($0)" } ?? ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.top, 22)

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

                VStack(spacing: -4) {
                    Text(Fmt.distText(ride.distance))
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.gradient)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(Fmt.distUnit.uppercased())
                        .font(.system(size: 14, weight: .bold)).tracking(4)
                        .foregroundStyle(Theme.dim)
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

    private func cell(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.system(size: 10)).foregroundStyle(Theme.dim) }
            }
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Genera l'immagine finale 1080×1920.
    @MainActor
    static func render(ride: Ride, bikeName: String?) -> UIImage? {
        let renderer = ImageRenderer(content: StoryCard(ride: ride, bikeName: bikeName))
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
