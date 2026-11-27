import Foundation

/// Unsicherheitsstufe der aktiven Schwelle (Farbe in der Anzeige)
public enum ThresholdConfidence: String, Sendable {
    /// σ ≤ 4 %
    case high
    /// σ ≤ 8 %
    case medium
    /// σ > 8 % („Test empfohlen“)
    case low

    public init(sigma: Double) {
        self = sigma <= 4 ? .high : (sigma <= 8 ? .medium : .low)
    }

    public var title: String {
        switch self {
        case .high: return String(localized: "hoch")
        case .medium: return String(localized: "mittel")
        case .low: return String(localized: "niedrig")
        }
    }
}

/// Wie ein neues Testergebnis übernommen wird (docs/schwelle/SPEC.md, Abschnitt 6)
public enum ThresholdDecision: Equatable, Sendable {
    /// sofort aktiv (höher oder fast gleich); Hinweis „Neue Schwelle 171 W (+5 %)“, Knopf „Rückgängig“
    case adopt(changePct: Double)
    /// Rückfrage „übernehmen oder alte Schwelle behalten?“ (niedriger als 3 % oder aktive Schwelle ist eine Eingabe)
    case ask(changePct: Double)
    /// nur als Hinweis (Prüfhinweis wie „nicht all-out“)
    case hintOnly
}

/// Vorschlag, eine andere Schätzung zu übernehmen
public struct ThresholdProposal: Equatable, Sendable {
    public var estimate: ThresholdEstimate
    public var current: ThresholdEstimate
    public var changePct: Double
}

/// Wählt die aktive Schätzung, rechnet die aktuelle Unsicherheit, entscheidet über neue Ergebnisse und Vorschläge.
public enum ThresholdSelector {
    static let day: TimeInterval = 86400

    /// Aktuelle Unsicherheit σ(t) in %: Grundunsicherheit (mit Aufschlägen) + 0,5 % je Woche ab der 7. Woche nach dem
    /// Datum, nach einer Trainingspause ≥ 14 Tage zusätzlich 3 %; höchstens 15 %.
    /// - Parameter pauseDays: Tage ohne Fahrt bis heute (bzw. längste Pause seit dem Datum der Schätzung)
    public static func sigma(_ e: ThresholdEstimate, now: Date, pauseDays: Int = 0) -> Double {
        let days = max(now.timeIntervalSince(e.date) / day, 0)
        let week = Int(days / 7) + 1
        var s = e.sigmaPct + Double(max(week - 6, 0)) * 0.5
        if pauseDays >= 14 { s += 3 }
        return min(max(s, e.sigmaPct), max(15, e.sigmaPct))
    }

    /// Kandidaten für die automatische Wahl: nicht verworfen, kein reiner Hinweis, keine offene Rückfrage
    public static func eligible(_ p: ThresholdProfile) -> [ThresholdEstimate] {
        p.estimates.filter { e in
            e.statusValue != .rejected && e.statusValue != .candidate && !e.isHintOnly && e.powerW > 0
        }
    }

    /// Die Schätzung mit dem kleinsten σ(t); bei Gleichstand die neuere
    public static func best(in p: ThresholdProfile, now: Date, pauseDays: Int = 0) -> ThresholdEstimate? {
        let list = eligible(p)
        return list.min { a, b in
            let sa = sigma(a, now: now, pauseDays: pauseDays), sb = sigma(b, now: now, pauseDays: pauseDays)
            if abs(sa - sb) > 1e-9 { return sa < sb }
            return a.date > b.date
        }
    }

    /// Aktive Schätzung mit Unsicherheit und Stufe
    public static func activeSigma(_ p: ThresholdProfile, now: Date, pauseDays: Int = 0) -> Double? {
        p.active.map { sigma($0, now: now, pauseDays: pauseDays) }
    }

