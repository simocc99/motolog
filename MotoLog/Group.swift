import SwiftUI
import MapKit
import AVFoundation

struct Rider: Identifiable {
    let id: String
    var name: String
    var coordinate: CLLocationCoordinate2D
    var speed: Double          // m/s
    var age: Double            // secondi dall'ultimo aggiornamento
    var isMe = false
}

/// Gruppo di moto: posizioni sulla mappa e avviso se qualcuno resta indietro.
/// Usa il server in `server/` (WebSocket) oppure una demo con piloti simulati.
@MainActor
final class GroupSession: ObservableObject {
    @Published private(set) var riders: [Rider] = []
    @Published private(set) var active = false
    @Published private(set) var connected = false
    @Published private(set) var demo = false
    @Published private(set) var code = ""
    @Published private(set) var behind: [(rider: Rider, gap: Double)] = []
    @Published var gapLimit: Double = UserDefaults.standard.object(forKey: "groupGap") as? Double ?? 500 {
        didSet { UserDefaults.standard.set(gapLimit, forKey: "groupGap"); recompute() }
    }

    let myID: String = {
        if let s = UserDefaults.standard.string(forKey: "groupID") { return s }
        let s = UUID().uuidString
        UserDefaults.standard.set(s, forKey: "groupID")
        return s
    }()
    private(set) var myName = "Io"

    private var task: URLSessionWebSocketTask?
    private var serverURL: URL?
    private var me: CLLocation?
    private var lastSent = Date.distantPast
    private var remote: [Rider] = []
    private var announced: [String: Date] = [:]
    private var demoTimer: Timer?
    private var demoStep = 0
    private var retry = 0
    private let synth = AVSpeechSynthesizer()

    // MARK: Entrare e uscire

