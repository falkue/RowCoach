import Foundation

/// Hält die Ruderfigur im Takt der echten Schläge.
///
/// Der PM5 meldet in 0x0031 den Schlagzustand (Durchzug, Freilauf …) und in 0x0035 nach jedem Schlag die Dauer
/// von Durchzug und Freilauf. Daraus ergibt sich der Zeitpunkt des Wasserfassens (Wechsel in „driving“) und eine
/// Schlagphase 0…1 (0 = Wasserfassen, bis `visualDriveShare` Durchzug, danach Freilauf), wie sie die 3D-Figur
/// erwartet (`BoatRig.StrokePose.at(phase:strokeRate:)`).
public struct StrokePhaseTracker: Sendable {
    /// Zeitpunkt des letzten Wasserfassens (Sekunden, beliebige monotone Uhr)
    public private(set) var lastCatch: TimeInterval?
    /// Zuletzt gemessene Dauer von Durchzug und Freilauf (Startwerte für ca. 22 Schläge/min)
    public private(set) var driveTime: TimeInterval = 0.8
    public private(set) var recoveryTime: TimeInterval = 1.9
    private var lastState: PM5StrokeState?

    public init() {}

    /// Anteil des Durchzugs an der Schlagphase, den die 3D-Figur verwendet (muss zu BoatRig passen)
    public static func visualDriveShare(strokeRate: Int) -> Double {
        min(0.5, 0.25 + Double(max(strokeRate, 0)) * 0.006)
    }

    /// Schlagzustand aus 0x0031. Der Wechsel in „driving“ ist das Wasserfassen.
    public mutating func update(state: PM5StrokeState?, at t: TimeInterval) {
        defer { lastState = state }
        guard let state, state != lastState else { return }
        if state == .driving { lastCatch = t }
    }

    /// Schlagdaten aus 0x0035 (nach jedem Schlag): gemessene Dauern übernehmen, unplausible Werte ignorieren.
    public mutating func update(driveTime d: TimeInterval, recoveryTime r: TimeInterval) {
        if d > 0.3 && d < 2.5 { driveTime = d }
        if r > 0.3 && r < 6 { recoveryTime = r }
    }

    /// Schlagphase zum Zeitpunkt t; nil, wenn seit über 6 s kein Wasserfassen erkannt wurde (Figur taktet dann
    /// selbst bzw. ruht).
    public func phase(at t: TimeInterval, strokeRate: Int) -> Double? {
        guard let c = lastCatch else { return nil }
        let dt = t - c
        guard dt >= 0, dt < 6 else { return nil }
        let share = Self.visualDriveShare(strokeRate: strokeRate)
        if dt < driveTime {
            return dt / driveTime * share
        }
        let rec = (dt - driveTime) / recoveryTime
        // Bis zum nächsten Wasserfassen kurz vor 1 verharren (Auslage), statt vorzeitig neu zu beginnen
        return min(share + rec * (1 - share), 0.995)
    }
}
