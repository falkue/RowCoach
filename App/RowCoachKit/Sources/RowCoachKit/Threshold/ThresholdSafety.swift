import Foundation

// MARK: - Pulsüberwachung in der Fahrt (docs/schwelle/SPEC.md 9 „Automatisch“)

/// Zwei dezente Sicherheitsmeldungen während der Fahrt, beide ohne Abbruch:
/// - **„Pulsgurt prüfen“**: Puls über Maximalpuls + 8 über mindestens 10 s (unplausibel) oder ein Sprung von mehr als
///   30 Schlägen pro Sekunde zwischen zwei Messwerten. Die Meldung bleibt 15 s nach dem letzten Befund stehen.
/// - **„Puls fehlt“**: nur während eines Stufentests (`watchMissing`): mehr als 15 s ohne gültigen Messwert. Die
///   Auswertung zählt solche Lücken nicht (die Stufe braucht 45 s Puls in der letzten Minute) und vermerkt
///   `EvaluationNote.heartRateMissing` (`ThresholdSeries.longestHeartRateGap`).
///
/// Die App ruft `update` einmal je Takt (1 s) und bei jedem neuen Messwert auf; `heartRate` ist nil, wenn kein frischer
/// Messwert vorliegt (Gurt getrennt, kein Hautkontakt, PM5 meldet nichts).
public struct HeartRateSafetyMonitor: Equatable, Sendable {
    /// Schläge über dem Maximalpuls, ab denen ein Wert unplausibel ist
    public static let implausibleMargin = 8
    /// so lange muss der Puls unplausibel hoch sein (s)
    public static let implausibleSeconds: Double = 10
    /// Sprung pro Sekunde, ab dem ein Wert unplausibel ist (bpm/s)
    public static let jumpPerSecond: Double = 30
    /// Pulsausfall im Stufentest, ab dem „Puls fehlt“ gilt (s)
    public static let missingSeconds: Double = 15
    /// „Pulsgurt prüfen“ bleibt so lange nach dem letzten Befund stehen (s)
    public static let holdSeconds: Double = 15

    /// Meldung „Pulsgurt prüfen“ zeigen
    public private(set) var strapCheck = false
    /// Meldung „Puls fehlt“ zeigen (nur im Stufentest)
    public private(set) var heartRateMissing = false
    /// Anzahl der Pulsausfälle > 15 s im Stufentest (für das Protokoll)
    public private(set) var gapCount = 0

    private var overSince: Double?
    private var strapCheckUntil: Double?
    private var lastValue: (time: Double, bpm: Int)?
    private var lastValidTime: Double?
    private var watchStart: Double?

    public init() {}

    public static func == (a: Self, b: Self) -> Bool {
        a.strapCheck == b.strapCheck && a.heartRateMissing == b.heartRateMissing && a.gapCount == b.gapCount
    }

    /// - Parameters:
    ///   - time: Sekunden seit Start (monoton)
    ///   - heartRate: frischer Messwert (nil oder ≤ 0 = keiner)
    ///   - maxHR: Maximalpuls aus dem Profil (nil = unbekannt, dann nur die Sprungregel)
    ///   - watchMissing: ein Stufentest läuft (Stufe oder Pause zwischen den Stufen)
    public mutating func update(time: Double, heartRate: Int?, maxHR: Int?, watchMissing: Bool) {
        let bpm = heartRate.flatMap { $0 > 0 && $0 < 255 ? $0 : nil }
        if let bpm {
            // Sprung zwischen zwei frischen Werten
            if let last = lastValue, time > last.time, time - last.time <= 3 {
                let rate = Double(abs(bpm - last.bpm)) / max(time - last.time, 1)
                if rate > Self.jumpPerSecond { strapCheckUntil = time + Self.holdSeconds }
            }
            if lastValue == nil || time > lastValue!.time { lastValue = (time, bpm) }
            lastValidTime = time
            // dauerhaft über Maximalpuls + 8
            if let m = maxHR, m > 0, bpm > m + Self.implausibleMargin {
                if overSince == nil { overSince = time }
                if time - overSince! >= Self.implausibleSeconds { strapCheckUntil = time + Self.holdSeconds }
            } else {
                overSince = nil
            }
        }
        strapCheck = strapCheckUntil.map { time < $0 } ?? false

        if watchMissing {
            if watchStart == nil { watchStart = time }
            let since = max(lastValidTime ?? -.infinity, watchStart ?? time)
            let missing = bpm == nil && time - since > Self.missingSeconds
            if missing && !heartRateMissing { gapCount += 1 }
            heartRateMissing = missing
        } else {
            watchStart = nil
            heartRateMissing = false
        }
    }

    /// Neue Fahrt
    public mutating func reset() {
        self = HeartRateSafetyMonitor()
    }
}

extension ThresholdSeries {
    /// Längste Strecke ohne gültigen Puls im Fenster [a, b] (s); Lücken in der Zeitreihe zählen mit
    public func longestHeartRateGap(from a: Double, to b: Double) -> Double {
        guard b > a else { return 0 }
        var longest = 0.0
        var covered = a
        for s in segments where s.end > a && s.start < b {
            guard s.heartRate != nil else { continue }
            let start = max(s.start, a)
            if start > covered { longest = max(longest, start - covered) }
            covered = max(covered, min(s.end, b))
        }
        return max(longest, b - covered)
    }
}
