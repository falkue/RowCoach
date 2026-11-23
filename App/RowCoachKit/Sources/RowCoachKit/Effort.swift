import Foundation

/// Belastung eines Trainings auf Apples Skala 1–10 („Anstrengung“ in Apple Health und Fitness).
///
/// - `estimate`: Einschätzung der App (`EffortEstimator`), wird in Apple Health als geschätzte Belastung geschrieben,
///   wenn Health das erlaubt.
/// - `userScore`: Einschätzung des Ruderers nach der Fahrt; nil = (noch) nicht eingetragen oder übersprungen.
/// Fehlt in älteren JSONs ganz (`WorkoutRecord.effort == nil`).
public struct WorkoutEffort: Codable, Equatable, Sendable {
    /// Einschätzung der App, 1…10
    public var estimate: Int?
    /// Grundlage der Einschätzung (`EffortBasis.rawValue`); als Text, damit unbekannte Werte nie das Lesen stören
    public var estimateBasis: String?
    /// eigene Einschätzung, 1…10
    public var userScore: Int?
    /// Zeitpunkt der eigenen Einschätzung
    public var ratedAt: Date?

    public init(estimate: Int? = nil, estimateBasis: String? = nil, userScore: Int? = nil, ratedAt: Date? = nil) {
        self.estimate = estimate
        self.estimateBasis = estimateBasis
        self.userScore = userScore
        self.ratedAt = ratedAt
    }

    public var basis: EffortBasis? { estimateBasis.flatMap(EffortBasis.init(rawValue:)) }
}

/// Woraus die App die Belastung geschätzt hat
public enum EffortBasis: String, Codable, Sendable {
    /// Puls (Edwards-Bänder), mit dem Tempo als Untergrenze
    case heartRate
    /// Tempo im Vergleich zum Tempo der 2000-m-Bestzeit (kein Puls)
    case pace
    /// nur das Trainingsprogramm (keine Messwerte)
    case plan

    public var title: String {
        switch self {
        case .heartRate: return String(localized: "aus dem Puls")
        case .pace: return String(localized: "aus dem Tempo")
        case .plan: return String(localized: "aus dem Programm")
        }
    }
}

/// Apples Stufen der Belastungsskala (Fitness/Health: 1–3 leicht, 4–6 moderat, 7–8 hart, 9–10 alles gegeben).
public enum EffortScale {
    public static let range = 1...10

    public enum Level: String, Sendable, CaseIterable {
        case easy, moderate, hard, allOut

        public var title: String {
            switch self {
            case .easy: return String(localized: "leicht")
            case .moderate: return String(localized: "moderat")
            case .hard: return String(localized: "hart")
            case .allOut: return String(localized: "alles gegeben")
            }
        }

        public var scores: ClosedRange<Int> {
            switch self {
            case .easy: return 1...3
            case .moderate: return 4...6
            case .hard: return 7...8
            case .allOut: return 9...10
            }
        }
    }

    public static func level(_ score: Int) -> Level {
        let s = clamp(score)
        return Level.allCases.first { $0.scores.contains(s) } ?? .easy
    }

    /// „7 · hart“
    public static func label(_ score: Int) -> String { "\(clamp(score)) · \(level(score).title)" }

    public static func clamp(_ score: Int) -> Int { min(max(score, range.lowerBound), range.upperBound) }
}

/// Ergebnis der Schätzung mit den Zwischenwerten (für Anzeige, Protokoll und Tests)
public struct EffortEstimate: Equatable, Sendable {
    /// 1…10
    public var score: Int
    public var basis: EffortBasis
    /// ungerundeter Wert vor dem Deckeln
    public var raw: Double
    /// mittleres Gewicht (0…5) der härtesten 5 Minuten
    public var intensity: Double
    /// Summe Minuten × Gewicht (Edwards-TRIMP bzw. dieselbe Rechnung mit Tempo- oder Programmgewichten)
    public var trimp: Double

    public init(score: Int, basis: EffortBasis, raw: Double, intensity: Double, trimp: Double) {
        self.score = score
        self.basis = basis
        self.raw = raw
        self.intensity = intensity
        self.trimp = trimp
    }
}

