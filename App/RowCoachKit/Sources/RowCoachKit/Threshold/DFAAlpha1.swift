import Foundation

/// Kurzzeit-Skalierungsexponent α1 der trendbereinigten Fluktuationsanalyse (DFA) aus RR-Intervallen
/// (docs/schwelle/SPEC.md 3.2 Schritt 7; Rogers et al. 2021). Experimentell, am Rudern nicht validiert.
///
/// Verfahren: Artefakte markieren (Abweichung > 20 % vom gleitenden Median der 11 umgebenden Schläge) und linear
/// ersetzen; Fenster 120 s, alle 10 s neu; Fenster mit > 5 % Artefakten verwerfen. α1 = Steigung von log F(n) über
/// log n für n = 4…16 Schläge (Standard-DFA, lineare Trendbereinigung je Box).
public enum DFAAlpha1 {
    public static let scales = 4...16
    public static let windowSeconds: Double = 120
    public static let stepSeconds: Double = 10
    public static let maxArtifactShare = 0.05

    /// α1 einer Reihe (z. B. RR in ms); nil bei weniger als 4 × 16 Werten
    public static func alpha1(_ x: [Double], scales: ClosedRange<Int> = DFAAlpha1.scales) -> Double? {
        guard x.count >= scales.upperBound * 4 else { return nil }
        let mean = x.reduce(0, +) / Double(x.count)
        var y = [Double](repeating: 0, count: x.count)
        var acc = 0.0
        for (i, v) in x.enumerated() {
            acc += v - mean
            y[i] = acc
        }
        var lx: [Double] = [], ly: [Double] = []
        for n in scales {
            let boxes = y.count / n
            guard boxes >= 1 else { continue }
            // lineare Regression über k = 0…n−1 (Mittelwerte und Nenner hängen nur von n ab)
            let kMean = Double(n - 1) / 2
            var kVar = 0.0
            for k in 0..<n { kVar += (Double(k) - kMean) * (Double(k) - kMean) }
            var total = 0.0
            for b in 0..<boxes {
                let off = b * n
                var yMean = 0.0
                for k in 0..<n { yMean += y[off + k] }
                yMean /= Double(n)
                var cov = 0.0
                for k in 0..<n { cov += (Double(k) - kMean) * (y[off + k] - yMean) }
                let slope = kVar > 0 ? cov / kVar : 0
                for k in 0..<n {
                    let fit = yMean + slope * (Double(k) - kMean)
                    let r = y[off + k] - fit
                    total += r * r
                }
            }
            let f = sqrt(total / Double(boxes * n))
            guard f > 0 else { continue }
            lx.append(log10(Double(n)))
            ly.append(log10(f))
        }
        return LinearFit(x: lx, y: ly)?.slope
    }

    /// Artefakte markieren und ersetzen (lineare Interpolation zwischen gültigen Nachbarn)
    public static func clean(_ rr: [Double]) -> (values: [Double], artifact: [Bool]) {
        let n = rr.count
        guard n > 0 else { return ([], []) }
        var art = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let lo = max(0, i - 5), hi = min(n - 1, i + 5)
            let window = rr[lo...hi].sorted()
            let med = window[window.count / 2]
            if !(rr[i] > 0) || (med > 0 && abs(rr[i] - med) / med > 0.2) { art[i] = true }
        }
        var out = rr
        var i = 0
        while i < n {
            guard art[i] else { i += 1; continue }
            var j = i
            while j < n && art[j] { j += 1 }
            let left = i > 0 ? out[i - 1] : nil
            let right = j < n ? rr[j] : nil
            for k in i..<j {
                switch (left, right) {
                case let (l?, r?):
                    let f = Double(k - i + 1) / Double(j - i + 1)
                    out[k] = l + (r - l) * f
                case let (l?, nil): out[k] = l
                case let (nil, r?): out[k] = r
                default: break
                }
            }
            i = j
        }
        return (out, art)
    }

    /// α1 eines Fensters mit Endzeit
    public struct Window: Equatable, Sendable {
        /// Beginn und Ende (s seit Beginn der RR-Reihe)
        public var start: Double
        public var end: Double
        public var alpha1: Double
    }

    /// Gleitende Fenster über eine RR-Reihe (Sekunden). Die Zeit der Schläge ergibt sich aus der Summe der Intervalle
    /// ab `startTime` (die RR-Reihe beginnt mit der Fahrt).
    public static func windows(rr: [Double], startTime: Double = 0, windowSeconds: Double = DFAAlpha1.windowSeconds,
                               step: Double = DFAAlpha1.stepSeconds,
                               maxArtifactShare: Double = DFAAlpha1.maxArtifactShare) -> [Window] {
        guard rr.count > 20 else { return [] }
        let (vals, art) = clean(rr)
        var times = [Double](repeating: 0, count: rr.count)
        var t = startTime
        for (i, v) in rr.enumerated() {
            t += v > 0 && v < 3 ? v : (vals[i] > 0 && vals[i] < 3 ? vals[i] : 0.8)
            times[i] = t
        }
        guard let last = times.last else { return [] }
        var out: [Window] = []
        var end = startTime + windowSeconds
        var lo = 0
        while end <= last + 1e-9 {
            let start = end - windowSeconds
            while lo < times.count && times[lo] <= start { lo += 1 }
            var hi = lo
            while hi < times.count && times[hi] <= end { hi += 1 }
            if hi > lo {
                let n = hi - lo
                let bad = art[lo..<hi].filter { $0 }.count
                if Double(bad) / Double(n) <= maxArtifactShare, let a = alpha1(Array(vals[lo..<hi])) {
                    out.append(Window(start: start, end: end, alpha1: a))
                }
            }
            end += step
        }
        return out
    }
}

/// Einfache lineare Regression y = intercept + slope · x mit Bestimmtheitsmass
public struct LinearFit: Equatable, Sendable {
    public var intercept: Double
    public var slope: Double
    public var r2: Double

    public init?(x: [Double], y: [Double]) {
        let n = Double(x.count)
        guard x.count == y.count, x.count >= 2 else { return nil }
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in x.indices {
            sxx += (x[i] - mx) * (x[i] - mx)
            sxy += (x[i] - mx) * (y[i] - my)
            syy += (y[i] - my) * (y[i] - my)
        }
        guard sxx > 0 else { return nil }
        slope = sxy / sxx
        intercept = my - slope * mx
        r2 = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1
    }

    public func y(at x: Double) -> Double { intercept + slope * x }

    /// x zu einem y; nil bei Steigung 0
    public func x(at y: Double) -> Double? { slope != 0 ? (y - intercept) / slope : nil }
}
