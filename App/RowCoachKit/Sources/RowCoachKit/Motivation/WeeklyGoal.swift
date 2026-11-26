import Foundation

// Wochenziel flexibel (Fahrten oder Minuten) mit Pause, docs/motivation/RECHERCHE.md Katalog #7, aufbauend auf der
// Wochenserie mit Joker (docs/design/startscreen-gamification.md 3e, `TrainingStats.Streak`).

/// Wochenziel: Fahrten (1–6) oder Minuten (30–600) je Woche Mo–So
public struct WeeklyGoal: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case rides, minutes
    }

    public static let rideRange = 1...6
    public static let minuteRange = 30...600
    public static let minuteStep = 15
    /// Hinweis ab so vielen Fahrten pro Woche (Erholungs-Wächter: Ruhetage gehören dazu)
    public static let ridesHintFrom = 7

    public var kind: Kind
    public var value: Int

    public init(kind: Kind = .rides, value: Int = 3) {
        self.kind = kind
        switch kind {
        case .rides: self.value = min(max(value, Self.rideRange.lowerBound), Self.rideRange.upperBound)
        case .minutes: self.value = min(max(value, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
        }
    }

    public static let `default` = WeeklyGoal(kind: .rides, value: 3)

    /// „3 Fahrten“ bzw. „90 min“
    public var title: String {
        switch kind {
        case .rides:
            let rides = value
            return String(localized: "\(rides) Fahrten")
        case .minutes:
            let minutes = value
            return String(localized: "\(minutes) min")
        }
    }

    /// Ziel für eine Woche, in der nur `freeDays` von 7 Tagen ohne Pause sind (gerundet; 0 = Woche eingefroren)
    public func target(freeDays: Int) -> Int {
        let f = min(max(freeDays, 0), 7)
        if f == 7 { return value }
        return Int((Double(value) * Double(f) / 7).rounded())
    }

    /// Stand einer Woche gegenüber dem Ziel
    public func progress(sessions: Int, minutes: Double) -> Int {
        kind == .rides ? sessions : Int(minutes.rounded(.down))
    }
}

/// Pause im Wochenziel (Krankheit, Ferien): friert Serie und Ziel ein, ohne den Joker zu verbrauchen.
/// Dauer 1 Tag bis 4 Wochen; `end` ist der letzte Pausentag (einschliesslich).
public struct GoalPause: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Reason: String, Codable, Sendable, CaseIterable {
        case ill, holiday, other

        public var title: String {
            switch self {
            case .ill: return String(localized: "Krank")
            case .holiday: return String(localized: "Ferien")
            case .other: return String(localized: "Anderes")
            }
        }
    }

    public static let maxDays = 28

    public var id: UUID
    public var start: Date
    public var end: Date
    public var reason: Reason

    /// `days` = Anzahl Pausentage ab `start` (1…28)
    public init(id: UUID = UUID(), start: Date, days: Int, reason: Reason = .other,
                calendar cal: Calendar = TrainingCalendar.swiss()) {
        self.id = id
        let s = cal.startOfDay(for: start)
        self.start = s
        let n = min(max(days, 1), Self.maxDays)
        self.end = cal.date(byAdding: .day, value: n - 1, to: s) ?? s
        self.reason = reason
    }

    public func contains(_ date: Date, calendar cal: Calendar = TrainingCalendar.swiss()) -> Bool {
        let d = cal.startOfDay(for: date)
        return d >= cal.startOfDay(for: start) && d <= cal.startOfDay(for: end)
    }

    /// Pause vorzeitig beenden: letzter Pausentag ist gestern (heute zählt wieder); vor dem ersten Tag entfällt sie
    public func ended(at now: Date, calendar cal: Calendar = TrainingCalendar.swiss()) -> GoalPause? {
        let today = cal.startOfDay(for: now)
        guard today > cal.startOfDay(for: start) else { return nil }
        var p = self
        p.end = min(end, cal.date(byAdding: .day, value: -1, to: today) ?? today)
        return p
    }
}

extension Array where Element == GoalPause {
    public func contains(_ date: Date, calendar cal: Calendar = TrainingCalendar.swiss()) -> Bool {
        contains { $0.contains(date, calendar: cal) }
    }

