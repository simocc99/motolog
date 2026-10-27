import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var tracker: RideTracker

    @AppStorage("units") private var units = "metric"
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("voice") private var voice = false
    @AppStorage("fallDetection") private var fallDetection = false

    @State private var exportURL: URL?
    @State private var confirmReset = false
    @State private var calibrated = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Unità di misura") {
                    Picker("Sistema", selection: $units) {
                        Text("Metrico (km, km/h)").tag("metric")
                        Text("Imperiale (mi, mph)").tag("imperial")
                    }
                }

                Section("Durante il giro") {
                    Toggle("Tieni lo schermo acceso", isOn: $keepAwake)
                    Toggle("Annunci vocali ogni chilometro", isOn: $voice)
                    Toggle("Rilevamento caduta", isOn: $fallDetection)
                }
                Section {
                    Button(calibrated ? "Calibrato ✓" : "Calibra angolo di piega") {
                        tracker.calibrateLean()
                        calibrated = true
                    }
                } footer: {
                    Text("Fissa il telefono in verticale sul manubrio, con la moto dritta, poi tocca Calibra. Se tieni il telefono in tasca la piega non è affidabile.")
                }

                Section("Dati") {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Esporta tutti i dati (JSON)", systemImage: "square.and.arrow.up") }
                    }
                    Button("Elimina tutti i dati", role: .destructive) { confirmReset = true }
                }

                Section("Info") {
                    LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Giri salvati", value: "\(store.rides.count)")
                }
            }
            .navigationTitle("Altro")
            .onAppear(perform: prepareExport)
            .onChange(of: store.rides.count) { _, _ in prepareExport() }
            .confirmationDialog("Eliminare tutti i giri, le moto e le scadenze?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Elimina tutto", role: .destructive) { store.resetAll(); prepareExport() }
            }
        }
    }

    private struct Export: Codable {
        var rides: [Ride]
        var bikes: [Bike]
        var maintenance: [MaintenanceItem]
        var fuel: [FuelEntry]
        var deadlines: [Deadline]
    }

    private func prepareExport() {
        let payload = Export(rides: store.rides, bikes: store.bikes, maintenance: store.maintenance,
                             fuel: store.fuel, deadlines: store.deadlines)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(payload) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MotoLog-backup.json")
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }
}
