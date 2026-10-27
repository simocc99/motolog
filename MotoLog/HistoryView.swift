import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: DataStore
    @State private var search = ""
    @State private var sort = Sort.date

    enum Sort: String, CaseIterable, Identifiable {
        case date = "Data", distance = "Distanza", speed = "Velocità max"
        var id: String { rawValue }
    }

    private var filtered: [Ride] {
        var list = store.rides
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search) }
        }
        switch sort {
        case .date: return list.sorted { $0.start > $1.start }
        case .distance: return list.sorted { $0.distance > $1.distance }
        case .speed: return list.sorted { $0.maxSpeed > $1.maxSpeed }
        }
    }

    private var groups: [(String, [Ride])] {
        let fmt = Date.FormatStyle().month(.wide).year()
        var order: [String] = []
        var dict: [String: [Ride]] = [:]
        for r in filtered {
            let key = r.start.formatted(fmt).capitalized
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(r)
        }
        return order.map { ($0, dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.rides.isEmpty {
                    ContentUnavailableView("Nessun giro", systemImage: "road.lanes",
                                           description: Text("Registra il tuo primo giro dalla scheda Registra."))
                } else if sort == .date {
                    List {
                        ForEach(groups, id: \.0) { month, rides in
                            Section(month) { rows(rides) }
                        }
                    }
                } else {
                    List { rows(filtered) }
                }
            }
            .navigationTitle("Giri")
            .searchable(text: $search, prompt: "Cerca per nome o note")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Ordina", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ rides: [Ride]) -> some View {
        ForEach(rides) { ride in
            NavigationLink {
                RideDetailView(rideID: ride.id, isSheet: false)
            } label: {
                RideRow(ride: ride, bikeName: store.bike(ride.bikeID)?.name)
            }
        }
        .onDelete { offsets in
            let ids = offsets.map { rides[$0].id }
            store.rides.removeAll { ids.contains($0.id) }
        }
    }
}

private struct RideRow: View {
    let ride: Ride
    let bikeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ride.name).font(.headline)
                Spacer()
                if ride.rating > 0 {
                    HStack(spacing: 1) {
                        Image(systemName: "star.fill")
                        Text("\(ride.rating)")
                    }
                    .font(.caption).foregroundStyle(.yellow)
                }
            }
            Text("\(ride.start.shortDate) · \(ride.start.shortTime)" + (bikeName.map { " · \($0)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label("\(Fmt.distText(ride.distance)) \(Fmt.distUnit)", systemImage: "arrow.triangle.swap")
                Label(Fmt.durationLong(ride.elapsed), systemImage: "clock")
                Label("\(Fmt.speedText(ride.maxSpeed)) \(Fmt.speedUnit)", systemImage: "speedometer")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
        }
        .padding(.vertical, 3)
    }
}
