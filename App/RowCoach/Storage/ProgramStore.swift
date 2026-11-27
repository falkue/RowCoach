import Foundation
import os
import Observation
import RowCoachKit

private let programLog = Logger(subsystem: "com.falkue.RowCoach", category: "Program")

/// Trainingspläne aus `training_plans.json` im App-Bundle (Quelle: docs/trainingsplaene/gen_training_plans.py)
enum ProgramLibrary {
    static let catalog: TrainingProgramCatalog = TrainingProgramCatalog.loadBundled()

    static var programs: [TrainingProgram] { catalog.programs }

    static func program(id: String) -> TrainingProgram? { catalog.program(id: id) }
}

/// Aktiver Trainingsplan (docs/trainingsplaene/UMSETZUNG.md): Zustand als JSON in UserDefaults
/// (`trainingProgram.active`), alle Regeln in RowCoachKit (`TrainingProgramEngine`). Offline, ohne Konto.
///
/// - `sync` gleicht den Plan bei jedem Neurechnen des Startbildschirms mit den gespeicherten Fahrten ab (erledigt,
///   verpasst, verschoben, Wochenwechsel, Pause nach 10 Tagen) und liefert die Tage für den Tagesvorschlag.
/// - Ein schnellerer Test übernimmt die neue 2000-m-Referenz sofort; ein langsamerer wartet auf die Rückfrage
///   (`reference`), RECHERCHE 5.4.
/// - `launchRef` gibt beim Start einer Fahrt den Bezug zur Einheit, damit die Fahrt als erledigt zählt.
@MainActor
@Observable
final class ProgramStore {
    static let storageKey = "trainingProgram.active"

    private(set) var active: ActiveTrainingProgram?

