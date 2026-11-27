import Foundation
import Observation
import RowCoachKit

/// Synthetischer Ruderer für Entwicklung und Tests ohne Gerät (Einstellungen → Entwickler).
/// Erzeugt mit `ErgSimulator` dieselben Bytes wie PM5 und Pulsgurt und speist sie über den DeviceManager ein,
/// also durch denselben Parser und dieselben Callbacks wie echte Geräte.
/// Testbetrieb: `-simulateFTMS 1` simuliert statt des PM5 ein FTMS-Rudergerät (Rower Data 0x2AD1, aufgeteilt in
/// Teilpakete), `-simulateFTMS 2` ein karges FTMS-Gerät nur mit Schlagzahl, Schlagzähler und Distanz (Tempo und Watt
/// leitet die App ab).
@MainActor
@Observable
final class SimulatorDevice {
    private(set) var isRunning = false
    /// Zieltempo, s pro 500 m
    var pace: Double = 125 { didSet { sim.settings.pace = pace; ftms?.sim.settings.pace = pace } }
    var strokeRate: Int = 22 { didSet { sim.settings.strokeRate = strokeRate; ftms?.sim.settings.strokeRate = strokeRate } }
    /// false = Ruderer hört auf (Pause testen)
    var rowing = true { didSet { sim.settings.rowing = rowing; ftms?.sim.settings.rowing = rowing } }
    var sendHeartRate = true {
        didSet { sim.settings.sendHeartRate = sendHeartRate; ftms?.sim.settings.sendHeartRate = sendHeartRate }
    }
    /// Meter, die der simulierte PM5 beim Einschalten schon auf der Uhr hat (Grundlinie testen)
    var startDistance: Double = 0

    @ObservationIgnored private let devices: DeviceManager
    @ObservationIgnored private var sim = ErgSimulator()
    /// FTMS-Modus (nur über das Startargument `-simulateFTMS`)
    @ObservationIgnored private var ftms: FTMSRowerSimulator?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick: Date?

    private static let interval: TimeInterval = 0.25

    init(devices: DeviceManager) {
        self.devices = devices
    }

    func start() {
        guard !isRunning else { return }
        let defaults = UserDefaults.standard
        let maxHR = defaults.integer(forKey: "profile.maxHR")
        let restHR = defaults.integer(forKey: "profile.restHR")
        let settings = ErgSimulator.Settings(pace: pace, strokeRate: strokeRate,
                                             restHR: restHR > 0 ? restHR : 60, maxHR: maxHR > 0 ? maxHR : 185,
                                             rowing: rowing, sendHeartRate: sendHeartRate)
        sim = ErgSimulator(settings: settings, startDistance: startDistance)
        let ftmsMode = defaults.integer(forKey: "simulateFTMS")
        ftms = ftmsMode > 0
            ? FTMSRowerSimulator(settings: settings, startDistance: startDistance, minimal: ftmsMode == 2) : nil
        devices.setSimulatorActive(true, kind: ftms == nil ? .pm5 : .ftms)
        isRunning = true
        lastTick = Date()
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        devices.setSimulatorActive(false)
    }

    /// Wie ein Neustart am PM5: Distanz und Uhr springen auf 0.
    func resetMonitor() {
        sim.resetMonitor()
        ftms?.resetMonitor()
    }

    private func tick() {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? Self.interval
        lastTick = now
        if var f = ftms {
            let out = f.step(dt: dt)
            ftms = f
            for bytes in out.rowerData { devices.ingestSimulatedFTMS(bytes: bytes, at: now) }
            if let hr = out.heartRate { devices.ingestSimulatedHeartRate(bytes: hr, at: now) }
            return
        }
        let out = sim.step(dt: dt)
        for p in out.pm5 {
            devices.ingestSimulated(characteristic: p.characteristic, bytes: p.bytes, at: now)
        }
        if let hr = out.heartRate {
            devices.ingestSimulatedHeartRate(bytes: hr, at: now)
        }
    }
}
