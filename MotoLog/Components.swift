import SwiftUI

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var icon: String = ""
    var tint: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if !icon.isEmpty {
                    Image(systemName: icon).font(.caption).foregroundStyle(tint)
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }
}

/// Indicatore di piega: la moto ruota in base all'angolo.
struct LeanGauge: View {
    let lean: Double
    let maxLeft: Double
    let maxRight: Double
    var dark = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.35), lineWidth: 6)
                ForEach([-45.0, -30.0, -15.0, 0, 15.0, 30.0, 45.0], id: \.self) { a in
                    Rectangle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 2, height: a == 0 ? 12 : 8)
                        .offset(y: -58)
                        .rotationEffect(.degrees(a))
                }
                Capsule()
                    .fill(abs(lean) > 30 ? Color.red : Color.orange)
                    .frame(width: 8, height: 90)
                    .rotationEffect(.degrees(lean))
                    .animation(.easeOut(duration: 0.12), value: lean)
                Text(String(format: "%.0f°", abs(lean)))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dark ? .white : .primary)
                    .offset(y: 38)
            }
            .frame(width: 130, height: 130)
            HStack(spacing: 14) {
                Label(String(format: "%.0f°", maxLeft), systemImage: "arrow.left")
                Label(String(format: "%.0f°", maxRight), systemImage: "arrow.right")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }
}

struct StarRating: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .foregroundStyle(i <= rating ? Color.yellow : Color.gray.opacity(0.5))
                    .onTapGesture { rating = (rating == i ? 0 : i) }
            }
        }
        .font(.title3)
    }
}

struct IdentifiedID: Identifiable { let id: UUID }
