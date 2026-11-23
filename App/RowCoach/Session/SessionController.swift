import Foundation
import os
import Observation
import RowCoachKit

/// Verbindet DeviceManager.snapshot → RowingSession → HealthService und Verlaufsspeicher.
///
/// Ablauf: `prepare(course:)` beim Öffnen des Ruderbildschirms → erster Schlag startet die Fahrt und die
/// Health-Aufzeichnung → Pausen werden an Health gemeldet → im Ziel (oder bei „Beenden“) wird das Training
/// im Verlauf gespeichert und in Apple Health abgeschlossen.
@MainActor
@Observable
final class SessionController {
    enum Phase: Equatable {
        /// kein Ruderbildschirm offen
        case idle
        /// Fahrt läuft (bereit, rudert oder Pause; siehe `session.state`)
        case active
        /// Ziel erreicht, Training wird gespeichert
        case saving
        /// gespeichert, Zusammenfassung anzeigen
        case done
    }

    private(set) var phase: Phase = .idle
    private(set) var course: Course?
    private(set) var session: RowingSession?
    /// Ergebnis nach dem Ziel
    private(set) var record: WorkoutRecord?
    private(set) var healthSaved = false
    /// Hinweis zu Apple Health (z. B. nicht verbunden)
    private(set) var healthNote: String?
    /// letzter fertiger Split (für die kurze Einblendung im HUD)
    private(set) var lastSplit: SplitTime?
    private(set) var lastSplitAt: Date?
    private(set) var turnReachedAt: Date?

    @ObservationIgnored private let devices: DeviceManager
    @ObservationIgnored private let health: HealthService
    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSnapshot: RowingSnapshot?
    @ObservationIgnored private var storedItem: StoredWorkout?

    /// Sekunden ohne Schlag bis zur Pause (Einstellungen)
    nonisolated static let pauseAfterKey = "session.pauseAfter"

    init(devices: DeviceManager, health: HealthService, store: WorkoutStore) {
        self.devices = devices
        self.health = health
        self.store = store
    }

    // MARK: Bedienung

    /// Ruderbildschirm geöffnet: neue Fahrt auf der Strecke, wartet auf den ersten Schlag.
    func prepare(course: Course) {
        stopTimer()
        if health.isRecording { health.discard() }
        let pauseAfter = UserDefaults.standard.double(forKey: Self.pauseAfterKey)
        self.course = course
        session = RowingSession(track: CourseTrack(course: course), pauseAfter: pauseAfter > 0 ? pauseAfter : 6)
        record = nil
        storedItem = nil
        healthSaved = false
        healthNote = nil
        lastSplit = nil
        lastSplitAt = nil
        turnReachedAt = nil
        lastSnapshot = nil
        phase = .active
        startTimer()
    }

    /// Vorzeitig beenden und speichern (wenn schon gerudert wurde), sonst verwerfen.
    func endAndSave() {
        guard phase == .active, var s = session else { return }
        guard s.state != .ready, s.distance > 0 else {
            cancel()
            return
        }
        s.finish(at: Date())
        session = s
        complete()
    }

    /// Abbrechen ohne Speichern.
    func cancel() {
        stopTimer()
        if health.isRecording { health.discard() }
        session = nil
        course = nil
        record = nil
        phase = .idle
    }

    /// Zusammenfassung geschlossen.
    func close() {
        stopTimer()
        session = nil
        course = nil
        record = nil
        storedItem = nil
        phase = .idle
    }

    // MARK: Eingang (vom DeviceManager, Hauptthread)

    func handlePM5(_ message: PM5Message, at date: Date) {
        let snap = devices.snapshot
        guard phase == .active, session != nil else {
            // Keine Fahrt: Diagnose-Aufzeichnung aus der alten Live-Ansicht (absolute PM5-Werte).
            // Während des Speicherns nichts mehr an Health geben.
            if phase == .idle { health.record(snapshot: snap, at: date) }
            return
        }
        lastSnapshot = snap
        apply(snap, at: date)
    }

