import Foundation

// Länder der virtuellen Teilnehmenden: Gewicht im Pool, Zeitzonen (mit Anteil), Sommerzeit-Regel und Halbkugel
// (saisonale Formkurve). docs/MULTIPLAYER.md „Virtuelle Teilnehmende“. Nur Foundation, nur Ganzzahl-Kalender.

/// Sommerzeit-Regel (genähert, auf den Tag genau; eine Stunde Abweichung an Umstelltagen ist hier ohne Bedeutung)
public enum VirtualDSTRule: UInt8, Sendable, Codable {
    case none = 0
    /// EU/Grossbritannien: letzter Sonntag im März bis letzter Sonntag im Oktober
    case eu = 1
    /// USA/Kanada: zweiter Sonntag im März bis erster Sonntag im November
    case us = 2
    /// Südost-Australien: erster Sonntag im Oktober bis erster Sonntag im April
    case au = 3
    /// Neuseeland: letzter Sonntag im September bis erster Sonntag im April
    case nz = 4
    /// Chile: erster Sonntag im September bis erster Sonntag im April
    case cl = 5

    /// Gilt am Tag `days` (seit 1970, UTC-Datum) Sommerzeit?
    public func isActive(days: Int) -> Bool {
        let c = DetMath.civil(days: days)
        // nur Monate 1…11 (Dezember kommt in keiner Regel vor)
        func lastSunday(_ month: Int) -> Int {
            let lastDay = DetMath.days(year: c.year, month: month + 1, day: 1) - 1
            return lastDay - DetMath.weekday(days: lastDay)
        }
        func nthSunday(_ month: Int, _ n: Int) -> Int {
            let first = DetMath.days(year: c.year, month: month, day: 1)
            let firstSunday = first + (7 - DetMath.weekday(days: first)) % 7
            return firstSunday + 7 * (n - 1)
        }
        switch self {
        case .none: return false
        case .eu: return days >= lastSunday(3) && days < lastSunday(10)
        case .us: return days >= nthSunday(3, 2) && days < nthSunday(11, 1)
        case .au: return days >= nthSunday(10, 1) || days < nthSunday(4, 1)
        case .nz: return days >= lastSunday(9) || days < nthSunday(4, 1)
        case .cl: return days >= nthSunday(9, 1) || days < nthSunday(4, 1)
        }
    }
}

/// Halbkugel für die saisonale Formkurve (Hallensaison im Winter)
public enum VirtualHemisphere: UInt8, Sendable, Codable {
    case north = 0, south = 1, tropic = 2
}

public enum VirtualRowerCountries {
    public struct Zone: Equatable, Sendable {
        /// Normalzeit (Minuten gegenüber UTC)
        public var offsetMinutes: Int
        /// Anteil der Bevölkerung des Landes in dieser Zone (relativ)
        public var share: Double
        public var dst: VirtualDSTRule
    }

    public struct Entry: Equatable, Sendable {
        public var code: String
        /// relatives Gewicht im Pool (Summe ≈ 110)
        public var weight: Double
        public var zones: [Zone]
        public var hemisphere: VirtualHemisphere
    }

    private static func z(_ minutes: Int, _ share: Double = 1, _ dst: VirtualDSTRule = .none) -> Zone {
        Zone(offsetMinutes: minutes, share: share, dst: dst)
    }

    private static func e(_ code: String, _ weight: Double, _ zones: [Zone], _ h: VirtualHemisphere = .north) -> Entry {
        Entry(code: code, weight: weight, zones: zones, hemisphere: h)
    }

