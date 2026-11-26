import Foundation
import Observation
import SwiftData
import SwiftUI
import RowCoachKit

/// Ein gespeichertes Training aus Sicht des Zwischenspeichers: ändert sich die Belastung, wird es neu gelesen.
struct HomeWorkoutKey: Hashable, Sendable {
    let id: UUID
    let effort: Int?
}

/// Daten des Startbildschirms: Kennzahlen (`TrainingStats`) und „Vorschlag für heute“ (`DailySuggestion`).
///
/// Die gespeicherten Trainings werden einmal im Hintergrund gelesen (eigener `ModelContext`), zu schlanken
/// `TrainingSession`s verdichtet und zwischengespeichert. Nach jedem Speichern (neue Fahrt, neue Belastung,
/// Löschen) liest `refresh` nur die neuen bzw. geänderten Trainings und rechnet neu. So bleibt der Start auch mit
/// Hunderten Trainings schnell.
@MainActor
@Observable
final class HomeModel {
    private(set) var stats: TrainingStats?
    private(set) var suggestion: DailySuggestion?
    /// im Seen-Pass gewählte Strecke für den Vorschlag (nil = automatisch, wechselnde Strecke)
    private(set) var preferredCourseId: String?
    /// Motivationszeilen der Startseite und Erholungs-Wächter (docs/motivation/UMSETZUNG.md)
    private(set) var motivation: HomeMotivation?
    /// Persönliche Rekorde je Distanz und Zeit (auch Teilstücke)
    private(set) var records: [EffortTarget: PersonalRecords.Record] = [:]
    /// Erreichte Meilensteine (leer, wenn Meilensteine aus sind)
    private(set) var milestones: [Milestone] = []
    /// Orte der Strecken für Meilensteine je Gewässer und Land (gesetzt in `RootView`)
    @ObservationIgnored var places: [CoursePlace] = []
    /// aktiver Trainingsplan (gesetzt in `RootView`): wird bei jedem Neurechnen mit den Fahrten abgeglichen und
    /// steuert den Tagesvorschlag (Regel „plan“)
    @ObservationIgnored weak var programs: ProgramStore?

    private struct Entry {
        let effort: Int?
        let session: TrainingSession?
        /// mit Bestmarken und Intervalltempi (Motivation)
        let digest: RideDigest?
    }

    private struct Inputs: Equatable {
        var keys: [HomeWorkoutKey]
        var courseIds: [String]
        var best2k: Double
        var weeklyGoal: Int
    }

    @ObservationIgnored private var cache: [UUID: Entry] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastInputs: Inputs?
    /// Trainings, die gerade gelesen werden (id → Belastung beim Start des Lesens)
    @ObservationIgnored private var inFlight: [UUID: Int?] = [:]

    init() {}

    /// Neue bzw. geänderte Trainings lesen und alles neu rechnen. Trainings, die ein früherer Aufruf gerade liest,
    /// werden nicht doppelt gelesen; nach jedem Lesen wird mit den neuesten Eingaben gerechnet.
    func refresh(container: ModelContainer, keys: [HomeWorkoutKey], courseIds: [String], best2k: Double,
                 weeklyGoal: Int = 3) async {
        let inputs = Inputs(keys: keys, courseIds: courseIds, best2k: best2k, weeklyGoal: weeklyGoal)
        lastInputs = inputs
        let wanted = Dictionary(keys.map { ($0.id, $0.effort) }, uniquingKeysWith: { a, _ in a })
        // gelöschte Trainings vergessen
        for id in cache.keys where wanted[id] == nil { cache[id] = nil }
        let missing = Set(keys.filter { k in
            if inFlight[k.id] == k.effort { return false }
            guard let e = cache[k.id] else { return true }
            return e.effort != k.effort
        }.map(\.id))
        if !missing.isEmpty {
            for id in missing { inFlight[id] = wanted[id] ?? nil }
            let plans = PlanLibrary.plans
            let loaded = await Task.detached(priority: .userInitiated) {
                HomeModel.loadSessions(container: container, ids: missing, plans: plans)
            }.value
            for id in missing {
                cache[id] = Entry(effort: inFlight[id] ?? nil, session: loaded[id]?.session, digest: loaded[id])
                inFlight[id] = nil
            }
        }
        generation += 1
        let gen = generation
        await compute(lastInputs ?? inputs, generation: gen)
    }

    /// Gezählte Fahrten (ohne Simulator) auf einer Strecke, neueste zuerst (für die Streckenseite)
    func sessions(courseId: String, title: String? = nil) -> [TrainingSession] {
        cache.values.compactMap(\.session)
            .filter { $0.countsInStats && ($0.courseId == courseId || ($0.courseId == nil && $0.courseTitle == title)) }
            .sorted { $0.start > $1.start }
    }