    /// Neues Testergebnis: übernehmen, nachfragen oder nur zeigen?
    /// - Eingaben (`manual*`) werden nie automatisch abgelöst → Rückfrage, wenn das Ergebnis um mehr als 3 % abweicht
    ///   (sonst bleibt die Eingabe ohne Rückfrage aktiv: `.ask(0)` nur, wenn > 3 %, sonst `.hintOnly`).
    /// - höher als die aktive Schwelle → sofort aktiv; niedriger um mehr als 3 % → Rückfrage; bis 3 % tiefer → aktiv.
    /// - Prüfhinweise wie „nicht all-out“ → nur Hinweis.
    public static func decide(_ new: ThresholdEstimate, profile: ThresholdProfile) -> ThresholdDecision {
        if new.isHintOnly { return .hintOnly }
        guard let cur = profile.active, cur.id != new.id, cur.powerW > 0 else { return .adopt(changePct: 0) }
        let change = (new.powerW - cur.powerW) / cur.powerW * 100
        if cur.isManual { return abs(change) > 3 ? .ask(changePct: change) : .hintOnly }
        if change >= -3 { return .adopt(changePct: change) }
        return .ask(changePct: change)
    }

    /// Vorschlag, eine sicherere Schätzung statt der aktiven zu verwenden (aktive Eingabe: „Dein Test vom … ergab
    /// 171 W, eingetragen sind 160 W. Übernehmen?“): um ≥ 1 Prozentpunkt sicherer und mehr als 3 % Abweichung.
    public static func proposal(_ p: ThresholdProfile, now: Date, pauseDays: Int = 0) -> ThresholdProposal? {
        guard let cur = p.active, cur.isManual else { return nil }
        let sCur = sigma(cur, now: now, pauseDays: pauseDays)
        let others = eligible(p).filter { $0.id != cur.id && !$0.isManual && $0.date >= cur.date }
        guard let b = others.min(by: { sigma($0, now: now) < sigma($1, now: now) }),
              sigma(b, now: now, pauseDays: pauseDays) <= sCur - 1 else { return nil }
        let change = (b.powerW - cur.powerW) / cur.powerW * 100
        guard abs(change) > 3 else { return nil }
        return ThresholdProposal(estimate: b, current: cur, changePct: change)
    }

    // MARK: Ergebnis übernehmen

    /// Ergebnis ins Profil eintragen und nach `decide` aktiv setzen (bei `.ask` bleibt es `candidate`, bei
    /// `.hintOnly` ebenfalls). Liefert die Entscheidung.
    @discardableResult
    public static func submit(_ e: ThresholdEstimate, to p: inout ThresholdProfile) -> ThresholdDecision {
        let d = decide(e, profile: p)
        var e = e
        e.status = ThresholdEstimate.Status.candidate.rawValue
        // dieselbe Fahrt nicht doppelt
        if let w = e.workoutId, let old = p.estimates.first(where: { $0.workoutId == w && $0.kind == e.kind }) {
            e.id = old.id
        }
        p.insert(e)
        if case .adopt = d { p.activate(id: e.id) }
        return d
    }

    // MARK: Kalibrierung (SPEC 2.3)

    /// Exponent b aus zwei gültigen maximalen Zeitfahren (Quelle `timeTrial`) innerhalb von 42 Tagen mit
    /// Dauerverhältnis ≥ 2,5; bei mehreren Paaren das jüngste. Begrenzt auf 0,08–0,22.
    public static func calibratedExponent(_ p: ThresholdProfile) -> Double? {
        let tts = p.estimates.filter {
            $0.source == .timeTrial && $0.statusValue != .rejected && !$0.isHintOnly
                && ($0.details["p"] ?? 0) > 0 && ($0.details["t"] ?? 0) > 0
        }.sorted { $0.date > $1.date }
        for (i, a) in tts.enumerated() {
            for b in tts[(i + 1)...] where abs(a.date.timeIntervalSince(b.date)) <= 42 * day {
                let ta = a.details["t"]!, tb = b.details["t"]!
                guard max(ta, tb) / min(ta, tb) >= 2.5,
                      let x = ThresholdMath.exponent(powerA: a.details["p"]!, durationA: ta,
                                                     powerB: b.details["p"]!, durationB: tb) else { continue }
                return min(max(x, 0.08), 0.22)
            }
        }
        return nil
    }