    /// Länder mit Gewicht (Pool v1). Eigene Schätzung: Orientierung an der Herkunft der Einträge in den
    /// Concept2-Ranglisten 2025 (2000 m; Stichproben: USA ≈ 45 %, Grossbritannien ≈ 20 %, Australien ≈ 6 %,
    /// Deutschland ≈ 5 %, Kanada ≈ 3 %), an der Verbreitung des Rudersports und an der Bevölkerung. Die USA sind
    /// bewusst geringer gewichtet als in der Rangliste, damit das Feld international wirkt. Nur Länder mit
    /// offener Vornamensliste (`VirtualRowerNames`) für beide Namensgruppen.
    public static let all: [Entry] = [
        // Europa (Mitteleuropäische Zeit u. a.)
        e("GB", 10, [z(0, 1, .eu)]),
        e("DE", 7, [z(60, 1, .eu)]),
        e("FR", 3.5, [z(60, 1, .eu)]),
        e("IT", 3.5, [z(60, 1, .eu)]),
        e("ES", 3, [z(60, 1, .eu)]),
        e("NL", 3, [z(60, 1, .eu)]),
        e("CH", 2, [z(60, 1, .eu)]),
        e("SE", 2, [z(60, 1, .eu)]),
        e("PL", 2, [z(60, 1, .eu)]),
        e("AT", 1.5, [z(60, 1, .eu)]),
        e("IE", 1.5, [z(0, 1, .eu)]),
        e("NO", 1.5, [z(60, 1, .eu)]),
        e("DK", 1.5, [z(60, 1, .eu)]),
        e("BE", 1.2, [z(60, 1, .eu)]),
        e("FI", 1, [z(120, 1, .eu)]),
        e("CZ", 1, [z(60, 1, .eu)]),
        e("RU", 1, [z(180, 0.72), z(240, 0.03), z(300, 0.09), z(360, 0.03), z(420, 0.09), z(480, 0.02),
                    z(540, 0.01), z(600, 0.01)]),
        e("HU", 0.8, [z(60, 1, .eu)]),
        e("PT", 0.8, [z(0, 1, .eu)]),
        e("UA", 0.8, [z(120, 1, .eu)]),
        e("TR", 0.8, [z(180)]),
        e("GR", 0.6, [z(120, 1, .eu)]),
        e("RO", 0.6, [z(120, 1, .eu)]),
        e("HR", 0.5, [z(60, 1, .eu)]),
        e("SK", 0.4, [z(60, 1, .eu)]),
        e("RS", 0.4, [z(60, 1, .eu)]),
        e("LT", 0.4, [z(120, 1, .eu)]),
        e("IL", 0.4, [z(120, 1, .eu)]),
        e("SI", 0.3, [z(60, 1, .eu)]),
        e("LV", 0.3, [z(120, 1, .eu)]),
        e("EE", 0.3, [z(120, 1, .eu)]),
        e("BG", 0.3, [z(120, 1, .eu)]),
        e("BY", 0.2, [z(180)]),
        e("LU", 0.15, [z(60, 1, .eu)]),
        e("IS", 0.15, [z(0)]),
        e("CY", 0.1, [z(120, 1, .eu)]),
        e("MT", 0.1, [z(60, 1, .eu)]),
        e("MC", 0.05, [z(60, 1, .eu)]),
        e("LI", 0.05, [z(60, 1, .eu)]),
        // Nordamerika (Anteile der Zonen ≈ Bevölkerung)
        e("US", 22, [z(-300, 0.47, .us), z(-360, 0.29, .us), z(-420, 0.07, .us), z(-480, 0.17, .us)]),
        e("CA", 5, [z(-300, 0.61, .us), z(-360, 0.07, .us), z(-420, 0.13, .us), z(-480, 0.14, .us),
                    z(-240, 0.03, .us), z(-210, 0.02, .us)]),
        e("MX", 0.8, [z(-360, 0.80), z(-420, 0.13), z(-480, 0.07, .us)], .tropic),
        e("PR", 0.1, [z(-240)], .tropic),
        // Ozeanien
        e("AU", 5, [z(600, 0.58, .au), z(600, 0.20), z(570, 0.07, .au), z(570, 0.01), z(480, 0.11)], .south),
        e("NZ", 2, [z(720, 1, .nz)], .south),
        // Asien und Naher Osten
        e("CN", 1.2, [z(480)]),
        e("JP", 1, [z(540)]),
        e("KR", 0.6, [z(540)]),
        e("IN", 0.6, [z(330)], .tropic),
        e("TW", 0.4, [z(480)]),
        e("AE", 0.3, [z(240)], .tropic),
        e("KZ", 0.2, [z(300)]),
        e("PH", 0.2, [z(480)], .tropic),
        e("MY", 0.2, [z(480)], .tropic),
        e("SA", 0.1, [z(180)], .tropic),
        // Südamerika
        e("BR", 1, [z(-180, 0.92), z(-240, 0.08)], .south),
        e("AR", 0.8, [z(-180)], .south),
        e("CL", 0.4, [z(-240, 1, .cl)], .south),
        e("CO", 0.3, [z(-300)], .tropic),
        e("PE", 0.2, [z(-300)], .tropic),
        e("UY", 0.2, [z(-180)], .south),
        e("VE", 0.1, [z(-240)], .tropic),
        e("EC", 0.1, [z(-300)], .tropic),
        e("PY", 0.05, [z(-180)], .south),
        // Afrika
        e("ZA", 0.8, [z(120)], .south),
        e("EG", 0.3, [z(120)]),
        e("MA", 0.15, [z(60)]),
        e("TN", 0.1, [z(60)]),
        e("DZ", 0.1, [z(60)]),
    ]

    public static func entry(_ code: String) -> Entry? { all.first { $0.code == code.uppercased() } }

    /// Ortszeit in Stunden (0 ≤ h < 24, mit Bruchteil) zur UTC-Zeit `t` in einer Zone
    public static func localHour(at t: TimeInterval, offsetMinutes: Int, dst: VirtualDSTRule) -> Double {
        let local = localTime(at: t, offsetMinutes: offsetMinutes, dst: dst)
        let s = local - (local / 86400).rounded(.down) * 86400
        return s / 3600
    }

    /// Ortszeit als Sekunden seit 1970 (für Tagesgrenzen: `DetMath.dayIndex`)
    public static func localTime(at t: TimeInterval, offsetMinutes: Int, dst: VirtualDSTRule) -> TimeInterval {
        let standard = t + Double(offsetMinutes) * 60
        let summer = dst.isActive(days: DetMath.dayIndex(standard)) ? 3600.0 : 0
        return standard + summer
    }
}
