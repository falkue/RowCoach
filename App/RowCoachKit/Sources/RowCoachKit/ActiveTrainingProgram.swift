import Foundation

// Gewählter Trainingsplan mit Startdatum, Wunschtagen, Fortschritt, erledigten, verpassten und verschobenen Einheiten
// und Pausen (docs/trainingsplaene/RECHERCHE.md, Kapitel 5; Umsetzung: docs/trainingsplaene/UMSETZUNG.md).
//
// Der Zustand ist ein Codable-Wert (die App speichert ihn als JSON in UserDefaults). Alle Änderungen laufen über
// reine Funktionen: `TrainingProgramEngine.start` legt ihn an, `update` gleicht ihn mit den gespeicherten Fahrten
// und dem Datum ab (erledigt, verpasst, verschieben, Wochenwechsel, Pause nach 10 Tagen, Effort- und Test-Regeln),
// `pause`/`resume`, `swapToEasy` und `end` setzen die Wünsche des Nutzers um. Gleiche Eingaben ergeben immer
// denselben Zustand.

/// Bezug einer Fahrt auf eine Einheit eines Plans (im gespeicherten Training: `WorkoutHeader.trainingProgram`)
public struct ProgramSessionRef: Codable, Hashable, Sendable {
    /// Plan (bzw. Wiedereinstiegsplan), aus dem die Einheit stammt
    public var programId: String
    /// laufende Nummer der Planwoche im Zustand (`ProgramWeekRun.run`)
    public var run: Int
    /// Woche im Plan (1…)
    public var week: Int
    /// Einheit in der Woche (1…)
    public var slot: Int

    public init(programId: String, run: Int, week: Int, slot: Int) {
        self.programId = programId
        self.run = run
        self.week = week
        self.slot = slot
    }
}

/// Eine Einheit, wie sie im Kalender liegt
public struct ScheduledProgramSession: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case planned, done, skipped
    }

    public enum SkipReason: String, Codable, Sendable {
        /// Tag verstrichen, kein Ersatztag
        case missed
        /// kein Wunschtag frei (weniger Tage als Einheiten)
        case noDay
        /// Plan wurde pausiert
        case paused
        /// nach kurzer Pause: in der Woche schon erledigt
        case alreadyDone
    }

    /// Anzeige in der Wochenansicht
    public enum Display: String, Sendable {
        case done, open, missed, moved
    }

    public var run: Int
    public var week: Int
    public var programId: String
    public var slot: Int
    /// gefahrenes Programm (nach einem Tausch die leichte Variante)
    public var planId: String
    /// Programm laut Plan
    public var originalPlanId: String
    public var intensity: PlanIntensity
    public var originalIntensity: PlanIntensity
    public var optional: Bool
    public var event: Bool
    public var note: String
    /// Tag (Tagesbeginn); nil = ohne Tag (freiwillig ohne passenden Tag oder entfallen)
    public var date: Date?
    /// ursprünglich geplanter Tag
    public var originalDate: Date?
    public var status: Status
    public var skipReason: SkipReason?
    public var workoutId: UUID?
    public var completedAt: Date?
    /// Belastung 1–10 der Fahrt (eigene, sonst geschätzte)
    public var effort: Int?
    /// Tempo der Belastungsphasen der Fahrt (s/500 m)
    public var workPace: Double?
    /// Test bereits für die Referenz ausgewertet
    public var testEvaluated: Bool?

    public var id: String { "\(run)-\(slot)" }
    public var ref: ProgramSessionRef { ProgramSessionRef(programId: programId, run: run, week: week, slot: slot) }
    public var isHard: Bool { intensity >= .hard }
    public var isMoved: Bool { date != nil && originalDate != nil && date != originalDate }
    public var isReplaced: Bool { planId != originalPlanId }

    public func display(today: Date) -> Display {
        switch status {
        case .done: return .done
        case .skipped: return .missed
        case .planned: return isMoved ? .moved : .open
        }
    }
}

/// Eine Planwoche im Kalender (eine Woche kann wiederholt oder um 1–2 Tage verlängert werden)
public struct ProgramWeekRun: Codable, Equatable, Sendable {
    public var run: Int
    /// Plan dieser Woche (Hauptplan oder Wiedereinstieg)
    public var programId: String
    public var week: Int
    /// Runde bei offenen Plänen (`repeatFrom`), 0 = erste
    public var cycle: Int
    /// erster Tag (Tagesbeginn)
    public var start: Date
    /// Tag nach dem letzten Tag (Tagesbeginn)
    public var end: Date
    /// um so viele Tage verlängert (Policy `shift`, Zieleinheit)
    public var extendedDays: Int
    /// Wiederholung der vorherigen Woche (Einsteiger: zu viele Einheiten verpasst; nach einer Pause)
    public var repeated: Bool
    /// leichtere Variante nach hohem Effort (RECHERCHE 5.5)
    public var deload: Bool
    /// schon eine harte Einheit in dieser Woche nachgeholt (nie zwei)
    public var rescheduledHard: Int
    /// abgeschlossen (Woche vorbei oder durch Pause beendet)
    public var closed: Bool
}

/// Rückkehr in den Hauptplan nach dem Wiedereinstiegsplan (RECHERCHE 5.3)
public struct ProgramBridge: Codable, Equatable, Sendable {
    public var programId: String
    /// Woche im Hauptplan nach dem Wiedereinstieg
    public var resumeWeek: Int
}

