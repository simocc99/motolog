import SwiftUI

struct GarageView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                if store.bikes.isEmpty {
                    VStack(spacing: 14) {
                        IconBadge(icon: "wrench.and.screwdriver", size: 64)
                        Text("Garage vuoto").font(.title3.weight(.bold))
                        Text("Aggiungi la tua moto per tenere traccia di chilometri, tagliandi, carburante e scadenze.")
                            .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        Button { showAdd = true } label: {
                            Text("Aggiungi moto").font(.headline).foregroundStyle(.black)
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .background(Theme.gradient, in: Capsule())
                        }
                    }
                    .padding(40)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(store.bikes) { bike in
                                NavigationLink {
                                    BikeDetailView(bikeID: bike.id)
                                } label: { bikeCard(bike) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Garage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddBikeSheet() }
        }
    }
}

extension GarageView {
    fileprivate func bikeCard(_ bike: Bike) -> some View {
        let sub = [bike.brand, bike.year > 0 ? String(bike.year) : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let due = store.maintenance.filter { $0.bikeID == bike.id }
            .filter { store.odometer(of: bike) - $0.lastDoneKm >= $0.intervalKm }.count
        return HStack(spacing: 14) {
            IconBadge(icon: "scooter", size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(bike.name).font(.title3.weight(.bold))
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Theme.dim) }
                if due > 0 { Chip(text: "\(due) da fare", icon: "exclamationmark.triangle.fill", tint: .orange) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: -2) {
                Text(Fmt.distText(store.odometer(of: bike) * 1000))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gradient)
                Text(Fmt.distUnit).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            }
        }
        .card()
    }
}

private struct AddBikeSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var year = ""
    @State private var km = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome (es. Tracer 9)", text: $name)
                TextField("Marca", text: $brand)
                TextField("Anno", text: $year).keyboardType(.numberPad)
                TextField("Chilometri attuali", text: $km).keyboardType(.decimalPad)
            }
            .navigationTitle("Nuova moto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        store.bikes.append(Bike(name: name, brand: brand, year: Int(year) ?? 0,
                                                initialKm: Double(km.replacingOccurrences(of: ",", with: ".")) ?? 0))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct BikeDetailView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let bikeID: UUID

    @State private var sheet: Sheet?
    @State private var confirmDelete = false

    enum Sheet: String, Identifiable {
        case maintenance, fuel, deadline
        var id: String { rawValue }
    }

    private var bike: Bike? { store.bikes.first { $0.id == bikeID } }

    var body: some View {
        Group {
            if let bike {
                content(bike)
            } else {
                ContentUnavailableView("Moto non trovata", systemImage: "questionmark.folder")
            }
        }
    }

    private func content(_ bike: Bike) -> some View {
        let odo = store.odometer(of: bike)
        let items = store.maintenance.filter { $0.bikeID == bike.id }
        let fuel = store.fuel.filter { $0.bikeID == bike.id }.sorted { $0.date > $1.date }
        let deadlines = store.deadlines.filter { $0.bikeID == bike.id }.sorted { $0.date < $1.date }
        let spent = fuel.reduce(0) { $0 + $1.cost }
        let rides = store.rides.filter { $0.bikeID == bike.id }

        return List {
            Section {
                LabeledContent("Contachilometri", value: "\(Fmt.distText(odo * 1000)) \(Fmt.distUnit)")
                LabeledContent("Giri registrati", value: "\(rides.count)")
                if let c = store.consumption(for: bike) {
                    LabeledContent("Consumo medio", value: String(format: "%.1f L/100km", c))
                }
                if spent > 0 { LabeledContent("Spesa carburante", value: String(format: "%.2f €", spent)) }
            }

            Section("Manutenzione") {
                ForEach(items) { item in
                    let done = odo - item.lastDoneKm
                    let remaining = item.intervalKm - done
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.title).font(.headline)
                            Spacer()
                            Text(remaining >= 0 ? "tra \(Int(remaining)) km" : "scaduto da \(Int(-remaining)) km")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(remaining < 0 ? .red : (remaining < item.intervalKm * 0.1 ? .orange : .secondary))
                        }
                        ProgressView(value: min(max(done / item.intervalKm, 0), 1))
                            .tint(remaining < 0 ? .red : (remaining < item.intervalKm * 0.1 ? .orange : .green))
                    }
                    .swipeActions(edge: .leading) {
                        Button("Fatto") {
                            if let i = store.maintenance.firstIndex(where: { $0.id == item.id }) {
                                store.maintenance[i].lastDoneKm = odo
                            }
                        }
                        .tint(.green)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { items[$0].id }
                    store.maintenance.removeAll { ids.contains($0.id) }
                }
                Button { sheet = .maintenance } label: { Label("Aggiungi intervento", systemImage: "plus") }
            }

            Section("Scadenze") {
                ForEach(deadlines) { d in
                    HStack {
                        Text(d.title)
                        Spacer()
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: d.date).day ?? 0
                        Text(days < 0 ? "scaduta" : "\(d.date.shortDate) (\(days) g)")
                            .font(.caption).foregroundStyle(days < 0 ? .red : (days < 30 ? .orange : .secondary))
                    }
                }
                .onDelete { offsets in
                    for i in offsets { Notifier.cancel(deadlines[i]) }
                    let ids = offsets.map { deadlines[$0].id }
                    store.deadlines.removeAll { ids.contains($0.id) }
                }
                Button { sheet = .deadline } label: { Label("Aggiungi scadenza", systemImage: "plus") }
            }

            Section("Rifornimenti") {
                ForEach(fuel) { f in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(f.date.shortDate)
                            Text("\(Int(f.odometerKm)) km").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(String(format: "%.2f L", f.liters))
                            Text(String(format: "%.2f €", f.cost)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { fuel[$0].id }
                    store.fuel.removeAll { ids.contains($0.id) }
                }
                Button { sheet = .fuel } label: { Label("Registra rifornimento", systemImage: "fuelpump") }
            }

            Section {
                Button("Elimina moto", role: .destructive) { confirmDelete = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(bike.name)
        .sheet(item: $sheet) { s in
            switch s {
            case .maintenance: AddMaintenanceSheet(bike: bike, odometer: odo)
            case .fuel: AddFuelSheet(bike: bike, odometer: odo)
            case .deadline: AddDeadlineSheet(bike: bike)
            }
        }
        .confirmationDialog("Eliminare \(bike.name) e tutti i suoi dati?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                store.deleteBike(bike)
                dismiss()
            }
        }
    }
}

