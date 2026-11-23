import Foundation

/// Tempo-Linie („Pace-Boot“) beim freien Rudern: eine gedachte Linie, die mit gleichmässigem Zieltempo fährt.
///
/// - Zeitbasis ist die Ruderzeit der Fahrt (`RowingSession.activeTime`, dieselbe Zeit wie die Anzeige „Zeit“).
///   Die Linie hält deshalb bei Pausen an: Wer kurz anhält, fällt nicht zurück – genau wie das Durchschnittstempo
///   der Zusammenfassung, das Pausen ebenfalls nicht mitzählt.
/// - Erreicht die Linie das Ziel (`total`), bleibt sie dort stehen.
/// - Abstand positiv = Boot voraus.
public struct PaceLine: Equatable, Sendable {
    /// Zieltempo in Sekunden pro 500 m
    public var pace: Double

    /// sinnvoller Bereich des Zieltempos (1:15 … 4:00 pro 500 m)
    public static let paceRange: ClosedRange<Double> = 75...240

    public init(pace: Double) {
        self.pace = pace
    }

    /// Zielgeschwindigkeit in m/s (0 bei ungültigem Tempo)
    public var speed: Double { pace > 0 && pace.isFinite ? 500 / pace : 0 }

    /// Distanz der Linie nach `activeTime` Sekunden Ruderzeit; mit `total` höchstens bis ins Ziel.
    public func distance(activeTime: TimeInterval, total: Double? = nil) -> Double {
        guard activeTime.isFinite, activeTime > 0 else { return 0 }
        let d = speed * activeTime
        if let total, total > 0, total.isFinite { return min(d, total) }
        return d
    }

    /// Ruderzeit, nach der die Linie `distance` Meter geschafft hat (0 bei ungültigem Tempo).
    public func time(forDistance distance: Double) -> TimeInterval {
        guard speed > 0, distance.isFinite, distance > 0 else { return 0 }
        return distance / speed
    }

    /// Abstand Boot ↔ Linie.
    public func gap(boatDistance: Double, activeTime: TimeInterval, total: Double? = nil) -> PaceLineGap {
        let line = distance(activeTime: activeTime, total: total)
        var boat = boatDistance.isFinite ? max(boatDistance, 0) : 0
        if let total, total > 0, total.isFinite { boat = min(boat, total) }
        let t = activeTime.isFinite ? max(activeTime, 0) : 0
        // Zeitabstand: wann die Linie die Position des Boots erreicht (bzw. erreicht hat), verglichen mit der
        // Ruderzeit. Solange die Linie fährt, ist das genau Meterabstand / Zielgeschwindigkeit; steht sie im Ziel,
        // wächst der Rückstand mit der Zeit weiter. Im Ziel des Boots = Zielzeit der Linie − eigene Zeit.
        let seconds = speed > 0 ? time(forDistance: boat) - t : 0
        let finished = total.map { $0 > 0 && line >= $0 - 1e-9 } ?? false
        return PaceLineGap(meters: boat - line, seconds: seconds, lineDistance: line, lineFinished: finished)
    }

    /// Voreinstellung ohne zuletzt verwendetes Tempo: 2000-m-Bestzeit / 4 + 18 s, auf 0,5 s gerundet.
    public static func defaultPace(best2k: Double) -> Double {
        let b = best2k > 0 && best2k.isFinite ? best2k : PaceTargets.defaultBest2k
        return clamp(rounded(b / 4 + 18))
    }

    /// Tempo auf 0,5 s runden
    public static func rounded(_ pace: Double) -> Double { (pace * 2).rounded() / 2 }

    /// Tempo in den sinnvollen Bereich legen
    public static func clamp(_ pace: Double) -> Double {
        guard pace.isFinite else { return paceRange.lowerBound }
        return min(max(pace, paceRange.lowerBound), paceRange.upperBound)
    }
}

/// Abstand zwischen Boot und Tempo-Linie (positiv = Boot voraus)
public struct PaceLineGap: Equatable, Sendable {
    /// Meter (Boot − Linie)
    public var meters: Double
    /// Sekunden (positiv = Boot ist so viele Sekunden früher an dieser Stelle als die Linie)
    public var seconds: Double
    /// Distanz der Linie ab Start (m)
    public var lineDistance: Double
    /// Linie steht im Ziel
    public var lineFinished: Bool

    public init(meters: Double, seconds: Double, lineDistance: Double, lineFinished: Bool) {
        self.meters = meters
        self.seconds = seconds
        self.lineDistance = lineDistance
        self.lineFinished = lineFinished
    }

    /// Lage mit Toleranz von ±1 m (darunter „gleichauf“)
    public enum Standing: Equatable, Sendable { case ahead, level, behind }

    public var standing: Standing {
        if meters >= 1 { return .ahead }
        if meters <= -1 { return .behind }
        return .level
    }
}
