import SwiftUI
import CoreLocation

enum Theme {
    private static func dyn(_ dark: UIColor, _ light: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let bg = dyn(UIColor(red: 0.035, green: 0.035, blue: 0.05, alpha: 1), UIColor(red: 0.945, green: 0.945, blue: 0.965, alpha: 1))
    static let card = dyn(UIColor(red: 0.085, green: 0.085, blue: 0.11, alpha: 1), .white)
    static let stroke = dyn(UIColor(white: 1, alpha: 0.08), UIColor(white: 0, alpha: 0.07))
    static let dim = dyn(UIColor(white: 1, alpha: 0.55), UIColor(white: 0, alpha: 0.55))
    static let fill = dyn(UIColor(white: 1, alpha: 0.08), UIColor(white: 0, alpha: 0.06))
    static let accent = Color(red: 1.0, green: 0.56, blue: 0.08)
    static let accent2 = Color(red: 1.0, green: 0.30, blue: 0.22)
    /// Sfondo fisso scuro per l'immagine della storia (non dipende dal tema).
    static let storyBg = Color(red: 0.035, green: 0.035, blue: 0.05)

    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Sfondo con un leggero bagliore arancione in alto.
    static var background: some View {
        ZStack {
            bg
            RadialGradient(colors: [accent.opacity(0.16), .clear], center: .top, startRadius: 10, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

struct IconBadge: View {
    let icon: String
    var tint: Color = Theme.accent
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.dim

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var icon: String = ""
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 10) {
            if !icon.isEmpty { IconBadge(icon: icon, tint: tint) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if !unit.isEmpty {
                        Text(unit).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12)
    }
}

/// Tachimetro ad arco con gradiente verde → rosso.
struct SpeedGauge: View {
    let speed: Double   // m/s

    var body: some View {
        let top = Fmt.imperial ? 125.0 : 200.0
        let p = min(max(Fmt.speed(speed) / top, 0), 1)
        ZStack {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Theme.fill, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                Circle().trim(from: 0, to: 0.75)
                    .stroke(AngularGradient(colors: [.green, .yellow, .orange, .red],
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .mask(Circle().trim(from: 0, to: 0.75 * p)
                        .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round)))
            }
            .rotationEffect(.degrees(135))
            .animation(.easeOut(duration: 0.4), value: p)

            VStack(spacing: -2) {
                Text(Fmt.speedText(speed))
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(Fmt.speedUnit.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(Theme.dim)
            }
            .offset(y: -6)
        }
        .padding(14)
    }
}

/// Semicerchio con indicatore dell'angolo di piega (±45°).
struct LeanArc: View {
    let lean: Double
    let maxLeft: Double
    let maxRight: Double

    var body: some View {
        let angle = max(-45, min(45, lean)) * 2 * .pi / 180
        let hot = abs(lean) > 30
        VStack(spacing: 8) {
            ZStack {
                Circle().trim(from: 0.5, to: 1)
                    .stroke(Theme.fill, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .position(x: 75, y: 75)
                Circle()
                    .fill(hot ? Color.red : Theme.accent)
                    .frame(width: 18, height: 18)
                    .shadow(color: (hot ? Color.red : Theme.accent).opacity(0.7), radius: 6)
                    .position(x: 75 + 70 * sin(angle), y: 75 - 70 * cos(angle))
                    .animation(.easeOut(duration: 0.12), value: lean)
                VStack(spacing: -2) {
                    Text(String(format: "%.0f°", abs(lean)))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("PIEGA").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(Theme.dim)
                }
                .position(x: 75, y: 52)
            }
            .frame(width: 150, height: 82)
            HStack {
                Label(String(format: "%.0f°", maxLeft), systemImage: "arrow.left")
                Spacer()
                Label(String(format: "%.0f°", maxRight), systemImage: "arrow.right")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.dim)
            .frame(width: 150)
        }
    }
}

struct RouteShape: Shape {
    let pts: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        guard pts.count > 1,
              let minLat = pts.map(\.latitude).min(), let maxLat = pts.map(\.latitude).max(),
              let minLon = pts.map(\.longitude).min(), let maxLon = pts.map(\.longitude).max() else { return Path() }
        let k = cos((minLat + maxLat) / 2 * .pi / 180)
        let w = (maxLon - minLon) * k, h = maxLat - minLat
        let scale = min(rect.width, rect.height) / max(w, h, 1e-9)
        let ox = rect.midX - w * scale / 2, oy = rect.midY - h * scale / 2
        var path = Path()
        for (i, c) in pts.enumerated() {
            let pt = CGPoint(x: ox + (c.longitude - minLon) * k * scale, y: oy + (maxLat - c.latitude) * scale)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }
}

/// Miniatura del percorso disegnata senza mappa.
struct RouteThumb: View {
    let track: [TrackPoint]

    var body: some View {
        let step = max(1, track.count / 90)
        let pts = stride(from: 0, to: track.count, by: step).map { track[$0].coordinate }
        RouteShape(pts: pts)
            .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .padding(12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StarRating: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .foregroundStyle(i <= rating ? Color.yellow : Color.gray.opacity(0.4))
                    .onTapGesture { rating = (rating == i ? 0 : i) }
            }
        }
        .font(.title3)
    }
}

struct IdentifiedID: Identifiable { let id: UUID }