/// Einschätzung der Belastung durch die App. Einfache, offene Regel, abgeleitet aus dem Edwards-TRIMP
/// (Minuten in 50–60/60–70/70–80/80–90/≥90 % HFmax × Gewicht 1/2/3/4/5; Edwards 1993, vgl. docs/design/startscreen-sport.md):
///
/// 1. Jede Sekunde bekommt ein Gewicht 0…5: mit Puls nach den Edwards-Bändern (% des Maximalpulses);
///    ohne Puls nach dem Tempo gegenüber dem Tempo der 2000-m-Bestzeit (≤ +3 s/500 m → 5, ≤ +12 → 4, ≤ +25 → 3,
///    ≤ +40 → 2, langsamer → 1, Stillstand → 0); ohne Messwerte nach den Phasen des Programms.
/// 2. Intensität I = mittleres Gewicht der härtesten 5 Minuten (bei kürzeren Fahrten: der ganzen Fahrt).
/// 3. TRIMP = Σ Minuten × Gewicht.
/// 4. Belastung = 2 × I − 3,5 + log2(TRIMP / 40), gerundet und auf 1…10 gedeckelt.
///    Die Intensität bestimmt die Stufe, die Menge (TRIMP) verschiebt sie: doppelte Menge = +1.
/// 5. Mit Puls gilt zusätzlich das Tempo als Untergrenze (Tempo-Wert − 1), weil der Puls bei kurzen harten
///    Stücken nachläuft.
///
/// Beispiele (Maximalpuls 185): 20 min Zone 2 → 3; 60 min Zone 2 → 5; 30 min Zone 3 → 6; 8 × 500 m hart → 8;
/// 2000-m-Test → 7.
public enum EffortEstimator {
    /// Länge des härtesten Abschnitts für die Intensität (s)
    public static let coreSeconds: Double = 300
    /// Bezugsmenge: TRIMP 40 verschiebt nichts
    public static let referenceTrimp: Double = 40
    /// Mindestanteil der Zeit mit Puls, damit der Puls zählt
    public static let minHeartRateCoverage = 0.5

    /// Ein Abschnitt mit Dauer (s) und Gewicht 0…5
    public struct Slice: Equatable, Sendable {
        public var seconds: Double
        public var weight: Double
        public init(seconds: Double, weight: Double) {
            self.seconds = seconds
            self.weight = weight
        }
    }

    // MARK: Gewichte

    /// Edwards-Gewicht 0…5 nach Anteil am Maximalpuls
    public static func heartRateWeight(bpm: Int, maxHR: Int) -> Double {
        guard maxHR > 0, bpm > 0 else { return 0 }
        let p = Double(bpm) / Double(maxHR)
        switch p {
        case 0.9...: return 5
        case 0.8..<0.9: return 4
        case 0.7..<0.8: return 3
        case 0.6..<0.7: return 2
        case 0.5..<0.6: return 1
        default: return 0
        }
    }

    /// Gewicht 0…5 nach dem Tempo (s/500 m) gegenüber dem Tempo der 2000-m-Bestzeit; 0 = Stillstand
    public static func paceWeight(pace: Double, best2k: Double) -> Double {
        guard pace > 0, pace.isFinite else { return 0 }
        let offset = pace - PaceTargets.basePace500(best2k: best2k)
        switch offset {
        case ...3: return 5
        case ...12: return 4
        case ...25: return 3
        case ...40: return 2
        default: return 1
        }
    }

    /// Gewicht einer Programmphase: das höhere aus Zielzone und Zieltempo, sonst nach Phasenart
    public static func phaseWeight(_ p: WorkoutPhase, best2k: Double) -> Double {
        if p.kind == .rest { return p.activeRest == false ? 0 : 1 }
        var w: Double?
        if let z = p.hrZone {
            // Zonen nach Herzfrequenzreserve, umgerechnet auf die Edwards-Bänder (bei 185/55: Z2 ≈ 72–79 % HFmax)
            let byZone: Double = [2, 3, 4, 5, 5][min(max(z, 1), 5) - 1]
            w = byZone
        }
        if let r = p.paceRange(best2k: best2k) {
            let byPace = paceWeight(pace: (r.lowerBound + r.upperBound) / 2, best2k: best2k)
            w = max(w ?? 0, byPace)
        }
        if let w { return w }
        switch p.kind {
        case .work: return 4
        case .warmup, .cooldown: return 2
        case .other: return 3
        case .rest: return 1
        }
    }

    // MARK: Regel