/// Hinweis an den Nutzer (Wochenansicht des Plans); die App entfernt ihn mit `dismissNotice`
public struct ProgramNotice: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// drei leichte Einheiten mit RPE ≥ 7: nächste Woche leichter
        case recoveryCheck
        /// zwei harte Einheiten mit RPE 10 und verfehltem Tempo: Tempoziele langsamer (`value` s/500 m)
        case paceLowered
        /// harte Einheiten fallen leicht: Test vorschlagen
        case retestSuggested
        /// auch nach der leichteren Woche hoher RPE: pausieren und Wiedereinstieg
        case pauseSuggested
        /// Einsteiger: Woche wird wiederholt (`week`)
        case weekRepeated
        /// 10 Tage ohne Fahrt: Plan pausiert
        case autoPaused
        /// Plan fortgesetzt (`value` = Pausentage, `week` = Woche)
        case resumed
        /// nach langer Pause neu gestartet
        case restarted
        /// Test schneller als die Referenz: neue Referenz übernommen (`value` = neue 2000-m-Zeit in s)
        case referenceImproved
        /// Test langsamer als die Referenz: Rückfrage (`value` = Testwert in s)
        case referenceWorse
        /// Plan zu Ende
        case finished
    }

    public var id: UUID
    public var kind: Kind
    public var date: Date
    public var value: Double?
    public var week: Int?

    public init(id: UUID = UUID(), kind: Kind, date: Date, value: Double? = nil, week: Int? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.value = value
        self.week = week
    }
}

/// Neue 2000-m-Referenz aus einem Test im Plan (RECHERCHE 5.4)
public struct ReferenceProposal: Codable, Equatable, Sendable {
    /// geschätzte 2000-m-Zeit (s)
    public var best2k: Double
    /// bisherige Referenz (s)
    public var previous: Double
    public var planId: String
    public var workoutId: UUID?
    public var date: Date
    /// schlechter als die bisherige Referenz: nur nach Rückfrage übernehmen
    public var isWorse: Bool
}

/// Zustand eines laufenden Plans
public struct ActiveTrainingProgram: Codable, Equatable, Sendable {
    public var programId: String
    public var startDate: Date
    public var weekdays: [Weekday]
    /// Verpasstes darf auch auf Tage ausserhalb der Wunschtage rücken
    public var allowAnyDay: Bool
    public var runs: [ProgramWeekRun]
    public var sessions: [ScheduledProgramSession]
    public var bridge: ProgramBridge?
    public var pausedAt: Date?
    public var autoPaused: Bool
    /// Tempoziele langsamer um so viele s/500 m (nach Pause oder RPE-Regel; ein Test setzt zurück)
    public var paceAdjustment: Double
    /// nächste Woche als leichtere Woche (RPE-Regel)
    public var forceDeloadNext: Bool
    public var notices: [ProgramNotice]
    /// offene Rückfrage zur Referenz
    public var reference: ReferenceProposal?
    public var finishedAt: Date?
    /// Zeitpunkt der zuletzt ausgelösten Effort-Regel (je Regel), damit sie nicht zweimal greift
    public var effortRuleMarks: [String: Date]

    public init(programId: String, startDate: Date, weekdays: [Weekday], allowAnyDay: Bool = false) {
        self.programId = programId
        self.startDate = startDate
        self.weekdays = Array(Set(weekdays)).sorted()
        self.allowAnyDay = allowAnyDay
        runs = []
        sessions = []
        bridge = nil
        pausedAt = nil
        autoPaused = false
        paceAdjustment = 0
        forceDeloadNext = false
        notices = []
        reference = nil
        finishedAt = nil
        effortRuleMarks = [:]
    }

    public var isPaused: Bool { pausedAt != nil }
    public var isFinished: Bool { finishedAt != nil }
    public var currentRun: ProgramWeekRun? { runs.last }

    /// Einheiten einer Planwoche (nach Tag, ohne Tag am Ende)
    public func sessions(inRun run: Int) -> [ScheduledProgramSession] {
        sessions.filter { $0.run == run }.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): return x != y ? x < y : a.slot < b.slot
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.slot < b.slot
            }
        }
    }

    public func session(id: String) -> ScheduledProgramSession? { sessions.first { $0.id == id } }

    /// Woche im Hauptplan (beim Wiedereinstieg die Woche, zu der danach zurückgekehrt wird)
    public var mainWeek: Int {
        guard let r = currentRun else { return 1 }
        return r.programId == programId ? r.week : (bridge?.resumeWeek ?? r.week)
    }

    /// Läuft gerade der Wiedereinstiegsplan?
    public var inBridge: Bool { currentRun.map { $0.programId != programId } ?? false }

    /// effektive 2000-m-Zeit für die Tempoziele (Referenz plus Anpassung, 4 × s/500 m)
    public func effectiveBest2k(_ best2k: Double) -> Double { best2k + 4 * paceAdjustment }
}

/// Eingaben aus der App: Pläne, Programme, Kalender, Referenz
public struct ProgramEnvironment: Sendable {
    public var catalog: TrainingProgramCatalog
    public var workouts: [WorkoutPlan]
    public var calendar: Calendar
    /// 2000-m-Referenz (s)
    public var best2k: Double

    public init(catalog: TrainingProgramCatalog, workouts: [WorkoutPlan], calendar: Calendar = TrainingCalendar.swiss(),
                best2k: Double = PaceTargets.defaultBest2k) {
        self.catalog = catalog
        self.workouts = workouts
        self.calendar = calendar
        self.best2k = best2k
    }

    func workout(_ id: String) -> WorkoutPlan? { workouts.first { $0.id == id } }
}

/// Eine gespeicherte Fahrt aus Sicht des Plans
public struct ProgramRide: Equatable, Sendable {
    public var workoutId: UUID
    public var start: Date
    public var planId: String?
    public var ref: ProgramSessionRef?
    /// Belastung 1–10
    public var effort: Int?
    /// Tempo der Belastungsphasen (s/500 m)
    public var workPace: Double?
    public var activeDuration: Double
    public var distance: Double
    /// Programm zu Ende gefahren
    public var completed: Bool

    public init(workoutId: UUID = UUID(), start: Date, planId: String? = nil, ref: ProgramSessionRef? = nil,
                effort: Int? = nil, workPace: Double? = nil, activeDuration: Double = 1800, distance: Double = 7000,
                completed: Bool = true) {
        self.workoutId = workoutId
        self.start = start
        self.planId = planId
        self.ref = ref
        self.effort = effort
        self.workPace = workPace
        self.activeDuration = activeDuration
        self.distance = distance
        self.completed = completed
    }

