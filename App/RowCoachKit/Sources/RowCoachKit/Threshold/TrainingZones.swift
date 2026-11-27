import Foundation

/// Leistungs- und Tempozonen in Prozent der Schwelle (docs/schwelle/SPEC.md, Abschnitt 4.1) und die Wahl des
/// Pulszonenmodells (Abschnitt 4.2).
public enum TrainingZones {
    /// Untere Grenzen der Zonen 2…5 in % der Schwelle (Zone 1 beginnt bei 0)
    public static let boundaries: [Double] = [55, 75, 88, 102]

    public struct Band: Equatable, Sendable, Identifiable {
        /// 1…5 (wie `hrZone`)
        public var zone: Int
        /// % der Schwelle; nil = offen
        public var lowerPct: Double?
        public var upperPct: Double?
        /// Watt; nil = offen
        public var lowerW: Double?
        public var upperW: Double?
        /// Tempo s/500 m: schnelle und langsame Grenze; nil = offen
        public var fastPace: Double?
        public var slowPace: Double?

        public var id: Int { zone }

        /// „UT3“ … „TR/AN“
        public var band: String { TrainingZones.bandNames[zone - 1] }

        /// „Regeneration“ … „Über der Schwelle“
        public var title: String {
            switch zone {
            case 1: return String(localized: "Regeneration")
            case 2: return String(localized: "Grundlage")
            case 3: return String(localized: "Grundlage intensiv")
            case 4: return String(localized: "Schwelle")
            default: return String(localized: "Über der Schwelle")
            }
        }
    }

    public static let bandNames = ["UT3", "UT2", "UT1", "AT", "TR/AN"]

    /// Fünf Zonen zur Schwelle T (Watt)
    public static func bands(threshold t: Double) -> [Band] {
        (1...5).map { z in
            let lo: Double? = z == 1 ? nil : boundaries[z - 2]
            let hi: Double? = z == 5 ? nil : boundaries[z - 1]
            return Band(zone: z, lowerPct: lo, upperPct: hi,
                        lowerW: lo.map { t * $0 / 100 }, upperW: hi.map { t * $0 / 100 },
                        fastPace: hi.map { ThresholdMath.pace(percent: $0, of: t) },
                        slowPace: lo.map { ThresholdMath.pace(percent: $0, of: t) })
        }
    }

    /// Zone 1…5 einer Leistung zur Schwelle
    public static func zone(power: Double, threshold t: Double) -> Int {
        guard t > 0 else { return 1 }
        let pct = power / t * 100
        var z = 1
        for (i, b) in boundaries.enumerated() where pct >= b { z = i + 2 }
        return z
    }

    // MARK: Pulszonen

    /// Woher das gewählte Pulszonenmodell kommt (für den Hinweis „Pulszonen geschätzt“)
    public enum HeartModelSource: String, Sendable {
        case lthr, reserve, percentMax, estimated
    }

    /// Pulszonen nach der automatischen Reihenfolge: LTHR (≤ 12 Monate) → Maximal- und Ruhepuls (Karvonen) → nur
    /// Maximalpuls (% HFmax) → geschätzt (Tanaka bzw. 185).
    /// - Parameter preferred: vom Nutzer gewähltes Modell; nil = automatisch
    public static func heartZones(_ heart: HeartProfile, now: Date, preferred: HeartRateZones.ModelKind? = nil)
        -> (zones: HeartRateZones, source: HeartModelSource) {
        let lthr = heart.currentLTHR(now: now)
        let maxHR = heart.maxHR
        let restHR = heart.restHR
        switch preferred {
        case .lthr?:
            if let l = lthr { return (HeartRateZones(lthr: l, maxHR: maxHR ?? 185, restHR: restHR ?? 55), .lthr) }
        case .reserve?:
            if let m = maxHR, let r = restHR { return (HeartRateZones(maxHR: m, restHR: r), .reserve) }
        case .percentMax?:
            if let m = maxHR { return (HeartRateZones(percentMax: m, restHR: restHR ?? 55), .percentMax) }
        case nil:
            break
        }
        if let l = lthr { return (HeartRateZones(lthr: l, maxHR: maxHR ?? 185, restHR: restHR ?? 55), .lthr) }
        if let m = maxHR, let r = restHR { return (HeartRateZones(maxHR: m, restHR: r), .reserve) }
        if let m = maxHR { return (HeartRateZones(percentMax: m, restHR: restHR ?? 55), .percentMax) }
        let est = heart.tanakaMaxHR(now: now) ?? 185
        return (HeartRateZones(maxHR: est, restHR: restHR ?? 55), .estimated)
    }
}
