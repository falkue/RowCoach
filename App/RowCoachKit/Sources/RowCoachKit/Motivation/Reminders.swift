import Foundation

/// „Wann ruderst du?“: Wenn-dann-Plan aus Tagen, Uhrzeit und Anlass (docs/motivation/RECHERCHE.md Katalog #3,
/// Implementation Intentions). Die Wunschtage dienen auch dem sanften Wiedereinstieg. Die Erinnerung ist eine lokale
/// Mitteilung, standardmässig aus.
public struct RowingIntention: Codable, Equatable, Sendable {
    /// Anlass („nach der Arbeit“): verankert das Rudern an einem festen Moment im Tag
    public enum Cue: String, Codable, Sendable, CaseIterable {
        case morning, lunch, afterWork, evening, none

        /// „vor dem Frühstück“ (klein, für den Satz)
        public var phrase: String {
            switch self {
            case .morning: return String(localized: "vor dem Frühstück")
            case .lunch: return String(localized: "in der Mittagspause")
            case .afterWork: return String(localized: "nach der Arbeit")
            case .evening: return String(localized: "am Abend")
            case .none: return String(localized: "zur gewählten Zeit")
            }
        }

        /// „Vor dem Frühstück“ (Auswahl, Satzanfang)
        public var title: String {
            switch self {
            case .morning: return String(localized: "Vor dem Frühstück")
            case .lunch: return String(localized: "In der Mittagspause")
            case .afterWork: return String(localized: "Nach der Arbeit")
            case .evening: return String(localized: "Am Abend")
            case .none: return String(localized: "Ohne Anlass")
            }
        }

        /// Vorschlag für die Uhrzeit
        public var defaultHour: Int {
            switch self {
            case .morning: return 7
            case .lunch: return 12
            case .afterWork: return 18
            case .evening: return 20
            case .none: return 18
            }
        }
    }

    public var days: Set<Weekday>
    public var hour: Int
    public var minute: Int
    public var cue: Cue
    /// Hindernisplan: „Wenn ich müde bin, dann kurz und locker“
    public var obstaclePlan: Bool
    /// mit aktivem Trainingsplan dessen Tage verwenden
    public var usePlanDays: Bool
    /// lokale Mitteilung an den Wunschtagen
    public var remindersOn: Bool

    public init(days: Set<Weekday> = [], hour: Int = 18, minute: Int = 0, cue: Cue = .afterWork,
                obstaclePlan: Bool = true, usePlanDays: Bool = true, remindersOn: Bool = false) {
        self.days = days
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.cue = cue
        self.obstaclePlan = obstaclePlan
        self.usePlanDays = usePlanDays
        self.remindersOn = remindersOn
    }

    /// Tage, die gelten: mit aktivem Plan (und `usePlanDays`) die Tage des Plans, sonst die eigenen
    public func effectiveDays(planDays: [Weekday]?) -> Set<Weekday> {
        if usePlanDays, let p = planDays, !p.isEmpty { return Set(p) }
        return days
    }

