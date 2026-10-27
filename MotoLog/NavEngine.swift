import SwiftUI
import MapKit
import AVFoundation

/// Un tratto del percorso con la manovra che lo introduce ("Svolta a destra su…").
struct NavStep {
    let instruction: String
    let points: [MKMapPoint]
    let cum: [Double]            // metri dall'inizio del tratto a ogni punto

    var length: Double { cum.last ?? 0 }

    init(instruction: String, points: [MKMapPoint]) {
        var pts = points
        if pts.count == 1 { pts.append(pts[0]) }
        self.instruction = instruction
        self.points = pts
        var c = [0.0]
        for i in 1..<max(pts.count, 1) { c.append(c[i - 1] + pts[i - 1].distance(to: pts[i])) }
        self.cum = c
    }

    /// Distanza dal percorso e posizione (in metri dall'inizio del tratto) del punto più vicino.
    func project(_ p: MKMapPoint) -> (dist: Double, along: Double) {
        var best = (dist: Double.infinity, along: 0.0)
        guard points.count > 1 else { return best }
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
            t = min(max(t, 0), 1)
            let d = p.distance(to: MKMapPoint(x: a.x + t * dx, y: a.y + t * dy))
            if d < best.dist { best = (d, cum[i] + t * (cum[i + 1] - cum[i])) }
        }
        return best
    }

    static func build(_ route: MKRoute) -> [NavStep] {
        var out: [(String, [MKMapPoint])] = []
        for s in route.steps {
            let n = s.polyline.pointCount
            guard n > 0 else { continue }
            let pts = Array(UnsafeBufferPointer(start: s.polyline.points(), count: n))
            let text = s.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty, !out.isEmpty {
                out[out.count - 1].1 += pts.dropFirst()   // tratto senza manovra: si unisce al precedente
            } else {
                out.append((text.isEmpty ? "Procedi" : text, pts))
            }
        }
        return out.map { NavStep(instruction: $0.0, points: $0.1) }
    }
}

enum NavText {
    /// La voce segue la lingua del telefono: le indicazioni di Apple sono nella stessa lingua.
    static var italian: Bool { (Locale.preferredLanguages.first ?? "it").hasPrefix("it") }
    static var voiceLanguage: String { Locale.preferredLanguages.first ?? "it-IT" }

    static func distance(_ m: Double) -> String {
        if Fmt.imperial {
            let ft = m * 3.28084
            return ft < 1000 ? "\(Int((ft / 50).rounded()) * 50) ft" : String(format: "%.1f mi", m / 1609.344)
        }
        if m < 1000 { return "\(max(10, Int((m / 10).rounded()) * 10)) m" }
        return String(format: "%.1f km", m / 1000)
    }

