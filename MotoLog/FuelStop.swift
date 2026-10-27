import SwiftUI
import PhotosUI
import Vision

/// Legge litri e importo da una foto del display della pompa o dello scontrino, tutto sul telefono.
enum ReceiptReader {
    struct Result {
        var liters: Double?
        var cost: Double?
    }

    static func read(_ image: UIImage) async -> Result {
        parse(await recognize(image))
    }

    private static func recognize(_ image: UIImage) async -> [String] {
        let src = Cutout.normalized(image, maxSide: 2000)
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            guard let cg = src.cgImage else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["it-IT", "en-US"]
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    private static func numbers(in s: String) -> [Double] {
        guard let re = try? NSRegularExpression(pattern: #"\d{1,4}[.,]\d{1,3}"#) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            Range(m.range, in: s).flatMap { Double(s[$0].replacingOccurrences(of: ",", with: ".")) }
        }
    }

    static func parse(_ lines: [String]) -> Result {
        var liters: [Double] = [], euros: [Double] = [], prices: [Double] = [], all: [Double] = []
        for (i, line) in lines.enumerated() {
            let low = line.lowercased()
            let own = numbers(in: line)
            // Se la riga è solo un'etichetta, il valore sta in quella dopo.
            let target = own.isEmpty && i + 1 < lines.count ? numbers(in: lines[i + 1]) : own
            all += own
            if low.contains("€/l") || low.contains("/l") || low.contains("prezzo") {
                prices += target
            } else if ["litri", "lit", "volume", "quantit", "qta", "ltr"].contains(where: low.contains)
                        || low.range(of: #"\bl\b"#, options: .regularExpression) != nil {
                liters += target
            } else if ["euro", "€", "eur", "totale", "importo"].contains(where: low.contains) {
                euros += target
            }
        }

        func plausible(_ cost: Double, _ l: Double) -> Bool {
            l >= 0.5 && l <= 40 && cost / l >= 1.0 && cost / l <= 3.5
        }
        func pairs(_ cs: [Double], _ ls: [Double]) -> [(cost: Double, liters: Double)] {
            cs.flatMap { c in ls.filter { $0 != c && plausible(c, $0) }.map { (c, $0) } }
        }
        let candidates = pairs(euros, liters) + pairs(all, all)
        let best = candidates.first { p in prices.contains { abs(p.cost / p.liters - $0) < 0.03 } } ?? candidates.first
        if let best { return Result(liters: best.liters, cost: best.cost) }
        return Result(liters: liters.first { $0 <= 40 }, cost: euros.first)
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Pulsanti "Scatta" e "Da foto": compilano litri e importo leggendo l'immagine.
struct ReceiptScanButton: View {
    let onResult: (ReceiptReader.Result) -> Void

    @State private var item: PhotosPickerItem?
    @State private var camera = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 18) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { camera = true } label: { Label("Scatta", systemImage: "camera.viewfinder") }
                }
                PhotosPicker(selection: $item, matching: .images) { Label("Da foto", systemImage: "photo") }
                Spacer()
                if busy { ProgressView() }
            }
            .buttonStyle(.borderless)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self), let ui = UIImage(data: data) { await process(ui) }
                item = nil
            }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in Task { await process(img) } }.ignoresSafeArea()
        }
    }

    @MainActor
    private func process(_ image: UIImage) async {
        busy = true; message = nil
        let r = await ReceiptReader.read(image)
        busy = false
        if r.liters == nil && r.cost == nil {
            message = "Non ho trovato numeri leggibili: riprova più vicino al display o scrivili a mano."
        } else {
            message = "Controlla che litri e importo siano giusti."
            onResult(r)
        }
    }
}

/// Registra un rifornimento mentre sei fermo (o dal chip della benzina).
struct FuelStopSheet: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var tracker: RideTracker
    @Environment(\.dismiss) private var dismiss

    let bike: Bike?
    let station: String?

    @State private var liters = ""
    @State private var cost = ""
    @State private var full = true

    private func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                if let station {
                    Section { Label("Sei fermo a \(station)", systemImage: "fuelpump.fill").foregroundStyle(Theme.accent) }
                }
                Section {
                    ReceiptScanButton { r in
                        if let l = r.liters { liters = String(format: "%.2f", l) }
                        if let c = r.cost { cost = String(format: "%.2f", c) }
                    }
                } footer: {
                    Text("Fotografa il display della pompa o lo scontrino: litri e importo si compilano da soli.")
                }
                Section {
                    TextField("Litri messi", text: $liters).keyboardType(.decimalPad)
                    TextField("Importo (€)", text: $cost).keyboardType(.decimalPad)
                    Toggle("Ho fatto il pieno", isOn: $full)
                } footer: {
                    Text(bike == nil ? "Scegli prima una moto nella schermata Registra." : "Con il pieno la stima riparte dal serbatoio completo; altrimenti aggiungo i litri a quelli stimati.")
                }
            }
            .navigationTitle("Rifornimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        guard let bike else { return }
                        let odo = store.odometer(of: bike) + tracker.distance / 1000
                        store.fuel.append(FuelEntry(bikeID: bike.id, date: Date(), liters: number(liters),
                                                    cost: number(cost), odometerKm: odo, isFull: full))
                        dismiss()
                    }
                    .disabled(bike == nil || number(liters) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