    /// Aus einer verdichteten Fahrt; nil für Simulatorfahrten, ausser `includeSimulated` (Testbetrieb: Einstellung
    /// „Simulatorfahrten im Verlauf zeigen“ oder Debug-Build – dann zählt auch eine Simulatorfahrt als erledigt)
    public init?(session s: TrainingSession, includeSimulated: Bool = false) {
        guard s.countsInStats || includeSimulated else { return nil }
        self.init(workoutId: s.id, start: s.start, planId: s.planId, ref: s.programRef, effort: s.effortScore,
                  workPace: s.workPace ?? (s.averagePace > 0 ? s.averagePace : nil),
                  activeDuration: s.activeDuration, distance: s.distance, completed: s.completedCourse)
    }
}

/// Tage mit Einheit für den Tagesvorschlag (`DailySuggestion`)
public struct ProgramAgenda: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public var date: Date
        public var sessionId: String
        public var planId: String
        public var intensity: PlanIntensity
        public var week: Int
        /// Nummer unter den Pflicht-Einheiten der Woche (nil = freiwillig)
        public var index: Int?
        public var count: Int
        public var event: Bool
        public var optional: Bool
        public var done: Bool
    }

    public var programName: String
    public var week: Int
    public var weeks: Int
    public var inBridge: Bool
    public var paused: Bool
    public var startDate: Date
    public var hasOwnTest: Bool
    public var days: [Day]
    /// freiwillige Einheit der Woche ohne festen Tag (Angebot an Ruhetagen)
    public var weekOptional: String?

    public func day(_ date: Date, calendar: Calendar) -> Day? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) && !$0.done } ?? days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

/// Logik der Trainingspläne (reine Funktionen auf `ActiveTrainingProgram`)
public enum TrainingProgramEngine {
    /// Programme, die als Test zählen und eine neue Referenz liefern
    public static func isTestPlan(_ planId: String) -> Bool {
        planId.hasPrefix("test-") || planId.hasPrefix("einsteiger-test") || planId.hasPrefix("schwelle-test-")
            || planId == "schwelle-rampentest" || planId == "schwelle-stufentest-puls"
    }

    /// Wiedereinstiegsplan (RECHERCHE 5.3)
    public static let reentryProgramId = "wiedereinstieg-3-wochen"
    /// Tage ohne Fahrt, nach denen der Plan pausiert
    public static let autoPauseDays = 10

    /// Leichte Grundlage ähnlicher Dauer als Ersatz für eine harte oder mittlere Einheit (RECHERCHE 5.2)
    public static let easyCandidates = ["grundlage-ut2-20", "grundlage-locker-30", "grundlage-3x10-r20",
                                        "grundlage-locker-45", "grundlage-5000m-ut2", "grundlage-8000m-steady-r22"]

    public static func easyVariant(for planId: String, workouts: [WorkoutPlan], best2k: Double) -> String {
        let fallback = DailySuggestion.Plans.easy30
        guard let plan = workouts.first(where: { $0.id == planId }) else { return fallback }
        let available = easyCandidates.compactMap { id in workouts.first { $0.id == id } }
        guard !available.isEmpty else { return fallback }
        let target = plan.estimatedDuration(best2k: best2k)
        return available.min { abs($0.estimatedDuration(best2k: best2k) - target) < abs($1.estimatedDuration(best2k: best2k) - target) }?.id
            ?? fallback
    }

    /// Leichtere Variante für „Einheit tauschen“: harte und mittlere → leichte Grundlage ähnlicher Dauer;
    /// leichte → Regeneration 20 (nil, wenn es keine leichtere gibt)
    public static func lighterVariant(for s: ScheduledProgramSession, env: ProgramEnvironment) -> String? {
        if s.event { return nil }
        if s.intensity >= .moderate { return easyVariant(for: s.planId, workouts: env.workouts, best2k: env.best2k) }
        let reg = "regeneration-20"
        guard s.planId != reg, env.workouts.isEmpty || env.workout(reg) != nil else { return nil }
        return reg
    }

    // MARK: Start

    /// Neuen Plan anlegen; erste Woche ab `startDate` auf die Wunschtage verteilt
    public static func start(program: TrainingProgram, startDate: Date, weekdays: [Weekday], env: ProgramEnvironment,
                             now: Date, allowAnyDay: Bool = false) throws -> ActiveTrainingProgram {
        if let problem = TrainingProgramScheduler.check(weekdays: Set(weekdays), program: program) { throw problem }
        let d = ProgramDays(calendar: env.calendar)
        var state = ActiveTrainingProgram(programId: program.id, startDate: d.startOfDay(startDate), weekdays: weekdays,
                                          allowAnyDay: allowAnyDay)
        var ctx = Context(state: state, env: env, today: d.number(now))
        ctx.startRun(programId: program.id, week: 1, cycle: 0, start: d.number(startDate), repeated: false)
        state = ctx.state
        return state
    }

    // MARK: Abgleich

    /// Abgleich mit den gespeicherten Fahrten und dem heutigen Datum
    public static func update(_ state: inout ActiveTrainingProgram, rides: [ProgramRide], now: Date,
                              env: ProgramEnvironment) {
        guard !state.isFinished, !state.runs.isEmpty else { return }
        var ctx = Context(state: state, env: env, today: ProgramDays(calendar: env.calendar).number(now))
        ctx.update(rides: rides, now: now)
        state = ctx.state
    }

    /// Plan anhalten (Einheiten bleiben stehen, nichts gilt als verpasst)
    public static func pause(_ state: inout ActiveTrainingProgram, now: Date, calendar: Calendar) {
        guard !state.isPaused, !state.isFinished else { return }
        state.pausedAt = calendar.startOfDay(for: now)
        state.autoPaused = false
    }

    /// Plan fortsetzen; Vorgehen nach Länge der Pause (RECHERCHE 5.3)
    public static func resume(_ state: inout ActiveTrainingProgram, now: Date, env: ProgramEnvironment) {
        guard state.isPaused, !state.isFinished else { return }
        var ctx = Context(state: state, env: env, today: ProgramDays(calendar: env.calendar).number(now))
        ctx.resume(now: now)
        state = ctx.state
    }

