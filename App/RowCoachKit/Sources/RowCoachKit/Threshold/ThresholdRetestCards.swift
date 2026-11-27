import Foundation

// MARK: - Einheiten für R4/R5 aus gespeicherten Fahrten

/// Verdichtete Fahrt der Kategorien Schwelle/Intervalle für die Retest-Hinweise R4/R5 (docs/schwelle/SPEC.md 7).
/// Unabhängig von der 2k-Referenz gespeichert, damit sich die Ziele später mit der aktuellen Referenz rechnen lassen
/// (`session(best2k:zones:)`): je Belastungsphase mit Tempoziel die Dauer, die Mitte des Zielbereichs, die mittlere
/// Leistung, der mittlere Puls und – für die Tempoampel – Quantile von `Tempo − Ziel langsam − 3 s` (rot = zu langsam,
/// wenn der Wert über dem 2k-Tempo liegt).
public struct RetestRide: Equatable, Sendable {
    public struct Phase: Equatable, Sendable {
        /// Belastungszeit (s)
        public var duration: Double
        /// Mitte des Zielbereichs relativ zum 2k-Tempo (s/500 m)
        public var paceOffsetMid: Double
        /// mittlere Leistung (W) über Messpunkte mit Schlag
        public var averagePower: Double?
        /// mittlerer Puls
        public var averageHeartRate: Int?
        /// aufsteigend sortierte Quantile von `Tempo − paceOffsetMax − 3` (s/500 m)
        public var slowExcess: [Double]

        public init(duration: Double, paceOffsetMid: Double, averagePower: Double?, averageHeartRate: Int?,
                    slowExcess: [Double]) {
            self.duration = duration
            self.paceOffsetMid = paceOffsetMid
            self.averagePower = averagePower
            self.averageHeartRate = averageHeartRate
            self.slowExcess = slowExcess
        }
    }

    public var date: Date
    /// Kategorie Schwelle (nur diese zählen für R5)
    public var isThreshold: Bool
    public var userScore: Int?
    public var phases: [Phase]

    /// Höchstzahl gespeicherter Quantile je Phase
    public static let quantiles = 100
    /// Toleranz der Tempoampel (gelb bis 3 s neben dem Ziel, `TargetLight.pace`)
    public static let paceTolerance: Double = 3

    public init(date: Date, isThreshold: Bool, userScore: Int?, phases: [Phase]) {
        self.date = date
        self.isThreshold = isThreshold
        self.userScore = userScore
        self.phases = phases
    }

    /// Kategorie eines Programms, die für R4/R5 zählt (deutscher Schlüssel `categoryID`)
    public static func counts(_ plan: WorkoutPlan) -> Bool {
        plan.categoryID == "Schwelle" || plan.categoryID == "Intervalle"
    }

    /// nil, wenn das Programm nicht zu Schwelle/Intervalle gehört oder keine Belastungsphase mit Tempoziel gefahren ist
    public static func make(record: WorkoutRecord, plan: WorkoutPlan?) -> RetestRide? {
        guard let plan, counts(plan), let results = record.planPhases else { return nil }
        var phases: [Phase] = []
        for r in results where r.duration >= 30 {
            guard plan.phases.indices.contains(r.index) else { continue }
            let p = plan.phases[r.index]
            // nur Belastung mit Tempoziel relativ zum 2k-Tempo (Phasen in % der Schwelle gibt es nur in Tests)
            guard p.kind == .work, p.powerPctRange == nil, let a = p.paceOffsetMinS ?? p.paceOffsetMaxS else { continue }
            let b = p.paceOffsetMaxS ?? a
            let slow = max(a, b)
            let inPhase = record.samples.filter { $0.time >= r.startTime && $0.time < r.endTime && $0.strokeRate > 0 }
            let paces = inPhase.map(\.pace).filter { $0 > 0 && $0.isFinite }
            guard !paces.isEmpty else { continue }
            let excess = paces.map { $0 - slow - paceTolerance }.sorted()
            let power = inPhase.isEmpty ? nil : Double(inPhase.reduce(0) { $0 + $1.power }) / Double(inPhase.count)
            let hrs = inPhase.compactMap { $0.heartRate }.filter { $0 > 0 }
            phases.append(Phase(duration: r.duration, paceOffsetMid: (a + b) / 2,
                                averagePower: power.flatMap { $0 > 0 ? $0 : nil },
                                averageHeartRate: hrs.isEmpty ? r.averageHeartRate : hrs.reduce(0, +) / hrs.count,
                                slowExcess: Self.compress(excess)))
        }
        guard !phases.isEmpty else { return nil }
        return RetestRide(date: record.header.startDate, isThreshold: plan.categoryID == "Schwelle",
                          userScore: record.effort?.userScore, phases: phases)
    }