    /// Belastung aus Abschnitten (Schritte 2–4). nil ohne Zeit.
    public static func score(slices: [Slice], basis: EffortBasis) -> EffortEstimate? {
        let valid = slices.filter { $0.seconds > 0 && $0.seconds.isFinite }
        let total = valid.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return nil }
        let trimp = valid.reduce(0) { $0 + $1.seconds / 60 * min(max($1.weight, 0), 5) }
        let core = min(coreSeconds, total)
        var taken = 0.0, weighted = 0.0
        for s in valid.sorted(by: { $0.weight > $1.weight }) {
            let take = min(s.seconds, core - taken)
            if take <= 0 { break }
            taken += take
            weighted += take * min(max(s.weight, 0), 5)
        }
        let intensity = taken > 0 ? weighted / taken : 0
        let raw = 2 * intensity - 3.5 + log2(max(trimp, 1) / referenceTrimp)
        let score = EffortScale.clamp(Int(raw.rounded()))
        return EffortEstimate(score: score, basis: basis, raw: raw, intensity: intensity, trimp: trimp)
    }

    /// Dauer je Messpunkt wie bei den Pulszonen: bis zum nächsten Punkt, höchstens 5 s
    private static func durations(_ samples: [WorkoutSample]) -> [Double] {
        samples.indices.map { i in
            let next = i + 1 < samples.count ? samples[i + 1].time : samples[i].time + 1
            return min(max(next - samples[i].time, 0), 5)
        }
    }

    /// Nur nach Puls (nil, wenn weniger als die Hälfte der Zeit Puls hat)
    public static func heartRateEstimate(samples: [WorkoutSample], maxHR: Int) -> EffortEstimate? {
        let d = durations(samples)
        let total = d.reduce(0, +)
        var slices: [Slice] = []
        var covered = 0.0
        for (i, s) in samples.enumerated() {
            guard let hr = s.heartRate, hr > 0 else { continue }
            covered += d[i]
            slices.append(Slice(seconds: d[i], weight: heartRateWeight(bpm: hr, maxHR: maxHR)))
        }
        guard total > 0, covered / total >= minHeartRateCoverage else { return nil }
        return score(slices: slices, basis: .heartRate)
    }

    /// Nur nach Tempo (nil ohne ein einziges Tempo)
    public static func paceEstimate(samples: [WorkoutSample], best2k: Double) -> EffortEstimate? {
        let d = durations(samples)
        guard samples.contains(where: { $0.pace > 0 }) else { return nil }
        let slices = samples.indices.map { Slice(seconds: d[$0], weight: paceWeight(pace: samples[$0].pace, best2k: best2k)) }
        return score(slices: slices, basis: .pace)
    }

    /// Nur nach dem Programm (Dauer der Phasen geschätzt mit den Zieltempi)
    public static func planEstimate(_ plan: WorkoutPlan, best2k: Double) -> EffortEstimate? {
        let slices = plan.phases.map { Slice(seconds: $0.estimatedSeconds(best2k: best2k), weight: phaseWeight($0, best2k: best2k)) }
        return score(slices: slices, basis: .plan)
    }

    /// Einschätzung eines Trainings: Puls (mit Tempo − 1 als Untergrenze), sonst Tempo, sonst Programm.
    public static func estimate(samples: [WorkoutSample], maxHR: Int, best2k: Double,
                                plan: WorkoutPlan? = nil) -> EffortEstimate? {
        let byPace = paceEstimate(samples: samples, best2k: best2k)
        if var byHR = heartRateEstimate(samples: samples, maxHR: maxHR) {
            if let p = byPace, p.score - 1 > byHR.score { byHR.score = p.score - 1 }
            return byHR
        }
        if let byPace { return byPace }
        return plan.flatMap { planEstimate($0, best2k: best2k) }
    }

    public static func estimate(record: WorkoutRecord, maxHR: Int, best2k: Double,
                                plan: WorkoutPlan? = nil) -> EffortEstimate? {
        estimate(samples: record.samples, maxHR: maxHR, best2k: best2k, plan: plan)
    }
}

extension WorkoutRecord {
    /// Setzt die Einschätzung der App, falls sie noch fehlt (eine schon gespeicherte bleibt unverändert).
    public mutating func ensureEffortEstimate(maxHR: Int, best2k: Double, plan: WorkoutPlan? = nil) {
        guard effort?.estimate == nil,
              let e = EffortEstimator.estimate(record: self, maxHR: maxHR, best2k: best2k, plan: plan) else { return }
        var eff = effort ?? WorkoutEffort()
        eff.estimate = e.score
        eff.estimateBasis = e.basis.rawValue
        effort = eff
    }

    /// Eigene Einschätzung setzen (1…10)
    public mutating func setUserEffort(_ score: Int, at date: Date = Date()) {
        var eff = effort ?? WorkoutEffort()
        eff.userScore = EffortScale.clamp(score)
        eff.ratedAt = date
        effort = eff
    }
}