    /// Verdichtetes Training (Programm, Herkunft, Stufe) für den Verlauf; nil, solange es noch nicht gelesen ist
    func session(id: UUID) -> TrainingSession? {
        cache[id]?.session
    }

    /// Strecke für den Vorschlag wählen (Seen-Pass); nil = wieder automatisch
    func selectCourse(_ id: String?) {
        preferredCourseId = id
        guard let inputs = lastInputs else { return }
        generation += 1
        let gen = generation
        Task { await compute(inputs, generation: gen) }
    }

    /// Neu rechnen ohne neu zu lesen (z. B. neuer Tag, App wieder aktiv)
    func recompute() {
        guard let inputs = lastInputs else { return }
        generation += 1
        let gen = generation
        Task { await compute(inputs, generation: gen) }
    }

    private func compute(_ inputs: Inputs, generation gen: Int) async {
        let digests = inputs.keys.compactMap { cache[$0.id]?.digest }
        let sessions = inputs.keys.compactMap { cache[$0.id]?.session }
        let preferred = preferredCourseId
        let plans = PlanLibrary.plans
        let now = Date()
        let agenda = programs?.sync(sessions: sessions, now: now)
        let m = motivationInputs(agenda: agenda, now: now)
        let result = await Task.detached(priority: .userInitiated) {
            () -> (TrainingStats, DailySuggestion, HomeMotivation, [EffortTarget: PersonalRecords.Record], [Milestone]) in
            let cal = TrainingCalendar.swiss()
            let stats = TrainingStats(sessions: sessions, now: now, calendar: cal, best2k: inputs.best2k,
                                      weeklyGoal: inputs.weeklyGoal, goal: m.home.goal, pauses: m.home.pauses)
            let suggestion = DailySuggestion.make(sessions: sessions, plans: plans, courseIds: inputs.courseIds,
                                                  now: now, calendar: cal, best2k: inputs.best2k,
                                                  preferredCourseId: preferred, program: agenda,
                                                  wishDays: m.home.wishDays)
            var homeInputs = m.home
            homeInputs.suggestedCourseId = suggestion.courseId
            let motivation = HomeMotivation.make(sessions: sessions, now: now, calendar: cal, best2k: inputs.best2k,
                                                 inputs: homeInputs)
            let records = PersonalRecords.best(digests)
            let milestones = homeInputs.milestonesOn ? Milestones.reached(sessions: sessions, places: homeInputs.places) : []
            return (stats, suggestion, motivation, records, milestones)
        }.value
        guard gen == generation else { return }
        stats = result.0
        suggestion = result.1
        motivation = result.2
        records = result.3
        milestones = result.4
        // Erinnerungen neu planen (lokal; ohne Erlaubnis oder ausgeschaltet entfernt der Dienst nur alte)
        let s = result.1
        var texts: [Date: String] = [:]
        if let plan = PlanLibrary.plan(id: s.planId) {
            texts[TrainingCalendar.swiss().startOfDay(for: s.forDate)] = plan.shortName
        }
        Task {
            await ReminderService.shared.reschedule(sessions: sessions, planDays: m.planDays,
                                                    trainingDates: m.trainingDates, suggestions: texts, now: now)
        }
    }

    /// Eingaben der Motivationsfunktionen aus Einstellungen und Trainingsplan
    private func motivationInputs(agenda: ProgramAgenda?, now: Date)
        -> (home: HomeMotivation.Inputs, planDays: [Weekday]?, trainingDates: [Date]?) {
        let cal = TrainingCalendar.swiss()
        let active = programs?.active.flatMap { $0.isFinished ? nil : $0 }
        let planDays = active.map(\.weekdays)
        let planRecovery = active?.notices.contains {
            ($0.kind == .recoveryCheck || $0.kind == .pauseSuggested) && now.timeIntervalSince($0.date) < 7 * 86400
        } ?? false
        let planRestToday = agenda.map { !$0.paused && $0.day(now, calendar: cal) == nil } ?? false
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let planRestYesterday = planDays.map { !$0.contains(Weekday.of(yesterday, calendar: cal)) } ?? false
        let trainingDates = agenda.map { $0.paused ? [] : $0.days.map(\.date) }
        let home = HomeMotivation.Inputs(goal: MotivationSettings.goal, pauses: MotivationSettings.pauses,
                                         goalSince: MotivationSettings.goalSince,
                                         reviewDismissedAt: MotivationSettings.reviewDismissedAt,
                                         intention: MotivationSettings.intention,
                                         wishDays: MotivationSettings.wishDays(planDays: planDays, now: now),
                                         places: places, milestonesOn: MotivationSettings.milestonesOn,
                                         hardGapHours: programs?.program?.rules.hardSessionsMinGapHours ?? 48,
                                         planRecovery: planRecovery, planRestToday: planRestToday,
                                         planRestYesterday: planRestYesterday)
        return (home, planDays, trainingDates)
    }

