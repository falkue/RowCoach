import Foundation
import RowCoachKit

/// Einstellungen der Motivationsfunktionen (docs/motivation/UMSETZUNG.md), alle lokal in UserDefaults, ohne Konto.
/// Jede Funktion ist einzeln abschaltbar (Einstellungen → Motivation). Die Logik steckt in RowCoachKit
/// (Motivation/…); hier nur Speichern und Lesen.
enum MotivationSettings {
    /// „Was heute gut war“ in der Auswertung und Coach-Satz nach der Fahrt (Standard an)
    static let successLinesKey = "motivation.successLines"
    /// Meilensteine in Auswertung und Startseite (Standard an)
    static let milestonesKey = "motivation.milestones"
    /// Art des Wochenziels (`WeeklyGoal.Kind.rawValue`); die Zahl der Fahrten bleibt unter `HomeSettings.weeklyGoalKey`
    static let goalKindKey = "motivation.goalKind"
    static let goalMinutesKey = "motivation.goalMinutes"
    static let defaultGoalMinutes = 90
    /// Zeitpunkt der letzten Zieländerung (für den Vorschlag nach 4 Wochen)
    static let goalSinceKey = "motivation.goalSince"
    /// „Passt so“ beim Vorschlag zum Wochenziel
    static let reviewDismissedKey = "motivation.goalReviewDismissed"
    /// Pausen im Wochenziel (JSON `[GoalPause]`)
    static let pausesKey = "motivation.pauses"
    /// „Wann ruderst du?“ (JSON `RowingIntention`)
    static let intentionKey = "motivation.intention"
    /// Zeitpunkte bereits zugestellter Erinnerungen (JSON `[Date]`, für „eine Woche Ruhe nach zwei unbeachteten“)
    static let reminderLogKey = "motivation.reminderLog"

    private static var d: UserDefaults { .standard }

    static var successLinesOn: Bool { d.object(forKey: successLinesKey) as? Bool ?? true }
    static var milestonesOn: Bool { d.object(forKey: milestonesKey) as? Bool ?? true }

    static var goal: WeeklyGoal {
        let kind = d.string(forKey: goalKindKey).flatMap(WeeklyGoal.Kind.init(rawValue:)) ?? .rides
        switch kind {
        case .rides:
            let n = d.object(forKey: HomeSettings.weeklyGoalKey) as? Int ?? HomeSettings.defaultWeeklyGoal
            return WeeklyGoal(kind: .rides, value: n)
        case .minutes:
            return WeeklyGoal(kind: .minutes, value: d.object(forKey: goalMinutesKey) as? Int ?? defaultGoalMinutes)
        }
    }

    static func setGoal(_ goal: WeeklyGoal) {
        d.set(goal.kind.rawValue, forKey: goalKindKey)
        switch goal.kind {
        case .rides: d.set(goal.value, forKey: HomeSettings.weeklyGoalKey)
        case .minutes: d.set(goal.value, forKey: goalMinutesKey)
        }
        markGoalChanged()
    }

    static func markGoalChanged() {
        d.set(Date().timeIntervalSince1970, forKey: goalSinceKey)
    }

    static var goalSince: Date? {
        let t = d.double(forKey: goalSinceKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var reviewDismissedAt: Date? {
        let t = d.double(forKey: reviewDismissedKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func dismissReview() {
        d.set(Date().timeIntervalSince1970, forKey: reviewDismissedKey)
    }

    static var pauses: [GoalPause] {
        get { decode([GoalPause].self, pausesKey) ?? [] }
        set {
            // ältere als ein Jahr vergessen
            let cutoff = Date().addingTimeInterval(-365 * 86400)
            encode(newValue.filter { $0.end >= cutoff }, pausesKey)
        }
    }

    static var intention: RowingIntention? {
        get { decode(RowingIntention.self, intentionKey) }
        set { if let v = newValue { encode(v, intentionKey) } else { d.removeObject(forKey: intentionKey) } }
    }

    static var reminderLog: [Date] {
        get { decode([Date].self, reminderLogKey) ?? [] }
        set { encode(Array(newValue.sorted().suffix(30)), reminderLogKey) }
    }

    /// Geltende Wunschtage: mit aktivem Plan (und „Tage aus dem Plan“) dessen Tage, sonst die eigenen; leer in einer
    /// Pause
    static func wishDays(planDays: [Weekday]?, now: Date = Date()) -> Set<Weekday> {
        guard !pauses.contains(now, calendar: TrainingCalendar.swiss()) else { return [] }
        return intention?.effectiveDays(planDays: planDays) ?? Set(planDays ?? [])
    }


    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { d.set(data, forKey: key) }
    }
}

/// Orte der Strecken für Meilensteine je Gewässer und Land
enum MotivationPlaces {
    static func make(_ courses: [Course]) -> [CoursePlace] {
        let locale = Locale(identifier: AppLanguage.code)
        return courses.map { c in
            CoursePlace(courseId: c.id, region: CourseText.localized(c.region), countryCode: c.countryCode,
                        countryName: c.countryCode.map { locale.localizedString(forRegionCode: $0) ?? $0 })
        }
    }
}

/// Texte der Wochenserie für flexible Ziele und Pausen (WeekCards); für „Fahrten“ ohne Pause die bisherigen Sätze
enum StreakText {
    static func main(_ s: TrainingStats.Streak) -> String {
        if s.pausedToday, let end = s.pauseEnd {
            let day = end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return String(localized: "Pause bis \(day) – Serie und Wochenziel ruhen")
        }
        if s.kind == .rides {
            if s.weeks >= 2 { return String(localized: "\(s.weeks) Wochen in Folge mit \(s.goal) Fahrten") }
            if s.weeks == 1 {
                return s.thisWeekMet ? String(localized: "Wochenziel erreicht: \(s.goal) Fahrten")
                    : String(localized: "1 Woche mit \(s.goal) Fahrten")
            }
            return String(localized: "Wochenziel: \(s.goal) Fahrten · diese Woche \(s.thisWeekSessions)")
        }
        let minutes = s.goal
        if s.weeks >= 2 { return String(localized: "\(s.weeks) Wochen in Folge mit \(minutes) min") }
        if s.thisWeekMet { return String(localized: "Wochenziel erreicht: \(minutes) min") }
        return String(localized: "Wochenziel: \(minutes) min · diese Woche \(Int(s.thisWeekProgress)) min")
    }

    /// „2 von 3 Fahrten“ bzw. „45 von 90 min“; in einer Pause „Pause“
    static func count(_ s: TrainingStats.Streak) -> String {
        if s.pausedToday || s.effectiveTarget == 0 { return String(localized: "Pausiert") }
        return s.progressText
    }

    /// „2 von 3“ bzw. „45/90 min“
    static func short(_ s: TrainingStats.Streak) -> String {
        if s.pausedToday || s.effectiveTarget == 0 { return String(localized: "Pausiert") }
        let n = s.thisWeekSessions, goal = s.effectiveTarget
        if s.kind == .rides { return String(localized: "\(n) von \(goal)") }
        return "\(s.thisWeekProgress)/\(s.effectiveTarget) min"
    }
}
