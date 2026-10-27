import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var tracker: RideTracker

    @AppStorage("theme") private var theme = "dark"
    @AppStorage("monthlyGoalKm") private var monthlyGoalKm = 300.0
    @AppStorage("units") private var units = "metric"
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("voice") private var voice = false
    @AppStorage("fallDetection") private var fallDetection = false
    @AppStorage("speedAlert") private var speedAlert = false
    @AppStorage("speedLimitKmh") private var speedLimit = 130.0
    @AppStorage("preflight") private var preflight = false
    @AppStorage("saver") private var saver = false
    @AppStorage("breakHours") private var breakHours = 0.0
    @AppStorage("emergencyPhone") private var emergencyPhone = ""

    @State private var exportURL: URL?
    @State private var confirmReset = false
    @State private var calibrated = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Aspetto") {
                    Picker("Tema", selection: $theme) {
                        Label("Scuro", systemImage: "moon.fill").tag("dark")
                        Label("Chiaro", systemImage: "sun.max.fill").tag("light")
                        Label("Automatico", systemImage: "circle.lefthalf.filled").tag("system")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper(value: $monthlyGoalKm, in: 50...5000, step: 50) {
                        LabeledContent("Obiettivo mensile", value: "\(Int(monthlyGoalKm)) km")
                    }
                } header: {
                    Text("Obiettivi")
                } footer: {
                    Text("Lo vedi come anello nella scheda Statistiche.")
                }

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
                    Toggle("Risparmio batteria in marcia", isOn: $saver)
                } header: {
                    Text("Batteria")
                } footer: {
                    Text("Dopo 25 secondi senza toccare lo schermo diventa nero con solo velocità e distanza (tocca per riattivare) e la luminosità scende. Sensori meno frequenti e GPS a precisione ridotta dopo 90 secondi da fermo. Si attiva da solo se l'iPhone è in Risparmio energetico.")
                }

                Section {
                    Picker("Promemoria pausa", selection: $breakHours) {
                        Text("Mai").tag(0.0)
                        Text("Ogni ora").tag(1.0)
                        Text("Ogni 2 ore").tag(2.0)
                        Text("Ogni 3 ore").tag(3.0)
                    }
                    TextField("Telefono contatto di emergenza", text: $emergencyPhone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    Text("Salute e sicurezza")
                } footer: {
                    Text("Se rilevo una caduta, potrai preparare un SMS con la tua posizione per il contatto (lo invii tu con un tocco). Il promemoria ti avvisa dopo le ore di guida scelte.")
                }

                Section {
                    Toggle("Avviso di velocità", isOn: $speedAlert)
                    if speedAlert {
                        Stepper(value: $speedLimit, in: 30...250, step: 10) {
                            LabeledContent("Limite", value: "\(Int(speedLimit)) km/h")
                        }
                    }
                    Toggle("Controllo prima di partire", isOn: $preflight)
                } header: {
                    Text("Sicurezza")
                } footer: {
                    Text("L'avviso vibra e suona quando superi il limite. Il controllo mostra una lista (gomme, freni, luci, guanti e paraschiena…) prima di iniziare il giro.")
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
            .scrollContentBackground(.hidden)
            .background(Theme.background)
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
