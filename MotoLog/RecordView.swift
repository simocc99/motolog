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
        .sheet(item: $summary) { item in
            NavigationStack { RideDetailView(rideID: item.id, isSheet: true) }
        }
    }

    // MARK: Cruscotto

    private var dashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header
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
            case .recording: Chip(text: "IN REGISTRAZIONE", icon: "circle.fill", tint: .red)
            case .paused: Chip(text: "IN PAUSA", icon: "pause.fill", tint: .yellow)
            case .idle: Chip(text: "PRONTO", icon: "checkmark.circle.fill", tint: .green)
            }
            Spacer()
            if tracker.state == .idle, !store.bikes.isEmpty {
                Menu {
                    ForEach(store.bikes) { b in Button(b.name) { bikeID = b.id } }
                    Button("Nessuna moto") { bikeID = nil }
                } label: {
                    Chip(text: store.bike(bikeID)?.name ?? "Nessuna moto", icon: "scooter", tint: Theme.accent)
                }
            }
            gpsChip
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
                    Capsule().fill(i == page ? Theme.accent : Color.white.opacity(0.2))
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: page)

            if tracker.state == .idle {
                if !tracker.isAuthorized && tracker.authorization != .notDetermined {
                    Text("Abilita la posizione in Impostazioni › MotoLog per registrare i giri.")
                        .font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button { tracker.start(bikeID: bikeID) } label: {
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
                            .background(Color.white.opacity(0.1), in: Capsule())
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