    /// Gleichmässig verteilte Quantile einer sortierten Liste (höchstens `quantiles` Werte)
    static func compress(_ sorted: [Double]) -> [Double] {
        guard sorted.count > quantiles else { return sorted }
        return (0..<quantiles).map { i in
            sorted[min(Int((Double(i) + 0.5) / Double(quantiles) * Double(sorted.count)), sorted.count - 1)]
        }
    }

    /// Einheit für `ThresholdRetest.targetHint` mit der aktuellen 2k-Referenz und Pulszonen
    public func session(best2k: Double, zones: HeartRateZones?) -> ThresholdRetest.Session {
        let base = PaceTargets.basePace500(best2k: best2k)
        var red = 0.0, total = 0.0
        var powerSum = 0.0, targetSum = 0.0
        var maxZone: Int?
        for p in phases {
            if !p.slowExcess.isEmpty {
                let share = Double(p.slowExcess.filter { $0 > base }.count) / Double(p.slowExcess.count)
                red += share * p.duration
                total += p.duration
            }
            if let w = p.averagePower {
                powerSum += w * p.duration
                targetSum += ThresholdMath.watts(pace: base + p.paceOffsetMid) * p.duration
            }
            if let hr = p.averageHeartRate, let z = zones?.zone(for: hr) { maxZone = max(maxZone ?? 0, z) }
        }
        return ThresholdRetest.Session(date: date, redShare: total > 0 ? red / total : 0, userScore: userScore,
                                       powerVsTargetPct: targetSum > 0 ? powerSum / targetSum * 100 : nil,
                                       maxZone: maxZone, isThreshold: isThreshold)
    }
}

// MARK: - Karte auf Startseite und in „Schwelle & Zonen“ (R3, R4, R5)