    /// Pause, die `date` umfasst
    public func active(at date: Date, calendar cal: Calendar = TrainingCalendar.swiss()) -> GoalPause? {
        first { $0.contains(date, calendar: cal) }
    }

    /// Tage der Woche ab `weekStart` (7 Tage) ohne Pause
    func freeDays(weekStart: Date, calendar cal: Calendar) -> Int {
        (0..<7).filter { i in
            guard let d = cal.date(byAdding: .day, value: i, to: weekStart) else { return true }
            return !contains(d, calendar: cal)
        }.count
    }
}

/// Wochenserie mit flexiblem Ziel und Pausen (erweitert `TrainingStats.streak`):
/// - Eine Woche zählt, wenn sie ihr Ziel erreicht. Das Ziel einer Woche mit Pausentagen sinkt anteilig
///   (`WeeklyGoal.target(freeDays:)`); ist es 0, ist die Woche eingefroren: Sie zählt nicht, bricht nichts und
///   verbraucht keinen Joker.
/// - Sonst wie bisher: Eine verfehlte Woche verbraucht den Joker, danach beginnt die Serie neu; der Joker kommt nach
///   4 erreichten Wochen zurück. Die laufende Woche bricht nie etwas.
public enum WeeklyGoalTracker {
    public static func streak(_ all: [TrainingSession], now: Date, calendar cal: Calendar, goal: WeeklyGoal,
                              pauses: [GoalPause]) -> TrainingStats.Streak {
        let sessions = all.filter { $0.countsInStats && $0.start <= now }
        var counts: [Date: Int] = [:]
        var minutes: [Date: Double] = [:]
        for s in sessions {
            let w = TrainingStats.weekStart(of: s.start, cal)
            counts[w, default: 0] += 1
            minutes[w, default: 0] += s.activeDuration / 60
        }
        func progress(_ w: Date) -> Int { goal.progress(sessions: counts[w] ?? 0, minutes: minutes[w] ?? 0) }
        func target(_ w: Date) -> Int { goal.target(freeDays: pauses.freeDays(weekStart: w, calendar: cal)) }

        let current = TrainingStats.weekStart(of: now, cal)
        let thisTarget = target(current)
        let thisProgress = progress(current)
        let thisMet = thisTarget > 0 && thisProgress >= thisTarget
        var streak = 0, joker = true, sinceJoker = 0, usedLast = false
        if let first = counts.keys.min(), first < current {
            var w = first
            var guardCount = 0
            while w < current && guardCount < 5000 {
                guardCount += 1
                let tg = target(w)
                if tg == 0 {
                    // eingefroren: nichts ändert sich (auch „Joker letzte Woche“ bleibt, wie es war)
                } else if progress(w) >= tg {
                    usedLast = false
                    streak += 1
                    sinceJoker += 1
                    if !joker && sinceJoker >= TrainingStats.Streak.weeksToRegainJoker { joker = true }
                } else if streak > 0 && joker {
                    joker = false
                    sinceJoker = 0
                    usedLast = true
                } else {
                    usedLast = false
                    streak = 0
                    joker = true
                    sinceJoker = 0
                }
                guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: w) else { break }
                w = next
            }
        }
        if thisMet { streak += 1 }
        var s = TrainingStats.Streak(weeks: streak, goal: goal.value, jokerAvailable: joker, jokerUsedLastWeek: usedLast,
                                     thisWeekSessions: counts[current] ?? 0, thisWeekMet: thisMet)
        s.kind = goal.kind
        s.thisWeekMinutes = minutes[current] ?? 0
        s.thisWeekTarget = thisTarget
        s.pausedToday = pauses.contains(now, calendar: cal)
        s.pauseEnd = pauses.active(at: now, calendar: cal)?.end
        return s
    }
}

extension TrainingStats.Streak {
    /// Stand der laufenden Woche in der Einheit des Ziels (Fahrten bzw. Minuten)
    public var thisWeekProgress: Int {
        kind == .rides ? thisWeekSessions : Int(thisWeekMinutes.rounded(.down))
    }

    /// Ziel der laufenden Woche (bei Pausentagen anteilig kleiner)
    public var effectiveTarget: Int { thisWeekTarget ?? goal }

