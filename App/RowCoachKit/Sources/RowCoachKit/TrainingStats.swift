import Foundation

// Kennzahlen für den Startbildschirm (docs/design/startscreen*.md). Reine Funktionen ohne UI und ohne Speicher:
// Eingabe sind gespeicherte Trainings (bzw. ihre schlanke Form `TrainingSession`), ein Zeitpunkt „jetzt“ und ein
// Kalender. Gleiche Eingaben ergeben immer dasselbe Ergebnis.

/// Intensitätsstufe einer ganzen Einheit (Session-Goal-Prinzip): leicht, mittel, hart.
public enum IntensityLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    case easy = 0, moderate = 1, hard = 2

    public var title: String {
        switch self {
        case .easy: return "leicht"
        case .moderate: return "mittel"
        case .hard: return "hart"
        }
    }

    public static func < (a: IntensityLevel, b: IntensityLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Kalender für Wochen und Tage: Woche Mo–So, ISO-Kalenderwoche, Sprache de_CH.
public enum TrainingCalendar {
    public static func swiss(timeZone: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_CH")
        c.timeZone = timeZone
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }
}

/// Regeln zur Einstufung einer Einheit (startscreen-sport.md, Abschnitt 2):
/// 1. mit Programm nach `category`: Grundlage, Technik & Rhythmus = leicht (Programme dieser Art mit Belastung in
///    Zone 3, z. B. die Frequenzleiter, = mittel); Schwelle = mittel; Intervalle, Sprint, Test = hart.
///    Unbekannte Art: nach der höchsten Zielzone der Belastungsphasen (≥ 4 hart, 3 mittel, sonst leicht).
/// 2. frei gerudert mit Puls: hart ab 10 min in Zone 4–5, mittel ab 20 min in Zone 3–5, sonst leicht. Bei kurzen
///    Fahrten genügt jeweils die Hälfte der Pulszeit (eigene Ergänzung, damit 8 min Vollgas nicht „leicht“ ist).
/// 3. ohne Puls nach dem Durchschnittstempo zur 2000-m-Bestzeit: höchstens +12 s/500 m hart, höchstens +25 s mittel
///    (dieselben Stufen wie `EffortEstimator.paceWeight`).
/// 4. ohne Tempo nach der Belastung 1–10 (eigene, sonst geschätzte): ab 7 hart, ab 4 mittel.
public enum IntensityRules {
    public static func level(plan: WorkoutPlan) -> IntensityLevel {
        let cat = plan.category.lowercased()
        let workZone = plan.phases.filter { $0.kind == .work }.compactMap(\.hrZone).max() ?? 0
        if cat.contains("grundlage") { return .easy }
        if cat.contains("technik") || cat.contains("rhythmus") { return workZone >= 3 ? .moderate : .easy }
        if cat.contains("schwelle") { return .moderate }
        if cat.contains("intervall") || cat.contains("sprint") || cat.contains("test") { return .hard }
        if workZone >= 4 { return .hard }
        return workZone == 3 ? .moderate : .easy
    }

    /// nil, wenn weniger als 60 s Puls vorliegen
    public static func level(zoneSeconds z: [Double]?) -> IntensityLevel? {
        guard let z, z.count >= 6 else { return nil }
        let total = z.reduce(0, +)
        guard total >= 60 else { return nil }
        let hard = z[4] + z[5], mid = z[3] + hard
        if hard >= min(600, total / 2) { return .hard }
        if mid >= min(1200, total / 2) { return .moderate }
        return .easy
    }

    public static func level(averagePace: Double, best2k: Double) -> IntensityLevel? {
        guard averagePace > 0, averagePace.isFinite else { return nil }
        let delta = averagePace - PaceTargets.basePace500(best2k: best2k)
        if delta <= 12 { return .hard }
        if delta <= 25 { return .moderate }
        return .easy
    }

    public static func level(effort: Int?) -> IntensityLevel? {
        guard let e = effort else { return nil }
        if e >= 7 { return .hard }
        return e >= 4 ? .moderate : .easy
    }
}

/// Schlanke Form eines gespeicherten Trainings für die Kennzahlen (ohne Zeitreihe). Wird einmal je Training aus dem
/// `WorkoutRecord` gebaut und kann zwischengespeichert werden.
public struct TrainingSession: Equatable, Sendable, Identifiable {
    /// Herkunft: echte PM5-Fahrt, Simulator (zählt nie) oder Beispieltraining (zählt, nur Testbetrieb)
    public enum Origin: String, Sendable { case pm5, simulator, demo }

    public var id: UUID
    public var start: Date
    public var courseId: String?
    public var courseTitle: String?
    /// Länge der Strecke (m)
    public var courseLength: Double?
    public var planId: String?
    public var planName: String?
    /// Stufe des Programms (nil = frei gerudert oder Programm unbekannt)
    public var planLevel: IntensityLevel?
    /// m
    public var distance: Double
    /// Ruderzeit ohne Pausen (s)
    public var activeDuration: Double
    /// s/500 m über die ganze Einheit
    public var averagePace: Double
    /// s/500 m nur über die Belastungsphasen (Intervalle), nil ohne Programm
    public var workPace: Double?
    public var averageHeartRate: Int?
    /// Sekunden je Pulszone 0…5
    public var zoneSeconds: [Double]?
    public var completedCourse: Bool
    public var interrupted: Bool
    /// Belastung 1–10: eigene Einschätzung, sonst die der App
    public var effortScore: Int?
    public var origin: Origin

    public init(id: UUID = UUID(), start: Date, courseId: String? = nil, courseTitle: String? = nil,
                courseLength: Double? = nil, planId: String? = nil, planName: String? = nil,
                planLevel: IntensityLevel? = nil, distance: Double = 0, activeDuration: Double = 0,
                averagePace: Double = 0, workPace: Double? = nil, averageHeartRate: Int? = nil,
                zoneSeconds: [Double]? = nil, completedCourse: Bool = false, interrupted: Bool = false,
                effortScore: Int? = nil, origin: Origin = .pm5) {
        self.id = id
        self.start = start
        self.courseId = courseId
        self.courseTitle = courseTitle
        self.courseLength = courseLength
        self.planId = planId
        self.planName = planName
        self.planLevel = planLevel
        self.distance = distance
        self.activeDuration = activeDuration
        self.averagePace = averagePace
        self.workPace = workPace
        self.averageHeartRate = averageHeartRate
        self.zoneSeconds = zoneSeconds
        self.completedCourse = completedCourse
        self.interrupted = interrupted
        self.effortScore = effortScore
        self.origin = origin
    }

    /// Aus einem gespeicherten Training; `plan` ist das Programm zu `header.workoutPlanId` (für die Einstufung).
    public init(record: WorkoutRecord, plan: WorkoutPlan?) {
        let h = record.header, s = record.summary
        var work: Double?
        if let phases = record.planPhases {
            let w = phases.filter { $0.phaseKind == .work && $0.distance >= 10 }
            let d = w.reduce(0) { $0 + $1.distance }, t = w.reduce(0) { $0 + $1.duration }
            if d >= 10, t > 0 { work = t / d * 500 }
        }
        let origin: Origin = record.isDemo ? .demo : (h.device.source == .simulator ? .simulator : .pm5)
        self.init(id: record.id, start: h.startDate, courseId: h.courseId, courseTitle: h.courseTitle,
                  courseLength: h.courseLength, planId: h.workoutPlanId,
                  planName: h.workoutPlanName ?? plan?.name, planLevel: plan.map(IntensityRules.level(plan:)),
                  distance: s.distance, activeDuration: s.activeDuration, averagePace: s.averagePace,
                  workPace: work, averageHeartRate: s.averageHeartRate, zoneSeconds: s.heartRateZoneSeconds,
                  completedCourse: s.completedCourse, interrupted: record.isInterrupted,
                  effortScore: record.effort?.userScore ?? record.effort?.estimate, origin: origin)
    }

    /// Simulatorfahrten zählen in keiner Kennzahl (Beispieltrainings schon)
    public var countsInStats: Bool { origin != .simulator }
    /// Schlüssel für „je Strecke“
    public var courseKey: String? { courseId ?? courseTitle }
    /// Tempo für die Anzeige: bei Intervallen das der Belastungsphasen
    public var displayPace: Double { workPace ?? averagePace }
    /// Zählt für die Bestzeit: ganze Strecke frei gerudert, nicht unterbrochen
    public var isFullCourseRun: Bool { completedCourse && !interrupted && planId == nil && activeDuration > 0 }
    /// Mit Puls (für den Balken leicht/hart)
    public var hasHeartRate: Bool { (zoneSeconds?.reduce(0, +) ?? 0) >= 60 }

    /// Stufe der Einheit nach `IntensityRules`
    public func intensity(best2k: Double) -> IntensityLevel {
        if let p = planLevel { return p }
        if let z = IntensityRules.level(zoneSeconds: zoneSeconds) { return z }
        if let p = IntensityRules.level(averagePace: averagePace, best2k: best2k) { return p }
        return IntensityRules.level(effort: effortScore) ?? .easy
    }
}

/// Kennzahlen für „Diese Woche“, „Leicht und hart“, Wochenserie, „Letzte Fahrt“ und den Seen-Pass.
public struct TrainingStats: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public var date: Date
        /// härteste Einheit des Tages; nil = keine Fahrt
        public var level: IntensityLevel?
        public var minutes: Double
        public var isToday: Bool
        public var isFuture: Bool
    }

    public struct Week: Equatable, Sendable {
        public var start: Date
        /// ISO-Kalenderwoche
        public var number: Int
        /// Mo…So
        public var days: [Day]
        public var minutes: Double
        /// m
        public var distance: Double
        public var sessions: Int
        /// Schnitt der 4 Wochen davor (min pro Woche); nil, wenn es vor dieser Woche keine Fahrt gibt
        public var previousAverageMinutes: Double?
        public var previousAverageDistance: Double?
    }

    /// Verteilung nach Zeit in den Pulszonen (leicht = Zone 0–2, mittel = 3, hart = 4–5), letzte 28 Tage
    public struct Distribution: Equatable, Sendable {
        public var easySeconds: Double = 0
        public var moderateSeconds: Double = 0
        public var hardSeconds: Double = 0
        public var sessions: Int = 0
        public var sessionsWithHeartRate: Int = 0
        /// Einheiten mit Stufe hart (nach `IntensityRules`)
        public var hardSessions: Int = 0

        /// Prozentwerte erst ab 6 Fahrten mit Puls
        public static let minimumSessions = 6
        public var isMeaningful: Bool { sessionsWithHeartRate >= Self.minimumSessions && totalSeconds > 0 }
        public var totalSeconds: Double { easySeconds + moderateSeconds + hardSeconds }
        public var easyShare: Double { totalSeconds > 0 ? easySeconds / totalSeconds : 0 }
        public var moderateShare: Double { totalSeconds > 0 ? moderateSeconds / totalSeconds : 0 }
        public var hardShare: Double { totalSeconds > 0 ? hardSeconds / totalSeconds : 0 }
    }

    /// Wochenserie mit Joker (startscreen-gamification.md 3e, Synthese Abschnitt 3):
    /// - Eine Woche zählt, wenn sie mindestens `goal` Fahrten hat (Standard 3).
    /// - Die Serie hat einen Joker. Eine verpasste Woche verbraucht ihn, die Serie läuft weiter (die Woche zählt aber
    ///   nicht mit). Ist der Joker schon verbraucht, beginnt die Serie neu.
    /// - Der Joker kommt zurück, sobald nach seinem Einsatz wieder 4 Wochen in Folge erreicht sind.
    /// - Die laufende Woche bricht nie etwas: Sie zählt, sobald das Ziel erreicht ist, sonst bleibt sie offen.
    public struct Streak: Equatable, Sendable {
        public var weeks: Int
        public var goal: Int
        public var jokerAvailable: Bool
        /// Die letzte abgeschlossene Woche wurde mit dem Joker überbrückt
        public var jokerUsedLastWeek: Bool
        public var thisWeekSessions: Int
        public var thisWeekMet: Bool

        public static let weeksToRegainJoker = 4
    }

    public struct CourseRecord: Equatable, Sendable {
        public var key: String
        public var courseId: String?
        public var title: String?
        public var rides: Int
        /// m
        public var distance: Double
        /// beste Ruderzeit über die ganze Strecke (s), frei gerudert
        public var bestTime: Double?
        public var bestDate: Date?
        public var lastDate: Date
    }

    public struct LastRide: Equatable, Sendable {
        public var session: TrainingSession
        public var level: IntensityLevel
        /// neue Bestzeit auf dieser Strecke (nur wenn es vorher schon eine ganze Fahrt gab)
        public var isCourseBest: Bool
        /// Sekunden schneller als die bisherige Bestzeit
        public var improvement: Double?
    }

    public var now: Date
    public var week: Week
    public var distribution: Distribution
    public var streak: Streak
    public var lastRide: LastRide?
    /// je Strecke (Schlüssel `TrainingSession.courseKey`)
    public var courses: [String: CourseRecord]
    /// gezählte Fahrten insgesamt (ohne Simulator)
    public var totalSessions: Int

    public var isEmpty: Bool { totalSessions == 0 }

    /// - Parameters:
    ///   - sessions: alle gespeicherten Trainings (Simulatorfahrten und Fahrten nach `now` werden ignoriert)
    ///   - best2k: 2000-m-Bestzeit (s) für die Einstufung ohne Puls
    ///   - weeklyGoal: Fahrten pro Woche für die Wochenserie
    public init(sessions all: [TrainingSession], now: Date, calendar cal: Calendar = TrainingCalendar.swiss(),
                best2k: Double = PaceTargets.defaultBest2k, weeklyGoal: Int = 3) {
        let sessions = all.filter { $0.countsInStats && $0.start <= now }.sorted { $0.start < $1.start }
        self.now = now
        totalSessions = sessions.count

        // Woche Mo–So
        let weekStart = Self.weekStart(of: now, cal)
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86400)
        let today = cal.startOfDay(for: now)
        var days: [Day] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: weekStart) ?? weekStart
            let ofDay = sessions.filter { cal.isDate($0.start, inSameDayAs: d) }
            days.append(Day(date: d, level: ofDay.map { $0.intensity(best2k: best2k) }.max(),
                            minutes: ofDay.reduce(0) { $0 + $1.activeDuration } / 60,
                            isToday: cal.isDate(d, inSameDayAs: today), isFuture: d > today))
        }
        let inWeek = sessions.filter { $0.start >= weekStart && $0.start < weekEnd }
        let prevStart = cal.date(byAdding: .weekOfYear, value: -4, to: weekStart) ?? weekStart.addingTimeInterval(-28 * 86400)
        let prev = sessions.filter { $0.start >= prevStart && $0.start < weekStart }
        let hasEarlier = sessions.contains { $0.start < weekStart }
        week = Week(start: weekStart, number: cal.component(.weekOfYear, from: now), days: days,
                    minutes: inWeek.reduce(0) { $0 + $1.activeDuration } / 60,
                    distance: inWeek.reduce(0) { $0 + $1.distance }, sessions: inWeek.count,
                    previousAverageMinutes: hasEarlier ? prev.reduce(0) { $0 + $1.activeDuration } / 60 / 4 : nil,
                    previousAverageDistance: hasEarlier ? prev.reduce(0) { $0 + $1.distance } / 4 : nil)

        distribution = Self.distribution(sessions, endingAt: now, days: 28, calendar: cal, best2k: best2k)
        streak = Self.streak(sessions, now: now, calendar: cal, goal: weeklyGoal)

        // je Strecke
        var courses: [String: CourseRecord] = [:]
        for s in sessions {
            guard let key = s.courseKey else { continue }
            var r = courses[key] ?? CourseRecord(key: key, courseId: s.courseId, title: s.courseTitle, rides: 0,
                                                 distance: 0, bestTime: nil, bestDate: nil, lastDate: s.start)
            r.rides += 1
            r.distance += s.distance
            r.lastDate = max(r.lastDate, s.start)
            if s.courseTitle != nil { r.title = s.courseTitle }
            if s.isFullCourseRun, r.bestTime.map({ s.activeDuration < $0 }) ?? true {
                r.bestTime = s.activeDuration
                r.bestDate = s.start
            }
            courses[key] = r
        }
        self.courses = courses

        // letzte Fahrt mit Bestzeit-Hinweis (nur positiv)
        if let last = sessions.last {
            var isBest = false
            var improvement: Double?
            if last.isFullCourseRun, let key = last.courseKey {
                let earlier = sessions.dropLast().filter { $0.courseKey == key && $0.isFullCourseRun }
                if let prevBest = earlier.map(\.activeDuration).min(), last.activeDuration < prevBest {
                    isBest = true
                    improvement = prevBest - last.activeDuration
                }
            }
            lastRide = LastRide(session: last, level: last.intensity(best2k: best2k), isCourseBest: isBest,
                                improvement: improvement)
        } else {
            lastRide = nil
        }
    }

    /// Bequem direkt aus gespeicherten Trainings; `plans` dient der Einstufung nach Programmart.
    public init(records: [WorkoutRecord], plans: [WorkoutPlan], now: Date,
                calendar: Calendar = TrainingCalendar.swiss(), best2k: Double = PaceTargets.defaultBest2k,
                weeklyGoal: Int = 3) {
        let byId = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sessions = records.map { TrainingSession(record: $0, plan: $0.header.workoutPlanId.flatMap { byId[$0] }) }
        self.init(sessions: sessions, now: now, calendar: calendar, best2k: best2k, weeklyGoal: weeklyGoal)
    }

    // MARK: Bausteine (auch für DailySuggestion)

    static func weekStart(of date: Date, _ cal: Calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// Verteilung über die letzten `days` Tage (rollend, heute eingeschlossen)
    public static func distribution(_ sessions: [TrainingSession], endingAt now: Date, days: Int = 28,
                                    calendar cal: Calendar = TrainingCalendar.swiss(),
                                    best2k: Double = PaceTargets.defaultBest2k) -> Distribution {
        let from = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now)) ?? now
        var d = Distribution()
        for s in sessions where s.countsInStats && s.start >= from && s.start <= now {
            d.sessions += 1
            if s.intensity(best2k: best2k) == .hard { d.hardSessions += 1 }
            guard s.hasHeartRate, let z = s.zoneSeconds, z.count >= 6 else { continue }
            d.sessionsWithHeartRate += 1
            d.easySeconds += z[0] + z[1] + z[2]
            d.moderateSeconds += z[3]
            d.hardSeconds += z[4] + z[5]
        }
        return d
    }

    static func streak(_ sessions: [TrainingSession], now: Date, calendar cal: Calendar, goal: Int) -> Streak {
        let goal = max(goal, 1)
        var counts: [Date: Int] = [:]
        for s in sessions { counts[weekStart(of: s.start, cal), default: 0] += 1 }
        let current = weekStart(of: now, cal)
        let thisWeek = counts[current] ?? 0
        guard let first = counts.keys.min(), first < current else {
            return Streak(weeks: thisWeek >= goal ? 1 : 0, goal: goal, jokerAvailable: true, jokerUsedLastWeek: false,
                          thisWeekSessions: thisWeek, thisWeekMet: thisWeek >= goal)
        }
        var streak = 0, joker = true, sinceJoker = 0, usedLast = false
        var w = first
        var guardCount = 0
        while w < current && guardCount < 5000 {
            guardCount += 1
            usedLast = false
            if (counts[w] ?? 0) >= goal {
                streak += 1
                sinceJoker += 1
                if !joker && sinceJoker >= Streak.weeksToRegainJoker { joker = true }
            } else if streak > 0 && joker {
                joker = false
                sinceJoker = 0
                usedLast = true
            } else {
                streak = 0
                joker = true
                sinceJoker = 0
            }
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: w) else { break }
            w = next
        }
        if thisWeek >= goal { streak += 1 }
        return Streak(weeks: streak, goal: goal, jokerAvailable: joker, jokerUsedLastWeek: usedLast,
                      thisWeekSessions: thisWeek, thisWeekMet: thisWeek >= goal)
    }
}

