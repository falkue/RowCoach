import Foundation
import Observation
import RowCoachKit

/// Synthetischer Ruderer für Entwicklung und Tests ohne Gerät (Einstellungen → Entwickler).
/// Erzeugt mit `ErgSimulator` dieselben Bytes wie PM5 und Pulsgurt und speist sie über den DeviceManager ein,
/// also durch denselben Parser und dieselben Callbacks wie echte Geräte.
@MainActor
@Observable
final class SimulatorDevice {
    private(set) var isRunning = false
    /// Zieltempo, s pro 500 m
    var pace: Double = 125 { didSet { sim.settings.pace = pace } }
    var strokeRate: Int = 22 { didSet { sim.settings.strokeRate = strokeRate } }
    /// false = Ruderer hört auf (Pause testen)
    var rowing = true { didSet { sim.settings.rowing = rowing } }
    var sendHeartRate = true { didSet { sim.settings.sendHeartRate = sendHeartRate } }
    /// Meter, die der simulierte PM5 beim Einschalten schon auf der Uhr hat (Grundlinie testen)
    var startDistance: Double = 0

    @ObservationIgnored private let devices: DeviceManager
    @ObservationIgnored private var sim = ErgSimulator()
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
        sim = ErgSimulator(settings: .init(pace: pace, strokeRate: strokeRate,
                                           restHR: restHR > 0 ? restHR : 60, maxHR: maxHR > 0 ? maxHR : 185,
                                           rowing: rowing, sendHeartRate: sendHeartRate),
                           startDistance: startDistance)
        devices.setSimulatorActive(true)
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
    }

    private func tick() {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? Self.interval
        lastTick = now
        let out = sim.step(dt: dt)
        for p in out.pm5 {
            devices.ingestSimulated(characteristic: p.characteristic, bytes: p.bytes, at: now)
        }
        if let hr = out.heartRate {
            devices.ingestSimulatedHeartRate(bytes: hr, at: now)
        }
    }
}
