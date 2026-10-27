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
        var order: [String] = []
        var dict: [String: [Ride]] = [:]
        for r in filtered {
            let key = r.start.monthYear.capitalized
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(r)
        }
        return order.map { ($0, dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                if store.rides.isEmpty {
                    VStack(spacing: 14) {
                        IconBadge(icon: "road.lanes", size: 64)
                        Text("Nessun giro ancora").font(.title3.weight(.bold))
                        Text("Registra il tuo primo giro dalla scheda Registra.")
                            .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    List {
                        if sort == .date {
                            ForEach(groups, id: \.0) { month, rides in
                                Section {
                                    rows(rides)
                                } header: {
                                    Text(month.uppercased())
                                        .font(.system(size: 12, weight: .bold)).tracking(1.5)
                                        .foregroundStyle(Theme.dim)
                                }
                            }
                        } else {
                            rows(filtered)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Giri")
            .searchable(text: $search, prompt: "Cerca per nome o note")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Ordina", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ rides: [Ride]) -> some View {
        ForEach(rides) { ride in
            ZStack {
                RideCard(ride: ride, bikeName: store.bike(ride.bikeID)?.name)
                NavigationLink {
                    RideDetailView(rideID: ride.id, isSheet: false)
                } label: { EmptyView() }
                .opacity(0)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .swipeActions {
                Button(role: .destructive) {
                    store.rides.removeAll { $0.id == ride.id }
                } label: { Label("Elimina", systemImage: "trash") }
            }
        }
    }
}

private struct RideCard: View {
    let ride: Ride
    let bikeName: String?

    var body: some View {
        HStack(spacing: 14) {
            RouteThumb(track: ride.points)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(ride.name).font(.headline).lineLimit(1)
                    if ride.rating > 0 {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                Text("\(ride.start.dayMonth) · \(ride.start.shortTime)" + (bikeName.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                HStack(spacing: 6) {
                    Chip(text: Fmt.durationLong(ride.elapsed), icon: "clock")
                    Chip(text: "\(Fmt.speedText(ride.maxSpeed))", icon: "speedometer")
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: -2) {
                Text(Fmt.distText(ride.distance))
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gradient)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(Fmt.distUnit).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            }
        }
        .card(padding: 12)
    }
}
