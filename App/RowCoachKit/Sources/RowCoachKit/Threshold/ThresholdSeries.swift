import Foundation

/// Mittelwerte über Zeitfenster einer Fahrt. Jeder Messwert gilt bis zum nächsten Zeitpunkt, höchstens 5 s
/// (wie `HeartRateZones.secondsPerZone`); Lücken zählen nicht mit.
public struct ThresholdSeries: Sendable {
    public static let maxHold: Double = 5

    struct Segment: Sendable {
        var start: Double
        var end: Double
        var power: Double
        var heartRate: Double?
        var strokeRate: Int
    }

    let segments: [Segment]

    public init(samples: [WorkoutSample]) {
        let sorted = samples.sorted { $0.time < $1.time }
        var segs: [Segment] = []
        segs.reserveCapacity(sorted.count)
        for (i, s) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].time : s.time + 1
            let end = s.time + min(max(next - s.time, 0), Self.maxHold)
            guard end > s.time else { continue }
            segs.append(Segment(start: s.time, end: end, power: Double(max(s.power, 0)),
                                heartRate: s.heartRate.flatMap { $0 > 0 ? Double($0) : nil }, strokeRate: s.strokeRate))
        }
        segments = segs
    }

    public var startTime: Double { segments.first?.start ?? 0 }
    public var endTime: Double { segments.last?.end ?? 0 }
    public var isEmpty: Bool { segments.isEmpty }

    /// Index des ersten Segments, das nach `t` endet
    private func firstIndex(endingAfter t: Double) -> Int {
        var lo = 0, hi = segments.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if segments[mid].end <= t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Mittlere Leistung (W) und abgedeckte Sekunden im Fenster [a, b]
    public func power(from a: Double, to b: Double) -> (mean: Double, covered: Double) {
        guard b > a else { return (0, 0) }
        var sum = 0.0, cov = 0.0
        var i = firstIndex(endingAfter: a)
        while i < segments.count, segments[i].start < b {
            let s = segments[i]
            let ov = min(s.end, b) - max(s.start, a)
            if ov > 0 { sum += s.power * ov; cov += ov }
            i += 1
        }
        return (cov > 0 ? sum / cov : 0, cov)
    }

    /// Mittlere Leistung im Fenster; nil, wenn weniger als die Hälfte abgedeckt ist
    public func meanPower(from a: Double, to b: Double) -> Double? {
        let r = power(from: a, to: b)
        return r.covered >= 0.5 * (b - a) && r.covered > 0 ? r.mean : nil
    }

    /// Mittlerer Puls und Sekunden mit Pulswert im Fenster [a, b]
    public func heartRate(from a: Double, to b: Double) -> (mean: Double, covered: Double) {
        guard b > a else { return (0, 0) }
        var sum = 0.0, cov = 0.0
        var i = firstIndex(endingAfter: a)
        while i < segments.count, segments[i].start < b {
            let s = segments[i]
            if let hr = s.heartRate {
                let ov = min(s.end, b) - max(s.start, a)
                if ov > 0 { sum += hr * ov; cov += ov }
            }
            i += 1
        }
        return (cov > 0 ? sum / cov : 0, cov)
    }

    /// Längste Strecke ohne Schlag (Schlagzahl 0 und Leistung 0, oder Lücke ohne Messwert) im Fenster [a, b] (s)
    public func longestStop(from a: Double, to b: Double) -> Double {
        var longest = 0.0
        var runStart: Double?
        var cursor = a
        var i = firstIndex(endingAfter: a)
        while i < segments.count, segments[i].start < b {
            let s = segments[i]
            // Lücke vor dem Segment
            if s.start > cursor {
                if runStart == nil { runStart = cursor }
            }
            let idle = s.strokeRate <= 0 && s.power <= 0
            if idle {
                if runStart == nil { runStart = max(s.start, a) }
            } else if let r = runStart {
                longest = max(longest, max(s.start, a) - r)
                runStart = nil
            }
            cursor = min(s.end, b)
            i += 1
        }
        if cursor < b, runStart == nil { runStart = cursor }
        if let r = runStart { longest = max(longest, b - r) }
        return longest
    }

    /// Höchste gleitende Mittelleistung über `length` s innerhalb [a, b] (Schritt 1 s)
    public func bestRolling(length: Double, from a: Double, to b: Double) -> (power: Double, end: Double)? {
        guard b - a >= length, length > 0 else { return nil }
        var best: (Double, Double)?
        var e = a + length
        while e <= b + 1e-9 {
            if let p = meanPower(from: e - length, to: e), best == nil || p > best!.0 { best = (p, e) }
            e += 1
        }
        return best.map { (power: $0.0, end: $0.1) }
    }

    /// Höchster gleitender 5-s-Mittelwert des Pulses (für „gemessener Maximalpuls“); Sprünge > 15 bpm in 2 s
    /// gelten als Messfehler und werden übergangen.
    public func peakHeartRate5s() -> Int? {
        var best: Double?
        for (i, s) in segments.enumerated() where s.heartRate != nil {
            if i > 0, let prev = segments[i - 1].heartRate, let hr = s.heartRate, s.start - segments[i - 1].start <= 2,
               abs(hr - prev) > 15 { continue }
            let r = heartRate(from: s.start, to: s.start + 5)
            if r.covered >= 4, r.mean <= 220, best == nil || r.mean > best! { best = r.mean }
        }
        return best.map { Int($0.rounded()) }
    }

    // MARK: Leistungs-Dauer-Kurve

    /// Kumulierte Arbeit (J) an den Segmentgrenzen über die Uhrzeit (Lücken zählen mit Leistung 0)
    private var cumulative: (times: [Double], work: [Double]) {
        var times: [Double] = [], work: [Double] = []
        times.reserveCapacity(segments.count * 2)
        var w = 0.0
        for s in segments {
            if times.last != s.start {
                times.append(s.start)
                work.append(w)
            }
            w += s.power * (s.end - s.start)
            times.append(s.end)
            work.append(w)
        }
        return (times, work)
    }

    /// Höchste mittlere Leistung über ein Uhrzeitfenster der Länge `duration` (Pausen zählen mit Leistung 0, wie bei
    /// `BestEffortFinder`); Zwei-Zeiger-Verfahren über die kumulierte Arbeit, linear interpoliert.
    /// Liefert Leistung und Beginn des Fensters; nil, wenn die Fahrt kürzer ist.
    public func maxMeanPower(duration: Double) -> (power: Double, start: Double)? {
        let (ts, ws) = cumulative
        guard let first = ts.first, let last = ts.last, last - first >= duration - 1e-6, duration > 0 else { return nil }
        func work(at t: Double, hint j: inout Int) -> Double {
            while j + 1 < ts.count, ts[j + 1] < t { j += 1 }
            if t <= ts[0] { return ws[0] }
            if j + 1 >= ts.count { return ws[ws.count - 1] }
            let t0 = ts[j], t1 = ts[j + 1]
            return t1 > t0 ? ws[j] + (ws[j + 1] - ws[j]) * (t - t0) / (t1 - t0) : ws[j + 1]
        }
        var best: (Double, Double)?
        // Fenster, die an einem Stützpunkt beginnen
        var j = 0
        for (i, t) in ts.enumerated() where t + duration <= last + 1e-6 {
            let p = (work(at: t + duration, hint: &j) - ws[i]) / duration
            if best == nil || p > best!.0 { best = (p, t) }
        }
        // Fenster, die an einem Stützpunkt enden
        j = 0
        for (i, t) in ts.enumerated() where t - duration >= first - 1e-6 {
            let p = (ws[i] - work(at: t - duration, hint: &j)) / duration
            if best == nil || p > best!.0 { best = (p, t - duration) }
        }
        return best.map { (power: $0.0, start: $0.1) }
    }
}