    static func spokenDistance(_ m: Double) -> String {
        if !italian {
            if Fmt.imperial { let ft = m * 3.28084; return ft < 1000 ? "\(Int((ft / 100).rounded()) * 100) feet" : String(format: "%.1f miles", m / 1609.344) }
            return m < 1000 ? "\(max(50, Int((m / 50).rounded()) * 50)) meters" : String(format: "%.1f kilometers", m / 1000)
        }
        if Fmt.imperial {
            let ft = m * 3.28084
            return ft < 1000 ? "\(Int((ft / 100).rounded()) * 100) piedi" : String(format: "%.1f miglia", m / 1609.344).replacingOccurrences(of: ".", with: ",")
        }
        if m < 1000 { return "\(max(50, Int((m / 50).rounded()) * 50)) metri" }
        return String(format: "%.1f chilometri", m / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func symbol(for text: String) -> String {
        let t = text.lowercased()
        if t.contains("arriv") || t.contains("destination") || t.contains("destinazione") { return "flag.checkered" }
        if t.contains("inversione") || t.contains("u-turn") { return "arrow.uturn.left" }
        if t.contains("rotator") || t.contains("rotond") || t.contains("roundabout") { return "arrow.triangle.turn.up.right.circle" }
        let slight = t.contains("legger") || t.contains("slight") || t.contains("keep") || t.contains("mantieni")
        if t.contains("sinistr") || t.contains("left") { return slight ? "arrow.up.left" : "arrow.turn.up.left" }
        if t.contains("destr") || t.contains("right") { return slight ? "arrow.up.right" : "arrow.turn.up.right" }
        return "arrow.up"
    }
}

/// Guida passo passo sopra i percorsi di Apple Maps: segue la posizione, avvisa a voce e ricalcola se esci strada.
@MainActor
final class NavEngine: ObservableObject {
    @Published private(set) var route: MKRoute
    @Published private(set) var routeVersion = 0
    @Published private(set) var steps: [NavStep] = []
    @Published private(set) var index = 0
    @Published private(set) var distToNext = 0.0
    @Published private(set) var remaining = 0.0
    @Published private(set) var nextText = ""
    @Published private(set) var thenText: String?
    @Published private(set) var offRoute = false
    @Published private(set) var rerouting = false
    @Published private(set) var arrived = false
    private(set) var lastUpdate = Date()
    @Published var destination: MKMapItem
    @Published var pendingFinal: MKMapItem?
    @Published var muted = false

    private var offCount = 0
    private var spoken: Set<String> = []
    private var lastReroute = Date.distantPast
    private let synth = AVSpeechSynthesizer()

    init(route: MKRoute, destination: MKMapItem) {
        self.route = route
        self.destination = destination
        setRoute(route)
    }

    var symbol: String { NavText.symbol(for: nextText) }

    private func setRoute(_ r: MKRoute) {
        route = r
        steps = NavStep.build(r)
        index = 0
        spoken = []
        offCount = 0
        offRoute = false
        remaining = r.distance
        distToNext = steps.first?.length ?? 0
        refreshTexts()
        routeVersion += 1
    }

    private func refreshTexts() {
        nextText = index + 1 < steps.count ? steps[index + 1].instruction : "Arrivo a destinazione"
        thenText = index + 2 < steps.count ? steps[index + 2].instruction : nil
    }

    func update(_ loc: CLLocation) {
        guard !arrived, !steps.isEmpty else { return }
        lastUpdate = Date()
        let p = MKMapPoint(loc.coordinate)
        let v = max(loc.speed, 0)

        // Il tratto corrente può solo avanzare (di poco alla volta).
        var best = index, bestD = Double.infinity, bestAlong = 0.0
        for j in index..<min(index + 4, steps.count) {
            let r = steps[j].project(p)
            if r.dist < bestD - 3 { bestD = r.dist; best = j; bestAlong = r.along }
        }
        if bestD > max(40, loc.horizontalAccuracy * 1.5, v * 2.5) {
            offCount += 1
            if offCount >= 3 { offRoute = true; reroute(from: loc) }
            return
        }
        offCount = 0
        offRoute = false

        // Quasi arrivati alla manovra: passa al tratto successivo.
        if best == index, index + 1 < steps.count, steps[index].length - bestAlong < 20 {
            best = index + 1
            bestAlong = 0
        }
        index = best
        distToNext = max(0, steps[index].length - bestAlong)
        remaining = distToNext + steps[(index + 1)...].reduce(0) { $0 + $1.length }
        refreshTexts()

        if index == steps.count - 1, distToNext < 25 {
            arrived = true
            say(NavText.italian ? "Sei arrivato a destinazione." : "You have arrived.")
            return
        }
        announce(speed: v)
    }

    /// Due avvisi per ogni manovra: uno da lontano e uno vicino, in base alla velocità.
    private func announce(speed v: Double) {
        guard index + 1 < steps.count else { return }
        let far = max(450, v * 30), near = max(110, v * 9)
        let text = steps[index + 1].instruction
        let kFar = "\(index)-far", kNear = "\(index)-near"
        if distToNext < near, !spoken.contains(kNear) {
            spoken.insert(kNear); spoken.insert(kFar)
            say(text)
        } else if distToNext < far, !spoken.contains(kFar) {
            spoken.insert(kFar)
            say("\(NavText.italian ? "Tra" : "In") \(NavText.spokenDistance(distToNext)), \(text)")
        }
    }

    private func reroute(from loc: CLLocation) {
        guard !rerouting, Date().timeIntervalSince(lastReroute) > 12 else { return }
        rerouting = true
        lastReroute = Date()
        say(NavText.italian ? "Ricalcolo del percorso." : "Recalculating.")
        Task {
            if let r = await Self.route(from: loc.coordinate, to: destination) { setRoute(r) }
            rerouting = false
        }
    }

    /// Cambia destinazione (per esempio un distributore) ricordando quella finale.
    func divert(to item: MKMapItem, from loc: CLLocation) async {
        guard let r = await Self.route(from: loc.coordinate, to: item) else { return }
        if pendingFinal == nil { pendingFinal = destination }
        destination = item
        arrived = false
        setRoute(r)
    }

    func resumeFinal(from loc: CLLocation) async {
        guard let final = pendingFinal, let r = await Self.route(from: loc.coordinate, to: final) else { return }
        pendingFinal = nil
        destination = final
        arrived = false
        setRoute(r)
    }

    static func route(from c: CLLocationCoordinate2D, to item: MKMapItem) async -> MKRoute? {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: c))
        req.destination = item
        req.transportType = .automobile
        return try? await MKDirections(request: req).calculate().routes.first
    }

