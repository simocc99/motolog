import SwiftUI
import MapKit

/// Classifica personale dei tuoi giri migliori per categoria.
struct RankingView: View {
    @EnvironmentObject var store: DataStore
    @State private var cat = Cat.speed

    enum Cat: String, CaseIterable, Identifiable {
        case speed = "Velocità", distance = "Distanza", lean = "Piega"
        case climb = "Dislivello", avg = "Media", duration = "Durata"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .speed: return "gauge.high"
            case .distance: return "arrow.triangle.swap"
            case .lean: return "rotate.right.fill"
            case .climb: return "mountain.2.fill"
            case .avg: return "speedometer"
            case .duration: return "clock.fill"
            }
        }

        func value(_ r: Ride) -> Double {
            switch self {
            case .speed: return r.maxSpeed
            case .distance: return r.distance
            case .lean: return r.maxLean
            case .climb: return r.elevationGain
            case .avg: return r.avgSpeed
            case .duration: return r.elapsed
            }
        }

        func text(_ r: Ride) -> String {
            switch self {
            case .speed: return "\(Fmt.speedText(r.maxSpeed)) \(Fmt.speedUnit)"
            case .distance: return "\(Fmt.distText(r.distance)) \(Fmt.distUnit)"
            case .lean: return String(format: "%.0f°", r.maxLean)
            case .climb: return "\(Fmt.altText(r.elevationGain)) \(Fmt.altUnit)"
            case .avg: return "\(Fmt.speedText(r.avgSpeed)) \(Fmt.speedUnit)"
            case .duration: return Fmt.durationLong(r.elapsed)
            }
        }
    }

    private var ranked: [Ride] {
        Array(store.rides.filter { cat.value($0) > 0 }.sorted { cat.value($0) > cat.value($1) }.prefix(20))
    }

    private func medal(_ i: Int) -> Color? {
        switch i {
        case 0: return Color(red: 1, green: 0.8, blue: 0.2)
        case 1: return Color(red: 0.78, green: 0.8, blue: 0.84)
        case 2: return Color(red: 0.8, green: 0.5, blue: 0.25)
        default: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Cat.allCases) { c in
                            Button { withAnimation(.easeOut(duration: 0.2)) { cat = c } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: c.icon)
                                    Text(c.rawValue)
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .foregroundStyle(c == cat ? Color.black : Color.primary)
                                .background(c == cat ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.fill), in: Capsule())
                            }
                        }
                    }
                }

                if ranked.isEmpty {
                    Text("Nessun giro con questo dato.")
                        .foregroundStyle(Theme.dim).padding(.top, 40)
                }

                ForEach(Array(ranked.enumerated()), id: \.element.id) { i, ride in
                    NavigationLink {
                        RideDetailView(rideID: ride.id, isSheet: false)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                if let m = medal(i) {
                                    Image(systemName: "medal.fill").font(.title2).foregroundStyle(m)
                                } else {
                                    Text("\(i + 1)").font(.headline).foregroundStyle(Theme.dim)
                                }
                            }
                            .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ride.name).font(.headline).lineLimit(1)
                                Text("\(ride.start.shortDate) · \(Fmt.distText(ride.distance)) \(Fmt.distUnit)")
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Text(cat.text(ride))
                                .font(.system(size: i == 0 ? 24 : 19, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(i < 3 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary))
                        }
                        .card(padding: i == 0 ? 18 : 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(i == 0 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Classifica")
    }
}

/// Tutti i tuoi giri sovrapposti su un'unica mappa.
struct AllRidesMapView: View {
    @EnvironmentObject var store: DataStore

    private func coords(_ r: Ride) -> [CLLocationCoordinate2D] {
        let step = max(1, r.points.count / 120)
        return stride(from: 0, to: r.points.count, by: step).map { r.points[$0].coordinate }
    }

    private var region: MKCoordinateRegion {
        let pts = store.rides.flatMap(\.points)
        guard let minLat = pts.map(\.lat).min(), let maxLat = pts.map(\.lat).max(),
              let minLon = pts.map(\.lon).min(), let maxLon = pts.map(\.lon).max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45.46, longitude: 9.19),
                                      span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.01),
                                   longitudeDelta: max((maxLon - minLon) * 1.3, 0.01)))
    }

    var body: some View {
        let total = store.rides.reduce(0) { $0 + $1.distance }
        Map(initialPosition: .region(region)) {
            ForEach(store.rides) { r in
                MapPolyline(coordinates: coords(r)).stroke(Theme.accent.opacity(0.85), lineWidth: 3)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            HStack(spacing: 14) {
                Label("\(store.rides.count) giri", systemImage: "flag.checkered")
                Label("\(Fmt.distText(total)) \(Fmt.distUnit)", systemImage: "road.lanes")
            }
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 24)
        }
        .navigationTitle("Mappa dei giri")
        .navigationBarTitleDisplayMode(.inline)
    }
}