/// Zielwerte eines Programms für die Vorschlagskarte: Bereich über alle Belastungsphasen (ohne Belastungsphasen:
/// über alle Phasen ausser Pausen).
public struct PlanTargetSummary: Equatable, Sendable {
    /// s/500 m (schnell…langsam)
    public var pace: ClosedRange<Double>?
    public var strokeRate: ClosedRange<Int>?
    /// höchste Zielzone
    public var zone: Int?

    public init(plan: WorkoutPlan, best2k: Double) {
        var phases = plan.phases.filter { $0.kind == .work }
        if phases.isEmpty { phases = plan.phases.filter { $0.kind != .rest } }
        let paces = phases.compactMap { $0.paceRange(best2k: best2k) }
        if let lo = paces.map(\.lowerBound).min(), let hi = paces.map(\.upperBound).max() {
            pace = lo...max(lo, hi)
        } else {
            pace = nil
        }
        let spm = phases.compactMap(\.spmRange)
        if let lo = spm.map(\.lowerBound).min(), let hi = spm.map(\.upperBound).max() {
            strokeRate = lo...max(lo, hi)
        } else {
            strokeRate = nil
        }
        zone = phases.compactMap(\.hrZone).max()
    }
}

extension WorkoutPlan {
    /// Kürzerer Name für Karten und Begründungen: „Minuten“ → „min“, „ x “ → „ × “
    public var shortName: String {
        name.replacingOccurrences(of: " Minuten", with: " min").replacingOccurrences(of: " x ", with: " × ")
    }
}