    /// Rampenfaktor aus einer Rampe und einem Zeitfahren 20–60 min innerhalb von 28 Tagen, begrenzt 0,68–0,82
    public static func calibratedRampFactor(_ p: ThresholdProfile) -> Double? {
        let ramps = p.estimates.filter { $0.source == .ramp && !$0.isHintOnly && ($0.details["map"] ?? 0) > 0 }
            .sorted { $0.date > $1.date }
        let tts = p.estimates.filter {
            $0.source == .timeTrial && $0.statusValue != .rejected && !$0.isHintOnly
                && (1200...3600).contains($0.details["t"] ?? 0)
        }
        for r in ramps {
            if let tt = tts.filter({ abs($0.date.timeIntervalSince(r.date)) <= 28 * day })
                .min(by: { abs($0.date.timeIntervalSince(r.date)) < abs($1.date.timeIntervalSince(r.date)) }) {
                return min(max(tt.powerW / r.details["map"]!, 0.68), 0.82)
            }
        }
        return nil
    }

    /// Kalibrierung anwenden (gilt für neue Umrechnungen; alte Schätzungen bleiben)
    public static func applyCalibration(_ p: inout ThresholdProfile) {
        if let b = calibratedExponent(p) {
            p.exponentB = b
            p.exponentBSource = "calibrated"
        }
        if let r = calibratedRampFactor(p) { p.rampFactor = r }
    }

    /// „eher Ausdauertyp“ (b klein) bzw. „eher Sprinttyp“ (b gross); nil beim Standardwert
    public static func enduranceProfile(_ p: ThresholdProfile) -> String? {
        guard p.exponentBSource == "calibrated" else { return nil }
        if p.exponentB < 0.13 { return String(localized: "Dein Ausdauerprofil: eher Ausdauertyp") }
        if p.exponentB > 0.17 { return String(localized: "Dein Ausdauerprofil: eher Sprinttyp") }
        return String(localized: "Dein Ausdauerprofil: ausgeglichen")
    }
}

// MARK: - Retest-Regeln (SPEC Abschnitt 7)

/// Eingang für die Retest-Regel R1 in `DailySuggestion` (Regel 4 „Schwellentest fällig“)
public struct ThresholdRetestInput: Equatable, Sendable {
    /// Datum der aktiven Schwelle (nil = keine)
    public var activeDate: Date?
    /// aktuelle Unsicherheit der aktiven Schwelle (%)
    public var sigma: Double
    /// bevorzugter Test (Plan-id)
    public var preferredTest: String
    /// maximale Tests sind gesperrt (Gesundheitsfrage mit Ja, ohne ärztliche Freigabe)
    public var maximalBlocked: Bool

    public init(activeDate: Date?, sigma: Double, preferredTest: String, maximalBlocked: Bool = false) {
        self.activeDate = activeDate
        self.sigma = sigma
        self.preferredTest = preferredTest
        self.maximalBlocked = maximalBlocked
    }
}

public enum ThresholdRetest {
    public static let submaxTest = "schwelle-stufentest-puls"
    public static let ftpTest = "schwelle-test-20min"
    public static let rampTest = "schwelle-rampentest"
    public static let cpTest = "schwelle-test-3min"
    /// Mindestabstand zwischen zwei vorgeschlagenen Tests (Tage)
    public static let minDaysBetweenTests = 21

