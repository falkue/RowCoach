import Foundation

/// Rechenhilfen, die auf allen Plattformen bitgenau dasselbe liefern (iPad, Mac, Linux-Server, Android).
///
/// `log`, `exp`, `pow`, `sin`, `cbrt` der Systembibliotheken sind nicht überall gleich gerundet; schon eine Abweichung
/// in der letzten Stelle kann eine Zielzeit auf die Millisekunde verschieben. Virtuelle Teilnehmende sollen auf jedem
/// Gerät und auf dem Server dasselbe Ergebnis haben (docs/MULTIPLAYER.md „Virtuelle Teilnehmende“). Deshalb rechnen
/// Pool, Auswahl und Rennsimulation nur mit + − × ÷ und `squareRoot()` (nach IEEE 754 überall exakt gerundet) in
/// fester Reihenfolge.
public enum DetMath {
    private static let ln2 = 0.693_147_180_559_945_3

    /// Natürlicher Logarithmus (x > 0), relativer Fehler < 1e-15
    public static func ln(_ x: Double) -> Double {
        guard x > 0, x.isFinite else { return x == 0 ? -.infinity : .nan }
        // x = m · 2^k mit m in [0,75; 1,5)
        var m = x
        var k = 0
        while m >= 1.5 { m /= 2; k += 1 }
        while m < 0.75 { m *= 2; k -= 1 }
        // ln m = 2 · atanh(s), s = (m − 1)/(m + 1), |s| ≤ 0,2
        let s = (m - 1) / (m + 1)
        let s2 = s * s
        var term = s
        var sum = 0.0
        var n = 1.0
        for _ in 0..<30 {
            sum += term / n
            term *= s2
            n += 2
            if abs(term) < 1e-18 { break }
        }
        return 2 * sum + Double(k) * ln2
    }

    /// e^x, relativer Fehler < 1e-15 (|x| < 700)
    public static func exp(_ x: Double) -> Double {
        guard x.isFinite else { return x > 0 ? .infinity : 0 }
        if x > 709 { return .infinity }
        if x < -745 { return 0 }
        // x = k · ln2 + r, |r| ≤ ln2/2
        let k = (x / ln2).rounded()
        let r = x - k * ln2
        var term = 1.0
        var sum = 1.0
        for i in 1...25 {
            term *= r / Double(i)
            sum += term
            if abs(term) < 1e-18 { break }
        }
        var result = sum
        var e = Int(k)
        while e > 0 { result *= 2; e -= 1 }
        while e < 0 { result /= 2; e += 1 }
        return result
    }

    /// x^y für x > 0
    public static func pow(_ x: Double, _ y: Double) -> Double {
        guard x > 0 else { return x == 0 ? 0 : .nan }
        return exp(y * ln(x))
    }

    /// Kubikwurzel (x > 0) per Newton-Verfahren
    public static func cbrt(_ x: Double) -> Double {
        guard x > 0, x.isFinite else { return x == 0 ? 0 : .nan }
        var y = exp(ln(x) / 3)
        for _ in 0..<3 { y -= (y * y * y - x) / (3 * y * y) }
        return y
    }

    /// Sinus über Reihe nach Reduktion auf [−π, π]
    public static func sin(_ x: Double) -> Double {
        guard x.isFinite else { return .nan }
        let twoPi = 6.283_185_307_179_586
        var r = x - (x / twoPi).rounded() * twoPi
        if r > 3.141_592_653_589_793 { r -= twoPi }
        let r2 = r * r
        var term = r
        var sum = r
        var n = 1.0
        for _ in 0..<20 {
            term *= -r2 / ((n + 1) * (n + 2))
            n += 2
            sum += term
            if abs(term) < 1e-18 { break }
        }
        return sum
    }

    /// Näherungsweise normalverteilt (Summe von 12 Gleichverteilten − 6, Irwin-Hall), Werte in [−6, 6]
    public static func normal(_ rng: inout RaceRandom) -> Double {
        var s = 0.0
        for _ in 0..<12 { s += rng.unit() }
        return s - 6
    }

    /// FNV-1a 64 über UTF-8 (stabil über Programmstarts, anders als `Hasher`)
    public static func fnv64(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// Gleichverteilte Zahl in [0, 1) aus einem Schlüssel (eine Runde SplitMix64)
    public static func unit(_ key: UInt64) -> Double {
        var r = RaceRandom(seed: key)
        return r.unit()
    }

    /// Kalenderdatum (UTC) aus Tagen seit 1970-01-01 (Algorithmus von H. Hinnant), ohne `Calendar`
    public static func civil(days z0: Int) -> (year: Int, month: Int, day: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// Tage seit 1970-01-01 für ein Kalenderdatum (UTC)
    public static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Ganze Tage seit 1970 (abgerundet, auch vor 1970)
    public static func dayIndex(_ t: TimeInterval) -> Int { Int((t / 86400).rounded(.down)) }

    /// Wochentag 0 = Sonntag … 6 = Samstag
    public static func weekday(days: Int) -> Int { ((days % 7) + 11) % 7 }
}
