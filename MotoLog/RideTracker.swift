import Foundation
import CoreLocation
import CoreMotion
import AVFoundation
import UIKit

enum RideState { case idle, recording, paused }

final class RideTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var state: RideState = .idle
    @Published var points: [TrackPoint] = []
    @Published var distance = 0.0
    @Published var speed = 0.0
    @Published var maxSpeed = 0.0
    @Published var elapsed: TimeInterval = 0
    @Published var movingTime: TimeInterval = 0
    @Published var altitude = 0.0
    @Published var elevationGain = 0.0
    @Published var lean = 0.0
    @Published var maxLeft = 0.0
    @Published var maxRight = 0.0
    @Published var gForce = 0.0
    @Published var maxG = 0.0
    @Published var fallAlert = false
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var bikeID: UUID?
    @Published var accuracy: Double = -1

    /// Chiamato periodicamente con la bozza del giro, per poterlo recuperare se l'app viene chiusa.
    var draftHandler: ((Ride?) -> Void)?

    private let manager = CLLocationManager()
    private let motion = CMMotionManager()
    private let synth = AVSpeechSynthesizer()

    private var timer: Timer?
    private var startDate = Date()
    private var activeSince: Date?
    private var accumulated: TimeInterval = 0
    private var lastLocation: CLLocation?
    private var lastPointTime = Date.distantPast
    private var refAltitude: Double?
    private var leanFiltered = 0.0
    private var leanOffset: Double {
        get { UserDefaults.standard.double(forKey: "leanOffset") }
        set { UserDefaults.standard.set(newValue, forKey: "leanOffset") }
    }
    private var rawLean = 0.0
    private var announcedKm = 0
    private var impactTime: Date?
    private var speedBeforeImpact = 0.0
    private var tick = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    // MARK: Permessi

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.startUpdatingLocation()   // mostra la posizione sulla mappa anche prima di iniziare
        }
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    // MARK: Controllo del giro

    func start(bikeID: UUID?) {
        reset()
        self.bikeID = bikeID
        startDate = Date()
        activeSince = Date()
        state = .recording
        beginSensors()
        startTimer()
        if UserDefaults.standard.bool(forKey: "voice") { speak("Giro iniziato. Buona strada!") }
    }

    func pause() {
        guard state == .recording else { return }
        accumulated += Date().timeIntervalSince(activeSince ?? Date())
        activeSince = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        activeSince = Date()
        lastLocation = nil
        state = .recording
    }

    /// Termina il giro e restituisce il risultato (nil se troppo breve).
    func finish() -> Ride? {
        if state == .recording { pause() }
        endSensors()
        defer { reset(); draftHandler?(nil) }
        guard points.count >= 2, distance >= 50 else { return nil }
        return makeRide()
    }

    func discard() {
        endSensors()
        reset()
        draftHandler?(nil)
    }

    func calibrateLean() {
        leanOffset = rawLean
        leanFiltered = 0
        lean = 0
    }

    private func reset() {
        state = .idle
        points = []
        distance = 0; maxSpeed = 0; elapsed = 0; movingTime = 0
        elevationGain = 0; maxLeft = 0; maxRight = 0; maxG = 0
        lean = 0; gForce = 0
        accumulated = 0; activeSince = nil
        lastLocation = nil; refAltitude = nil
        announcedKm = 0; impactTime = nil; fallAlert = false
        lastPointTime = .distantPast
    }

    private func makeRide() -> Ride {
        var r = Ride(name: Ride.defaultName(for: startDate), start: startDate, end: Date())
        r.bikeID = bikeID
        r.distance = distance
        r.movingTime = movingTime
        r.elapsed = elapsed
        r.maxSpeed = maxSpeed
        r.elevationGain = elevationGain
        r.maxLeanLeft = maxLeft
        r.maxLeanRight = maxRight
        r.maxG = maxG
        r.points = points
        return r
    }

    // MARK: Sensori

    private func beginSensors() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()

        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
                guard let self, let dm else { return }
                self.handleMotion(dm)
            }
        }
    }

    private func endSensors() {
        timer?.invalidate(); timer = nil
        motion.stopDeviceMotionUpdates()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        if !isAuthorized { manager.stopUpdatingLocation() }
    }

    private func handleMotion(_ dm: CMDeviceMotion) {
        // Telefono montato in verticale sul manubrio: la piega è l'inclinazione laterale rispetto alla gravità.
        rawLean = atan2(dm.gravity.x, -dm.gravity.y) * 180 / .pi
        let target = max(-75, min(75, rawLean - leanOffset))
        leanFiltered = leanFiltered * 0.8 + target * 0.2
        lean = leanFiltered

        let a = dm.userAcceleration
        let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        gForce = gForce * 0.7 + g * 0.3

        guard state == .recording else { return }
        if speed > 3 {
            if lean < 0 { maxLeft = max(maxLeft, -lean) } else { maxRight = max(maxRight, lean) }
        }
        maxG = max(maxG, min(gForce, 6))

        if g > 4, impactTime == nil, UserDefaults.standard.bool(forKey: "fallDetection") {
            impactTime = Date()
            speedBeforeImpact = speed
        }
    }

    // MARK: Posizione

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            accuracy = loc.horizontalAccuracy
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 35 else { continue }
            altitude = loc.altitude

            var v = loc.speed
            if v < 0 {
                if let last = lastLocation {
                    let dt = loc.timestamp.timeIntervalSince(last.timestamp)
                    v = dt > 0 ? loc.distance(from: last) / dt : 0
                } else { v = 0 }
            }
            guard v < 120 else { continue }
            speed = v

            guard state == .recording else { continue }

            // Scarta i salti GPS impossibili (oltre ~430 km/h tra due fix ravvicinati).
            if let last = lastLocation {
                let gap = loc.timestamp.timeIntervalSince(last.timestamp)
                if gap > 0, gap < 60, loc.distance(from: last) / gap > 120 { continue }
            }

            if let last = lastLocation {
                let d = loc.distance(from: last)
                let dt = min(loc.timestamp.timeIntervalSince(last.timestamp), 10)
                if dt > 0, v > 1.0, d / max(dt, 0.01) < 120 {
                    distance += d
                    movingTime += dt
                }
            }
            lastLocation = loc

            maxSpeed = max(maxSpeed, v)
            updateElevation(loc)

            let now = Date()
            if v > 1.0 || now.timeIntervalSince(lastPointTime) >= 10 {
                lastPointTime = now
                points.append(TrackPoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                                         alt: loc.altitude, speed: v, time: loc.timestamp,
                                         lean: lean, g: gForce))
            }
            announceIfNeeded()
        }
    }

    private func updateElevation(_ loc: CLLocation) {
        guard loc.verticalAccuracy > 0, loc.verticalAccuracy <= 15 else { return }
        guard let ref = refAltitude else { refAltitude = loc.altitude; return }
        let diff = loc.altitude - ref
        if abs(diff) >= 3 {
            if diff > 0 { elevationGain += diff }
            refAltitude = loc.altitude
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Timer / bozza / cadute

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.onTick()
        }
    }

    private func onTick() {
        if state == .recording, let since = activeSince {
            elapsed = accumulated + Date().timeIntervalSince(since)
        }
        tick += 1
        if tick % 30 == 0, state != .idle, points.count > 1 {
            draftHandler?(makeRide())
        }
        if let t = impactTime, Date().timeIntervalSince(t) > 4 {
            if speed < 2, speedBeforeImpact > 5 { fallAlert = true }
            impactTime = nil
        }
    }

    // MARK: Annunci vocali

    private func announceIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "voice") else { return }
        let unitMeters = Fmt.imperial ? 1609.344 : 1000.0
        let n = Int(distance / unitMeters)
        guard n > announcedKm else { return }
        announcedKm = n
        let avg = movingTime > 0 ? distance / movingTime : 0
        let unit = Fmt.imperial ? "miglia" : "chilometri"
        speak("\(n) \(unit). Velocità media \(Fmt.speedText(avg)).")
    }

    private func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "it-IT")
        synth.speak(u)
    }
}
