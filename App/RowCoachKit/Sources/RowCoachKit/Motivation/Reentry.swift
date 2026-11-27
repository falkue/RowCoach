import Foundation

/// Sanfter Wiedereinstieg („nie zweimal verpassen“, docs/motivation/RECHERCHE.md Katalog #4): Nach einem verstrichenen
/// Wunschtag bietet der Tagesvorschlag am nächsten Tag eine kurze, lockere Einheit an – ohne Hinweis auf das
/// Verpasste. Grundlage: Wiederkommen nach einem Ausfall war das wirksamste von 54 Programmen (Milkman 2021); ein
/// einzelner Ausfall stört die Gewohnheit nicht (Lally 2010).
public enum ReentryRule {
    /// Kurze Einheiten in dieser Reihenfolge (die erste vorhandene gilt): „Lockere Grundlage 15 Minuten“
    /// (`grundlage-locker-15`, docs/plans-new/grundlage.json); fehlt sie, „Einstieg 1-2-3-2-1“ (17 min) usw.
    public static let shortPlans = ["grundlage-locker-15", "einsteiger-1-2-3-2-1", "einsteiger-90-30",
                                    "regeneration-20", "einsteiger-5x1-2x5", "grundlage-locker-30"]

    /// Erstes vorhandenes Programm aus `shortPlans` (leerer Katalog: das erste nach dem Platzhalter)
    public static func shortPlan(plans: [WorkoutPlan]) -> String {
        guard !plans.isEmpty else { return shortPlans[1] }
        return shortPlans.first { id in plans.contains { $0.id == id } } ?? DailySuggestion.Plans.easy30
    }

    /// Dauer in Minuten, wenn alle Phasen eine Zeit haben
    public static func minutes(of plan: WorkoutPlan) -> Int? {
        var total = 0.0
        for p in plan.phases {
            guard let d = p.durationS, d > 0 else { return nil }
            total += d
        }
        return total > 0 ? Int((total / 60).rounded()) : nil
    }

    /// Der Tag vor `date` war ein Wunschtag ohne Fahrt, am Tag `date` gibt es noch keine Fahrt, und es gab schon
    /// vorher Fahrten (ohne Simulator).
    public static func missedWishDay(sessions all: [TrainingSession], at date: Date, calendar cal: Calendar,
                                     wishDays: Set<Weekday>) -> Bool {
        guard !wishDays.isEmpty else { return false }
        let sessions = all.filter(\.countsInStats)
        let day = cal.startOfDay(for: date)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: day),
              wishDays.contains(Weekday.of(yesterday, calendar: cal)),
              sessions.contains(where: { $0.start < yesterday }),
              !sessions.contains(where: { cal.isDate($0.start, inSameDayAs: yesterday) || cal.isDate($0.start, inSameDayAs: day) })
        else { return false }
        return true
    }
}