    /// Alle verdichteten Fahrten mit Bestmarken (für Rekordliste und Auswertung)
    func digests() -> [RideDigest] {
        cache.values.compactMap(\.digest)
    }

    /// „Was heute gut war“ und erreichte Meilensteine einer Fahrt (gegenüber allen früheren Fahrten). Die Fahrt muss
    /// noch nicht im Zwischenspeicher sein (direkt nach dem Ziel).
    func highlights(for record: WorkoutRecord) async -> (lines: [RideHighlight], milestones: [Milestone]) {
        let history = cache.values.compactMap(\.digest).filter { $0.id != record.id }
        let places = self.places
        let goal = MotivationSettings.goal, pauses = MotivationSettings.pauses
        let milestonesOn = MotivationSettings.milestonesOn
        let best2k = lastInputs?.best2k ?? TrainingSettings.best2k
        let plans = PlanLibrary.plans
        return await Task.detached(priority: .userInitiated) { () -> (lines: [RideHighlight], milestones: [Milestone]) in
            let plan = record.header.workoutPlanId.flatMap { id in plans.first { $0.id == id } }
            let ride = RideDigest(record: record, plan: plan)
            let all = history.map(\.session) + [ride.session]
            let ms = milestonesOn ? Milestones.reached(by: ride.id, sessions: all, places: places) : []
            let lines = RideHighlights.make(ride: ride, history: history, milestones: ms, goal: goal, pauses: pauses,
                                            calendar: TrainingCalendar.swiss(), best2k: best2k)
            return (lines, ms)
        }.value
    }

    /// Liest die Trainings mit diesen ids in einem eigenen Kontext (Hintergrund) und verdichtet sie (mit Bestmarken
    /// aus der Zeitreihe, einmal je Fahrt).
    nonisolated static func loadSessions(container: ModelContainer, ids: Set<UUID>,
                                         plans: [WorkoutPlan]) -> [UUID: RideDigest] {
        let context = ModelContext(container)
        let byPlan = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let all = (try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? []
        var out: [UUID: RideDigest] = [:]
        for item in all where ids.contains(item.id) {
            guard let rec = item.record else { continue }
            out[item.id] = RideDigest(record: rec, plan: rec.header.workoutPlanId.flatMap { byPlan[$0] })
        }
        return out
    }
}

/// Startet eine Fahrt aus dem Startbildschirm, der Streckenseite oder der Programmansicht (gesetzt in `RootView`).
struct RowingLaunchAction {
    let start: (DailySuggestion.Option) -> Void
    /// Rennen gegen eine gespeicherte Fahrt auf einer Strecke („Gegen meine Bestfahrt“, Streckenseite)
    var startGhost: ((String, WorkoutRecord) -> Void)? = nil

    func callAsFunction(_ option: DailySuggestion.Option) { start(option) }
}

private struct RowingLaunchKey: EnvironmentKey {
    static let defaultValue: RowingLaunchAction? = nil
}

extension EnvironmentValues {
    var rowingLaunch: RowingLaunchAction? {
        get { self[RowingLaunchKey.self] }
        set { self[RowingLaunchKey.self] = newValue }
    }
}

/// Einstellungen des Startbildschirms
enum HomeSettings {
    /// Fahrten pro Woche für die Wochenserie (Einstellungen → Training)
    static let weeklyGoalKey = "home.weeklyGoal"
    static let defaultWeeklyGoal = 3
    /// Banner „Profil prüfen“ auf dem Startbildschirm geschlossen (erscheint nur einmal)
    static let profileBannerDismissedKey = "home.profileBannerDismissed"
}

/// Profil gesetzt? Maximalpuls, Ruhepuls und 2000-m-Bestzeit gelten als Voreinstellung, solange sie nie gespeichert
/// wurden (im Profil oder mit „Werte stimmen“ im Hinweis).
enum ProfileState {
    static let maxHRKey = "profile.maxHR"
    static let restHRKey = "profile.restHR"

    static var isDefault: Bool {
        let d = UserDefaults.standard
        return [maxHRKey, restHRKey, TrainingSettings.best2kKey].contains { d.object(forKey: $0) == nil }
    }

    static var best2kIsDefault: Bool { UserDefaults.standard.object(forKey: TrainingSettings.best2kKey) == nil }
}
