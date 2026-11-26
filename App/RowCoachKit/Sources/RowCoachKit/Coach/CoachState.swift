import Foundation

/// Kennzahlen des Coachs: geglättete Messwerte, Werte der laufenden Phase (Basiswert, Mittel, kurzes Mittel,
/// Trend), letzter Schlag und Ergebnisse der Intervalle für Vergleiche.
public struct CoachState: Sendable {
    /// Ein Messpunkt der laufenden Phase (nur während gerudert wird)
    struct Sample: Sendable {
        var t: Double
        var spm: Double
        var pace: Double
        /// Summen bis einschliesslich dieses Punkts (für schnelle Mittel)
        var cumSpm: Double = 0
        var cumPace: Double = 0
    }

    /// Ergebnis einer Belastungsphase
    public struct IntervalStat: Equatable, Sendable {
        public var phaseIndex: Int
        public var workNumber: Int?
        /// Mitteltempo (s/500 m) und Mittelschlagzahl über die Phase
        public var pace: Double?
        public var strokeRate: Double?
        /// Länge laut Programm (s bzw. m) für den Vergleich ähnlicher Intervalle
        public var plannedSeconds: Double?
        public var plannedMeters: Double?
    }

    public private(set) var smoothedRate: Double?
    public private(set) var smoothedPace: Double?
    public private(set) var smoothedPower: Double?
    public private(set) var smoothedHeartRate: Double?
    /// Zeitpunkt des letzten Schlags
    public private(set) var lastStrokeTime: Double?
    public private(set) var phaseStart: Double = 0
    public private(set) var intervals: [IntervalStat] = []

    private var lastTime: Double?
    private var lastStrokeCount: Int?
    /// Schlagzähler hat sich mindestens einmal geändert (dann gilt er statt der Schlagzahl)
    private var strokeCountWorks = false
    private var samples: [Sample] = []
    let config: CoachConfig

    init(config: CoachConfig) {
        self.config = config
    }

    // MARK: Eingang

    mutating func ingest(_ input: CoachInput) {
        let t = input.time
        let dt = lastTime.map { max(t - $0, 0) } ?? 0
        lastTime = t
        let a = dt > 0 ? 1 - exp(-dt / max(config.smoothingTau, 0.1)) : 1
        func ema(_ old: Double?, _ v: Double) -> Double { old.map { $0 + (v - $0) * a } ?? v }

        // Schlag erkannt: Zähler gestiegen, sonst (ohne Zähler) Schlagzahl > 0 während der Fahrt
        if let c = input.strokeCount {
            if let last = lastStrokeCount, c > last {
                strokeCountWorks = true
                lastStrokeTime = t
            }
            lastStrokeCount = c
        }
        let rowing = input.isRowing && input.strokeRate > 0
        if !strokeCountWorks, rowing { lastStrokeTime = t }

        if rowing {
            smoothedRate = ema(smoothedRate, input.strokeRate)
            if input.pace > 0, input.pace.isFinite {
                smoothedPace = ema(smoothedPace, input.pace)
                let prev = samples.last
                samples.append(Sample(t: t, spm: input.strokeRate, pace: input.pace,
                                      cumSpm: (prev?.cumSpm ?? 0) + input.strokeRate,
                                      cumPace: (prev?.cumPace ?? 0) + input.pace))
            }
            if let w = input.power, w > 0 { smoothedPower = ema(smoothedPower, Double(w)) }
        }
        if let hr = input.heartRate, hr > 0 { smoothedHeartRate = ema(smoothedHeartRate, Double(hr)) }
    }

    /// Neue Phase: Werte der Phase zurücksetzen
    mutating func beginPhase(at t: Double) {
        phaseStart = t
        samples.removeAll(keepingCapacity: true)
    }

    /// Belastungsphase beendet: Ergebnis festhalten
    mutating func closeInterval(phaseIndex: Int, workNumber: Int?, phase: WorkoutPhase) {
        let rowing = samples.filter { $0.pace > 0 }
        let pace = rowing.isEmpty ? nil : rowing.reduce(0) { $0 + $1.pace } / Double(rowing.count)
        let spm = rowing.isEmpty ? nil : rowing.reduce(0) { $0 + $1.spm } / Double(rowing.count)
        intervals.append(IntervalStat(phaseIndex: phaseIndex, workNumber: workNumber, pace: pace, strokeRate: spm,
                                      plannedSeconds: phase.durationS, plannedMeters: phase.distanceM))
    }

    // MARK: Kennzahlen der Phase

    /// Sekunden seit dem letzten Schlag (seit Phasenbeginn, wenn es in der Phase noch keinen gab)
    func secondsWithoutStroke(at t: Double) -> Double {
        t - max(lastStrokeTime ?? phaseStart, phaseStart)
    }

    /// erster Index mit `t >= x` (Messpunkte sind nach Zeit sortiert)
    private func lowerIndex(_ x: Double) -> Int {
        var lo = 0, hi = samples.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].t < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Mittel über die Messpunkte mit `from <= t <= to` (über Präfixsummen) und ihre Anzahl
    private func mean(_ key: KeyPath<Sample, Double>, from: Double, to: Double) -> (value: Double, count: Int)? {
        let i = lowerIndex(from), j = lowerIndex(to.nextUp) - 1
        guard i <= j, j < samples.count else { return nil }
        let cumKey: KeyPath<Sample, Double> = key == \Sample.spm ? \Sample.cumSpm : \Sample.cumPace
        let before = i > 0 ? samples[i - 1][keyPath: cumKey] : 0
        let n = j - i + 1
        return ((samples[j][keyPath: cumKey] - before) / Double(n), n)
    }

    /// Kurzes Mittel der letzten `config.recentWindow` s
    func recent(_ key: KeyPath<Sample, Double>, at t: Double) -> Double? {
        mean(key, from: t - config.recentWindow, to: t)?.value
    }

    /// Basiswert: Mittel über `config.baselineWindow` nach Phasenbeginn; nil, solange das Fenster nicht vorbei ist
    func baseline(_ key: KeyPath<Sample, Double>, at t: Double) -> Double? {
        let w = config.baselineWindow
        guard t >= phaseStart + w.upperBound else { return nil }
        return mean(key, from: phaseStart + w.lowerBound, to: phaseStart + w.upperBound)?.value
    }

    /// Mittel der Phase ab dem Anlauf bis vor `config.meanExcludesLast` s; nil bei weniger als 10 s Daten
    func phaseMean(_ key: KeyPath<Sample, Double>, at t: Double) -> Double? {
        let from = phaseStart + config.baselineWindow.lowerBound, to = t - config.meanExcludesLast
        guard to - from >= 10, let m = mean(key, from: from, to: to), m.count >= 5 else { return nil }
        return m.value
    }

    /// Trend (Änderung je Sekunde, lineare Regression) über die letzten `window` s; nil bei zu wenig Daten
    func trend(_ key: KeyPath<Sample, Double>, window: Double = 15, at t: Double) -> Double? {
        let xs = samples[lowerIndex(t - window)...]
        guard xs.count >= 5 else { return nil }
        let n = Double(xs.count)
        let mt = xs.reduce(0) { $0 + $1.t } / n, mv = xs.reduce(0) { $0 + $1[keyPath: key] } / n
        let sxx = xs.reduce(0) { $0 + ($1.t - mt) * ($1.t - mt) }
        guard sxx > 0 else { return nil }
        return xs.reduce(0) { $0 + ($1.t - mt) * ($1[keyPath: key] - mv) } / sxx
    }
}
