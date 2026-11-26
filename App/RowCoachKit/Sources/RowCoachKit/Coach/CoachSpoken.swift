import Foundation

/// Zahlen und Zeiten als gesprochener Text für die Variablen der Phrasen (de/en). Bewusst einfach und unabhängig
/// vom String Catalog, damit das Ergebnis auf allen Plattformen gleich und testbar ist; Ziffern liest die
/// Sprachausgabe selbst vor.
public enum CoachSpoken {
    /// „4 Minuten“, „30 Sekunden“, „1 Minute 30“ / „4 minutes“, „30 seconds“, „1 minute 30“
    public static func duration(_ seconds: Double, language: String) -> String {
        let t = max(Int(seconds.rounded()), 0)
        let m = t / 60, s = t % 60
        let de = language == "de"
        func minutes(_ n: Int) -> String { de ? (n == 1 ? "1 Minute" : "\(n) Minuten") : (n == 1 ? "1 minute" : "\(n) minutes") }
        func secs(_ n: Int) -> String { de ? (n == 1 ? "1 Sekunde" : "\(n) Sekunden") : (n == 1 ? "1 second" : "\(n) seconds") }
        if m == 0 { return secs(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) \(s)"
    }

    /// „500 Meter“ / „500 meters“
    public static func distance(_ meters: Double, language: String) -> String {
        let m = max(Int(meters.rounded()), 0)
        return language == "de" ? "\(m) Meter" : (m == 1 ? "1 meter" : "\(m) meters")
    }

    /// Tempo je 500 m: „2 Minuten 5“ / „2 minutes 5“ (ohne führende Null, damit die Stimme nicht „null fünf“ liest)
    public static func split(_ pace: Double, language: String) -> String {
        let t = max(Int(pace.rounded()), 0)
        let m = t / 60, s = t % 60
        let de = language == "de"
        let mins = de ? (m == 1 ? "1 Minute" : "\(m) Minuten") : (m == 1 ? "1 minute" : "\(m) minutes")
        return s == 0 ? mins : "\(mins) \(s)"
    }

    /// Unterschied in Sekunden (mindestens 1): „3 Sekunden“ / „3 seconds“
    public static func delta(_ seconds: Double, language: String) -> String {
        let s = max(Int(abs(seconds).rounded()), 1)
        return language == "de" ? (s == 1 ? "1 Sekunde" : "\(s) Sekunden") : (s == 1 ? "1 second" : "\(s) seconds")
    }
}
