import Foundation

/// Grundformeln (docs/schwelle/SPEC.md, Abschnitt 2.1): Watt ↔ Tempo nach Concept2, Potenzgesetz über die Dauer,
/// Schwelle aus Efforts und 2k-Zeit, gleichwertige 2k-Zeit.
public enum ThresholdMath {
    /// Bezugsdauer der Schwelle (s): Leistung, die man etwa 30 min hält
    public static let referenceDuration: Double = 1800

    /// Exponent b für Umrechnungen ohne Profil (z. B. `WorkoutPhase.paceRange(best2k:)` bei Phasen in % der
    /// Schwelle). Die App setzt ihn aus dem Schwellenprofil, damit Spiegel und Rückrechnung zusammenpassen.
    nonisolated(unsafe) public static var activeExponent: Double = ThresholdProfile.defaultExponent

    /// Watt aus Tempo (s/500 m): W = 2,80 / (p/500)³
    public static func watts(pace: Double) -> Double {
        guard pace > 0, pace.isFinite else { return 0 }
        return 2.80 / pow(pace / 500, 3)
    }

    /// Tempo (s/500 m) aus Watt: p = 500 · (2,80/W)^(1/3)
    public static func pace(watts: Double) -> Double {
        guard watts > 0, watts.isFinite else { return 0 }
        return 500 * cbrt(2.80 / watts)
    }

    /// Gleichwertige Leistung über eine andere Dauer: P(t2) = P(t1) · (t2/t1)^(−b)
    public static func equivalentPower(_ power: Double, from t1: Double, to t2: Double, b: Double) -> Double {
        guard t1 > 0, t2 > 0 else { return power }
        return power * pow(t2 / t1, -b)
    }

    /// Faktor von der maximalen Leistung über `duration` auf die Schwelle: (t/1800)^b
    public static func thresholdFactor(duration: Double, b: Double) -> Double {
        pow(max(duration, 1) / referenceDuration, b)
    }

    /// Schwelle aus maximaler Leistung `power` über `duration` s (gültig 180 s ≤ t ≤ 3600 s): T = P · (t/1800)^b
    public static func thresholdFromEffort(power: Double, duration: Double, b: Double) -> Double {
        power * thresholdFactor(duration: duration, b: b)
    }

    /// Schwelle aus der 2k-Zeit (s): P2k = W(t2k/4), T = P2k · (t2k/1800)^b
    public static func threshold(fromBest2k t2k: Double, b: Double) -> Double {
        let t = t2k > 0 && t2k.isFinite ? t2k : PaceTargets.defaultBest2k
        return thresholdFromEffort(power: watts(pace: t / 4), duration: t, b: b)
    }

    /// Gleichwertige 2k-Zeit (s) aus der Schwelle T (Fixpunktiteration, konvergiert in < 10 Schritten)
    public static func equivalentBest2k(threshold: Double, b: Double) -> Double {
        guard threshold > 0, threshold.isFinite else { return PaceTargets.defaultBest2k }
        var t = 480.0
        for _ in 0..<60 {
            let p2k = threshold * pow(t / referenceDuration, -b)
            let next = 4 * pace(watts: p2k)
            if abs(next - t) < 0.0005 { return next }
            t = next
        }
        return t
    }

    /// Tempo für x % der Schwelle (s/500 m)
    public static func pace(percent x: Double, of threshold: Double) -> Double {
        pace(watts: threshold * x / 100)
    }

    /// Exponent b aus zwei maximalen Leistungen über verschiedene Dauern: b = −ln(Pa/Pb) / ln(ta/tb)
    public static func exponent(powerA: Double, durationA: Double, powerB: Double, durationB: Double) -> Double? {
        guard powerA > 0, powerB > 0, durationA > 0, durationB > 0, durationA != durationB else { return nil }
        return -log(powerA / powerB) / log(durationA / durationB)
    }
}