    /// Bevorzugter Test nach Profil (Einstellung hat Vorrang): Pulsgurt bekannt und (Einsteiger, Gesundheitsfrage mit
    /// Ja oder Alter ≥ 60) → Stufentest submaximal; schon einmal 2000 m getestet → 2000 m; sonst 20 min.
    /// Mit gesperrten maximalen Tests immer der Stufentest.
    public static func preferredTest(profile: ThresholdProfile, hasHeartRateStrap: Bool, isBeginner: Bool,
                                     tested2k: Bool, now: Date) -> String {
        let blocked = profile.healthScreen?.blocksMaximalTests ?? false
        if let p = profile.preferredTest, !(blocked && p != submaxTest) { return p }
        if blocked { return submaxTest }
        let older = (profile.heart.age(now: now) ?? 0) >= 60
        if hasHeartRateStrap && (isBeginner || (profile.healthScreen?.anyYes ?? false) || older) { return submaxTest }
        if tested2k { return "test-2000m" }
        return ftpTest
    }

    /// Ist ein Programm ein maximaler Test (Gesundheitsfragen nötig)?
    public static func isMaximalTest(_ plan: WorkoutPlan) -> Bool {
        if let t = plan.test { return t.allOut || t.evaluatorKind == .timeTrial || t.evaluatorKind == .ramp }
        return TrainingProgramEngine.isTestPlan(plan.id) && !plan.id.hasPrefix("stufentest")
    }

    /// R1: Schwelle älter als 8 Wochen oder σ(t) > 8 %
    public static func isDue(_ input: ThresholdRetestInput, now: Date) -> Bool {
        guard let d = input.activeDate else { return true }
        return now.timeIntervalSince(d) > 56 * 86400 || input.sigma > 8
    }

    /// Einheit für R4/R5 (Schwelle/Intervalle)
    public struct Session: Equatable, Sendable {
        public var date: Date
        /// Anteil der Belastungszeit mit roter Tempoampel (zu langsam), 0…1
        public var redShare: Double
        /// eigene Belastung 1–10
        public var userScore: Int?
        /// gemessene Leistung in % des Ziels (Belastungsphasen)
        public var powerVsTargetPct: Double?
        /// höchste Pulszone in den Belastungsphasen
        public var maxZone: Int?
        /// Kategorie Schwelle (nur diese zählen für R5)
        public var isThreshold: Bool

        public init(date: Date, redShare: Double, userScore: Int? = nil, powerVsTargetPct: Double? = nil,
                    maxZone: Int? = nil, isThreshold: Bool = true) {
            self.date = date
            self.redShare = redShare
            self.userScore = userScore
            self.powerVsTargetPct = powerVsTargetPct
            self.maxZone = maxZone
            self.isThreshold = isThreshold
        }
    }

    public enum TargetHint: Equatable, Sendable {
        /// R4: „Ziele zu hoch?“ (Test oder Schwelle −3 %)
        case tooHard
        /// R5: „Ziele zu leicht?“ (Test)
        case tooEasy
    }

    /// R4/R5 aus den letzten Einheiten der Kategorien Schwelle/Intervalle (neueste zuletzt)
    public static func targetHint(_ sessions: [Session]) -> TargetHint? {
        let last3 = sessions.suffix(3)
        if last3.count >= 2,
           last3.filter({ $0.redShare > 0.4 || ($0.userScore ?? 0) >= 9 }).count >= 2 { return .tooHard }
        let thr = sessions.filter(\.isThreshold).suffix(4)
        if thr.count >= 3, thr.filter({ ($0.powerVsTargetPct ?? 0) > 105 && ($0.maxZone ?? 9) <= 3 }).count >= 3 {
            return .tooEasy
        }
        return nil
    }

    /// R3: nach einer Pause ≥ 14 Tage bei der 3. Fahrt danach den Stufentest zum Wiedereinstieg vorschlagen
    public static func reentryTestDue(rideDates: [Date]) -> Bool {
        let d = rideDates.sorted()
        guard d.count >= 4 else { return false }
        // letzte Pause ≥ 14 Tage, danach genau 3 Fahrten
        for i in stride(from: d.count - 1, to: 0, by: -1) where d[i].timeIntervalSince(d[i - 1]) >= 14 * 86400 {
            return d.count - i == 3
        }
        return false
    }
}
