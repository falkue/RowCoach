import Foundation

/// „Vorschlag für heute“ (docs/design/startscreen-sport.md, Abschnitt 3; Synthese startscreen.md, Abschnitt 2).
///
/// Es gilt die erste zutreffende Regel; Eingaben sind nur die eigenen Fahrten (ohne Simulator), jede Einheit
/// eingestuft nach `IntensityRules`:
///
/// | # | Bedingung | Vorschlag |
/// |---|---|---|
/// | 0 | weniger als 3 Fahrten oder mehr als 7 Tage seit der letzten | Lockere Grundlage 30 |
/// | 1 | harte oder mittlere Einheit vor weniger als 48 h | Technik 25, wenn gestern (oder heute) hart, sonst Grundlage 30 |
/// | 2 | mindestens 2 harte Einheiten in den letzten 7 Tagen | Grundlage 3 × 10 im Wechsel mit Grundlage 30 |
/// | 3 | Leicht-Anteil (Zeit, 28 Tage) unter 75 % bei mindestens 6 Fahrten mit Puls | Grundlage wie in Regel 2 |
/// | 4 | letzter 2000-m-Test vor mehr als 8 Wochen (oder nie), 4 Wochen regelmässig (in jedem der letzten vier 7-Tage-Fenster mindestens 2 Fahrten), letzte 48 h leicht | Test 2000 m |
/// | 5 | sonst | das am längsten nicht gefahrene aus Schwelle 4 × 6, 4 × 4, 8 × 2, Pyramide; Sprint 8 × 250 nur, wenn der letzte Sprint mindestens 14 Tage her ist |
///
/// Zusätze:
/// - Wurde heute schon gerudert, gilt „Heute erledigt“: Der Vorschlag wird für morgen (gleiche Uhrzeit) berechnet.
/// - Waren die letzten 3 leichten Einheiten dasselbe Programm, wird die Frequenzleiter als erste Alternative angeboten
///   (nur bei leichtem Vorschlag und nicht direkt nach einer harten oder mittleren Einheit).
/// - Strecke: die gewählte (`preferredCourseId`), sonst die am längsten nicht geruderte; nie geruderte zuerst, dabei
///   die Heimstrecke (`homeCourseId`) vor den anderen, sonst die Reihenfolge von `courseIds`.
/// - Zwei Alternativen: ein anderes Programm (leicht ↔ leicht, hart → Lockere Grundlage) und „Frei rudern“ auf der
///   zuletzt geruderten Strecke.
/// Gleiche Eingaben ergeben immer denselben Vorschlag.
public struct DailySuggestion: Equatable, Sendable {
    public enum Rule: String, Sendable {
        /// Regel 0: wenige Fahrten oder lange Pause
        case start
        /// Regel 1: harte oder mittlere Einheit vor weniger als 48 h
        case recovery
        /// Regel 2: genug harte Einheiten in 7 Tagen
        case enoughHard
        /// Regel 3: zu wenig leicht in 28 Tagen
        case moreEasy
        /// Regel 4: 2000-m-Test fällig
        case test
        /// Regel 5: harter Reiz fällig
        case stimulus
    }

    /// Eine Wahl auf der Karte (Vorschlag oder Alternative)
    public enum Option: Equatable, Hashable, Sendable {
        case plan(planId: String, courseId: String?)
        case free(courseId: String?)
    }

    public var planId: String
    public var courseId: String?
    public var rule: Rule
    /// Eine Zeile „weil …“
    public var reason: String
    /// Genau zwei Alternativen
    public var alternatives: [Option]
    /// Heute wurde schon gerudert; der Vorschlag gilt für morgen
    public var doneToday: Bool
    /// Zeitpunkt, für den der Vorschlag berechnet wurde (jetzt bzw. morgen)
    public var forDate: Date
    /// Stufe des vorgeschlagenen Programms
    public var level: IntensityLevel

    public var option: Option { .plan(planId: planId, courseId: courseId) }

    // Programme aus plans.json
    public enum Plans {
        public static let easy30 = "grundlage-locker-30"
        public static let easy3x10 = "grundlage-3x10-r20"
        public static let technique25 = "technik-locker-25"
        public static let ladder = "frequenzleiter-18-24"
        public static let test2k = "test-2000m"
        public static let sprint = "sprint-8x250"
        public static let hardRotation = ["schwelle-4x6", "langintervalle-4x4", "kurzintervalle-8x2",
                                          "pyramide-1-2-3-4-3-2-1"]
    }

    public static let defaultHomeCourseId = "zuerichsee-utoquai"

    public init(planId: String, courseId: String?, rule: Rule, reason: String, alternatives: [Option],
                doneToday: Bool, forDate: Date, level: IntensityLevel) {
        self.planId = planId
        self.courseId = courseId
        self.rule = rule
        self.reason = reason
        self.alternatives = alternatives
        self.doneToday = doneToday
        self.forDate = forDate
        self.level = level
    }