    func join(server: String, code: String, name: String) -> Bool {
        let trimmed = server.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), ["ws", "wss"].contains(url.scheme ?? "") else { return false }
        stop()
        serverURL = url
        self.code = code.uppercased()
        myName = name.isEmpty ? "Io" : name
        demo = false
        active = true
        connect()
        return true
    }

    func startDemo(name: String) {
        stop()
        code = "DEMO"
        myName = name.isEmpty ? "Io" : name
        demo = true
        active = true
        connected = true
        demoStep = 0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.demoTick() }
        }
    }

    func stop() {
        send(["type": "leave"])
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        demoTimer?.invalidate(); demoTimer = nil
        active = false; connected = false; demo = false
        remote = []; riders = []; behind = []
        retry = 0
    }

    // MARK: Rete

    private func connect() {
        guard let url = serverURL, active, !demo else { return }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        send(["type": "join", "code": code, "id": myID, "name": myName])
        connected = true
        listen(t)
    }

    private func listen(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch result {
                case .success(let msg):
                    self.retry = 0
                    if case .string(let text) = msg { self.handle(text) }
                    self.listen(t)
                case .failure:
                    self.connected = false
                    self.reconnect()
                }
            }
        }
    }

    /// Se cade la rete riprova dopo 2, 4, 8… secondi (massimo 30), senza consumare batteria a vuoto.
    private func reconnect() {
        guard active, !demo else { return }
        retry += 1
        let delay = min(30, pow(2, Double(retry)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.active, !self.connected else { return }
            self.connect()
        }
    }

    private func send(_ obj: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "roster", let list = obj["riders"] as? [[String: Any]] else { return }
        remote = list.compactMap { r in
            guard let id = r["id"] as? String, id != myID,
                  let lat = r["lat"] as? Double, let lon = r["lon"] as? Double else { return nil }
            return Rider(id: id, name: r["name"] as? String ?? "Pilota",
                         coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                         speed: r["speed"] as? Double ?? 0, age: r["age"] as? Double ?? 0)
        }
        recompute()
    }

    // MARK: La mia posizione

    /// Invio al massimo ogni 5 secondi (ogni 10 se la batteria è sotto il 20%).
    func updateMe(_ loc: CLLocation, lowBattery: Bool) {
        me = loc
        guard active else { return }
        if demo { recompute(); return }
        let every: TimeInterval = lowBattery ? 10 : 5
        guard connected, Date().timeIntervalSince(lastSent) >= every else { return }
        lastSent = Date()
        send(["type": "pos", "lat": loc.coordinate.latitude, "lon": loc.coordinate.longitude, "speed": max(loc.speed, 0)])
    }

    // MARK: Chi è indietro

    private func recompute() {
        var all = remote.filter { $0.age < 90 }
        if let me {
            all.append(Rider(id: myID, name: myName, coordinate: me.coordinate, speed: max(me.speed, 0), age: 0, isMe: true))
        }
        riders = all

        // Indietro = nessun compagno entro il limite scelto.
        var out: [(rider: Rider, gap: Double)] = []
        if all.count > 1 {
            for r in all where !r.isMe {
                let here = CLLocation(latitude: r.coordinate.latitude, longitude: r.coordinate.longitude)
                let nearest = all.filter { $0.id != r.id }.map {
                    here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
                }.min() ?? 0
                if nearest > gapLimit { out.append((r, nearest)) }
            }
        }
        behind = out
        announce()
    }

    private func announce() {
        guard UserDefaults.standard.bool(forKey: "voice") else { return }
        for b in behind where Date().timeIntervalSince(announced[b.rider.id] ?? .distantPast) > 90 {
            announced[b.rider.id] = Date()
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try? session.setActive(true)
            let u = AVSpeechUtterance(string: "\(b.rider.name) è rimasto indietro.")
            u.voice = AVSpeechSynthesisVoice(language: "it-IT")
            synth.speak(u)
        }
    }

    // MARK: Demo

    /// Tre piloti simulati attorno a te; Luca rallenta e resta sempre più indietro.
    private func demoTick() {
        guard let me else { return }
        demoStep += 1
        func shifted(_ north: Double, _ east: Double) -> CLLocationCoordinate2D {
            let dLat = north / 111_320
            let dLon = east / (111_320 * cos(me.coordinate.latitude * .pi / 180))
            return CLLocationCoordinate2D(latitude: me.coordinate.latitude + dLat, longitude: me.coordinate.longitude + dLon)
        }
        let s = Double(demoStep)
        remote = [
            Rider(id: "demo-1", name: "Marco", coordinate: shifted(-90, 25), speed: 21, age: 1),
            Rider(id: "demo-2", name: "Giulia", coordinate: shifted(260, -30), speed: 24, age: 2),
            Rider(id: "demo-3", name: "Luca", coordinate: shifted(-120 - s * 18, 15), speed: 14, age: 1)
        ]
        recompute()
    }
}

// MARK: Schermata

struct GroupView: View {
    @EnvironmentObject var group: GroupSession
    @EnvironmentObject var tracker: RideTracker
    @AppStorage("groupServer") private var server = ""
    @AppStorage("groupName") private var name = ""
    @AppStorage("groupCode") private var code = ""
    @State private var invalid = false

