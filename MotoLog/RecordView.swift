import SwiftUI
import MapKit

struct RecordView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var tracker: RideTracker
    @AppStorage("keepAwake") private var keepAwake = true

    @State private var page = 0
    @State private var bikeID: UUID?
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var showStopDialog = false
    @State private var summary: IdentifiedID?
    @State private var showFuel = false
    @State private var showPreflight = false
    @Environment(\.verticalSizeClass) private var vSize
    @AppStorage("preflight") private var preflight = false

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    dashboard.tag(0)
                    mapPage.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                controls
            }
        }
        .onChange(of: tracker.state) { _, new in
            UIApplication.shared.isIdleTimerDisabled = keepAwake && new == .recording
        }
        .onAppear {
            if !tracker.isAuthorized { tracker.requestPermission() }
            if bikeID == nil { bikeID = store.bikes.first?.id }
        }
        .confirmationDialog("Terminare il giro?", isPresented: $showStopDialog, titleVisibility: .visible) {
            Button("Salva giro") { finishRide() }
            Button("Elimina giro", role: .destructive) { tracker.discard() }
            Button("Continua", role: .cancel) {}
        }
        .alert("Possibile caduta rilevata", isPresented: $tracker.fallAlert) {
            Button("Sto bene", role: .cancel) {}
            Button("Chiama il 112", role: .destructive) {
                if let url = URL(string: "tel://112") { UIApplication.shared.open(url) }
            }
        } message: {
            Text("È stato rilevato un forte impatto seguito da un arresto. Stai bene?")
        }
        .alert("Giro interrotto trovato", isPresented: Binding(get: { store.draft != nil && tracker.state == .idle },
                                                                set: { _ in })) {
            Button("Recupera e salva") {
                if let d = store.draft { store.addRide(d) }
                store.saveDraft(nil)
            }
            Button("Elimina", role: .destructive) { store.saveDraft(nil) }
        } message: {
            Text("L'app si è chiusa durante un giro. Vuoi recuperarlo?")
        }
        .onChange(of: tracker.fuelStation) { _, s in if s != nil { showFuel = true } }
        .sheet(isPresented: $showFuel, onDismiss: { tracker.fuelStation = nil }) {
            FuelStopSheet(bike: activeBike, station: tracker.fuelStation)
        }
        .sheet(isPresented: $showPreflight) {
            PreflightSheet(fuelNote: fuelNote) { tracker.start(bikeID: bikeID) }
        }
        .sheet(item: $summary) { item in
            NavigationStack { RideDetailView(rideID: item.id, isSheet: true) }
        }
    }

    // MARK: Cruscotto

    private var dashboard: some View {
        Group {
            if vSize == .compact { landscapeDashboard } else { portraitDashboard }
        }
    }

    /// In orizzontale: tachimetro a sinistra e tutti i dati a destra, senza scorrere.
    private var landscapeDashboard: some View {
        VStack(spacing: 8) {
            header
            if tracker.overLimit {
                Chip(text: "LIMITE DI VELOCITÀ SUPERATO", icon: "exclamationmark.triangle.fill", tint: .red)
            }
            HStack(spacing: 16) {
                SpeedGauge(speed: tracker.speed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    DashCell(title: "Distanza", value: Fmt.distText(tracker.distance), unit: Fmt.distUnit)
                    DashCell(title: "Tempo", value: Fmt.duration(tracker.elapsed), unit: "")
                    DashCell(title: "Media", value: Fmt.speedText(tracker.movingTime > 0 ? tracker.distance / tracker.movingTime : 0), unit: Fmt.speedUnit)
                    DashCell(title: "Max", value: Fmt.speedText(tracker.maxSpeed), unit: Fmt.speedUnit)
                    DashCell(title: "Piega", value: String(format: "%.0f", abs(tracker.lean)), unit: "°")
                    DashCell(title: "Forza G", value: String(format: "%.1f", tracker.gForce), unit: "G")
                    DashCell(title: "Salita", value: Fmt.altText(tracker.elevationGain), unit: Fmt.altUnit)
                    DashCell(title: "Quota", value: Fmt.altText(tracker.altitude), unit: Fmt.altUnit)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var portraitDashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header
                if tracker.overLimit {
                    Chip(text: "LIMITE DI VELOCITÀ SUPERATO", icon: "exclamationmark.triangle.fill", tint: .red)
                }
                sunsetBanner
                SpeedGauge(speed: tracker.speed)
                    .frame(height: 270)

                HStack(spacing: 12) {
                    LeanArc(lean: tracker.lean, maxLeft: tracker.maxLeft, maxRight: tracker.maxRight)
                        .frame(maxWidth: .infinity)
                        .card(padding: 12)
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FORZA G").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                            Text(String(format: "%.1f", tracker.gForce))
                                .font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("G MAX").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                            Text(String(format: "%.1f", tracker.maxG))
                                .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .card(padding: 14)
                    .frame(width: 104)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    DashCell(title: "Distanza", value: Fmt.distText(tracker.distance), unit: Fmt.distUnit)
                    DashCell(title: "Tempo", value: Fmt.duration(tracker.elapsed), unit: "")
                    DashCell(title: "Media", value: Fmt.speedText(tracker.movingTime > 0 ? tracker.distance / tracker.movingTime : 0), unit: Fmt.speedUnit)
                    DashCell(title: "Max", value: Fmt.speedText(tracker.maxSpeed), unit: Fmt.speedUnit)
                    DashCell(title: "Salita", value: Fmt.altText(tracker.elevationGain), unit: Fmt.altUnit)
                    DashCell(title: "Quota", value: Fmt.altText(tracker.altitude), unit: Fmt.altUnit)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            switch tracker.state {
            case .recording: Chip(text: "REC", icon: "circle.fill", tint: .red)
            case .paused: Chip(text: "IN PAUSA", icon: "pause.fill", tint: .yellow)
            case .idle: Chip(text: "PRONTO", icon: "checkmark.circle.fill", tint: .green)
            }
            Spacer()
            if tracker.state == .idle, !store.bikes.isEmpty {
                Menu {
                    ForEach(store.bikes) { b in Button(b.name) { bikeID = b.id } }
                    Button("Nessuna moto") { bikeID = nil }
                } label: {
                    Chip(text: store.bike(bikeID)?.name ?? "Nessuna moto", icon: Theme.bikeSymbol, tint: Theme.accent)
                }
            }
            fuelChip
            gpsChip
        }
    }

    private var fuelNote: String? {
        guard let bike = activeBike, let st = store.fuelState(for: bike) else { return nil }
        return String(format: "Stimati %.1f L · %d km", st.liters, Int(st.range))
    }

    @ViewBuilder
    private var sunsetBanner: some View {
        if let loc = tracker.currentLocation,
           let sun = Sun.sunset(on: Date(), lat: loc.coordinate.latitude, lon: loc.coordinate.longitude) {
            let mins = Int(sun.timeIntervalSinceNow / 60)
            if (0...60).contains(mins) {
                banner("Tramonto tra \(mins) min", "Tieni a portata la visiera chiara e controlla i fari.")
            } else if (-45..<0).contains(mins) {
                banner("Il sole è tramontato", "Visibilità ridotta: fari accesi e attenzione alla fauna.")
            }
        }
    }

    private func banner(_ title: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(icon: "sunset.fill", tint: .orange, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.bold))
                Text(text).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .card(padding: 10)
    }

    private var activeBike: Bike? { store.bike(tracker.state == .idle ? bikeID : tracker.bikeID) }

    @ViewBuilder
    private var fuelChip: some View {
        if let bike = activeBike, let st = store.fuelState(for: bike, live: tracker.bikeID == bike.id ? tracker.points : []),
           tracker.state != .idle || st.low {
            Button { showFuel = true } label: {
                Chip(text: st.range <= 0 ? "RISERVA" : String(format: "%.0f L · %d km", st.liters, Int(st.range)),
                     icon: "fuelpump.fill", tint: st.low ? .orange : Theme.dim)
            }
        }
    }

    private var gpsChip: some View {
        let acc = tracker.accuracy
        if !tracker.isAuthorized { return Chip(text: "NO GPS", icon: "location.slash.fill", tint: .red) }
        if acc < 0 { return Chip(text: "GPS…", icon: "location", tint: Theme.dim) }
        if acc <= 10 { return Chip(text: "GPS OTTIMO", icon: "location.fill", tint: .green) }
        if acc <= 25 { return Chip(text: "GPS OK", icon: "location.fill", tint: .yellow) }
        return Chip(text: "GPS DEBOLE", icon: "location.fill", tint: .orange)
    }

    // MARK: Mappa

    private var mapPage: some View {
        Map(position: $camera) {
            UserAnnotation()
            if tracker.points.count > 1 {
                MapPolyline(coordinates: tracker.points.map(\.coordinate))
                    .stroke(Theme.gradient, lineWidth: 6)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .top) {
            HStack(spacing: 16) {
                Text("\(Fmt.speedText(tracker.speed)) \(Fmt.speedUnit)")
                Text("\(Fmt.distText(tracker.distance)) \(Fmt.distUnit)")
                Text(Fmt.duration(tracker.elapsed))
            }
            .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 12)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: Pulsanti

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule().fill(i == page ? Theme.accent : Color.gray.opacity(0.4))
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: page)

            if tracker.state == .idle {
                if !tracker.isAuthorized && tracker.authorization != .notDetermined {
                    Text("Abilita la posizione in Impostazioni › MotoLog per registrare i giri.")
                        .font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button {
                    if preflight { showPreflight = true } else { tracker.start(bikeID: bikeID) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                        Text("INIZIA GIRO")
                    }
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.gradient, in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.45), radius: 18, y: 6)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        tracker.state == .recording ? tracker.pause() : tracker.resume()
                    } label: {
                        Label(tracker.state == .recording ? "PAUSA" : "RIPRENDI",
                              systemImage: tracker.state == .recording ? "pause.fill" : "play.fill")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.yellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Theme.fill, in: Capsule())
                    }
                    Button { showStopDialog = true } label: {
                        Label("FINE", systemImage: "stop.fill")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(LinearGradient(colors: [.red, Color(red: 0.75, green: 0.1, blue: 0.15)],
                                                       startPoint: .top, endPoint: .bottom), in: Capsule())
                            .shadow(color: .red.opacity(0.35), radius: 14, y: 5)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .padding(.top, 6)
    }

    private func finishRide() {
        if let ride = tracker.finish() {
            if let last = ride.points.last { ParkingCard.save(last.coordinate) }
            store.addRide(ride)
            summary = IdentifiedID(id: ride.id)
        }
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

private struct DashCell: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
            }
        }
        .card(padding: 12)
    }
}
