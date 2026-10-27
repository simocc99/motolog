import SwiftUI
import MapKit

final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ text: String) {
        if text.trimmingCharacters(in: .whitespaces).count < 2 { results = [] }
        completer.queryFragment = text
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(6))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

/// Tempo di arrivo: percorso di Apple Maps corretto con il ritmo reale che tieni con la moto scelta.
struct ETAView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var tracker: RideTracker

    @StateObject private var search = PlaceSearch()
    @State private var query = ""
    @State private var bikeID: UUID?
    @State private var destination: MKMapItem?
    @State private var route: MKRoute?
    @State private var loading = false
    @State private var failed = false

    private var bike: Bike? { store.bike(bikeID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if store.bikes.count > 1 { bikePicker }
                searchCard
                if loading {
                    ProgressView("Calcolo il percorso…").padding(.top, 20)
                } else if failed {
                    Text("Non riesco a calcolare il percorso. Controlla la connessione e che la posizione sia attiva.")
                        .font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                } else if let route, let destination {
                    result(route, destination)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Tempo di arrivo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if bikeID == nil { bikeID = store.bikes.first?.id }
            if !tracker.isAuthorized { tracker.requestPermission() }
        }
    }

    private var bikePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.bikes) { b in
                    Button { bikeID = b.id } label: {
                        Chip(text: b.name, icon: "scooter", tint: b.id == bikeID ? Theme.accent : Theme.dim)
                    }
                }
            }
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("Dove vuoi andare?", text: $query)
                    .submitLabel(.search)
                    .onChange(of: query) { _, v in
                        if destination == nil || v != destination?.name { search.update(v) }
                    }
                if !query.isEmpty {
                    Button { query = ""; destination = nil; route = nil; search.update("") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim)
                    }
                }
            }
            if route == nil, !search.results.isEmpty {
                Divider()
                ForEach(search.results, id: \.self) { c in
                    Button { pick(c) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title).font(.subheadline.weight(.semibold))
                            if !c.subtitle.isEmpty { Text(c.subtitle).font(.caption).foregroundStyle(Theme.dim) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func result(_ route: MKRoute, _ dest: MKMapItem) -> some View {
        let km = route.distance / 1000
        let apple = route.expectedTravelTime
        let appleSpeed = route.distance / max(apple, 1)
        let typical = store.typicalSpeed(bikeID: bikeID)
        // Il ritmo personale corregge Apple, ma senza stravolgerla: tra 70% e 140% della sua velocità.
        let speed = typical.map { min(max($0, appleSpeed * 0.7), appleSpeed * 1.4) } ?? appleSpeed
        let mine = route.distance / speed
        let arrival = Date().addingTimeInterval(mine)

        Map(initialPosition: .rect(route.polyline.boundingMapRect.insetBy(dx: -route.polyline.boundingMapRect.width * 0.25,
                                                                          dy: -route.polyline.boundingMapRect.height * 0.25))) {
            MapPolyline(route.polyline).stroke(Theme.accent, lineWidth: 5)
            Marker(dest.name ?? "Arrivo", coordinate: dest.placemark.coordinate).tint(.red)
            UserAnnotation()
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)

        VStack(spacing: 4) {
            Text(Fmt.durationLong(mine))
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.gradient)
            Text("Arrivo verso le \(arrival.shortTime)" + (bike.map { " con \($0.name)" } ?? ""))
                .font(.subheadline).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .card()

        if route.hasHighways {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: "exclamationmark.shield.fill", tint: .orange, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tratti autostradali").font(.headline)
                    Text("Il percorso passa in autostrada: indossa guanti e paraschiena." + (route.hasTolls ? " Ci sono anche pedaggi." : ""))
                        .font(.subheadline).foregroundStyle(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }

        VStack(spacing: 10) {
            row("Distanza", "\(Fmt.distText(route.distance)) \(Fmt.distUnit)")
            row("Stima di Apple Maps", Fmt.durationLong(apple))
            if let typical {
                row("Il tuo ritmo medio", "\(Fmt.speedText(typical)) \(Fmt.speedUnit)")
            } else {
                Text("Servono almeno 3 giri registrati per correggere la stima con il tuo ritmo: per ora vale quella di Apple.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            if let bike, let c = store.consumption(for: bike) {
                row("Carburante necessario", String(format: "%.1f L", km * c / 100))
                if let left = store.remainingRange(for: bike) {
                    if left < km {
                        warning("Autonomia stimata \(Int(max(left, 0))) km: ti serve un rifornimento prima di arrivare.")
                    } else {
                        row("Autonomia a destinazione", "\(Int(left - km)) km")
                    }
                }
            }
        }
        .card()

        Button {
            dest.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } label: {
            Label("Avvia navigazione in Mappe", systemImage: "location.north.fill")
                .font(.headline.weight(.heavy)).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Theme.gradient, in: Capsule())
        }
        Text("Apple Maps non conosce la tua moto: il tempo è la sua stima per le auto, corretta con la velocità che hai tenuto nei tuoi giri.")
            .font(.caption2).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "fuelpump.fill")
            .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pick(_ c: MKLocalSearchCompletion) {
        loading = true; failed = false; route = nil
        search.update("")
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task {
            do {
                guard let item = try await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start().mapItems.first else {
                    throw CocoaError(.fileNoSuchFile)
                }
                destination = item
                query = item.name ?? c.title
                let req = MKDirections.Request()
                req.source = MKMapItem.forCurrentLocation()
                req.destination = item
                req.transportType = .automobile
                route = try await MKDirections(request: req).calculate().routes.first
                failed = route == nil
            } catch {
                failed = true
            }
            loading = false
        }
    }
}
