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
    /// aktiver Trainingsplan (gesetzt in `RootView`): wird bei jedem Neurechnen mit den Fahrten abgeglichen und
    /// steuert den Tagesvorschlag (Regel „plan“)
    @ObservationIgnored weak var programs: ProgramStore?

    private struct Entry {
        let effort: Int?
        let session: TrainingSession?
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
                cache[id] = Entry(effort: inFlight[id] ?? nil, session: loaded[id])
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
        let sessions = inputs.keys.compactMap { cache[$0.id]?.session }
        let preferred = preferredCourseId
        let plans = PlanLibrary.plans
        let now = Date()
        let agenda = programs?.sync(sessions: sessions, now: now)
        let result = await Task.detached(priority: .userInitiated) { () -> (TrainingStats, DailySuggestion) in
            let cal = TrainingCalendar.swiss()
            let stats = TrainingStats(sessions: sessions, now: now, calendar: cal, best2k: inputs.best2k,
                                      weeklyGoal: inputs.weeklyGoal)
            let suggestion = DailySuggestion.make(sessions: sessions, plans: plans, courseIds: inputs.courseIds,
                                                  now: now, calendar: cal, best2k: inputs.best2k,
                                                  preferredCourseId: preferred, program: agenda)
            return (stats, suggestion)
        }.value
        guard gen == generation else { return }
        stats = result.0
        suggestion = result.1
    }

    /// Liest die Trainings mit diesen ids in einem eigenen Kontext (Hintergrund) und verdichtet sie.
    nonisolated static func loadSessions(container: ModelContainer, ids: Set<UUID>,
                                         plans: [WorkoutPlan]) -> [UUID: TrainingSession] {
        let context = ModelContext(container)
        let byPlan = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let all = (try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? []
        var out: [UUID: TrainingSession] = [:]
        for item in all where ids.contains(item.id) {
            guard let rec = item.record else { continue }
            out[item.id] = TrainingSession(record: rec, plan: rec.header.workoutPlanId.flatMap { byPlan[$0] })
        }
        return out
    }
}

/// Startet eine Fahrt aus dem Startbildschirm, der Streckenseite oder der Programmansicht (gesetzt in `RootView`).
struct RowingLaunchAction {
    let start: (DailySuggestion.Option) -> Void

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
