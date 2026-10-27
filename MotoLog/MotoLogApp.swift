import SwiftUI

@main
struct MotoLogApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var tracker = RideTracker()
    @Environment(\.scenePhase) private var phase

    init() {
        UserDefaults.standard.register(defaults: [
            "keepAwake": true, "voice": false, "fallDetection": false, "units": "metric",
            "theme": "dark", "monthlyGoalKm": 300.0,
            "speedAlert": false, "saver": false, "speedLimitKmh": 130.0, "preflight": false
        ])
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
            : UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1) }
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
                .onChange(of: phase) { _, p in tracker.setActive(p == .active) }
        }
    }
}

struct RootView: View {
    @AppStorage("units") private var units = "metric"
    @AppStorage("theme") private var theme = "dark"

    private var scheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }

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
        .preferredColorScheme(scheme)
        .id(units)   // ricostruisce le viste quando cambiano le unità
    }
}
