import SwiftUI
import MapKit

/// Navigatore (beta): guida passo passo con i dati della moto, del giro e del serbatoio.
struct NavRunView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var tracker: RideTracker
    @Environment(\.dismiss) private var dismiss

    @StateObject private var engine: NavEngine
    let bike: Bike?
    let simulate: Bool

    @State private var smoother = SmoothPosition()
    @State private var pos: CLLocation?
    @State private var simPath: SimPath
    @State private var simS = 0.0
    @State private var detour = 0
    private let simSpeed = 22.0   // m/s, circa 80 km/h
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var showEnd = false
    @State private var showStations = false
    @State private var stations: [(item: MKMapItem, meters: Double)] = []
    @State private var searching = false

    init(route: MKRoute, destination: MKMapItem, bike: Bike?, simulate: Bool) {
        _engine = StateObject(wrappedValue: NavEngine(route: route, destination: destination))
        _simPath = State(initialValue: SimPath(route))
        self.bike = bike
        self.simulate = simulate
    }

    private var speed: Double { simulate ? simSpeed : tracker.speed }
    private var recording: Bool { !simulate && tracker.state != .idle }

    var body: some View {
        ZStack {
            map
            VStack(spacing: 10) {
                banner
                Spacer()
                if engine.arrived { arrivalCard } else { panel }
            }
            .padding(12)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if !simulate, tracker.state == .idle { tracker.start(bikeID: bike?.id) }
            if simulate { simulateTick() } else if let l = tracker.currentLocation { handle(l) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(tick) { _ in if simulate { simulateTick() } }
        .onChange(of: tracker.currentLocation) { _, l in if let l, !simulate { handle(l) } }
        .onChange(of: engine.routeVersion) { _, _ in
            simPath = SimPath(engine.route)
            simS = 0
            detour = 0
        }
        .confirmationDialog("Terminare la navigazione?", isPresented: $showEnd, titleVisibility: .visible) {
            if recording {
                Button("Termina e salva il giro") { finish(save: true) }
                Button("Termina solo la navigazione") { dismiss() }
            } else {
                Button("Termina navigazione", role: .destructive) { dismiss() }
            }
            Button("Continua", role: .cancel) {}
        }
        .sheet(isPresented: $showStations) { stationsSheet }
    }

    // MARK: Mappa

    /// La telecamera è ricalcolata 30 volte al secondo, così il movimento non va a scatti.
    private var map: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let frame = smoother.step(now: ctx.date)
            Map(position: .constant(cameraPosition(frame))) {
                MapPolyline(engine.route.polyline).stroke(Theme.accent, lineWidth: 9)
                Marker(engine.destination.name ?? "Arrivo", coordinate: engine.destination.placemark.coordinate).tint(.red)
                if let f = frame {
                    Annotation("", coordinate: f.coordinate) {
                        ZStack {
                            Circle().fill(.white).frame(width: 34, height: 34).shadow(radius: 4)
                            Image(systemName: "location.north.fill").foregroundStyle(Theme.accent).font(.system(size: 18))
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    /// Il centro della mappa sta un po' davanti a te, così vedi più strada.
    private func cameraPosition(_ f: SmoothPosition.Frame?) -> MapCameraPosition {
        guard let f else { return .automatic }
        let p = MKMapPoint(f.coordinate)
        let ppm = MKMapPointsPerMeterAtLatitude(f.coordinate.latitude)
        let rad = f.heading * .pi / 180
        let ahead = f.distance * 0.3 * ppm
        let center = MKMapPoint(x: p.x + sin(rad) * ahead, y: p.y - cos(rad) * ahead).coordinate
        return .camera(MapCamera(centerCoordinate: center, distance: f.distance, heading: f.heading, pitch: 55))
    }

    // MARK: Indicazioni

    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            if engine.rerouting || engine.offRoute {
                Label("Ricalcolo del percorso…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline).foregroundStyle(.orange)
            } else {
                HStack(spacing: 14) {
                    Image(systemName: engine.symbol)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        TimelineView(.animation(minimumInterval: 0.2)) { ctx in
                            Text(NavText.distance(predicted(engine.distToNext, at: ctx.date)))
                                .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                        }
                        Text(engine.nextText).font(.subheadline.weight(.semibold)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                if let then = engine.thenText {
                    Text("Poi: \(then)").font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                }
            }
            if simulate {
                Chip(text: "SIMULAZIONE", icon: "play.circle.fill", tint: .blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Dati in basso

    private var etaSeconds: Double {
        let r = engine.route
        let apple = r.distance / max(r.expectedTravelTime, 1)
        var v = apple
        if let t = store.typicalSpeed(bikeID: bike?.id) { v = min(max(t, apple * 0.7), apple * 1.4) }
        // Se sei in moto da almeno 3 minuti conta anche l'andatura di oggi.
        if recording, tracker.movingTime > 180 {
            let today = tracker.distance / tracker.movingTime
            v = (v + min(max(today, apple * 0.6), apple * 1.6)) / 2
        }
        return engine.remaining / max(v, 1)
    }

    private var fuel: FuelState? {
        guard let bike else { return nil }
        return store.fuelState(for: bike, live: recording && tracker.bikeID == bike.id ? tracker.points : [])
    }

    private var panel: some View {
        let eta = etaSeconds
        let arrival = Date().addingTimeInterval(eta)
        let sunset = pos.flatMap { Sun.sunset(on: Date(), lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
        let afterDark = sunset.map { Date() < $0 && arrival > $0 } ?? false

        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.speedText(speed)).font(.system(size: 54, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(Fmt.speedUnit).font(.footnote.weight(.bold)).foregroundStyle(Theme.dim)
                Spacer()
                if !simulate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "Piega %.0f°  ·  %.1f G", abs(tracker.lean), tracker.gForce))
                        Text("Max \(Fmt.speedText(tracker.maxSpeed)) \(Fmt.speedUnit) · \(Fmt.distText(tracker.distance)) \(Fmt.distUnit)")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.dim).monospacedDigit()
                }
            }
            HStack {
                stat(arrival.shortTime, "ARRIVO")
                stat(Fmt.durationLong(eta), "TEMPO")
                TimelineView(.animation(minimumInterval: 0.5)) { ctx in
                    stat("\(Fmt.distText(predicted(engine.remaining, at: ctx.date))) \(Fmt.distUnit)", "MANCANO")
                }
            }
            if let st = fuel {
                let short = st.range * 1000 < engine.remaining * 1.05
                HStack {
                    Image(systemName: "fuelpump.fill").foregroundStyle(short ? .orange : Theme.dim)
                    Text(String(format: "≈ %.1f L · %d km", st.liters, Int(st.range)))
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    if short {
                        Text("Rifornisci prima di arrivare").font(.caption.weight(.bold)).foregroundStyle(.orange)
                    }
                }
            }
            HStack(spacing: 6) {
                if tracker.overLimit && !simulate { Chip(text: "LIMITE", icon: "exclamationmark.triangle.fill", tint: .red) }
                if engine.route.hasHighways { Chip(text: "AUTOSTRADA: GUANTI E PARASCHIENA", icon: "exclamationmark.shield.fill", tint: .orange) }
                if engine.route.hasTolls { Chip(text: "PEDAGGI", icon: "eurosign.circle.fill", tint: Theme.dim) }
                if afterDark { Chip(text: "ARRIVO DOPO IL TRAMONTO", icon: "sunset.fill", tint: .orange) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                circle("fuelpump.fill") { Task { await openStations() } }
                circle(engine.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") { engine.muted.toggle() }
                if simulate {
                    circle("arrow.triangle.branch") { detour = 5 }
                }
                Spacer()
                Button { showEnd = true } label: {
                    Label("FINE", systemImage: "xmark")
                        .font(.headline.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Color.red, in: Capsule())
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    /// Tra due fix GPS i metri continuano a scendere in base alla velocità.
    private func predicted(_ meters: Double, at date: Date) -> Double {
        max(0, meters - speed * min(max(date.timeIntervalSince(engine.lastUpdate), 0), 2))
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private func circle(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.14), in: Circle())
        }
    }

    // MARK: Arrivo

    private var arrivalCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.checkered").font(.system(size: 34)).foregroundStyle(Theme.accent)
            Text("Sei arrivato").font(.title2.weight(.heavy))
            Text(engine.destination.name ?? "Destinazione").font(.subheadline).foregroundStyle(Theme.dim)
            if let final = engine.pendingFinal {
                Button {
                    if let p = pos { Task { await engine.resumeFinal(from: p) } }
                } label: {
                    Text("Riprendi verso \(final.name ?? "la destinazione")")
                        .font(.headline.weight(.heavy)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.gradient, in: Capsule())
                }
            } else {
                if recording {
                    Button { finish(save: true) } label: {
                        Text("Termina e salva il giro")
                            .font(.headline.weight(.heavy)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.gradient, in: Capsule())
                    }
                }
                Button("Chiudi") { dismiss() }.foregroundStyle(Theme.dim)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Distributori

    private func openStations() async {
        guard let c = (pos ?? tracker.currentLocation)?.coordinate else { return }
        showStations = true
        searching = true
        stations = await NavEngine.stations(around: c)
        searching = false
    }

    private var stationsSheet: some View {
        NavigationStack {
            List {
                if searching {
                    ProgressView("Cerco i distributori…")
                } else if stations.isEmpty {
                    Text("Nessun distributore trovato nel raggio di 15 km.").foregroundStyle(Theme.dim)
                }
                ForEach(stations, id: \.item) { s in
                    Button {
                        showStations = false
                        if let p = pos ?? tracker.currentLocation { Task { await engine.divert(to: s.item, from: p) } }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.item.name ?? "Distributore").foregroundStyle(.primary)
                                Text("a \(NavText.distance(s.meters)) in linea d'aria").font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: "arrow.turn.up.right").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Distributori vicini")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { showStations = false } } }
        }
        .presentationDetents([.medium])
    }

    // MARK: Posizione

    private func handle(_ loc: CLLocation) {
        pos = loc
        smoother.feed(loc)
        engine.update(loc)
    }

    /// Guida simulata lungo il percorso; "deviazione" ti porta 190 m fuori strada per provare il ricalcolo.
    private func simulateTick() {
        guard !engine.arrived else { return }
        if detour > 0 { detour -= 1 } else { simS = min(simS + simSpeed, simPath.total) }
        var (c, bearing) = simPath.at(simS)
        if detour > 0 { c.longitude += 0.0026 }
        handle(CLLocation(coordinate: c, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                          course: bearing, speed: simSpeed, timestamp: Date()))
    }

    private func finish(save: Bool) {
        if save, let ride = tracker.finish() {
            if let last = ride.points.last { ParkingCard.save(last.coordinate) }
            store.addRide(ride)
        }
        dismiss()
    }
}
