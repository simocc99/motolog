import SwiftUI

@main
struct MotoLogApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var tracker = RideTracker()

    init() {
        UserDefaults.standard.register(defaults: [
            "keepAwake": true, "voice": false, "fallDetection": false, "units": "metric"
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(tracker)
                .tint(.orange)
                .onAppear {
                    tracker.draftHandler = { [store] ride in store.saveDraft(ride) }
                }
        }
    }
}

struct RootView: View {
    @AppStorage("units") private var units = "metric"

    var body: some View {
        TabView {
            RecordView()
                .tabItem { Label("Registra", systemImage: "record.circle") }
            HistoryView()
                .tabItem { Label("Giri", systemImage: "list.bullet.rectangle") }
            StatsView()
                .tabItem { Label("Statistiche", systemImage: "chart.bar.xaxis") }
            GarageView()
                .tabItem { Label("Garage", systemImage: "wrench.and.screwdriver") }
            SettingsView()
                .tabItem { Label("Altro", systemImage: "gearshape") }
        }
        .id(units)   // ricostruisce le viste quando cambiano le unità
    }
}
