import SwiftUI
import MapKit
import Charts

struct RideDetailView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let rideID: UUID
    let isSheet: Bool

    @State private var metric = Metric.speed
    @State private var scrub = 0.0
    @State private var confirmDelete = false
    @State private var gpxURL: URL?
    @State private var story: StoryItem?

    enum Metric: String, CaseIterable, Identifiable {
        case speed = "Velocità", altitude = "Quota", lean = "Piega", g = "G"
        var id: String { rawValue }
    }

    private var index: Int? { store.rides.firstIndex { $0.id == rideID } }

    private func binding<T>(_ kp: WritableKeyPath<Ride, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { index.map { store.rides[$0][keyPath: kp] } ?? fallback },
            set: { v in if let i = index { store.rides[i][keyPath: kp] = v } }
        )
    }

    var body: some View {
        Group {
            if let i = index {
                content(store.rides[i])
            } else {
                ContentUnavailableView("Giro non trovato", systemImage: "questionmark.folder")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .topBarTrailing) { Button("Fine") { dismiss() } }
            }
            if let i = index {
                ToolbarItem(placement: .topBarLeading) {
                    if let url = gpxURL ?? GPX.fileURL(for: store.rides[i]) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
        .sheet(item: $story) { item in
            StoryPreviewSheet(image: item.image)
        }
        .confirmationDialog("Eliminare questo giro?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                store.rides.removeAll { $0.id == rideID }
                dismiss()
            }
        }
    }

    private func content(_ ride: Ride) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                routeMap(ride)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                scrubber(ride)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Nome del giro", text: binding(\.name, fallback: ""))
                        .font(.title2.weight(.bold))
                    Text("\(ride.start.shortDate) · \(ride.start.shortTime) – \(ride.end.shortTime)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        StarRating(rating: binding(\.rating, fallback: 0))
                        Spacer()
                        if !store.bikes.isEmpty {
                            Picker("Moto", selection: binding(\.bikeID, fallback: nil)) {
                                Text("Nessuna").tag(UUID?.none)
                                ForEach(store.bikes) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .card()

                Button {
                    if let img = StoryCard.render(ride: ride, bikeName: store.bike(ride.bikeID)?.name) {
                        story = StoryItem(image: img)
                    }
                } label: {
                    Label("Crea storia per Instagram", systemImage: "sparkles")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.gradient, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 5)
                }

                stats(ride)
                chartCard(ride)

                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Com'è andata? Strade, meteo, soste…", text: binding(\.notes, fallback: ""), axis: .vertical)
                        .lineLimit(2...8)
                }
                .card()

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Elimina giro", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding()
        }
        .background(Theme.background)
    }

    // MARK: Mappa

    private struct Segment: Identifiable {
        let id: Int
        let coords: [CLLocationCoordinate2D]
        let color: Color
    }

    private func segments(_ ride: Ride) -> [Segment] {
        let pts = ride.points
        guard pts.count > 1 else { return [] }
        let step = max(1, pts.count / 400)
        var out: [Segment] = []
        var i = 0
        while i < pts.count - 1 {
            let j = min(i + step, pts.count - 1)
            out.append(Segment(id: out.count, coords: [pts[i].coordinate, pts[j].coordinate],
                               color: Fmt.speedColor(pts[j].speed)))
            i = j
        }
        return out
    }

    private func region(_ ride: Ride) -> MKCoordinateRegion {
        let lats = ride.points.map(\.lat), lons = ride.points.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45, longitude: 9),
                                      span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                                   longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)))
    }

    private func scrubPoint(_ ride: Ride) -> TrackPoint? {
        guard !ride.points.isEmpty else { return nil }
        let i = Int((scrub * Double(ride.points.count - 1)).rounded())
        return ride.points[max(0, min(i, ride.points.count - 1))]
    }

    private func routeMap(_ ride: Ride) -> some View {
        Map(initialPosition: .region(region(ride))) {
            ForEach(segments(ride)) { seg in
                MapPolyline(coordinates: seg.coords).stroke(seg.color, lineWidth: 5)
            }
            if let first = ride.points.first {
                Marker("Partenza", systemImage: "flag.fill", coordinate: first.coordinate).tint(.green)
            }
            if let last = ride.points.last {
                Marker("Arrivo", systemImage: "flag.checkered", coordinate: last.coordinate).tint(.red)
            }
            if scrub > 0, let p = scrubPoint(ride) {
                Marker("", systemImage: "scooter", coordinate: p.coordinate).tint(.orange)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    private func scrubber(_ ride: Ride) -> some View {
        VStack(spacing: 6) {
            Slider(value: $scrub, in: 0...1)
            if scrub > 0, let p = scrubPoint(ride) {
                HStack {
                    Text(p.time.shortTime)
                    Spacer()
                    Text("\(Fmt.speedText(p.speed)) \(Fmt.speedUnit)")
                    Spacer()
                    Text("\(Fmt.altText(p.alt)) \(Fmt.altUnit)")
                    Spacer()
                    Text(String(format: "%.0f°", abs(p.lean)))
                }
                .font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.orange)
            } else {
                Text("Trascina per rivedere il giro punto per punto")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Statistiche

    private func stats(_ ride: Ride) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(title: "Distanza", value: Fmt.distText(ride.distance), unit: Fmt.distUnit, icon: "arrow.triangle.swap")
            StatTile(title: "Durata", value: Fmt.duration(ride.elapsed), icon: "clock")
            StatTile(title: "In movimento", value: Fmt.duration(ride.movingTime), icon: "figure.walk.motion")
            StatTile(title: "Soste", value: Fmt.duration(ride.stoppedTime), icon: "pause.circle")
            StatTile(title: "Media", value: Fmt.speedText(ride.avgSpeed), unit: Fmt.speedUnit, icon: "speedometer")
            StatTile(title: "Massima", value: Fmt.speedText(ride.maxSpeed), unit: Fmt.speedUnit, icon: "gauge.high", tint: .red)
            StatTile(title: "Dislivello +", value: Fmt.altText(ride.elevationGain), unit: Fmt.altUnit, icon: "mountain.2.fill")
            StatTile(title: "Quota max", value: Fmt.altText(ride.maxAltitude), unit: Fmt.altUnit, icon: "arrow.up.to.line")
            StatTile(title: "Piega sinistra", value: String(format: "%.0f", ride.maxLeanLeft), unit: "°", icon: "arrow.left")
            StatTile(title: "Piega destra", value: String(format: "%.0f", ride.maxLeanRight), unit: "°", icon: "arrow.right")
            StatTile(title: "G massimi", value: String(format: "%.1f", ride.maxG), unit: "G", icon: "bolt.fill")
            StatTile(title: "Punti GPS", value: "\(ride.points.count)", icon: "location.fill")
        }
    }

    // MARK: Grafici

    private struct Sample: Identifiable {
        let id: Int
        let minutes: Double
        let value: Double
    }

    private func samples(_ ride: Ride) -> [Sample] {
        guard let t0 = ride.points.first?.time else { return [] }
        let step = max(1, ride.points.count / 250)
        return stride(from: 0, to: ride.points.count, by: step).map { i in
            let p = ride.points[i]
            let v: Double
            switch metric {
            case .speed: v = Fmt.speed(p.speed)
            case .altitude: v = Fmt.alt(p.alt)
            case .lean: v = abs(p.lean)
            case .g: v = p.g
            }
            return Sample(id: i, minutes: p.time.timeIntervalSince(t0) / 60, value: v)
        }
    }

    private func chartCard(_ ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Grafico", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Chart(samples(ride)) { s in
                AreaMark(x: .value("Minuti", s.minutes), y: .value(metric.rawValue, s.value))
                    .foregroundStyle(.linearGradient(colors: [.orange.opacity(0.5), .orange.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Minuti", s.minutes), y: .value(metric.rawValue, s.value))
                    .foregroundStyle(.orange)
            }
            .chartXAxisLabel("minuti")
            .frame(height: 170)
        }
        .card()
    }
}
