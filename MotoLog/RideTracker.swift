import Foundation
import CoreLocation
import CoreMotion
import AVFoundation
import UIKit
import MapKit
import UserNotifications
import AudioToolbox

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
    /// Nome del distributore vicino quando ti fermi: la schermata chiede i litri.
    @Published var fuelStation: String?
    /// Ultima posizione valida (anche a moto ferma): serve a parcheggio e tramonto.
    @Published var currentLocation: CLLocation?
    /// Vero quando superi il limite impostato in Altro.
    @Published var overLimit = false

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
    private var stopSince: Date?
    // Risparmio energetico
    @Published var batteryLevel: Float = -1
    private var batteryStart: Float = -1
    private var batteryStartTime = Date()
    private var appActive = true
    private var lastMotionPublish = Date.distantPast
    private var gInternal = 0.0
    private var slowSince: Date?
    private var parkedMode = false
    private var lastSpeedAlert = Date.distantPast
    private var lastStationCheck: CLLocation?
    private var checkingStation = false

    override init() {
        super.init()
        manager.delegate = self
        // Da fermo basta una posizione approssimativa: il GPS preciso parte solo quando registri.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.batteryLevel = UIDevice.current.batteryLevel
        }
    }

    /// Modalità risparmio: attiva se l'hai scelta in Altro o se iOS è in "Risparmio energetico".
    var saver: Bool { UserDefaults.standard.bool(forKey: "saver") || ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// Fuori dall'app, se non stai registrando, il GPS si spegne.
    func setActive(_ active: Bool) {
        appActive = active
        guard state == .idle, isAuthorized else { return }
        if active { manager.startUpdatingLocation() } else { manager.stopUpdatingLocation() }
    }

    /// Ore di batteria rimaste al ritmo di consumo di questo giro (dopo almeno 10 minuti).
    var batteryHoursLeft: Double? {
        let hours = Date().timeIntervalSince(batteryStartTime) / 3600
        let drop = Double(batteryStart - batteryLevel)
        guard state != .idle, batteryStart >= 0, batteryLevel >= 0, hours > 1.0 / 6, drop >= 0.02 else { return nil }
        return Double(batteryLevel) / (drop / hours)
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
        Notifier.requestAuthorization()
        self.bikeID = bikeID
        batteryStart = UIDevice.current.batteryLevel
        batteryStartTime = Date()
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
        stopSince = nil; lastStationCheck = nil; fuelStation = nil
        overLimit = false
        slowSince = nil; parkedMode = false
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
        if batteryStart >= 0 { r.batteryStart = Double(batteryStart) }
        if UIDevice.current.batteryLevel >= 0 { r.batteryEnd = Double(UIDevice.current.batteryLevel) }
        return r
    }

    // MARK: Sensori

    private func beginSensors() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = saver ? 5 : kCLDistanceFilterNone
        manager.startUpdatingLocation()

        if motion.isDeviceMotionAvailable {
            // 10 Hz solo se serve il rilevamento caduta; altrimenti 5 Hz (4 Hz in risparmio): la piega si legge uguale.
            let fall = UserDefaults.standard.bool(forKey: "fallDetection")
            motion.deviceMotionUpdateInterval = fall ? 0.1 : (saver ? 0.25 : 0.2)
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
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
        if !isAuthorized || !appActive { manager.stopUpdatingLocation() }
    }

    private func handleMotion(_ dm: CMDeviceMotion) {
        // Telefono montato in verticale sul manubrio: la piega è l'inclinazione laterale rispetto alla gravità.
        rawLean = atan2(dm.gravity.x, -dm.gravity.y) * 180 / .pi
        let target = max(-75, min(75, rawLean - leanOffset))
        leanFiltered = leanFiltered * 0.8 + target * 0.2

        let a = dm.userAcceleration
        let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        gInternal = gInternal * 0.7 + g * 0.3

        // Il display si aggiorna al massimo 4 volte al secondo e mai a schermo spento.
        let now = Date()
        if appActive, now.timeIntervalSince(lastMotionPublish) > 0.25 {
            lastMotionPublish = now
            lean = leanFiltered
            gForce = gInternal
        }

        guard state == .recording else { return }
        if speed > 3 {
            if leanFiltered < 0, -leanFiltered > maxLeft + 0.5 { maxLeft = -leanFiltered }
            else if leanFiltered > 0, leanFiltered > maxRight + 0.5 { maxRight = leanFiltered }
        }
        if min(gInternal, 6) > maxG + 0.05 { maxG = min(gInternal, 6) }

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
            currentLocation = loc

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
            adaptAccuracy(v)
            watchForStation(loc, speed: v)
            checkSpeedLimit(v)

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
                                         lean: leanFiltered, g: gInternal))
            }
            announceIfNeeded()
        }
    }

    /// Fermo da più di 90 secondi (semaforo lungo, sosta): il GPS scende a precisione ridotta fino alla ripartenza.
    private func adaptAccuracy(_ v: Double) {
        if v < 1 {
            if slowSince == nil { slowSince = Date() }
            if !parkedMode, let s = slowSince, Date().timeIntervalSince(s) > 90 {
                parkedMode = true
                manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                manager.distanceFilter = 15
            }
        } else {
            slowSince = nil
            if parkedMode {
                parkedMode = false
                manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                manager.distanceFilter = saver ? 5 : kCLDistanceFilterNone
            }
        }
    }

    /// Avviso di velocità: vibrazione, suono e voce (se attiva) al massimo ogni 20 secondi.
    private func checkSpeedLimit(_ v: Double) {
        let d = UserDefaults.standard
        guard d.bool(forKey: "speedAlert") else { if overLimit { overLimit = false }; return }
        let over = v * 3.6 > max(d.double(forKey: "speedLimitKmh"), 30)
        if over != overLimit { overLimit = over }
        guard over, Date().timeIntervalSince(lastSpeedAlert) > 20 else { return }
        lastSpeedAlert = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        AudioServicesPlaySystemSound(1005)
        if d.bool(forKey: "voice") { speak("Attenzione, limite di velocità superato.") }
    }

    /// Fermo da più di 40 s: se nei 100 m c'è un distributore, propone di registrare il rifornimento.
    private func watchForStation(_ loc: CLLocation, speed v: Double) {
        guard fuelStation == nil, !checkingStation else { return }
        guard v < 1 else { stopSince = nil; return }
        guard let since = stopSince else { stopSince = loc.timestamp; return }
        guard loc.timestamp.timeIntervalSince(since) > 40 else { return }
        if let last = lastStationCheck, loc.distance(from: last) < 200 { return }
        checkingStation = true
        lastStationCheck = loc
        let request = MKLocalPointsOfInterestRequest(center: loc.coordinate, radius: 100)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        Task { @MainActor in
            let items = try? await MKLocalSearch(request: request).start().mapItems
            checkingStation = false
            guard let name = items?.first.map({ $0.name ?? "un distributore" }) else { return }
            fuelStation = name
            if UIApplication.shared.applicationState != .active {
                let content = UNMutableNotificationContent()
                content.title = "Sei a un distributore?"
                content.body = "Apri MotoLog e registra i litri che hai messo."
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "fuelstop", content: content, trigger: nil))
            }
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
        timer?.tolerance = 0.4   // permette a iOS di raggruppare i risvegli
    }

    private func onTick() {
        if state == .recording, let since = activeSince {
            elapsed = accumulated + Date().timeIntervalSince(since)
        }
        tick += 1
        if tick % 60 == 0, state != .idle, points.count > 1 {
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