/// Welche Retest-Karte gerade gilt. Höchstens eine; R3 vor R4 vor R5.
public struct ThresholdRetestCard: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        /// R3: nach ≥ 14 Tagen Pause bei der 3. Fahrt „Stufentest zum Wiedereinstieg“
        case reentry
        /// R4: „Ziele zu hoch?“ – Test oder Schwelle −3 %
        case tooHard
        /// R5: „Ziele zu leicht?“ – Test
        case tooEasy
    }

    public var kind: Kind
    /// Test vorschlagen (nicht innerhalb von 21 Tagen nach dem letzten Test)
    public var offerTest: Bool
    /// vorgeschlagener Test (Plan-id)
    public var testId: String

    public init(kind: Kind, offerTest: Bool, testId: String) {
        self.kind = kind
        self.offerTest = offerTest
        self.testId = testId
    }

    public struct Input: Equatable, Sendable {
        /// Startzeiten aller gezählten Fahrten
        public var rideDates: [Date]
        /// Einheiten der Kategorien Schwelle/Intervalle (Reihenfolge egal)
        public var sessions: [ThresholdRetest.Session]
        /// Datum der aktiven Schwelle (Einheiten davor zählen nicht: ihre Ziele kamen aus einer anderen Schwelle)
        public var activeDate: Date?
        /// letzter Schwellentest (beliebige Testfahrt)
        public var lastTestDate: Date?
        /// ein Trainingsplan läuft (der Plan hat eigene Regeln für zu harte Einheiten, Tests und Wiedereinstieg)
        public var planActive: Bool
        /// zuletzt geschlossen je Karte
        public var dismissed: [Kind: Date]
        /// bevorzugter Test (für R4/R5)
        public var preferredTest: String

        public init(rideDates: [Date], sessions: [ThresholdRetest.Session], activeDate: Date?, lastTestDate: Date?,
                    planActive: Bool, dismissed: [Kind: Date] = [:], preferredTest: String = ThresholdRetest.ftpTest) {
            self.rideDates = rideDates
            self.sessions = sessions
            self.activeDate = activeDate
            self.lastTestDate = lastTestDate
            self.planActive = planActive
            self.dismissed = dismissed
            self.preferredTest = preferredTest
        }
    }

    /// Eine geschlossene R3-Karte bleibt so lange weg (Tage)
    public static let reentryDismissDays = 14

    public static func make(_ input: Input, now: Date) -> ThresholdRetestCard? {
        guard !input.planActive else { return nil }
        let testOK = input.lastTestDate.map { now.timeIntervalSince($0) >= Double(ThresholdRetest.minDaysBetweenTests) * 86400 } ?? true
        // R3: Wiedereinstieg (nur als Testvorschlag sinnvoll)
        if testOK, ThresholdRetest.reentryTestDue(rideDates: input.rideDates.filter { $0 <= now }),
           !(input.dismissed[.reentry].map { now.timeIntervalSince($0) < Double(reentryDismissDays) * 86400 } ?? false) {
            return ThresholdRetestCard(kind: .reentry, offerTest: true, testId: ThresholdRetest.submaxTest)
        }
        // R4/R5: nur Einheiten seit der aktiven Schwelle und seit dem letzten Schliessen der Karte
        func relevant(_ kind: Kind) -> [ThresholdRetest.Session] {
            let since = [input.activeDate, input.dismissed[kind]].compactMap { $0 }.max() ?? .distantPast
            return input.sessions.filter { $0.date > since && $0.date <= now }.sorted { $0.date < $1.date }
        }
        if ThresholdRetest.targetHint(relevant(.tooHard)) == .tooHard {
            return ThresholdRetestCard(kind: .tooHard, offerTest: testOK, testId: input.preferredTest)
        }
        if testOK, ThresholdRetest.targetHint(relevant(.tooEasy)) == .tooEasy {
            return ThresholdRetestCard(kind: .tooEasy, offerTest: true, testId: input.preferredTest)
        }
        return nil
    }
}

// MARK: - Testergebnis im Trainingsplan: nur eine Rückfrage

/// Ein Test im Trainingsplan ergibt eine neue 2k-Referenz (`ActiveTrainingProgram.reference`); dieselbe Fahrt wertet
/// auch die Schwellen-Ergebniskarte aus (`ThresholdStore.submit`). Damit nicht zweimal gefragt wird, entscheidet das
/// Schwellenprofil, sobald es die Fahrt kennt; die Rückfrage des Plans erscheint nur, wenn es keine Schätzung zu
/// dieser Fahrt gibt.
public enum ProgramReferenceLink {
    public enum Action: Equatable, Sendable {
        /// keine Schätzung im Profil: der Plan fragt selbst („Neue Referenz übernehmen?“)
        case askInPlan
        /// keine Schätzung, Test schneller: Referenz übernehmen (wie bisher)
        case apply
        /// das Profil hat entschieden (übernommen, behalten oder nur Hinweis): Rückfrage im Plan erledigen
        case resolve
        /// das Profil fragt noch (Ergebniskarte bzw. Hinweis auf der Startseite): im Plan nichts zeigen
        case waitForProfile
    }

    /// - Parameters:
    ///   - isWorse: der Test war langsamer als die bisherige Referenz
    ///   - linked: Schätzungen im Profil zu derselben Fahrt (Testarten)
    public static func action(isWorse: Bool, linked: [ThresholdEstimate]) -> Action {
        guard !linked.isEmpty else { return isWorse ? .askInPlan : .apply }
        if linked.contains(where: { $0.statusValue == .active }) { return .resolve }
        if linked.contains(where: { $0.statusValue == .candidate && !$0.isHintOnly }) { return .waitForProfile }
        return .resolve
    }
}