    var body: some View {
        Group {
            if group.active { activeView } else { setupView }
        }
        .background(Theme.background)
        .navigationTitle("Gruppo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: tracker.currentLocation) { _, l in push(l) }
        .onAppear { push(tracker.currentLocation) }
        .onChange(of: group.active) { _, on in if on { push(tracker.currentLocation) } }
    }

    private func push(_ l: CLLocation?) {
        if let l { group.updateMe(l, lowBattery: tracker.batteryLevel >= 0 && tracker.batteryLevel < 0.2) }
    }

    // MARK: Prima di entrare

    private var setupView: some View {
        Form {
            Section {
                TextField("Il tuo nome", text: $name)
                HStack {
                    TextField("Codice del gruppo", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Nuovo") { code = Self.randomCode() }.buttonStyle(.borderless)
                }
                TextField("Server (ws://…:8787)", text: $server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                if invalid { Text("Indirizzo non valido: deve iniziare con ws:// o wss://").font(.caption).foregroundStyle(.red) }
                Button {
                    invalid = !group.join(server: server, code: code, name: name)
                } label: { Label("Entra nel gruppo", systemImage: "person.3.fill") }
                    .disabled(code.count < 3 || server.isEmpty)
            } header: {
                Text("Gruppo reale")
            } footer: {
                Text("Serve il piccolo server della cartella server/ (basta `node server.js` su un PC). Tutti usano lo stesso codice e lo stesso indirizzo. Istruzioni nel file server/README.md del progetto.")
            }
            Section {
                Button { group.startDemo(name: name) } label: { Label("Prova con piloti simulati", systemImage: "play.circle") }
            } footer: {
                Text("Senza server: tre piloti finti ti girano attorno e uno resta sempre più indietro, per vedere come funziona l'avviso.")
            }
            Section {
                if let c = tracker.currentLocation?.coordinate {
                    ShareLink(item: "Sono qui: https://maps.apple.com/?ll=\(c.latitude),\(c.longitude)") {
                        Label("Condividi dove sono", systemImage: "location.fill")
                    }
                } else {
                    Label("Aspetto la posizione GPS…", systemImage: "location").foregroundStyle(Theme.dim)
                }
            } footer: {
                Text("Manda un link di Apple Maps con la tua posizione di adesso: funziona anche senza server.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Dentro il gruppo

    private var activeView: some View {
        VStack(spacing: 0) {
            Map(position: .constant(.automatic)) {
                ForEach(group.riders) { r in
                    Annotation(r.name, coordinate: r.coordinate) {
                        let isBehind = group.behind.contains { $0.rider.id == r.id }
                        Text(String(r.name.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(r.isMe ? Theme.accent : (isBehind ? Color.red : Color.blue), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 280)

            List {
                Section {
                    HStack {
                        Chip(text: group.demo ? "DEMO" : (group.connected ? "COLLEGATO" : "RICONNESSIONE…"),
                             icon: group.connected ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark",
                             tint: group.connected ? .green : .orange)
                        Text("Codice \(group.code)").font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
                        Spacer()
                        if !group.demo {
                            ShareLink(item: "Entra nel mio gruppo MotoLog: codice \(group.code), server \(server)") {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    Stepper(value: $group.gapLimit, in: 200...3000, step: 100) {
                        LabeledContent("Avviso se più lontano di", value: NavText.distance(group.gapLimit))
                    }
                }
                Section("Piloti") {
                    ForEach(group.riders.sorted { $0.isMe && !$1.isMe }) { r in
                        let gap = group.behind.first { $0.rider.id == r.id }?.gap
                        HStack {
                            Image(systemName: r.isMe ? "location.fill" : "person.fill").foregroundStyle(r.isMe ? Theme.accent : Theme.dim)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.isMe ? "\(r.name) (tu)" : r.name).font(.headline)
                                Text("\(Fmt.speedText(r.speed)) \(Fmt.speedUnit)" + (r.isMe ? "" : " · \(distanceFromMe(r))"))
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if let gap { Chip(text: "INDIETRO \(NavText.distance(gap))", icon: "exclamationmark.triangle.fill", tint: .red) }
                        }
                    }
                }
                Section {
                    Button("Esci dal gruppo", role: .destructive) { group.stop() }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func distanceFromMe(_ r: Rider) -> String {
        guard let me = tracker.currentLocation else { return "—" }
        let d = me.distance(from: CLLocation(latitude: r.coordinate.latitude, longitude: r.coordinate.longitude))
        return "a \(NavText.distance(d))"
    }

    private static func randomCode() -> String {
        String((0..<5).map { _ in "ABCDEFGHJKMNPQRSTUVWXYZ23456789".randomElement()! })
    }
}
