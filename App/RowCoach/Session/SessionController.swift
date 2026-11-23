import Foundation
import os
import Observation
import RowCoachKit

/// Verbindet DeviceManager.snapshot → RowingSession → HealthService und Verlaufsspeicher.
///
/// Ablauf: `prepare(course:)` beim Öffnen des Ruderbildschirms → erster Schlag startet die Fahrt und die
/// Health-Aufzeichnung → Pausen werden an Health gemeldet → im Ziel (oder bei „Beenden“) wird das Training
/// im Verlauf gespeichert und in Apple Health abgeschlossen.
/// Während der Fahrt schreibt der Controller etwa alle 10 s (und bei Pause) einen Sicherungspunkt
/// (`CheckpointStore`); beim normalen Ende wird er gelöscht. Bleibt er liegen (Akku leer, App beendet oder abgestürzt),
/// übernimmt `WorkoutRecovery` das Training beim nächsten Start.
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
    @ObservationIgnored private let checkpoints: CheckpointStore
    /// ID der laufenden Fahrt: gleich im Sicherungspunkt und im gespeicherten Training (verhindert Doppelte)
    @ObservationIgnored private var rideId = UUID()
    @ObservationIgnored private var lastCheckpointAt = Date.distantPast

    /// Abstand der Sicherungspunkte (s)
    nonisolated static let checkpointInterval: TimeInterval = 10

    /// Sekunden ohne Schlag bis zur Pause (Einstellungen)
    nonisolated static let pauseAfterKey = "session.pauseAfter"

    init(devices: DeviceManager, health: HealthService, store: WorkoutStore, checkpoints: CheckpointStore) {
        self.devices = devices
        self.health = health
        self.store = store
        self.checkpoints = checkpoints
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
        rideId = UUID()
        lastCheckpointAt = .distantPast
        // Ein alter Sicherungspunkt wurde beim Start schon von WorkoutRecovery übernommen (umbenannt).
        checkpoints.clear()
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
        checkpoints.clear()
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
        if phase == .active, date.timeIntervalSince(lastCheckpointAt) >= Self.checkpointInterval {
            writeCheckpoint(at: date)
        }
    }

    /// Sicherungspunkt sofort schreiben (z. B. wenn die App in den Hintergrund geht).
    func writeCheckpointNow() {
        writeCheckpoint(at: Date())
    }

    /// Aktuellen Stand als Training in die Sicherungsdatei schreiben (Kodieren und Schreiben im Hintergrund).
    /// Eine Kopie der Session wird beendet, damit der angefangene Split mit drin ist; die laufende Fahrt bleibt unberührt.
    private func writeCheckpoint(at date: Date) {
        guard phase == .active, let s = session, s.state == .rowing || s.state == .paused else { return }
        var copy = s
        copy.finish(at: date)
        let rec = copy.makeRecord(id: rideId, device: deviceInfo(), zones: currentZones(), appVersion: appVersion(),
                                  now: date)
        checkpoints.save(WorkoutCheckpoint(record: rec, savedAt: date, healthRecording: health.isRecording))
        lastCheckpointAt = date
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
            writeCheckpoint(at: date)
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
        let rec = s.makeRecord(id: rideId, device: deviceInfo(), zones: currentZones(), appVersion: appVersion())
        record = rec
        let item = store.save(rec)
        storedItem = item
        // Sicherungspunkt nur löschen, wenn der Verlauf das Training sicher hat; sonst übernimmt ihn der nächste Start.
        if store.lastError == nil {
            checkpoints.clear()
        } else {
            Logger(subsystem: "com.falkue.RowCoach", category: "Session").error(
                "Verlauf speichern fehlgeschlagen, Sicherungspunkt bleibt: \(self.store.lastError ?? "-", privacy: .public)")
            // Endstand sichern und gleich beiseitelegen, damit die nächste Fahrt ihn nicht überschreibt
            checkpoints.save(WorkoutCheckpoint(record: rec, savedAt: Date(), healthRecording: health.isRecording))
            _ = checkpoints.claimPending()
        }
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