    /// „2 von 3 Fahrten“ bzw. „45 von 90 min“
    public var progressText: String {
        let n = thisWeekProgress, of = effectiveTarget
        switch kind {
        case .rides: return String(localized: "\(n) von \(Int(of)) Fahrten")
        case .minutes: return String(localized: "\(n) von \(Int(of)) min")
        }
    }
}

/// Vorschlag zum Wochenziel nach einigen Wochen (BCT 1.5, Ziel überprüfen): nach 4 erreichten Wochen in Folge
/// „etwas mehr?“, nach 3 verfehlten in Folge „etwas weniger?“. Eingefrorene Wochen zählen nicht; Wochen vor der
/// letzten Zieländerung (`goalSince`) auch nicht. Nach „Passt so“ (`dismissedAt`) 4 Wochen Ruhe.
public struct GoalReview: Equatable, Sendable {
    public enum Direction: String, Sendable { case up, down }

    public var direction: Direction
    public var current: WeeklyGoal
    public var proposed: WeeklyGoal

    public static let weeksUp = 4
    public static let weeksDown = 3

    public var text: String {
        switch direction {
        case .up:
            let weeks = Self.weeksUp
            return String(localized: "\(weeks) Wochen in Folge geschafft. Etwas mehr? Neues Wochenziel: \(proposed.title).")
        case .down:
            return String(localized: "Die letzten Wochen waren voll. Ein kleineres Ziel passt vielleicht besser: \(proposed.title).")
        }
    }

    public static func make(sessions all: [TrainingSession], now: Date, calendar cal: Calendar, goal: WeeklyGoal,
                            pauses: [GoalPause], goalSince: Date?, dismissedAt: Date?) -> GoalReview? {
        if let d = dismissedAt, now.timeIntervalSince(d) < 28 * 86400 { return nil }
        let sessions = all.filter { $0.countsInStats && $0.start <= now }
        let current = TrainingStats.weekStart(of: now, cal)
        let since = goalSince.map { TrainingStats.weekStart(of: $0, cal) }
        // abgeschlossene, nicht eingefrorene Wochen rückwärts
        var results: [Bool] = []
        var w = cal.date(byAdding: .weekOfYear, value: -1, to: current) ?? current
        for _ in 0..<12 {
            if let since, w < since { break }
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: w) ?? w
            let inWeek = sessions.filter { $0.start >= w && $0.start < end }
            let target = goal.target(freeDays: pauses.freeDays(weekStart: w, calendar: cal))
            if target > 0 {
                let p = goal.progress(sessions: inWeek.count, minutes: inWeek.reduce(0) { $0 + $1.activeDuration } / 60)
                results.append(p >= target)
            }
            if results.count >= max(weeksUp, weeksDown) { break }
            w = cal.date(byAdding: .weekOfYear, value: -1, to: w) ?? w
        }
        // ohne jede Fahrt vor diesen Wochen nichts vorschlagen (neue Nutzer)
        guard let firstRide = sessions.map(\.start).min(),
              firstRide < (cal.date(byAdding: .weekOfYear, value: -weeksDown, to: current) ?? current) else { return nil }
        if results.count >= weeksUp, results.prefix(weeksUp).allSatisfy({ $0 }) {
            let up: WeeklyGoal
            switch goal.kind {
            case .rides:
                guard goal.value < WeeklyGoal.rideRange.upperBound else { return nil }
                up = WeeklyGoal(kind: .rides, value: goal.value + 1)
            case .minutes:
                guard goal.value < WeeklyGoal.minuteRange.upperBound else { return nil }
                up = WeeklyGoal(kind: .minutes, value: goal.value + 2 * WeeklyGoal.minuteStep)
            }
            return GoalReview(direction: .up, current: goal, proposed: up)
        }
        if results.count >= weeksDown, results.prefix(weeksDown).allSatisfy({ !$0 }) {
            let down: WeeklyGoal
            switch goal.kind {
            case .rides:
                guard goal.value > WeeklyGoal.rideRange.lowerBound else { return nil }
                down = WeeklyGoal(kind: .rides, value: goal.value - 1)
            case .minutes:
                guard goal.value > WeeklyGoal.minuteRange.lowerBound else { return nil }
                down = WeeklyGoal(kind: .minutes, value: goal.value - 2 * WeeklyGoal.minuteStep)
            }
            return GoalReview(direction: .down, current: goal, proposed: down)
        }
        return nil
    }
}