    /// wird nach jeder Änderung durch den Nutzer aufgerufen (Startbildschirm neu rechnen)
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    /// zuletzt bekannte Fahrten (für Abgleich nach Änderungen ohne neue Fahrt)
    @ObservationIgnored private var rides: [ProgramRide] = []
    /// Einheit, die gerade aus der Wochenansicht gestartet wird
    @ObservationIgnored private var pendingLaunch: ProgramSessionRef?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var syncObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                active = try JSONDecoder().decode(ActiveTrainingProgram.self, from: data)
            } catch {
                programLog.error("Plan nicht lesbar: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Plan von einem anderen Gerät übernommen (Synchronisation, docs/SYNC.md)
        syncObserver = NotificationCenter.default.addObserver(forName: SyncNotifications.settingsApplied, object: nil,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadFromDefaults() }
        }
    }

    /// Zustand neu aus UserDefaults lesen (nach der Synchronisation); fehlt er, ist kein Plan aktiv
    func reloadFromDefaults() {
        let loaded = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(ActiveTrainingProgram.self, from: $0) }
        guard loaded != active else { return }
        active = loaded
        pendingLaunch = nil
        changed()
    }

    // MARK: Umgebung

    var calendar: Calendar { TrainingCalendar.swiss() }

    func environment() -> ProgramEnvironment {
        ProgramEnvironment(catalog: ProgramLibrary.catalog, workouts: PlanLibrary.plans, calendar: calendar,
                           best2k: TrainingSettings.best2k)
    }

    var program: TrainingProgram? { active.flatMap { ProgramLibrary.program(id: $0.programId) } }

    /// Tempoziele des Plans langsamer um so viele s/500 m (für den Start einer Planeinheit)
    var paceAdjustment: Double { active?.paceAdjustment ?? 0 }

    // MARK: Lebenszyklus

    /// Plan starten (ersetzt einen laufenden Plan)
    func start(_ program: TrainingProgram, startDate: Date, weekdays: [Weekday], now: Date = Date()) throws {
        var st = try TrainingProgramEngine.start(program: program, startDate: startDate, weekdays: weekdays,
                                                 env: environment(), now: now)
        TrainingProgramEngine.update(&st, rides: rides, now: now, env: environment())
        set(st)
        changed()
    }

    func pause(now: Date = Date()) {
        mutate { TrainingProgramEngine.pause(&$0, now: now, calendar: calendar) }
    }

    func resume(now: Date = Date()) {
        mutate { st in
            TrainingProgramEngine.resume(&st, now: now, env: environment())
            TrainingProgramEngine.update(&st, rides: rides, now: now, env: environment())
        }
    }

    /// Plan beenden (der Zustand wird gelöscht; die Fahrten bleiben im Verlauf)
    func end() {
        active = nil
        pendingLaunch = nil
        defaults.removeObject(forKey: Self.storageKey)
        changed()
    }

    func swapToEasy(sessionId: String) {
        mutate { _ = TrainingProgramEngine.swapToEasy(&$0, sessionId: sessionId, env: environment()) }
    }

    func restoreOriginal(sessionId: String) {
        mutate { TrainingProgramEngine.restoreOriginal(&$0, sessionId: sessionId) }
    }

    func dismissNotice(_ id: UUID) {
        mutate { TrainingProgramEngine.dismissNotice(&$0, id: id) }
    }

    /// Rückfrage „neue Referenz übernehmen?“ beantworten
    func answerReference(accept: Bool) {
        guard let proposal = active?.reference else { return }
        // Schwellenprofil ist die Quelle; es spiegelt die 2k-Referenz (docs/schwelle/SPEC.md 8.1)
        if accept {
            ThresholdStore.shared.applyProgramReference(best2k: proposal.best2k, planId: proposal.planId,
                                                        workoutId: proposal.workoutId, date: proposal.date)
        }
        mutate { TrainingProgramEngine.resolveReference(&$0) }
    }

    // MARK: Abgleich

    /// Abgleich mit den gespeicherten Fahrten; liefert die Tage für den Tagesvorschlag (nil ohne Plan)
    @discardableResult
    func sync(sessions: [TrainingSession], now: Date = Date()) -> ProgramAgenda? {
        let simulated = Self.countsSimulatedRides
        rides = sessions.compactMap { ProgramRide(session: $0, includeSimulated: simulated) }
        guard var st = active else { return nil }
        let env = environment()
        TrainingProgramEngine.update(&st, rides: rides, now: now, env: env)
        // schnellerer Test: neue Referenz ohne Rückfrage übernehmen
        if let r = st.reference, !r.isWorse {
            ThresholdStore.shared.applyProgramReference(best2k: r.best2k, planId: r.planId, workoutId: r.workoutId,
                                                        date: r.date)
            st.reference = nil
        }
        set(st)
        return TrainingProgramEngine.agenda(st, now: now, env: environment())
    }

    /// Tage für den Tagesvorschlag ohne neuen Abgleich
    func agenda(now: Date = Date()) -> ProgramAgenda? {
        active.flatMap { TrainingProgramEngine.agenda($0, now: now, env: environment()) }
    }

    /// Vorschau der nächsten Woche
    func preview(now: Date = Date()) -> [ScheduledProgramSession] {
        active.map { TrainingProgramEngine.preview($0, now: now, env: environment()) } ?? []
    }

    // MARK: Fahrt starten

    /// Die nächste Fahrt mit diesem Programm zählt für genau diese Einheit (Start aus der Wochenansicht)
    func prepareLaunch(sessionId: String) {
        pendingLaunch = active?.session(id: sessionId)?.ref
    }

    /// Bezug für eine Fahrt mit `planId`: die vorgemerkte Einheit, sonst die heutige bzw. nächste offene Einheit
    /// dieses Programms in der laufenden Woche; nil ohne passende Einheit (dann zählt die Fahrt frei).
    func launchRef(for planId: String, now: Date = Date()) -> ProgramSessionRef? {
        defer { pendingLaunch = nil }
        guard let st = active else { return nil }
        if let p = pendingLaunch, let s = st.sessions.first(where: { $0.ref == p }), s.status != .done,
           s.planId == planId || s.originalPlanId == planId {
            return p
        }
        return TrainingProgramEngine.launchRef(st, planId: planId, now: now, calendar: calendar)
    }

    /// Simulatorfahrten zählen für den Plan als erledigt im Debug-Build oder mit „Simulatorfahrten im Verlauf zeigen“
    /// (Testbetrieb); sonst nie, damit die echte Statistik sauber bleibt
    static var countsSimulatedRides: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: HistorySettings.showSimulatedKey)
        #endif
    }

    // MARK: intern

    private func mutate(_ change: (inout ActiveTrainingProgram) -> Void) {
        guard var st = active else { return }
        change(&st)
        set(st)
        changed()
    }

    private func set(_ st: ActiveTrainingProgram) {
        guard st != active else { return }
        active = st
        do {
            defaults.set(try JSONEncoder().encode(st), forKey: Self.storageKey)
        } catch {
            programLog.error("Plan nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func changed() {
        onChange?()
    }
}
