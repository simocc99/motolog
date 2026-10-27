import SwiftUI

@main
struct MotoLogApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var tracker = RideTracker()

    init() {
        UserDefaults.standard.register(defaults: [
            "keepAwake": true, "voice": false, "fallDetection": false, "units": "metric"
        ])
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .heavy)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
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
        .preferredColorScheme(.dark)
        .id(units)   // ricostruisce le viste quando cambiano le unità
    }
}
