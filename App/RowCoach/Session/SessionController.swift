import Foundation
import os
import Observation
import RowCoachKit

/// Verbindet DeviceManager.snapshot → RowingSession → HealthService und Verlaufsspeicher.
///
/// Ablauf: `prepare(course:)` beim Öffnen des Ruderbildschirms → erster Schlag startet die Fahrt und die
/// Health-Aufzeichnung → Pausen werden an Health gemeldet → im Ziel (oder bei „Beenden“) wird das Training
/// im Verlauf gespeichert und in Apple Health abgeschlossen.
/// Mit einem Trainingsprogramm (`prepare(course:plan:)`) führt `PlanEngine` durch die Phasen; das Training endet
/// mit der letzten Phase, gespeichert wird mit `workoutPlanId` und Werten je Phase (auch im Sicherungspunkt).
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

    /// Abfrage der Belastung (1–10) in der Zusammenfassung nach der Fahrt
    enum EffortPrompt: Equatable {
        /// Auswahl zeigen (vorausgewählt: Einschätzung der App)
        case asking
        /// eigene Belastung wird gespeichert
        case saving
        /// gespeichert (im Verlauf und, wenn möglich, in Apple Health)
        case saved
        /// übersprungen; nichts als eigene Einschätzung geschrieben
        case skipped
    }
    private(set) var effortPrompt: EffortPrompt = .asking
    /// Hinweis nach dem Speichern der Belastung (nur bei Problemen)
    private(set) var effortNote: String?

    // Training (Trainingsprogramm auf der Strecke; nil = frei rudern)
    /// gewähltes Programm
    private(set) var plan: WorkoutPlan?
    /// Stand des Trainings (aktuelle Phase, Countdown, Tor-Distanz …)
    private(set) var planStatus: PlanStatus?
    /// Strecke mit Runden: Position für Szene und Navigator bei einem Training
    private(set) var lapTrack: LapTrack?
    private(set) var phaseChangedAt: Date?
    private(set) var lapChangedAt: Date?

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
    @ObservationIgnored private var planEngine: PlanEngine?
    @ObservationIgnored private var phaseMarks: [PlanPhaseMark] = []
    @ObservationIgnored private var currentLap = 0

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
    /// Mit `plan` führt die App durch das Training; es endet mit der letzten Phase, und ist es länger als die
    /// Strecke, geht es in weiteren Runden weiter.
    func prepare(course: Course, plan: WorkoutPlan? = nil) {
        stopTimer()
        if health.isRecording { health.discard() }
        let pauseAfter = UserDefaults.standard.double(forKey: Self.pauseAfterKey)
        self.course = course
        // Training: Die Session darf nicht am Streckenende ins Ziel gehen. Sie rechnet deshalb auf einer
        // „endlosen“ Fassung derselben Strecke (ohne Wende); Position und Runden kommen aus `lapTrack`,
        // Streckenlänge und „geschafft“ werden im gespeicherten Training korrigiert (`makeRecord`).
        let sessionCourse = plan == nil ? course : Self.endlessCourse(course)
        session = RowingSession(track: CourseTrack(course: sessionCourse), pauseAfter: pauseAfter > 0 ? pauseAfter : 6)
        self.plan = plan
        if let plan {
            let best2k = UserDefaults.standard.double(forKey: TrainingSettings.best2kKey)
            let engine = PlanEngine(plan: plan, best2k: best2k > 0 ? best2k : PaceTargets.defaultBest2k)
            planEngine = engine
            planStatus = engine.status
            lapTrack = LapTrack(course: course, endDistance: plan.totalDistance)
        } else {
            planEngine = nil
            planStatus = nil
            lapTrack = nil
        }
        phaseMarks = []
        currentLap = 0
        phaseChangedAt = nil
        lapChangedAt = nil
        record = nil
        storedItem = nil
        healthSaved = false
        healthNote = nil
        lastSplit = nil
        lastSplitAt = nil
        turnReachedAt = nil
        effortPrompt = .asking
        effortNote = nil
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
        clearTraining()
        phase = .idle
    }

    /// Zusammenfassung geschlossen.
    func close() {
        stopTimer()
        session = nil
        course = nil
        record = nil
        storedItem = nil
        clearTraining()
        phase = .idle
    }

    // MARK: Belastung

    /// Eigene Belastung nach der Fahrt speichern: im Training (Verlauf) und in Apple Health als `workoutEffortScore`.
    /// Erneutes Speichern ersetzt den Wert (HealthService löscht die alte Probe dieser App).
    func saveEffort(_ score: Int) {
        guard phase == .done, var updated = record, effortPrompt != .saving else { return }
        updated.setUserEffort(score)
        let rec = updated
        record = rec
        if let item = storedItem { store.updateRecord(item, rec) }
        effortPrompt = .saving
        effortNote = nil
        let log = Logger(subsystem: "com.falkue.RowCoach", category: "Session")
        Task {
            if healthSaved {
                let result = await health.writeEffort(for: rec)
                effortNote = result.note
                log.info("Belastung \(score, privacy: .public) gespeichert: \(result.logText, privacy: .public)")
            } else {
                effortNote = "Die Belastung ist in RowCoach gespeichert (das Training ist nicht in Apple Health)."
                log.info("Belastung \(score, privacy: .public) nur im Verlauf gespeichert (Training nicht in Health)")
            }
            effortPrompt = .saved
        }
    }

    /// Abfrage überspringen: keine eigene Einschätzung (die Einschätzung der App bleibt).
    func skipEffort() {
        guard effortPrompt == .asking else { return }
        effortPrompt = .skipped
    }

    /// Nach „Überspringen“ oder „Speichern“ die Auswahl wieder zeigen
    func reopenEffort() {
        guard effortPrompt == .skipped || effortPrompt == .saved else { return }
        effortPrompt = .asking
    }

    private func clearTraining() {
        plan = nil
        planEngine = nil
        planStatus = nil
        lapTrack = nil
        phaseMarks = []
    }

    /// Dieselbe Strecke ohne Wende und mit sehr grosser Länge: Die Session zählt nur Distanz und Zeit.
    private static func endlessCourse(_ c: Course) -> Course {
        var e = c
        e.turns = 0
        e.oneWayM = 1_000_000
        e.totalM = 1_000_000
        return e
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
        var events = s.update(snap, at: date)
        // Training: Phasen weiterführen; nach der letzten Phase ist die Fahrt zu Ende
        if stepTraining(s, snap: snap, at: date), !s.isFinished {
            events += s.finish(at: date)
        }
        session = s
        if s.state != .ready {
            health.record(snapshot: relativeSnapshot(s, snap), at: date)
        }
        for e in events { handle(e, at: date) }
        if phase == .active, date.timeIntervalSince(lastCheckpointAt) >= Self.checkpointInterval {
            writeCheckpoint(at: date)
        }
    }

    /// Füttert den Trainingsablauf mit dem Stand der Fahrt. Gibt true zurück, wenn das Training gerade fertig ist.
    private func stepTraining(_ s: RowingSession, snap: RowingSnapshot, at date: Date) -> Bool {
        guard var engine = planEngine, s.state != .ready else { return false }
        let wasFinished = engine.finished
        let elapsed = s.totalTime(at: date)
        if phaseMarks.isEmpty { phaseMarks = [PlanPhaseMark(index: 0, startTime: 0, startDistance: 0)] }
        let before = engine.boundaries.count
        let status = engine.update(activeTime: s.activeTime, elapsedTime: elapsed, distance: s.distance,
                                   speed: s.state == .rowing ? snap.speed : 0)
        planEngine = engine
        planStatus = status
        if engine.boundaries.count > before {
            phaseChangedAt = date
            for b in engine.boundaries[before...] where b.index + 1 < engine.phases.count {
                phaseMarks.append(PlanPhaseMark(index: b.index + 1, startTime: elapsed, startDistance: b.endDistance))
            }
        }
        if let lt = lapTrack {
            let lap = Laps.split(distance: s.distance, lapLength: lt.lapLength).lap
            if lap > currentLap {
                currentLap = lap
                lapChangedAt = date
            }
        }
        return status.finished && !wasFinished
    }

    /// Training aus der Session; bei einem Trainingsprogramm mit Programm, Werten je Phase und echter Streckenlänge.
    private func makeRecord(_ s: RowingSession, now: Date) -> WorkoutRecord {
        var rec = s.makeRecord(id: rideId, device: deviceInfo(), zones: currentZones(), appVersion: appVersion(),
                               workoutPlanId: plan?.id, now: now)
        if let plan {
            rec.header.workoutPlanName = plan.name
            rec.header.courseLength = lapTrack?.lapLength
            let finished = planStatus?.finished ?? false
            rec.summary.completedCourse = finished
            rec.planPhases = PlanPhaseResult.compute(plan: plan, marks: phaseMarks, samples: rec.samples,
                                                     endTime: s.totalTime(at: now), endDistance: s.distance,
                                                     planFinished: finished)
        }
        return rec
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
        let rec = makeRecord(copy, now: date)
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
        var built = makeRecord(s, now: Date())
        // Einschätzung der Belastung durch die App (Vorschlag in der Zusammenfassung, geschätzte Belastung in Health)
        built.ensureEffortEstimate(maxHR: currentZones().maxHR, best2k: TrainingSettings.best2k, plan: plan)
        let rec = built
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
            // Mit dem Training geht die Strecke als Route mit (wenn freigegeben und die Strecke verortet ist)
            if health.isRecording { saved = await health.finish(route: rec) }
            healthSaved = saved
            Logger(subsystem: "com.falkue.RowCoach", category: "Session").info(
                "Fahrt beendet: \(Int(rec.summary.distance), privacy: .public) m, Health gespeichert: \(saved, privacy: .public), Hinweis: \(self.healthNote ?? self.health.lastError ?? "-", privacy: .public)")
            if !saved, healthNote == nil, let e = health.lastError { healthNote = e }
            if saved, healthNote == nil, let routeNote = health.lastRouteNote { healthNote = routeNote }
            store.markSavedToHealth(item, saved)
            phase = .done
            let estimateText = rec.effort?.estimate.map { "\($0)" } ?? "-"
            let basisText = rec.effort?.basis?.title ?? "-"
            Logger(subsystem: "com.falkue.RowCoach", category: "Session").info(
                "Belastung: Einschätzung der App \(estimateText, privacy: .public) (\(basisText, privacy: .public))")
            // Testbetrieb: `-demoEffort <1-10>` zusammen mit `-demoFinishAfter` trägt die Belastung ohne Bedienung ein
            let demoEffort = UserDefaults.standard.integer(forKey: "demoEffort")
            if (1...10).contains(demoEffort), UserDefaults.standard.double(forKey: "demoFinishAfter") > 0 {
                Logger(subsystem: "com.falkue.RowCoach", category: "Session").info("Demo-Belastung \(demoEffort, privacy: .public)")
                saveEffort(demoEffort)
            }
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