private func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

private struct AddMaintenanceSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let bike: Bike
    let odometer: Double
    @State private var title = ""
    @State private var interval = ""

    private let presets = ["Cambio olio", "Filtro aria", "Catena e corone", "Pastiglie freno", "Pneumatici", "Liquido freni", "Tagliando"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Intervento") {
                    TextField("Nome", text: $title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(presets, id: \.self) { p in
                                Button(p) { title = p }.buttonStyle(.bordered).font(.caption)
                            }
                        }
                    }
                }
                Section("Ogni quanti km?") {
                    TextField("es. 6000", text: $interval).keyboardType(.numberPad)
                }
                Text("Il conteggio parte dai chilometri attuali (\(Int(odometer)) km).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Nuovo intervento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        store.maintenance.append(MaintenanceItem(bikeID: bike.id, title: title,
                                                                 intervalKm: number(interval), lastDoneKm: odometer))
                        dismiss()
                    }
                    .disabled(title.isEmpty || number(interval) <= 0)
                }
            }
        }
    }
}

private struct AddFuelSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let bike: Bike
    let odometer: Double
    @State private var liters = ""
    @State private var cost = ""
    @State private var odo = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Data", selection: $date, displayedComponents: .date)
                TextField("Litri", text: $liters).keyboardType(.decimalPad)
                TextField("Costo (€)", text: $cost).keyboardType(.decimalPad)
                TextField("Chilometri moto (\(Int(odometer)))", text: $odo).keyboardType(.decimalPad)
                Text("Per un calcolo corretto del consumo, fai sempre il pieno.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Rifornimento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        store.fuel.append(FuelEntry(bikeID: bike.id, date: date, liters: number(liters),
                                                    cost: number(cost), odometerKm: odo.isEmpty ? odometer : number(odo)))
                        dismiss()
                    }
                    .disabled(number(liters) <= 0)
                }
            }
        }
    }
}

private struct AddDeadlineSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let bike: Bike
    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()

    private let presets = ["Assicurazione", "Bollo", "Revisione", "Tagliando", "Patente"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titolo", text: $title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(presets, id: \.self) { p in
                            Button(p) { title = p }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                }
                DatePicker("Scadenza", selection: $date, displayedComponents: .date)
                Text("Riceverai una notifica 7 giorni prima e il giorno stesso.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Nuova scadenza")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let d = Deadline(bikeID: bike.id, title: title, date: date)
                        store.deadlines.append(d)
                        Notifier.schedule(d)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