    /// Einheit gegen die leichtere Variante tauschen (nicht die Zieleinheit, nicht erledigte)
    @discardableResult
    public static func swapToEasy(_ state: inout ActiveTrainingProgram, sessionId: String, env: ProgramEnvironment) -> Bool {
        guard let i = state.sessions.firstIndex(where: { $0.id == sessionId }), state.sessions[i].status == .planned,
              let alt = lighterVariant(for: state.sessions[i], env: env) else { return false }
        state.sessions[i].planId = alt
        state.sessions[i].intensity = .easy
        return true
    }

    /// Tausch rückgängig machen
    public static func restoreOriginal(_ state: inout ActiveTrainingProgram, sessionId: String) {
        guard let i = state.sessions.firstIndex(where: { $0.id == sessionId }), state.sessions[i].status == .planned
        else { return }
        state.sessions[i].planId = state.sessions[i].originalPlanId
        state.sessions[i].intensity = state.sessions[i].originalIntensity
    }

    public static func dismissNotice(_ state: inout ActiveTrainingProgram, id: UUID) {
        state.notices.removeAll { $0.id == id }
    }

    /// Rückfrage zur Referenz erledigt (übernommen oder abgelehnt)
    public static func resolveReference(_ state: inout ActiveTrainingProgram) {
        state.reference = nil
        state.notices.removeAll { $0.kind == .referenceWorse }
    }

    // MARK: Abfragen