    func handleHeartRate(_ m: HeartRateMeasurement, at date: Date) {
        health.record(heartRate: m, at: date)
        guard phase == .active, var s = session, !m.rrIntervals.isEmpty else { return }
        s.record(rrIntervals: m.rrIntervals)
        session = s
    }

    // MARK: intern

    private func apply(_ snap: RowingSnapshot, at date: Date) {
        guard var s = session, !s.isFinished else { return }
        let events = s.update(snap, at: date)
        session = s
        if s.state != .ready {
            health.record(snapshot: relativeSnapshot(s, snap), at: date)
        }
        for e in events { handle(e, at: date) }
    }

    /// Werte relativ zum Start der Session für Apple Health (Distanz und Kalorien ab 0).
    private func relativeSnapshot(_ s: RowingSession, _ snap: RowingSnapshot) -> RowingSnapshot {
        var r = snap
        r.distance = s.distance
        r.calories = s.calories
        r.strokeCount = s.strokeCount
        r.elapsedTime = s.activeTime
        r.averagePower = s.averagePower
        r.averagePace = s.averagePace
        return r
    }

    private func handle(_ e: RowingEvent, at date: Date) {
        switch e {
        case .started:
            startHealth()
        case .paused:
            health.pause()
        case .resumed:
            health.resume()
        case .turnReached:
            turnReachedAt = date
        case .splitCompleted(let split):
            lastSplit = split
            lastSplitAt = date
        case .finished:
            complete()
        }
    }

    private func startHealth() {
        guard health.status == .authorized else {
            healthNote = health.status == .unavailable
                ? "Apple Health ist auf diesem Gerät nicht verfügbar."
                : "Apple Health ist nicht verbunden (Einstellungen)."
            return
        }
        let title = course?.title
        Task { await health.start(courseName: title) }
    }

    /// Ziel erreicht oder von Hand beendet: Training bauen, speichern, Health abschliessen.
    private func complete() {
        guard phase == .active, let s = session else { return }
        stopTimer()
        phase = .saving
        let rec = s.makeRecord(device: deviceInfo(), zones: currentZones(), appVersion: appVersion())
        record = rec
        let item = store.save(rec)
        storedItem = item
        Task {
            var saved = false
            if health.isRecording { saved = await health.finish() }
            healthSaved = saved
            Logger(subsystem: "com.falkue.RowCoach", category: "Session").info(
                "Fahrt beendet: \(Int(rec.summary.distance), privacy: .public) m, Health gespeichert: \(saved, privacy: .public), Hinweis: \(self.healthNote ?? self.health.lastError ?? "-", privacy: .public)")
            if !saved, healthNote == nil, let e = health.lastError { healthNote = e }
            store.markSavedToHealth(item, saved)
            phase = .done
        }
    }

    private func deviceInfo() -> WorkoutDevice {
        let snap = devices.snapshot
        return WorkoutDevice(source: devices.simulatorActive ? .simulator : .pm5,
                             pm5Name: devices.simulatorActive ? "Simulator" : devices.pm5Name,
                             heartRateSensorName: devices.simulatorActive ? "Simulator" : devices.strapName,
                             heartRateSource: snap.heartRateSource?.rawValue)
    }

    private func currentZones() -> HeartRateZones {
        let d = UserDefaults.standard
        let maxHR = d.integer(forKey: "profile.maxHR"), restHR = d.integer(forKey: "profile.restHR")
        return HeartRateZones(maxHR: maxHR > 0 ? maxHR : 185, restHR: restHR > 0 ? restHR : 55)
    }

    private func appVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Takt 1 s: Pause erkennen, auch wenn der PM5 nichts Neues schickt.
    private func startTimer() {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard phase == .active, let snap = lastSnapshot else { return }
        apply(snap, at: Date())
    }
}