    /// Distributori entro 15 km, dal più vicino.
    static func stations(around c: CLLocationCoordinate2D) async -> [(item: MKMapItem, meters: Double)] {
        let req = MKLocalPointsOfInterestRequest(center: c, radius: 15000)
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        guard let items = try? await MKLocalSearch(request: req).start().mapItems else { return [] }
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return items.map { ($0, here.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))) }
            .sorted { $0.1 < $1.1 }
            .prefix(4).map { (item: $0.0, meters: $0.1) }
    }

    func say(_ text: String) {
        guard !muted else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: NavText.voiceLanguage)
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }
}

/// Percorso campionato per la guida simulata.
struct SimPath {
    let points: [MKMapPoint]
    let cum: [Double]
    var total: Double { cum.last ?? 0 }

    init(_ route: MKRoute) {
        let n = route.polyline.pointCount
        points = Array(UnsafeBufferPointer(start: route.polyline.points(), count: n))
        var c = [0.0]
        for i in 1..<max(n, 1) { c.append(c[i - 1] + points[i - 1].distance(to: points[i])) }
        cum = c
    }

    /// Coordinata e direzione (gradi) dopo `s` metri.
    func at(_ s: Double) -> (CLLocationCoordinate2D, Double) {
        guard points.count > 1 else { return (points.first?.coordinate ?? CLLocationCoordinate2D(), 0) }
        var i = 0
        while i < points.count - 2, cum[i + 1] < s { i += 1 }
        let seg = max(cum[i + 1] - cum[i], 0.001)
        let t = min(max((s - cum[i]) / seg, 0), 1)
        let a = points[i], b = points[i + 1]
        let p = MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        let bearing = atan2(b.x - a.x, -(b.y - a.y)) * 180 / .pi
        return (p.coordinate, bearing < 0 ? bearing + 360 : bearing)
    }
}

/// Rende fluido il movimento tra un fix GPS (circa 1 al secondo) e il successivo:
/// stima dove sei adesso in base a velocità e direzione e ti ci porta con un inseguimento morbido.
final class SmoothPosition {
    private var fix: MKMapPoint?
    private var fixTime = Date()
    private var speed = 0.0
    private var course = 0.0
    private var targetHeading = 0.0
    private var shown: MKMapPoint?
    private var heading = 0.0
    private var distance = 600.0
    private var lastStep = Date()

    struct Frame {
        let coordinate: CLLocationCoordinate2D
        let heading: Double
        let distance: Double
    }

    func feed(_ loc: CLLocation) {
        let p = MKMapPoint(loc.coordinate)
        speed = max(loc.speed, 0)
        if loc.course >= 0, speed > 1 { course = loc.course; targetHeading = loc.course }
        fix = p
        fixTime = Date()
        if shown == nil { shown = p; heading = targetHeading; lastStep = Date() }
    }

    func step(now: Date) -> Frame? {
        guard let fix, var cur = shown else { return nil }
        let dt = min(max(now.timeIntervalSince(lastStep), 0), 0.25)
        lastStep = now

        let ahead = min(now.timeIntervalSince(fixTime), 2.5) * speed          // metri stimati dall'ultimo fix
        let ppm = MKMapPointsPerMeterAtLatitude(fix.coordinate.latitude)
        let rad = course * .pi / 180
        let target = MKMapPoint(x: fix.x + sin(rad) * ahead * ppm, y: fix.y - cos(rad) * ahead * ppm)
        if cur.distance(to: target) > 100 {
            cur = target                                                       // salto grande: niente scivolata
        } else {
            let k = min(1, dt * 8)
            cur = MKMapPoint(x: cur.x + (target.x - cur.x) * k, y: cur.y + (target.y - cur.y) * k)
        }
        shown = cur

        var d = targetHeading - heading
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        heading += d * min(1, dt * 2.5)
        heading = heading.truncatingRemainder(dividingBy: 360)
        if heading < 0 { heading += 360 }

        let wanted = max(450, speed * 14 + 350)
        distance += (wanted - distance) * min(1, dt * 1.5)
        return Frame(coordinate: cur.coordinate, heading: heading, distance: distance)
    }
}