    /// Einheit, die eine Fahrt mit `planId` heute erledigen würde (für den Bezug beim Start)
    public static func launchRef(_ state: ActiveTrainingProgram, planId: String, now: Date,
                                 calendar: Calendar) -> ProgramSessionRef? {
        guard !state.isPaused, !state.isFinished, let run = state.currentRun else { return nil }
        let open = state.sessions(inRun: run.run).filter {
            $0.status == .planned && ($0.planId == planId || $0.originalPlanId == planId)
        }
        let today = open.first { $0.date.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        return (today ?? open.first)?.ref
    }

    /// Tage mit Einheit (aktuelle Woche und Vorschau der nächsten) für den Tagesvorschlag
    public static func agenda(_ state: ActiveTrainingProgram, now: Date, env: ProgramEnvironment) -> ProgramAgenda? {
        guard !state.isFinished, let run = state.currentRun else { return nil }
        let program = env.catalog.program(id: state.programId)
        let runProgram = env.catalog.program(id: run.programId)
        var days: [ProgramAgenda.Day] = []
        var optionalFree: String?
        func add(_ list: [ScheduledProgramSession]) {
            let req = list.filter { !$0.optional && $0.status != .skipped && $0.date != nil }
            for s in list where s.status != .skipped {
                guard let date = s.date else {
                    if s.optional && s.status == .planned && optionalFree == nil && s.run == run.run { optionalFree = s.planId }
                    continue
                }
                days.append(.init(date: date, sessionId: s.id, planId: s.planId, intensity: s.intensity, week: s.week,
                                  index: s.optional ? nil : (req.firstIndex { $0.id == s.id }.map { $0 + 1 }),
                                  count: req.count, event: s.event, optional: s.optional, done: s.status == .done))
            }
        }
        if !state.isPaused {
            add(state.sessions(inRun: run.run))
            add(preview(state, now: now, env: env))
        }
        return ProgramAgenda(programName: (state.inBridge ? runProgram : program)?.name ?? state.programId,
                             week: run.week, weeks: (runProgram ?? program)?.weeks ?? run.week,
                             inBridge: state.inBridge, paused: state.isPaused, startDate: state.startDate,
                             hasOwnTest: program?.hasOwnTest ?? false, days: days, weekOptional: optionalFree)
    }

    /// Vorschau der nächsten Planwoche (ohne den Zustand zu ändern)
    public static func preview(_ state: ActiveTrainingProgram, now: Date, env: ProgramEnvironment) -> [ScheduledProgramSession] {
        guard !state.isFinished, !state.isPaused, let run = state.currentRun else { return [] }
        let d = ProgramDays(calendar: env.calendar)
        var ctx = Context(state: state, env: env, today: max(d.number(now), d.number(run.end)))
        guard ctx.startNextRun(after: run) else { return [] }
        let next = ctx.state.runs.last?.run ?? -1
        return ctx.state.sessions(inRun: next)
    }

    /// Fortschritt: Woche x von n und Anteil erledigter Pflicht-Einheiten
    public static func progress(_ state: ActiveTrainingProgram, env: ProgramEnvironment) -> (week: Int, weeks: Int, doneShare: Double) {
        let program = env.catalog.program(id: state.programId)
        let weeks = program?.weeks ?? state.mainWeek
        let main = state.sessions.filter { $0.programId == state.programId && !$0.optional }
        let done = main.filter { $0.status == .done }.count
        let total = max(1, program.map { p in p.weekPlans.reduce(0) { $0 + $1.required.count } } ?? main.count)
        return (min(state.mainWeek, max(weeks, 1)), weeks, min(1, Double(done) / Double(total)))
    }

    // MARK: - Rechenkontext

    struct Context {
        var state: ActiveTrainingProgram
        let env: ProgramEnvironment
        let today: Int
        let days: ProgramDays

        init(state: ActiveTrainingProgram, env: ProgramEnvironment, today: Int) {
            self.state = state
            self.env = env
            self.today = today
            days = ProgramDays(calendar: env.calendar)
        }

        var mainProgram: TrainingProgram? { env.catalog.program(id: state.programId) }

        func rules(for programId: String) -> ProgramRules {
            let main = mainProgram?.rules ?? ProgramRules()
            guard programId != state.programId, let other = env.catalog.program(id: programId)?.rules else { return main }
            // Wiedereinstieg mit den strengeren Regeln beider Pläne (z. B. Masters 72 h)
            var r = other
            r.hardSessionsMinGapHours = max(other.hardSessionsMinGapHours, main.hardSessionsMinGapHours)
            r.maxConsecutiveDays = min(other.maxConsecutiveDays, main.maxConsecutiveDays)
            return r
        }

        func isWishDay(_ n: Int) -> Bool { state.weekdays.contains(days.weekday(n)) }

        /// belegte Tage (geplante und erledigte Einheiten) → hart; ohne `excluding`
        func occupied(excluding id: String? = nil) -> [Int: Bool] {
            var map: [Int: Bool] = [:]
            for s in state.sessions where s.status != .skipped && s.id != id {
                guard let dt = s.date else { continue }
                let n = days.number(dt)
                map[n] = (map[n] ?? false) || s.isHard
            }
            return map
        }

        // MARK: Woche anlegen

        /// Neue Planwoche ab Tag `start`; verteilt die Einheiten auf freie Wunschtage ab heute
        mutating func startRun(programId: String, week: Int, cycle: Int, start: Int, repeated: Bool,
                               skipSlots: Set<Int> = []) {
            guard let program = env.catalog.program(id: programId), let wk = program.week(week) else { return }
            let runIndex = (state.runs.last?.run ?? -1) + 1
            let deload = state.forceDeloadNext && programId == state.programId
            if deload { state.forceDeloadNext = false }
            let run = ProgramWeekRun(run: runIndex, programId: programId, week: week, cycle: cycle,
                                     start: days.date(start), end: days.date(start + 7), extendedDays: 0,
                                     repeated: repeated, deload: deload, rescheduledHard: 0, closed: false)
            state.runs.append(run)
            var list: [ScheduledProgramSession] = wk.sessions.map { s in
                ScheduledProgramSession(run: runIndex, week: week, programId: programId, slot: s.slot, planId: s.planId,
                                        originalPlanId: s.planId, intensity: s.intensity, originalIntensity: s.intensity,
                                        optional: s.optional, event: s.event, note: s.note, date: nil, originalDate: nil,
                                        status: .planned, skipReason: nil, workoutId: nil, completedAt: nil, effort: nil,
                                        workPace: nil, testEvaluated: nil)
            }
            for i in list.indices where skipSlots.contains(list[i].slot) {
                list[i].status = .skipped
                list[i].skipReason = .alreadyDone
            }
            if deload {
                // leichtere Woche: harte Einheiten durch die leichte Variante, freiwillige entfallen
                for i in list.indices where list[i].isHard && !list[i].event { replaceEasy(&list[i]) }
                for i in list.indices where list[i].optional {
                    list[i].status = .skipped
                    list[i].skipReason = .noDay
                }
            }
            let rideDays = Set(state.sessions.filter { $0.status == .done }.compactMap { $0.date.map(days.number) })
            let first = max(start, today)
            let candidates = first < start + 7 ? (first..<(start + 7)).filter { isWishDay($0) && !rideDays.contains($0) } : []
            let items = list.filter { $0.status == .planned }
            let req = items.filter { !$0.optional }.map {
                TrainingProgramScheduler.Item(key: $0.slot, hard: $0.isHard, event: $0.event)
            }
            let opt = items.filter(\.optional).map {
                TrainingProgramScheduler.Item(key: $0.slot, hard: $0.isHard, event: $0.event)
            }
            // Vorwoche: belegte Tage bis 7 Tage vor dem Start (harte Einheiten über die Wochengrenze)
            let fixed = occupied().filter { $0.key >= start - 7 && $0.key < start + 7 }
            let placement = TrainingProgramScheduler.placeWeek(required: req, optional: opt, candidates: candidates,
                                                               fixed: fixed, rules: rules(for: programId))
            for i in list.indices where list[i].status == .planned {
                let slot = list[i].slot
                if placement.replaced.contains(slot) { replaceEasy(&list[i]) }
                if let n = placement.days[slot] {
                    list[i].date = days.date(n)
                    list[i].originalDate = days.date(n)
                } else if placement.dropped.contains(slot) {
                    list[i].status = .skipped
                    list[i].skipReason = .noDay
                }
            }
            state.sessions.append(contentsOf: list)
        }

        func replaceEasy(_ s: inout ScheduledProgramSession) {
            s.planId = TrainingProgramEngine.easyVariant(for: s.originalPlanId, workouts: env.workouts, best2k: env.best2k)
            s.intensity = .easy
        }

        /// Nächste Woche nach `run` anlegen (Wiederholung, Wiedereinstieg, offene Pläne); false = Plan zu Ende
        @discardableResult
        mutating func startNextRun(after run: ProgramWeekRun) -> Bool {
            let start = days.number(run.end)
            if run.programId != state.programId {
                // Wiedereinstieg
                if let bridgeProgram = env.catalog.program(id: run.programId), run.week < bridgeProgram.weeks {
                    startRun(programId: run.programId, week: run.week + 1, cycle: 0, start: start, repeated: false)
                } else {
                    let w = state.bridge?.resumeWeek ?? 1
                    state.bridge = nil
                    startRun(programId: state.programId, week: w, cycle: run.cycle, start: start, repeated: false)
                }
                return true
            }
            guard let program = mainProgram else { return false }
            let rules = program.rules
            let missedRequired = state.sessions.filter {
                $0.run == run.run && !$0.optional && $0.status == .skipped
                    && ($0.skipReason == .missed || $0.skipReason == .noDay)
            }.count
            if let n = rules.repeatWeekIfMissed, n > 0, missedRequired >= n {
                state.notices.append(ProgramNotice(kind: .weekRepeated, date: days.date(start), week: run.week))
                startRun(programId: program.id, week: run.week, cycle: run.cycle, start: start, repeated: true)
                return true
            }
            if run.week < program.weeks {
                startRun(programId: program.id, week: run.week + 1, cycle: run.cycle, start: start, repeated: false)
                return true
            }
            if let from = rules.repeatFrom, from >= 1, from <= program.weeks {
                startRun(programId: program.id, week: from, cycle: run.cycle + 1, start: start, repeated: false)
                return true
            }
            return false
        }

        // MARK: Abgleich

        mutating func update(rides all: [ProgramRide], now: Date) {
            let start = days.number(state.startDate)
            let rides = all.filter { days.number($0.start) >= start && $0.start <= now }.sorted { $0.start < $1.start }
            match(rides)
            if state.isPaused { return }
            // 10 Tage ohne Fahrt: pausieren (RECHERCHE 5.3)
            let lastActivity = max(start, rides.last.map { days.number($0.start) } ?? start)
            if today - lastActivity >= TrainingProgramEngine.autoPauseDays {
                state.pausedAt = days.date(lastActivity + 1)
                state.autoPaused = true
                state.notices.append(ProgramNotice(kind: .autoPaused, date: days.date(today)))
                return
            }
            var guardCount = 0
            while var run = state.runs.last, guardCount < 200 {
                guardCount += 1
                processMissed(runIndex: run.run, before: min(today, days.number(run.end)))
                run = state.runs.last ?? run
                guard today >= days.number(run.end) else { break }
                state.runs[state.runs.count - 1].closed = true
                if !startNextRun(after: run) {
                    state.finishedAt = run.end
                    state.notices.append(ProgramNotice(kind: .finished, date: run.end))
                    break
                }
                match(rides)
            }
            applyEffortRules()
            evaluateTests(rides: rides, now: now)
        }

        /// Fahrten den Einheiten zuordnen: über den Bezug aus dem Start, sonst über das Programm in derselben Woche
        mutating func match(_ rides: [ProgramRide]) {
            let linked = Set(state.sessions.compactMap(\.workoutId))
            for ride in rides where !linked.contains(ride.workoutId) {
                let day = days.number(ride.start)
                var target: Int?
                if let ref = ride.ref {
                    target = state.sessions.firstIndex {
                        $0.programId == ref.programId && $0.run == ref.run && $0.slot == ref.slot && $0.status != .done
                    }
                }
                if target == nil, let planId = ride.planId,
                   let run = state.runs.first(where: { days.number($0.start) <= day && day < days.number($0.end) }) {
                    let open = state.sessions.indices.filter {
                        let s = state.sessions[$0]
                        return s.run == run.run && (s.status == .planned || (s.status == .skipped && s.skipReason == .missed))
                            && (s.planId == planId || s.originalPlanId == planId)
                    }
                    // gleicher Tag zuerst, dann der nächstgelegene geplante Tag
                    target = open.min { a, b in
                        let da = state.sessions[a].date.map { abs(days.number($0) - day) } ?? 99
                        let db = state.sessions[b].date.map { abs(days.number($0) - day) } ?? 99
                        if da != db { return da < db }
                        return state.sessions[a].status == .planned && state.sessions[b].status != .planned
                    }
                }
                guard let i = target, counts(ride, for: state.sessions[i].planId) else { continue }
                state.sessions[i].status = .done
                state.sessions[i].skipReason = nil
                state.sessions[i].workoutId = ride.workoutId
                state.sessions[i].completedAt = ride.start
                state.sessions[i].effort = ride.effort
                state.sessions[i].workPace = ride.workPace
                state.sessions[i].date = days.date(day)
                if state.sessions[i].originalDate == nil { state.sessions[i].originalDate = days.date(day) }
            }
        }

        /// Zählt eine Fahrt als erledigt? Zu Ende gefahren oder mindestens 60 % der geplanten Ruderzeit.
        func counts(_ ride: ProgramRide, for planId: String) -> Bool {
            if ride.completed { return true }
            guard let plan = env.workout(planId) else { return ride.activeDuration >= 600 }
            let active = plan.phases.filter { $0.kind != .rest }.reduce(0) { $0 + $1.estimatedSeconds(best2k: env.best2k) }
            return ride.activeDuration >= 0.6 * active
        }

        /// Geplante Einheiten vor Tag `limit` sind verpasst: verschieben oder nach Policy behandeln (RECHERCHE 5.2)
        mutating func processMissed(runIndex: Int, before limit: Int) {
            let ids = state.sessions(inRun: runIndex).filter {
                $0.status == .planned && ($0.date.map { days.number($0) < limit } ?? false)
            }.map(\.id)
            for id in ids { handleMissed(id: id, runIndex: runIndex) }
        }

        mutating func handleMissed(id: String, runIndex: Int) {
            guard let i = state.sessions.firstIndex(where: { $0.id == id }),
                  let r = state.runs.firstIndex(where: { $0.run == runIndex }) else { return }
            let s = state.sessions[i]
            if s.optional {
                skip(i)
                return
            }
            let rules = rules(for: s.programId)
            let runEnd = days.number(state.runs[r].end)
            // Zieleinheit: verschieben, nie streichen (notfalls über das Wochenende hinaus)
            if s.event {
                if let d = freeDay(for: i, from: today, to: runEnd + 14, rules: rules, wishOnly: false) {
                    move(i, to: d, run: r)
                } else {
                    skip(i)
                }
                return
            }
            // 1. innerhalb der Woche verschieben (nie zwei harte nachholen)
            let mayMoveHard = !s.isHard || state.runs[r].rescheduledHard == 0
            if mayMoveHard, let d = freeDay(for: i, from: today, to: runEnd, rules: rules, wishOnly: !state.allowAnyDay) {
                move(i, to: d, run: r)
                if s.isHard { state.runs[r].rescheduledHard += 1 }
                return
            }
            // 2. Policy
            switch rules.missedSessionPolicy {
            case .shift:
                let room = 2 - state.runs[r].extendedDays
                if room > 0, (!s.isHard || mayMoveHard),
                   let d = freeDay(for: i, from: today, to: runEnd + room, rules: rules, wishOnly: false) {
                    move(i, to: d, run: r)
                    if s.isHard { state.runs[r].rescheduledHard += 1 }
                } else {
                    skip(i)
                }
            case .replaceEasy:
                if s.intensity >= .moderate {
                    var easy = state.sessions[i]
                    replaceEasy(&easy)
                    let saved = state.sessions[i]
                    state.sessions[i] = easy
                    if let d = freeDay(for: i, from: today, to: runEnd, rules: rules, wishOnly: !state.allowAnyDay) {
                        move(i, to: d, run: r)
                    } else {
                        state.sessions[i] = saved
                        skip(i)
                    }
                } else {
                    skip(i)
                }
            case .skip:
                skip(i)
            }
        }

        mutating func skip(_ i: Int) {
            state.sessions[i].status = .skipped
            state.sessions[i].skipReason = .missed
        }

        /// Einheit auf Tag `d` legen; verlängert die Woche, wenn der Tag dahinter liegt
        mutating func move(_ i: Int, to d: Int, run r: Int) {
            if state.sessions[i].originalDate == nil { state.sessions[i].originalDate = state.sessions[i].date }
            state.sessions[i].date = days.date(d)
            let end = days.number(state.runs[r].end)
            if d >= end {
                state.runs[r].extendedDays += d + 1 - end
                state.runs[r].end = days.date(d + 1)
            }
        }

        /// Erster freier Tag in [from, to) für Einheit i, der alle Regeln einhält
        func freeDay(for i: Int, from: Int, to: Int, rules: ProgramRules, wishOnly: Bool) -> Int? {
            guard from < to else { return nil }
            let s = state.sessions[i]
            let map = occupied(excluding: s.id)
            for d in from..<to where map[d] == nil && (!wishOnly || isWishDay(d)) {
                var trial = map
                trial[d] = s.isHard
                if TrainingProgramScheduler.valid(trial, focus: [d], gapDays: rules.hardGapDays,
                                                  maxConsecutive: rules.maxConsecutiveDays) {
                    return d
                }
            }
            return nil
        }

        // MARK: Pause und Wiedereinstieg

        mutating func resume(now: Date) {
            guard let pausedAt = state.pausedAt, var run = state.runs.last else { return }
            let gap = max(0, today - days.number(pausedAt))
            let mainWeek = state.mainWeek
            // schon erledigte Einheiten der laufenden Woche (für „dort weitermachen“)
            let doneSlots = Set(state.sessions.filter {
                $0.run == run.run && $0.programId == state.programId && $0.status == .done
            }.map(\.slot))
            let pausedMain = run.programId == state.programId
            // laufende Woche beenden: offene Einheiten gelten als „pausiert“, nicht als verpasst
            for i in state.sessions.indices where state.sessions[i].run == run.run && state.sessions[i].status == .planned {
                state.sessions[i].status = .skipped
                state.sessions[i].skipReason = .paused
            }
            state.runs[state.runs.count - 1].closed = true
            run = state.runs[state.runs.count - 1]
            state.pausedAt = nil
            state.autoPaused = false
            state.bridge = nil
            let pid = state.programId
            let hasReentry = env.catalog.program(id: TrainingProgramEngine.reentryProgramId) != nil
                && pid != TrainingProgramEngine.reentryProgramId
            switch gap {
            case ...7:
                // bis 7 Tage „weiter wie geplant“: keine Wiederholung (kein Chip); nach einer Pause unter einem Tag
                // bleibt auch die erste harte Einheit unverändert
                startRun(programId: pid, week: mainWeek, cycle: run.cycle, start: today, repeated: false,
                         skipSlots: pausedMain ? doneSlots : [])
                if gap >= 1 { easyFirstHard() }
            case 8...14:
                repeatLastWeek(mainWeek: mainWeek, gap: gap, cycle: run.cycle)
            case 15...28 where !hasReentry:
                repeatLastWeek(mainWeek: mainWeek, gap: gap, cycle: run.cycle)
            case 15...28:
                state.bridge = ProgramBridge(programId: TrainingProgramEngine.reentryProgramId,
                                             resumeWeek: max(1, mainWeek - 1))
                state.paceAdjustment += Double(gap / 7)
                startRun(programId: TrainingProgramEngine.reentryProgramId, week: gap >= 21 ? 1 : 2, cycle: run.cycle,
                         start: today, repeated: false)
            case 29...56:
                state.paceAdjustment += Double(gap / 7)
                state.notices.append(ProgramNotice(kind: .retestSuggested, date: days.date(today)))
                let block = blockStart(before: mainWeek)
                if hasReentry {
                    state.bridge = ProgramBridge(programId: TrainingProgramEngine.reentryProgramId, resumeWeek: block)
                    startRun(programId: TrainingProgramEngine.reentryProgramId, week: 1, cycle: run.cycle, start: today,
                             repeated: false)
                } else {
                    startRun(programId: pid, week: block, cycle: run.cycle, start: today, repeated: true)
                }
            default:
                state.paceAdjustment = 0
                state.notices.append(ProgramNotice(kind: .restarted, date: days.date(today)))
                state.notices.append(ProgramNotice(kind: .retestSuggested, date: days.date(today)))
                startRun(programId: pid, week: 1, cycle: 0, start: today, repeated: false)
            }
            // „Willkommen zurück“ nur nach einer Pause von mindestens einem Tag
            if gap >= 1 {
                state.notices.append(ProgramNotice(kind: .resumed, date: days.date(today), value: Double(gap),
                                                   week: state.runs.last?.week))
            }
        }

        /// 8–14 Tage Pause: letzte vollständige Woche wiederholen, Tempoziele 1–2 s/500 m langsamer
        mutating func repeatLastWeek(mainWeek: Int, gap: Int, cycle: Int) {
            state.paceAdjustment += gap <= 10 ? 1 : 2
            startRun(programId: state.programId, week: max(1, mainWeek - 1), cycle: cycle, start: today, repeated: true)
        }

        /// Erste Woche des aktuellen Blocks: Woche nach der letzten leichteren Woche vor `week`
        func blockStart(before week: Int) -> Int {
            guard let p = mainProgram else { return 1 }
            let last = p.weekPlans.prefix(max(0, week - 1)).lastIndex { $0.deload }
            return last.map { $0 + 2 } ?? 1
        }

        /// Nach kurzer Pause: die erste harte Einheit der neuen Woche durch die leichte Variante ersetzen
        mutating func easyFirstHard() {
            guard let run = state.runs.last,
                  let first = state.sessions(inRun: run.run).first(where: { $0.status == .planned && $0.isHard && !$0.event && $0.date != nil }),
                  let i = state.sessions.firstIndex(where: { $0.id == first.id }) else { return }
            replaceEasy(&state.sessions[i])
        }

        // MARK: Effort (RECHERCHE 5.5)

        mutating func applyEffortRules() {
            let done = state.sessions.filter { $0.status == .done && $0.effort != nil && $0.completedAt != nil }
                .sorted { $0.completedAt! < $1.completedAt! }
            func fresh(_ rule: String, _ last: ScheduledProgramSession) -> Bool {
                guard let mark = state.effortRuleMarks[rule] else { return true }
                return last.completedAt! > mark
            }
            // 1. leichte Einheiten zu hart empfunden → nächste Woche leichter
            let easy = done.filter { $0.originalIntensity == .easy }
            if let last = easy.last, fresh("easyHigh", last) {
                let three = easy.suffix(3), two = easy.suffix(2)
                if (three.count == 3 && three.allSatisfy { $0.effort! >= 7 }) || (two.count == 2 && two.allSatisfy { $0.effort! >= 9 }) {
                    // schon in einer leichteren Woche → pausieren vorschlagen (Regel 4)
                    let inDeload = state.runs.first { $0.run == last.run }?.deload ?? false
                    if inDeload {
                        state.notices.append(ProgramNotice(kind: .pauseSuggested, date: last.completedAt!))
                    } else {
                        state.forceDeloadNext = true
                        state.notices.append(ProgramNotice(kind: .recoveryCheck, date: last.completedAt!))
                    }
                    state.effortRuleMarks["easyHigh"] = last.completedAt!
                }
            }
            let hard = done.filter { $0.originalIntensity >= .hard && !TrainingProgramEngine.isTestPlan($0.planId) }
            // 2. zwei harte Einheiten mit RPE 10 und verfehltem Tempo → Tempoziele 2 s/500 m langsamer
            if let last = hard.last, fresh("hardMissed", last) {
                let two = hard.suffix(2)
                if two.count == 2 && two.allSatisfy({ $0.effort! >= 10 && paceGap($0).map { $0 > 2 } == true }) {
                    state.paceAdjustment += 2
                    state.notices.append(ProgramNotice(kind: .paceLowered, date: last.completedAt!, value: 2))
                    state.effortRuleMarks["hardMissed"] = last.completedAt!
                }
            }
            // 3. drei harte Einheiten mit RPE ≤ 6 und erreichtem Tempo → Test vorschlagen
            if let last = hard.last, fresh("hardEasy", last) {
                let three = hard.suffix(3)
                if three.count == 3 && three.allSatisfy({ $0.effort! <= 6 && paceGap($0).map { $0 <= 0 } == true }) {
                    state.notices.append(ProgramNotice(kind: .retestSuggested, date: last.completedAt!))
                    state.effortRuleMarks["hardEasy"] = last.completedAt!
                }
            }
        }

        /// s/500 m langsamer als die obere Grenze des Zieltempos (negativ = schneller); nil ohne Ziel oder Tempo
        func paceGap(_ s: ScheduledProgramSession) -> Double? {
            guard let pace = s.workPace, pace > 0, let plan = env.workout(s.planId),
                  let target = PlanTargetSummary(plan: plan, best2k: state.effectiveBest2k(env.best2k)).pace else { return nil }
            return pace - target.upperBound
        }

        // MARK: Tests (RECHERCHE 5.4)

        mutating func evaluateTests(rides: [ProgramRide], now: Date) {
            for i in state.sessions.indices {
                let s = state.sessions[i]
                guard s.status == .done, s.testEvaluated != true, TrainingProgramEngine.isTestPlan(s.planId) else { continue }
                state.sessions[i].testEvaluated = true
                guard let ride = rides.first(where: { $0.workoutId == s.workoutId }),
                      let est = TrainingProgramEngine.estimateBest2k(ride: ride, plan: env.workout(s.planId)) else { continue }
                let date = ride.start
                state.paceAdjustment = 0
                if est < env.best2k - 0.05 {
                    state.reference = ReferenceProposal(best2k: est, previous: env.best2k, planId: s.planId,
                                                        workoutId: ride.workoutId, date: date, isWorse: false)
                    state.notices.append(ProgramNotice(kind: .referenceImproved, date: date, value: est))
                } else if est > env.best2k + 0.05 {
                    state.reference = ReferenceProposal(best2k: est, previous: env.best2k, planId: s.planId,
                                                        workoutId: ride.workoutId, date: date, isWorse: true)
                    state.notices.append(ProgramNotice(kind: .referenceWorse, date: date, value: est))
                }
            }
        }
    }

    /// Geschätzte 2000-m-Referenz (s) aus einem Test (docs/schwelle/SPEC.md 8.1, Punkt 4): Tempo der
    /// Belastungsphasen → Leistung → Schwelle über das Potenzgesetz (`ThresholdMath`) → gleichwertige 2k-Zeit.
    /// Ein 2000-m-Test ergibt genau seine Zeit. nil ohne verwertbare Werte, für Belastungen unter 3 min (nur
    /// Bestmarke) und für Tests mit eigener Auswertung (Stufentest, Rampe, 3 min All-out).
    /// Früher Paul's Law (+5 s/500 m je Verdopplung); für Nicht-2k-Tests ergibt das Potenzgesetz leicht andere Werte.
    public static func estimateBest2k(ride: ProgramRide, plan: WorkoutPlan?,
                                      b: Double = ThresholdMath.activeExponent) -> Double? {
        guard let pace = ride.workPace, pace > 30, pace < 400 else { return nil }
        if let plan, let e = ThresholdEvaluator.evaluator(for: plan), e != .timeTrial { return nil }
        var workDistance: Double?
        if let plan {
            let work = plan.phases.filter { $0.kind == .work }
            if !work.isEmpty && work.allSatisfy({ $0.distanceM != nil }) {
                workDistance = work.reduce(0) { $0 + ($1.distanceM ?? 0) }
            } else if !work.isEmpty && work.allSatisfy({ $0.durationS != nil }) {
                workDistance = work.reduce(0) { $0 + ($1.durationS ?? 0) } / pace * 500
            }
        }
        let d = workDistance ?? (ride.distance > 0 ? ride.distance : 2000)
        guard d >= 100 else { return nil }
        if abs(d - 2000) < 1 { return (4 * pace * 10).rounded() / 10 }
        let duration = d / 500 * pace
        guard duration >= 180 else { return nil }
        let t = ThresholdMath.thresholdFromEffort(power: ThresholdMath.watts(pace: pace), duration: duration, b: b)
        return (ThresholdMath.equivalentBest2k(threshold: t, b: b) * 10).rounded() / 10
    }
}