    /// - Parameters:
    ///   - sessions: alle gespeicherten Trainings (Simulator und Zukunft werden ignoriert)
    ///   - plans: Programmkatalog (für Namen und Einstufung); leer = nur die ids
    ///   - courseIds: verfügbare Strecken in fester Reihenfolge
    ///   - preferredCourseId: im Seen-Pass gewählte Strecke (hat Vorrang)
    public static func make(sessions all: [TrainingSession], plans: [WorkoutPlan], courseIds: [String], now: Date,
                            calendar cal: Calendar = TrainingCalendar.swiss(),
                            best2k: Double = PaceTargets.defaultBest2k, preferredCourseId: String? = nil,
                            homeCourseId: String? = DailySuggestion.defaultHomeCourseId) -> DailySuggestion {
        let sessions = all.filter { $0.countsInStats && $0.start <= now }.sorted { $0.start < $1.start }
        let doneToday = sessions.contains { cal.isDate($0.start, inSameDayAs: now) }
        let t = doneToday ? (cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)) : now
        let ctx = Context(sessions: sessions, plans: plans, t: t, cal: cal, best2k: best2k)
        let (planId, rule, reason) = ctx.choosePlan()
        let course = ctx.chooseCourse(courseIds: courseIds, preferred: preferredCourseId, home: homeCourseId)
        let level = ctx.planLevel(planId)
        let alternatives = ctx.alternatives(for: planId, level: level, rule: rule, course: course)
        return DailySuggestion(planId: planId, courseId: course, rule: rule, reason: reason,
                               alternatives: alternatives, doneToday: doneToday, forDate: t, level: level)
    }

    /// Rechenkontext zum Zeitpunkt `t`
    struct Context {
        let sessions: [TrainingSession]
        let plans: [WorkoutPlan]
        let t: Date
        let cal: Calendar
        let best2k: Double

        static let day: TimeInterval = 86400

        func plan(_ id: String) -> WorkoutPlan? { plans.first { $0.id == id } }
        func name(_ id: String) -> String { plan(id)?.shortName ?? id }
        func exists(_ id: String) -> Bool { plans.isEmpty || plan(id) != nil }

        func planLevel(_ id: String) -> IntensityLevel {
            if let p = plan(id) { return IntensityRules.level(plan: p) }
            if id == Plans.test2k || id == Plans.sprint || Plans.hardRotation.contains(id) {
                return id == "schwelle-4x6" ? .moderate : .hard
            }
            return id == Plans.ladder ? .moderate : .easy
        }

        func level(_ s: TrainingSession) -> IntensityLevel { s.intensity(best2k: best2k) }

        func lastDate(plan id: String) -> Date? { sessions.last { $0.planId == id }?.start }

        /// Bezeichnung einer Einheit in der Begründung
        func label(_ s: TrainingSession) -> String {
            if let id = s.planId { return plan(id)?.shortName ?? s.planName ?? id }
            return "freie Fahrt"
        }

        /// „heute“, „gestern“, „vorgestern“, sonst „vor N Tagen“
        func dayWord(_ d: Date) -> String {
            let n = daysBetween(d, t)
            switch n {
            case ...0: return "heute"
            case 1: return "gestern"
            case 2: return "vorgestern"
            default: return "vor \(n) Tagen"
            }
        }

        func daysBetween(_ a: Date, _ b: Date) -> Int {
            cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
        }

        func choosePlan() -> (String, Rule, String) {
            // 0: Einstieg
            guard sessions.count >= 3, let last = sessions.last, t.timeIntervalSince(last.start) <= 7 * Self.day else {
                let reason = sessions.isEmpty ? "Willkommen – locker einsteigen und das Gerät kennenlernen."
                    : sessions.count < 3 ? "Locker einsteigen: Die ersten Fahrten bauen die Grundlage."
                    : "Locker wieder einsteigen, dann steigern."
                return (Plans.easy30, .start, reason)
            }
            // 1: Erholung nach hart/mittel
            if let lastHM = sessions.last(where: { level($0) >= .moderate }), t.timeIntervalSince(lastHM.start) < 2 * Self.day {
                let lv = level(lastHM)
                let recent = daysBetween(lastHM.start, t) <= 1
                if lv == .hard && recent && exists(Plans.technique25) {
                    return (Plans.technique25, .recovery,
                            "\(dayWord(lastHM.start).capitalizedFirst) \(label(lastHM)) – heute locker und sauber.")
                }
                return (Plans.easy30, .recovery,
                        "\(dayWord(lastHM.start).capitalizedFirst) \(lv.title): \(label(lastHM)) – heute locker.")
            }
            // 2: genug hart in 7 Tagen
            let week = sessions.filter { t.timeIntervalSince($0.start) < 7 * Self.day }
            let hardWeek = week.filter { level($0) == .hard }.count
            if hardWeek >= 2 {
                return (easyBase(), .enoughHard, "\(hardWeek) harte Einheiten in 7 Tagen sind genug – heute Grundlage.")
            }
            // 3: zu wenig leicht
            let dist = TrainingStats.distribution(sessions, endingAt: t, days: 28, calendar: cal, best2k: best2k)
            if dist.isMeaningful && dist.easyShare < 0.75 {
                let pct = Int((dist.easyShare * 100).rounded())
                return (easyBase(), .moreEasy, "Mehr lockere Kilometer: zuletzt \(pct) % leicht, Ziel etwa 80/20.")
            }
            // 4: 2000-m-Test
            if exists(Plans.test2k), regularFourWeeks(), !sessions.contains(where: {
                t.timeIntervalSince($0.start) < 2 * Self.day && level($0) >= .moderate }) {
                let lastTest = lastDate(plan: Plans.test2k)
                if lastTest == nil || t.timeIntervalSince(lastTest!) > 56 * Self.day {
                    let reason = lastTest == nil
                        ? "Vier Wochen regelmässig gerudert – ein 2000-m-Test setzt die Referenz für deine Tempoziele."
                        : "Letzter 2000-m-Test vor über 8 Wochen – neue Referenz für deine Tempoziele."
                    return (Plans.test2k, .test, reason)
                }
            }
            // 5: harter Reiz
            var candidates = Plans.hardRotation.filter(exists)
            if exists(Plans.sprint), lastDate(plan: Plans.sprint).map({ t.timeIntervalSince($0) >= 14 * Self.day }) ?? true {
                candidates.append(Plans.sprint)
            }
            if candidates.isEmpty { candidates = [Plans.hardRotation[0]] }
            let pick = oldest(candidates)
            if let lastHard = sessions.last(where: { level($0) == .hard }) {
                let n = daysBetween(lastHard.start, t)
                let when = n <= 2 ? dayWord(lastHard.start) : "vor \(n) Tagen"
                return (pick, .stimulus,
                        "Letzte harte Einheit \(when) – Zeit für einen Reiz. Zuletzt \(label(lastHard)).")
            }
            return (pick, .stimulus, "Zeit für einen Reiz: heute \(name(pick)).")
        }

        /// Grundlage im Wechsel: das länger nicht gefahrene aus 3 × 10 und 30 min (Gleichstand: 3 × 10)
        func easyBase() -> String {
            let opts = [Plans.easy3x10, Plans.easy30].filter(exists)
            guard !opts.isEmpty else { return Plans.easy30 }
            return oldest(opts)
        }

        /// Das am längsten nicht gefahrene Programm; nie gefahrene zuerst, sonst Reihenfolge der Liste
        func oldest(_ ids: [String]) -> String {
            var best = ids[0], bestDate = lastDate(plan: ids[0])
            for id in ids.dropFirst() {
                let d = lastDate(plan: id)
                switch (d, bestDate) {
                case (nil, .some): best = id; bestDate = d
                case let (.some(a), .some(b)) where a < b: best = id; bestDate = d
                default: break
                }
            }
            return best
        }

        /// In jedem der letzten vier 7-Tage-Fenster mindestens 2 Fahrten
        func regularFourWeeks() -> Bool {
            for w in 0..<4 {
                let hi = t.addingTimeInterval(-Double(w) * 7 * Self.day)
                let lo = hi.addingTimeInterval(-7 * Self.day)
                if sessions.filter({ $0.start >= lo && $0.start < hi }).count < 2 { return false }
            }
            return true
        }

        func chooseCourse(courseIds: [String], preferred: String?, home: String?) -> String? {
            if let p = preferred, courseIds.contains(p) { return p }
            guard !courseIds.isEmpty else { return preferred }
            var lastRowed: [String: Date] = [:]
            for s in sessions { if let c = s.courseId { lastRowed[c] = s.start } }
            func rank(_ id: String) -> (Int, Date, Int) {
                let idx = courseIds.firstIndex(of: id) ?? 0
                if let d = lastRowed[id] { return (2, d, idx) }
                return (id == home ? 0 : 1, .distantPast, idx)
            }
            return courseIds.min { a, b in
                let ra = rank(a), rb = rank(b)
                if ra.0 != rb.0 { return ra.0 < rb.0 }
                if ra.1 != rb.1 { return ra.1 < rb.1 }
                return ra.2 < rb.2
            }
        }

        func alternatives(for planId: String, level: IntensityLevel, rule: Rule, course: String?) -> [Option] {
            let altPlan: String
            if level >= .moderate {
                altPlan = Plans.easy30
            } else if rule != .recovery && rule != .start && repeatedEasy() && exists(Plans.ladder) {
                altPlan = Plans.ladder
            } else if planId == Plans.easy30 {
                altPlan = exists(Plans.easy3x10) ? Plans.easy3x10 : Plans.technique25
            } else {
                altPlan = Plans.easy30
            }
            let freeCourse = sessions.last?.courseId ?? course
            return [.plan(planId: altPlan, courseId: course), .free(courseId: freeCourse)]
        }

        /// Die letzten 3 leichten Einheiten waren dasselbe Programm
        func repeatedEasy() -> Bool {
            let easy = sessions.filter { level($0) == .easy }.suffix(3)
            guard easy.count == 3, let id = easy.first?.planId else { return false }
            return easy.allSatisfy { $0.planId == id }
        }
    }
}

extension String {
    /// Erster Buchstabe gross („gestern“ → „Gestern“)
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