    /// „Di, Do, Sa · nach der Arbeit · 18:00“
    public func summary(days list: Set<Weekday>) -> String {
        let d = list.sorted().map(\.shortLabel).joined(separator: ", ")
        let time = String(format: "%d:%02d", hour, minute)
        return [d, cue == .none ? nil : cue.phrase, time].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Eine geplante Erinnerung
public struct ReminderSlot: Equatable, Sendable {
    public var date: Date
    public var title: String
    public var body: String
    /// Kennung der Mitteilung („rowcoach.reminder.2026-11-26“)
    public var identifier: String
}

/// Plant die Erinnerungen der nächsten Tage (höchstens eine pro Tag, nur an Wunschtagen, nie an Ruhetagen laut Plan,
/// nie in einer Pause, nicht wenn heute schon gerudert wurde, eine Woche Ruhe nach zwei unbeachteten). Text ohne
/// Verlust-Sprache: „Dein Ruderplan für heute“.
public enum ReminderPlanner {
    public static let identifierPrefix = "rowcoach.reminder."
    /// so viele Tage im Voraus planen (die App plant bei jedem Öffnen neu)
    public static let horizonDays = 8
    public static let quietDays = 7

    /// - Parameters:
    ///   - days: geltende Wunschtage (`RowingIntention.effectiveDays`)
    ///   - trainingDates: mit aktivem Plan die Tage mit Einheit (andere Tage sind Ruhetage); nil ohne Plan
    ///   - suggestions: Kurztext des Vorschlags je Tag (Tagesbeginn → „Lockere Grundlage 30 min“), wo bekannt
    ///   - quietUntil: bis dahin keine Erinnerung (`quietUntil(reminders:…)`)
    public static func plan(intention: RowingIntention, days: Set<Weekday>, now: Date,
                            calendar cal: Calendar = TrainingCalendar.swiss(), sessions: [TrainingSession],
                            pauses: [GoalPause] = [], trainingDates: [Date]? = nil,
                            suggestions: [Date: String] = [:], quietUntil: Date? = nil) -> [ReminderSlot] {
        guard intention.remindersOn, !days.isEmpty else { return [] }
        let today = cal.startOfDay(for: now)
        let rowedToday = sessions.contains { $0.countsInStats && cal.isDate($0.start, inSameDayAs: now) }
        let planDays = trainingDates.map { Set($0.map { cal.startOfDay(for: $0) }) }
        var out: [ReminderSlot] = []
        for offset in 0..<horizonDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let fire = cal.date(bySettingHour: intention.hour, minute: intention.minute, second: 0, of: day),
                  fire > now else { continue }
            guard days.contains(Weekday.of(day, calendar: cal)) else { continue }
            if pauses.contains(day, calendar: cal) { continue }
            if let planDays, !planDays.contains(day) { continue }
            if offset == 0 && rowedToday { continue }
            if let q = quietUntil, day < cal.startOfDay(for: q) { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let id = identifierPrefix + String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            out.append(ReminderSlot(date: fire, title: String(localized: "Dein Ruderplan für heute"),
                                    body: body(intention: intention, suggestion: suggestions[day]), identifier: id))
        }
        return out
    }

    static func body(intention: RowingIntention, suggestion: String?) -> String {
        let cue = intention.cue.title
        var text: String
        if let suggestion {
            text = intention.cue == .none ? suggestion : String(localized: "\(cue): \(suggestion).")
        } else {
            text = intention.cue == .none ? String(localized: "Der Vorschlag für heute wartet in der App.")
                : String(localized: "\(cue) rudern – der Vorschlag wartet in der App.")
        }
        if intention.obstaclePlan {
            text += " " + String(localized: "Müde? Dann kurz und locker – zählt genauso.")
        }
        return text
    }

    /// Ruhe nach zwei unbeachteten Erinnerungen in Folge (an ihrem Tag keine Fahrt): eine Woche ab der zweiten.
    /// Erinnerungen in einer Ruhezeit zählen nicht. nil, wenn keine Ruhe gilt.
    public static func quietUntil(reminders: [Date], sessions: [TrainingSession], now: Date,
                                  calendar cal: Calendar = TrainingCalendar.swiss()) -> Date? {
        let rides = sessions.filter(\.countsInStats)
        var ignored = 0
        var quiet: Date?
        for r in reminders.filter({ $0 <= now }).sorted() {
            if let q = quiet, r < q { continue }
            let rowed = rides.contains { cal.isDate($0.start, inSameDayAs: r) }
            if rowed {
                ignored = 0
            } else {
                ignored += 1
                if ignored >= 2 {
                    quiet = cal.date(byAdding: .day, value: quietDays, to: cal.startOfDay(for: r))
                    ignored = 0
                }
            }
        }
        guard let q = quiet, q > now else { return nil }
        return q
    }
}
