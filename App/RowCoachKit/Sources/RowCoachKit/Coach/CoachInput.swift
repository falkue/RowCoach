import Foundation

/// Eingang des Sprachcoachs je Tick (etwa 1 Hz oder öfter; die Regeln rechnen mit `time`, nicht mit Ticks).
public struct CoachInput: Equatable, Sendable {
    /// Sekunden seit Beginn der Fahrt (monoton, Uhrzeit)
    public var time: Double
    /// Stand des Trainings; nil beim freien Rudern
    public var status: PlanStatus?
    /// Freies Rudern auf einer Strecke (nil bei einem Training)
    public var free: CoachFreeRide?
    /// Distanz der Fahrt (m), für `workout_done`; nil = unbekannt
    public var distance: Double?
    /// Schlagzahl (/min); 0 = keine Schläge bzw. unbekannt
    public var strokeRate: Double
    /// Schlagzähler des PM5 (genauer für „stehen geblieben“); nil = nicht verfügbar
    public var strokeCount: Int?
    /// Tempo s/500 m; 0 = unbekannt
    public var pace: Double
    public var power: Int?
    public var heartRate: Int?
    /// Fahrt läuft (nicht in der automatischen Pause)
    public var isRowing: Bool
    /// Die App spricht gerade (optional; sonst schätzt die Engine die Dauer der letzten Ansage)
    public var isSpeaking: Bool

    public init(time: Double, status: PlanStatus? = nil, free: CoachFreeRide? = nil, distance: Double? = nil,
                strokeRate: Double,
                strokeCount: Int? = nil, pace: Double, power: Int? = nil, heartRate: Int? = nil,
                isRowing: Bool = true, isSpeaking: Bool = false) {
        self.time = time
        self.status = status
        self.free = free
        self.distance = distance ?? free?.distance
        self.strokeRate = strokeRate
        self.strokeCount = strokeCount
        self.pace = pace
        self.power = power
        self.heartRate = heartRate
        self.isRowing = isRowing
        self.isSpeaking = isSpeaking
    }
}

/// Freies Rudern: Stand auf der Strecke und Abstand zur Tempo-Linie
public struct CoachFreeRide: Equatable, Sendable {
    /// Distanz der Fahrt (m)
    public var distance: Double
    /// Länge der Strecke (m)
    public var total: Double
    /// Abstand zur Tempo-Linie (m, positiv = vor der Linie); nil ohne Linie
    public var paceLineGap: Double?
    /// derselbe Abstand in Sekunden (positiv = vor der Linie); nil ohne Linie
    public var paceLineGapSeconds: Double?
    /// geschätzte Restzeit bis zum Ziel (s), für `free_half`; nil = unbekannt
    public var estimatedRemaining: Double?

    public init(distance: Double, total: Double, paceLineGap: Double? = nil, paceLineGapSeconds: Double? = nil,
                estimatedRemaining: Double? = nil) {
        self.distance = distance
        self.total = total
        self.paceLineGap = paceLineGap
        self.paceLineGapSeconds = paceLineGapSeconds
        self.estimatedRemaining = estimatedRemaining
    }
}
