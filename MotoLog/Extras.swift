import SwiftUI
import MapKit

// MARK: Analisi del giro

struct RideAnalysis {
    struct Stop: Identifiable {
        let id = UUID()
        let start: Date
        let duration: TimeInterval
    }

    var curves = 0
    var sharpest = 0.0
    var stops: [Stop] = []

    init(_ ride: Ride) {
        // Una curva conta quando la piega supera 15° e finisce quando torna sotto 8°.
        var inCurve = false
        for p in ride.points {
            let a = abs(p.lean)
            sharpest = max(sharpest, a)
            if !inCurve, a >= 15 { inCurve = true; curves += 1 } else if inCurve, a < 8 { inCurve = false }
        }

        // Sosta lunga: fermo per almeno 3 minuti.
        var first: TrackPoint?
        var last: TrackPoint?
        func close() {
            if let f = first, let l = last, l.time.timeIntervalSince(f.time) >= 180 {
                stops.append(Stop(start: f.time, duration: l.time.timeIntervalSince(f.time)))
            }
            first = nil; last = nil
        }
        for p in ride.points {
            if p.speed < 1 {
                if first == nil { first = p }
                last = p
            } else {
                close()
            }
        }
        close()
    }
}

struct RideAnalysisCard: View {
    let ride: Ride

    var body: some View {
        let a = RideAnalysis(ride)
        VStack(alignment: .leading, spacing: 12) {
            Label("Analisi del giro", systemImage: "waveform.path.ecg")
                .font(.headline)
            if a.sharpest > 0 {
                HStack(spacing: 10) {
                    StatTile(title: "Curve impegnative", value: "\(a.curves)", icon: "point.topleft.down.to.point.bottomright.curvepath")
                    StatTile(title: "Piega più forte", value: String(format: "%.0f", a.sharpest), unit: "°", icon: "angle")
                }
            }
            if a.stops.isEmpty {
                Text("Nessuna sosta lunga (oltre 3 minuti).").font(.footnote).foregroundStyle(Theme.dim)
            } else {
                Text("SOSTE LUNGHE").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                ForEach(a.stops) { s in
                    HStack {
                        Image(systemName: "cup.and.saucer.fill").foregroundStyle(Theme.accent)
                        Text(s.start.shortTime)
                        Spacer()
                        Text(Fmt.durationLong(s.duration)).fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: Tramonto

enum Sun {
    /// Ora del tramonto (algoritmo "Almanac for Computers"), nil se il sole non tramonta in quel giorno.
    static func sunset(on date: Date, lat: Double, lon: Double) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let n = cal.ordinality(of: .day, in: .year, for: date) else { return nil }
        let rad = Double.pi / 180
        func norm(_ x: Double, _ m: Double) -> Double { let r = x.truncatingRemainder(dividingBy: m); return r < 0 ? r + m : r }

        let lngHour = lon / 15
        let t = Double(n) + (18 - lngHour) / 24
        let M = 0.9856 * t - 3.289
        let L = norm(M + 1.916 * sin(M * rad) + 0.020 * sin(2 * M * rad) + 282.634, 360)
        var RA = norm(atan(0.91764 * tan(L * rad)) / rad, 360)
        RA += (floor(L / 90) * 90) - (floor(RA / 90) * 90)
        RA /= 15
        let sinDec = 0.39782 * sin(L * rad)
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(90.833 * rad) - sinDec * sin(lat * rad)) / (cosDec * cos(lat * rad))
        guard cosH >= -1, cosH <= 1 else { return nil }
        let H = acos(cosH) / rad / 15
        let T = H + RA - 0.06571 * t - 6.622
        let ut = norm(T - lngHour, 24)
        return cal.startOfDay(for: date).addingTimeInterval(ut * 3600)
    }
}

// MARK: Parcheggio

struct ParkingCard: View {
    @EnvironmentObject var tracker: RideTracker
    @AppStorage("parkLat") private var lat = 0.0
    @AppStorage("parkLon") private var lon = 0.0
    @AppStorage("parkTime") private var time = 0.0

    private var parked: Bool { time > 0 }

    private var subtitle: String {
        guard parked else { return "Segna dove l'hai lasciata per ritrovarla." }
        let ago = Date().timeIntervalSince(Date(timeIntervalSince1970: time))
        var s = "da \(Fmt.durationLong(ago))"
        if let here = tracker.currentLocation {
            let d = here.distance(from: CLLocation(latitude: lat, longitude: lon))
            s += d < 1000 ? " · a \(Int(d)) m" : " · a \(Fmt.distText(d)) \(Fmt.distUnit)"
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                IconBadge(icon: "parkingsign.circle.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(parked ? "Moto parcheggiata" : "Dove l'hai lasciata?").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                if parked {
                    Button { walkThere() } label: { pill("Portami lì", "figure.walk") }
                }
                Button { markHere() } label: { pill("Segna qui", "mappin.and.ellipse") }
                    .disabled(tracker.currentLocation == nil)
                if parked {
                    Button { time = 0 } label: { pill("Cancella", "xmark") }
                }
            }
        }
        .card()
    }

    private func pill(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.fill, in: Capsule())
    }

    private func markHere() {
        guard let loc = tracker.currentLocation else { return }
        lat = loc.coordinate.latitude; lon = loc.coordinate.longitude; time = Date().timeIntervalSince1970
    }

    private func walkThere() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        item.name = "La mia moto"
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    /// Chiamato a fine giro: l'ultima posizione registrata è dove hai lasciato la moto.
    static func save(_ coordinate: CLLocationCoordinate2D) {
        let d = UserDefaults.standard
        d.set(coordinate.latitude, forKey: "parkLat")
        d.set(coordinate.longitude, forKey: "parkLon")
        d.set(Date().timeIntervalSince1970, forKey: "parkTime")
    }
}

// MARK: Controllo prima di partire

struct PreflightSheet: View {
    @Environment(\.dismiss) private var dismiss
    let fuelNote: String?
    let onStart: () -> Void

    private let items: [(String, String)] = [
        ("Pneumatici", "gauge.with.dots.needle.33percent"),
        ("Olio e liquidi", "drop.fill"),
        ("Freni", "exclamationmark.octagon.fill"),
        ("Luci e frecce", "lightbulb.fill"),
        ("Catena", "link"),
        ("Benzina", "fuelpump.fill"),
        ("Casco e visiera", "helmet"),
        ("Guanti e paraschiena", "hand.raised.fill")
    ]
    @State private var done: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(items, id: \.0) { item in
                    Button {
                        if done.contains(item.0) { done.remove(item.0) } else { done.insert(item.0) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: done.contains(item.0) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done.contains(item.0) ? .green : Theme.dim)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.0).foregroundStyle(.primary)
                                if item.0 == "Benzina", let fuelNote {
                                    Text(fuelNote).font(.caption).foregroundStyle(Theme.dim)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Prima di partire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    onStart()
                } label: {
                    Text(done.count == items.count ? "TUTTO OK, VIA!" : "PARTI (\(done.count)/\(items.count))")
                        .font(.headline.weight(.heavy)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.gradient, in: Capsule())
                }
                .padding(16)
            }
        }
        .presentationDetents([.large])
    }
}
