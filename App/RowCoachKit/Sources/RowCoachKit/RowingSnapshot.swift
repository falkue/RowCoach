import Foundation

/// Aktueller Gesamtzustand aus allen PM5-Nachrichten und dem Pulsgurt: das, was das HUD anzeigt.
public struct RowingSnapshot: Equatable, Sendable {
    public var elapsedTime: TimeInterval = 0
    public var distance: Double = 0
    public var speed: Double = 0
    public var pace: TimeInterval = 0          // s/500 m, 0 = unbekannt
    public var averagePace: TimeInterval = 0
    public var strokeRate: Int = 0
    /// W, letzter Schlag (0x0036). Fehlt der Wert, liefert `displayPower` eine Schätzung aus dem Tempo.
    public var power: Int = 0
    public var averagePower: Int = 0
    public var calories: Int = 0
    public var strokeCount: Int = 0
    public var dragFactor: Int = 0
    public var workoutState: PM5WorkoutState?
    public var rowingState: PM5RowingState?
    /// Puls vom Gurt (bevorzugt) oder vom PM5
    public var heartRate: Int?
    public var heartRateSource: HeartRateSource?

    public enum HeartRateSource: String, Sendable { case strap, pm5 }

    public init() {}

    /// Leistung für die Anzeige: vom PM5, sonst aus dem Tempo nach der Concept2-Formel
    /// Watt = 2,80 / (Sekunden pro Meter)³.
    public var displayPower: Int {
        if power > 0 { return power }
        return RowingSnapshot.watts(pace500: pace)
    }

    public static func watts(pace500 pace: TimeInterval) -> Int {
        guard pace > 0, pace.isFinite else { return 0 }
        let spm = pace / 500
        return Int((2.80 / (spm * spm * spm)).rounded())
    }

    /// Übernimmt eine PM5-Nachricht. Puls vom PM5 nur, wenn kein Gurtwert vorliegt.
    public mutating func apply(_ m: PM5Message) {
        switch m {
        case .generalStatus(let s):
            elapsedTime = s.elapsedTime; distance = s.distance
            workoutState = s.workoutState; rowingState = s.rowingState; dragFactor = Int(s.dragFactor)
        case .additionalStatus1(let s):
            elapsedTime = s.elapsedTime; speed = s.speed; strokeRate = s.strokeRate
            pace = s.currentPace; averagePace = s.averagePace
            if heartRateSource != .strap, let h = s.heartRate { heartRate = h; heartRateSource = .pm5 }
        case .additionalStatus2(let s):
            averagePower = s.averagePower; calories = s.totalCalories
        case .strokeData(let s):
            strokeCount = s.strokeCount
        case .additionalStrokeData(let s):
            power = s.strokePower; strokeCount = s.strokeCount
        case .workoutSummary:
            break
        }
    }

    public mutating func apply(strap m: HeartRateMeasurement) {
        guard m.bpm > 0, m.sensorContact != false else { return }
        heartRate = m.bpm; heartRateSource = .strap
    }
}

public enum Format {
    /// 1:58.3 bzw. 1:02:03
    public static func duration(_ t: TimeInterval, tenths: Bool = false) -> String {
        guard t.isFinite, t >= 0 else { return "–" }
        let deci = tenths ? Int((t * 10).rounded()) : Int(t) * 10
        let total = deci / 10
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return tenths ? base + String(format: ".%d", deci % 10) : base
    }

    public static func pace(_ t: TimeInterval) -> String { t > 0 ? duration(t, tenths: true) : "–:––" }

    public static func distance(_ m: Double) -> String {
        m >= 10_000 ? String(format: "%.2f km", m / 1000) : String(format: "%.0f m", m)
    }
}
