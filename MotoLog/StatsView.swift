import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var store: DataStore
    @State private var period = Period.month
    @AppStorage("monthlyGoalKm") private var monthlyGoalKm = 300.0

    enum Period: String, CaseIterable, Identifiable {
        case week = "Settimana", month = "Mese", year = "Anno", all = "Sempre"
        var id: String { rawValue }
    }

    private struct Bucket: Identifiable {
        let id: Date
        let km: Double
    }

    private var rides: [Ride] {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .week: return store.rides.filter { $0.start >= cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))! }
        case .month: return store.rides.filter { $0.start >= cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now))! }
        case .year: return store.rides.filter { $0.start >= cal.date(byAdding: .month, value: -11, to: cal.startOfDay(for: now))! }
        case .all: return store.rides
        }
    }

    private var byDay: Bool { period == .week || period == .month }

    private var buckets: [Bucket] {
        let cal = Calendar.current
        var dict: [Date: Double] = [:]
        for r in rides {
            let key = byDay ? cal.startOfDay(for: r.start)
                            : cal.dateInterval(of: .month, for: r.start)!.start
            dict[key, default: 0] += Fmt.dist(r.distance)
        }
        return dict.map { Bucket(id: $0.key, km: $0.value) }.sorted { $0.id < $1.id }
    }

    /// Intervallo dell'asse X: mostra il periodo intero anche con pochi dati.
    private var domain: ClosedRange<Date> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: today)!
        func monthStart(_ monthsAgo: Int) -> Date {
            cal.dateInterval(of: .month, for: cal.date(byAdding: .month, value: -monthsAgo, to: today)!)!.start
        }
        let start: Date
        switch period {
        case .week: start = cal.date(byAdding: .day, value: -6, to: today)!
        case .month: start = cal.date(byAdding: .day, value: -29, to: today)!
        case .year: start = monthStart(11)
        case .all: start = min(buckets.first?.id ?? today, monthStart(5))
        }
        return start...end
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Periodo", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    levelCard
                    totals
                    chart
                    records
                    bikeBreakdown
                    let a = Achievements.compute(store.rides)
                    linkRow(icon: "medal.fill", tint: .yellow, title: "Classifica dei giri",
                            detail: "i tuoi migliori") { RankingView() }
                    linkRow(icon: "map.fill", tint: Theme.accent, title: "Mappa dei giri",
                            detail: "tutti i percorsi") { AllRidesMapView() }
                    linkRow(icon: "trophy.fill", tint: .yellow, title: "Traguardi",
                            detail: "\(a.filter(\.unlocked).count)/\(a.count)") { AchievementsView() }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Statistiche")
        }
    }

    private func linkRow<D: View>(icon: String, tint: Color, title: String, detail: String,
                                  @ViewBuilder destination: () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                IconBadge(icon: icon, tint: tint, size: 34)
                Text(title).font(.headline)
                Spacer()
                Text(detail).font(.subheadline).foregroundStyle(Theme.dim)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.dim)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    /// Livello da motociclista, serie settimanale e obiettivo mensile.
    private var levelCard: some View {
        let km = store.rides.reduce(0) { $0 + $1.distance } / 1000
        let level = RiderLevel.level(forKm: km)
        let cal = Calendar.current
        let monthKm = store.rides.filter { cal.isDate($0.start, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.distance } / 1000
        let goal = max(monthlyGoalKm, 1)
        let streak = RiderLevel.weekStreak(store.rides)
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.fill, lineWidth: 10)
                Circle().trim(from: 0, to: min(monthKm / goal, 1))
                    .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("\(Int(monthKm))").font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("/ \(Int(goal)) km").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text("LIVELLO").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Theme.dim)
                Text(level.name).font(.system(size: 24, weight: .heavy, design: .rounded))
                ProgressView(value: level.progress).tint(Theme.accent)
                if let next = level.next, let nextKm = level.nextKm {
                    Text("\(next) a \(Int(nextKm)) km")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
                if streak > 0 {
                    Chip(text: "\(streak) \(streak == 1 ? "settimana" : "settimane") di fila", icon: "flame.fill", tint: Theme.accent)
                }
            }
        }
        .card()
    }

    private var totals: some View {
        let dist = rides.reduce(0) { $0 + $1.distance }
        let time = rides.reduce(0) { $0 + $1.elapsed }
        let moving = rides.reduce(0) { $0 + $1.movingTime }
        let climb = rides.reduce(0) { $0 + $1.elevationGain }
        return VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DISTANZA TOTALE")
                    .font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Theme.dim)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.distText(dist))
                        .font(.system(size: 60, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.gradient)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(Fmt.distUnit).font(.title3.weight(.semibold)).foregroundStyle(Theme.dim)
                }
                Text("\(rides.count) \(rides.count == 1 ? "giro" : "giri") · \(Fmt.durationLong(time)) in sella")
                    .font(.subheadline).foregroundStyle(Theme.dim)
            }
            .card(padding: 18)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "Media", value: Fmt.speedText(moving > 0 ? dist / moving : 0), unit: Fmt.speedUnit, icon: "speedometer")
                StatTile(title: "Dislivello +", value: Fmt.altText(climb), unit: Fmt.altUnit, icon: "mountain.2.fill")
                StatTile(title: "Giro medio", value: rides.isEmpty ? "0" : Fmt.distText(dist / Double(rides.count)), unit: Fmt.distUnit, icon: "divide")
                StatTile(title: "In movimento", value: Fmt.durationLong(moving), icon: "figure.walk.motion")
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Fmt.distUnit.uppercased()) PERCORSI").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if buckets.isEmpty {
                Text("Nessun dato in questo periodo").foregroundStyle(.secondary).frame(height: 120)
            } else {
                Chart(buckets) { b in
                    BarMark(x: .value("Data", b.id, unit: byDay ? .day : .month),
                            y: .value(Fmt.distUnit, b.km))
                    .foregroundStyle(Theme.gradient)
                    .cornerRadius(4)
                }
                .chartXScale(domain: domain)
                .frame(height: 180)
            }
        }
        .card()
    }

    private var records: some View {
        let r = rides
        let fastest = r.max { $0.maxSpeed < $1.maxSpeed }
        let longest = r.max { $0.distance < $1.distance }
        let leanest = r.max { $0.maxLean < $1.maxLean }
        let highest = r.max { $0.maxAltitude < $1.maxAltitude }
        let biggestG = r.max { $0.maxG < $1.maxG }
        return VStack(alignment: .leading, spacing: 12) {
            Text("RECORD").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if r.isEmpty {
                Text("Registra dei giri per vedere i tuoi record.").foregroundStyle(.secondary)
            } else {
                RecordRow(icon: "gauge.high", title: "Velocità massima",
                          value: "\(Fmt.speedText(fastest?.maxSpeed ?? 0)) \(Fmt.speedUnit)", ride: fastest)
                RecordRow(icon: "arrow.triangle.swap", title: "Giro più lungo",
                          value: "\(Fmt.distText(longest?.distance ?? 0)) \(Fmt.distUnit)", ride: longest)
                RecordRow(icon: "rotate.right.fill", title: "Piega massima",
                          value: String(format: "%.0f°", leanest?.maxLean ?? 0), ride: leanest)
                RecordRow(icon: "mountain.2.fill", title: "Quota massima",
                          value: "\(Fmt.altText(highest?.maxAltitude ?? 0)) \(Fmt.altUnit)", ride: highest)
                RecordRow(icon: "bolt.fill", title: "G massimi",
                          value: String(format: "%.1f G", biggestG?.maxG ?? 0), ride: biggestG)
            }
        }
        .card()
    }

    @ViewBuilder
    private var bikeBreakdown: some View {
        let items = store.bikes.map { bike in
            (bike, rides.filter { $0.bikeID == bike.id }.reduce(0) { $0 + $1.distance })
        }.filter { $0.1 > 0 }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("PER MOTO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Chart(items, id: \.0.id) { item in
                    SectorMark(angle: .value("Distanza", item.1), innerRadius: .ratio(0.6))
                        .foregroundStyle(by: .value("Moto", item.0.name))
                }
                .frame(height: 170)
            }
            .card()
        }
    }
}

private struct RecordRow: View {
    let icon: String
    let title: String
    let value: String
    let ride: Ride?

    var body: some View {
        HStack {
            IconBadge(icon: icon, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                if let ride {
                    Text("\(ride.name) · \(ride.start.shortDate)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value).font(.headline).monospacedDigit()
        }
    }
}

struct AchievementsView: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        let list = Achievements.compute(store.rides)
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(list) { a in
                    VStack(spacing: 8) {
                        Image(systemName: a.icon)
                            .font(.system(size: 30))
                            .foregroundStyle(a.unlocked ? Color.yellow : Color.gray.opacity(0.5))
                            .frame(height: 36)
                        Text(a.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                        Text(a.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        ProgressView(value: a.progress).tint(a.unlocked ? .yellow : .orange)
                    }
                    .frame(maxWidth: .infinity)
                    .card()
                    .opacity(a.unlocked ? 1 : 0.7)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Traguardi")
    }
}
