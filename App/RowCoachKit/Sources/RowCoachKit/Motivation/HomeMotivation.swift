import Foundation

/// Ruhige Motivationszeilen für die Startseite (höchstens eine wird gezeigt, Startseite bleibt eine Startrampe):
/// Lob für den gehaltenen Ruhetag, Vorschlag zum Wochenziel, „Heute nach der Arbeit“ aus dem Wenn-dann-Plan und
/// höchstens ein naher Meilenstein. Der Erholungs-Wächter hat Vorrang: Solange er Erholung empfiehlt, gibt es keine
/// Meilenstein-Hinweise.
public struct HomeMotivation: Equatable, Sendable {
    public var recovery: RecoveryState
    public var restPraise: String?
    public var goalReview: GoalReview?
    public var intentionLine: String?
    public var milestone: MilestoneProgress?

    /// Die eine Zeile, die die Startseite zeigt (Vorrang: Ruhetag-Lob, Wochenziel-Vorschlag, Wenn-dann, Meilenstein)
    public enum Line: Equatable, Sendable {
        case restPraise(String)
        case goalReview(GoalReview)
        case intention(String)
        case milestone(MilestoneProgress)
    }

    public var line: Line? {
        if let t = restPraise { return .restPraise(t) }
        if let r = goalReview { return .goalReview(r) }
        if let t = intentionLine { return .intention(t) }
        if let m = milestone { return .milestone(m) }
        return nil
    }

    public struct Inputs: Sendable {
        public var goal: WeeklyGoal
        public var pauses: [GoalPause]
        public var goalSince: Date?
        public var reviewDismissedAt: Date?
        public var intention: RowingIntention?
        /// geltende Wunschtage (Plan oder eigene)
        public var wishDays: Set<Weekday>
        public var places: [CoursePlace]
        public var suggestedCourseId: String?
        public var milestonesOn: Bool
        public var hardGapHours: Int
        public var planRecovery: Bool
        public var planRestToday: Bool
        public var planRestYesterday: Bool

        public init(goal: WeeklyGoal = .default, pauses: [GoalPause] = [], goalSince: Date? = nil,
                    reviewDismissedAt: Date? = nil, intention: RowingIntention? = nil, wishDays: Set<Weekday> = [],
                    places: [CoursePlace] = [], suggestedCourseId: String? = nil, milestonesOn: Bool = true,
                    hardGapHours: Int = 48, planRecovery: Bool = false, planRestToday: Bool = false,
                    planRestYesterday: Bool = false) {
            self.goal = goal
            self.pauses = pauses
            self.goalSince = goalSince
            self.reviewDismissedAt = reviewDismissedAt
            self.intention = intention
            self.wishDays = wishDays
            self.places = places
            self.suggestedCourseId = suggestedCourseId
            self.milestonesOn = milestonesOn
            self.hardGapHours = hardGapHours
            self.planRecovery = planRecovery
            self.planRestToday = planRestToday
            self.planRestYesterday = planRestYesterday
        }
    }

    public static func make(sessions all: [TrainingSession], now: Date, calendar cal: Calendar = TrainingCalendar.swiss(),
                            best2k: Double = PaceTargets.defaultBest2k, inputs i: Inputs) -> HomeMotivation {
        let sessions = all.filter { $0.countsInStats && $0.start <= now }
        let paused = i.pauses.contains(now, calendar: cal)
        let recovery = RecoveryGuard.state(sessions: sessions, now: now, calendar: cal, best2k: best2k,
                                           hardGapHours: i.hardGapHours, planRecovery: i.planRecovery,
                                           planRestDay: i.planRestToday)
        let praise = paused ? nil : RecoveryGuard.restDayPraise(sessions: sessions, now: now, calendar: cal,
                                                                best2k: best2k, yesterdayWasPlanRest: i.planRestYesterday)
        let review = paused ? nil : GoalReview.make(sessions: sessions, now: now, calendar: cal, goal: i.goal,
                                                    pauses: i.pauses, goalSince: i.goalSince,
                                                    dismissedAt: i.reviewDismissedAt)
        var intention: String?
        if let plan = i.intention, !paused, i.wishDays.contains(Weekday.of(now, calendar: cal)),
           !sessions.contains(where: { cal.isDate($0.start, inSameDayAs: now) }) {
            let time = String(format: "%d:%02d", plan.hour, plan.minute)
            intention = plan.cue == .none ? String(localized: "Heute um \(time) – so hast du es dir vorgenommen.")
                : String(localized: "Heute \(plan.cue.phrase) (\(time)) – so hast du es dir vorgenommen.")
        }
        let milestone = i.milestonesOn && !recovery.silencesChallenges && !paused
            ? Milestones.next(sessions: sessions, places: i.places, suggestedCourseId: i.suggestedCourseId) : nil
        return HomeMotivation(recovery: recovery, restPraise: praise, goalReview: review, intentionLine: intention,
                              milestone: milestone)
    }
}
