import Foundation

/// Energieumsatz beim Rudern am Ergometer, gewichtsangepasst und getrennt in aktive Energie und Ruheanteil
/// (Formeln, Quellen und Grenzen: docs/KALORIEN.md).
///
/// - Der Concept2-PM5 zeigt `4 × Watt + 300` kcal/h für eine Referenzperson von 175 lb (79,5 kg), ohne Gewicht.
/// - Concept2-Korrektur fürs eigene Gewicht: `PM-kcal/h − 300 + 1,714 × Gewicht in lb`, also `4 × W + 3,779 × kg`.
///   Das ist der **gesamte** Umsatz während der Ruderzeit, einschliesslich Ruheumsatz.
/// - Ruheumsatz: 1 MET ≈ 1,0 kcal je kg und Stunde (Compendium of Physical Activities 2024).
/// - Aktive Energie (für Apple Health `activeEnergyBurned`, ohne Ruheanteil) = gesamt − Ruheumsatz
///   = `4 × W + 2,779 × kg` kcal/h.
///
/// Gerechnet wird über die Ruderzeit (ohne Pausen) mit der mittleren Leistung; die Formel ist linear in der
/// Leistung, daher ist das dasselbe wie die Summe über die einzelnen Sekunden.
public enum RowingEnergy {
    /// Concept2: kcal/h je Watt im PM-Wert (entspricht einem Wirkungsgrad von etwa 21,5 %)
    public static let kcalPerHourPerWatt = 4.0
    /// Concept2: fester Anteil im PM-Wert (kcal/h), gilt für 175 lb
    public static let pmOffsetKcalPerHour = 300.0
    /// Concept2-Korrektur: kcal/h je lb Körpergewicht (1,714 × 175 lb ≈ 300 kcal/h)
    public static let concept2KcalPerHourPerLb = 1.714
    public static let lbPerKg = 2.204_622_62
    /// Concept2-Korrektur je kg (≈ 3,779 kcal/h)
    public static var kcalPerHourPerKg: Double { concept2KcalPerHourPerLb * lbPerKg }
    /// Ruheumsatz 1 MET ≈ 1,0 kcal/(kg·h)
    public static let restingKcalPerKgHour = 1.0
    /// Gewicht, wenn keins bekannt ist (Standard im Profil)
    public static let defaultBodyMassKg = 75.0
    /// Plausible Körpergewichte (kg); ausserhalb gilt der Standard
    public static let plausibleBodyMassKg: ClosedRange<Double> = 30...250

    /// Energie einer Fahrt in kcal: gesamt = aktiv + Ruheanteil
    public struct Breakdown: Equatable, Sendable {
        public var total: Double
        public var active: Double
        public var resting: Double
    }

    /// Gewicht für die Rechnung: plausibler Wert oder der Standard (75 kg)
    public static func effectiveBodyMass(_ kg: Double?) -> Double {
        guard let kg, kg.isFinite, plausibleBodyMassKg.contains(kg) else { return defaultBodyMassKg }
        return kg
    }

    /// Kalorien wie der PM5 sie zählt (ohne Gewicht, Referenz 175 lb)
    public static func pm5Kcal(averageWatts: Double, seconds: TimeInterval) -> Double {
        let h = max(seconds, 0) / 3600
        return (kcalPerHourPerWatt * max(averageWatts, 0) + pmOffsetKcalPerHour) * h
    }

    /// Gewichtsangepasster Umsatz über die Ruderzeit `seconds` bei mittlerer Leistung `averageWatts`.
    /// Ohne (plausibles) Gewicht gilt 75 kg.
    public static func breakdown(averageWatts: Double, seconds: TimeInterval, bodyMassKg: Double?) -> Breakdown {
        let kg = effectiveBodyMass(bodyMassKg)
        let h = max(seconds, 0) / 3600
        let total = (kcalPerHourPerWatt * max(averageWatts, 0) + kcalPerHourPerKg * kg) * h
        let resting = restingKcalPerKgHour * kg * h
        return Breakdown(total: total, active: max(total - resting, 0), resting: resting)
    }

    /// Aktive Energie einer Fahrt (kcal): der beim Speichern festgehaltene Wert, sonst aus mittlerer Leistung und
    /// Ruderzeit mit dem angegebenen Gewicht (ältere Fahrten). Fahrten ohne Leistung (z. B. FTMS ohne Watt): 0.
    public static func activeKcal(_ summary: WorkoutSummary, bodyMassKg: Double?) -> Double {
        if let stored = summary.activeCalories { return Double(stored) }
        guard summary.averagePower > 0 else { return 0 }
        return breakdown(averageWatts: Double(summary.averagePower), seconds: summary.activeDuration,
                         bodyMassKg: bodyMassKg).active
    }
}
