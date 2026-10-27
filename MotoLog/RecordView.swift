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
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    dashboard.tag(0)
                    mapPage.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                controls
            }
        }
        .preferredColorScheme(.dark)
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
        VStack(spacing: 14) {
            Spacer(minLength: 4)
            VStack(spacing: -6) {
                Text(Fmt.speedText(tracker.speed))
                    .font(.system(size: 130, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Fmt.speedColor(tracker.speed))
                Text(Fmt.speedUnit).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 18) {
                LeanGauge(lean: tracker.lean, maxLeft: tracker.maxLeft, maxRight: tracker.maxRight, dark: true)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DashCell(title: "Distanza", value: Fmt.distText(tracker.distance), unit: Fmt.distUnit)
                    DashCell(title: "Tempo", value: Fmt.duration(tracker.elapsed), unit: "")
                    DashCell(title: "Media", value: Fmt.speedText(tracker.movingTime > 0 ? tracker.distance / tracker.movingTime : 0), unit: Fmt.speedUnit)
                    DashCell(title: "Max", value: Fmt.speedText(tracker.maxSpeed), unit: Fmt.speedUnit)
                    DashCell(title: "Quota", value: Fmt.altText(tracker.altitude), unit: Fmt.altUnit)
                    DashCell(title: "Salita", value: Fmt.altText(tracker.elevationGain), unit: Fmt.altUnit)
                }
            }
            .padding(.horizontal)

            HStack(spacing: 24) {
                Label(String(format: "%.1f G", tracker.gForce), systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                Label(String(format: "max %.1f G", tracker.maxG), systemImage: "bolt.fill")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer(minLength: 24)
        }
    }

    // MARK: Mappa

    private var mapPage: some View {
        Map(position: $camera) {
            UserAnnotation()
            if tracker.points.count > 1 {
                MapPolyline(coordinates: tracker.points.map(\.coordinate))
                    .stroke(.orange, lineWidth: 5)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
    }

    // MARK: Pulsanti

    private var controls: some View {
        VStack(spacing: 10) {
            if tracker.state == .idle {
                if !store.bikes.isEmpty {
                    Picker("Moto", selection: $bikeID) {
                        Text("Nessuna moto").tag(UUID?.none)
                        ForEach(store.bikes) { b in Text(b.name).tag(UUID?.some(b.id)) }
                    }
                    .pickerStyle(.menu)
                }
                if !tracker.isAuthorized && tracker.authorization != .notDetermined {
                    Text("Abilita la posizione in Impostazioni › MotoLog per registrare i giri.")
                        .font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button {
                    tracker.start(bikeID: bikeID)
                } label: {
                    Text("INIZIA GIRO")
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange, in: Capsule())
                        .foregroundStyle(.black)
                }
            } else {
                HStack(spacing: 14) {
                    Button {
                        tracker.state == .recording ? tracker.pause() : tracker.resume()
                    } label: {
                        Label(tracker.state == .recording ? "PAUSA" : "RIPRENDI",
                              systemImage: tracker.state == .recording ? "pause.fill" : "play.fill")
                            .font(.headline.weight(.heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Button { showStopDialog = true } label: {
                        Label("FINE", systemImage: "stop.fill")
                            .font(.headline.weight(.heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .padding(.top, 4)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
