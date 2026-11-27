import Foundation

/// Ein gespeichertes Training: Kopf, Zusammenfassung, Zeitreihe (ca. 1 Hz), Splits und optional RR-Intervalle.
/// Wird als JSON abgelegt (SwiftData-Feld `payload`) und kann später exportiert oder an einen RowServer geschickt werden.
public struct WorkoutRecord: Codable, Equatable, Sendable, Identifiable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var id: UUID
    public var header: WorkoutHeader
    public var summary: WorkoutSummary
    public var samples: [WorkoutSample]
    public var splits: [SplitTime]
    /// RR-Intervalle vom Pulsgurt in Sekunden (für spätere HRV-Auswertungen)
    public var rrIntervals: [Double]?
    /// true = Fahrt wurde unterbrochen (Akku leer, App beendet oder abgestürzt) und beim nächsten Start aus dem
    /// Sicherungspunkt wiederhergestellt. Fehlt in älteren JSONs (nil = normal beendet).
    public var interrupted: Bool?
    /// Werte je Phase, wenn ein Trainingsprogramm gefahren wurde (`header.workoutPlanId`); fehlt sonst
    public var planPhases: [PlanPhaseResult]?
    /// Belastung 1–10: Einschätzung der App und eigene Einschätzung (siehe `WorkoutEffort`); fehlt in älteren JSONs
    public var effort: WorkoutEffort?
    /// true = Beispieltraining für den Testbetrieb (Startargument `-seedDemoHistory 1`). Zählt in den Kennzahlen des
    /// Startbildschirms, geht aber nie nach Apple Health (die Fahrt trägt zusätzlich `device.source = simulator`).
    /// Fehlt in älteren JSONs (nil = echtes Training).
    public var demo: Bool?

    public init(id: UUID = UUID(), header: WorkoutHeader, summary: WorkoutSummary, samples: [WorkoutSample],
                splits: [SplitTime], rrIntervals: [Double]? = nil, interrupted: Bool? = nil,
                planPhases: [PlanPhaseResult]? = nil, effort: WorkoutEffort? = nil, demo: Bool? = nil) {
        self.formatVersion = Self.currentFormatVersion
        self.id = id
        self.header = header
        self.summary = summary
        self.samples = samples
        self.splits = splits
        self.rrIntervals = rrIntervals
        self.interrupted = interrupted
        self.planPhases = planPhases
        self.effort = effort
        self.demo = demo
    }

    public var isInterrupted: Bool { interrupted ?? false }
    public var isDemo: Bool { demo ?? false }

    public func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(WorkoutRecord.self, from: jsonData)
    }
}

/// Jahreszeit-Variante der Szene (später: Winter mit Schnee usw.)
public enum SceneSeason: String, Codable, Sendable, CaseIterable {
    case spring, summer, autumn, winter
}

/// Wetter-Variante der Szene (später: Sturm, Regen …)
public enum SceneWeather: String, Codable, Sendable, CaseIterable {
    case clear, cloudy, rain, storm, snow, fog
}

/// Woher die Ruderdaten kamen
public struct WorkoutDevice: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case pm5, simulator }
    public var source: Source
    public var pm5Name: String?
    public var heartRateSensorName: String?
    /// "strap", "pm5" oder "machine" (Puls aus den FTMS-Rower-Data)
    public var heartRateSource: String?
    /// Protokoll des Rudergeräts (`RowingMachineKind.rawValue`); nil = PM5 (ältere Trainings). `source` bleibt
    /// auch bei FTMS-Geräten `.pm5` („echtes Gerät“), damit ältere App-Fassungen synchronisierte Trainings lesen können;
    /// `pm5Name` enthält dann den Namen des FTMS-Geräts.
    public var machineKind: String?

    public init(source: Source, pm5Name: String? = nil, heartRateSensorName: String? = nil, heartRateSource: String? = nil,
                machineKind: String? = nil) {
        self.source = source
        self.pm5Name = pm5Name
        self.heartRateSensorName = heartRateSensorName
        self.heartRateSource = heartRateSource
        self.machineKind = machineKind
    }
}

public struct WorkoutHeader: Codable, Equatable, Sendable {
    public var startDate: Date
    public var endDate: Date
    public var courseId: String?
    public var courseTitle: String?
    /// Länge der Strecke (m)
    public var courseLength: Double?
    public var device: WorkoutDevice
    public var appVersion: String?

    /// Trainingsprogramm, das auf die Strecke angewendet wurde (`WorkoutPlan.id`); nil = frei gerudert
    public var workoutPlanId: String?
    /// Name des Programms zum Zeitpunkt der Fahrt (falls es später umbenannt wird oder fehlt)
    public var workoutPlanName: String?
    /// Zieltempo der Tempo-Linie (s/500 m), nur beim freien Rudern; nil = ohne Tempo-Linie
    public var paceTarget: Double?
    /// Einheit eines Trainingsplans, aus der die Fahrt gestartet wurde (zählt dann als erledigt); fehlt sonst
    public var trainingProgram: ProgramSessionRef?

    // Für spätere Ausbaustufen vorgesehen, noch ohne Funktion:
    public var weather: SceneWeather?
    public var season: SceneSeason?
    /// Rennen auf einem RowServer
    public var raceId: String?
    public var serverId: String?

    enum CodingKeys: String, CodingKey {
        case startDate, endDate, courseId, courseTitle, courseLength, device, appVersion
        case workoutPlanId, workoutPlanName, paceTarget, trainingProgram, weather, season, raceId, serverId
    }

    public init(startDate: Date, endDate: Date, courseId: String? = nil, courseTitle: String? = nil,
                courseLength: Double? = nil, device: WorkoutDevice, appVersion: String? = nil,
                workoutPlanId: String? = nil, weather: SceneWeather? = nil, season: SceneSeason? = nil,
                raceId: String? = nil, serverId: String? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.courseId = courseId
        self.courseTitle = courseTitle
        self.courseLength = courseLength
        self.device = device
        self.appVersion = appVersion
        self.workoutPlanId = workoutPlanId
        self.weather = weather
        self.season = season
        self.raceId = raceId
        self.serverId = serverId
    }

    /// Unbekannte Werte für Wetter/Jahreszeit (aus neueren App-Versionen) werden zu nil statt zum Fehler.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        courseId = try c.decodeIfPresent(String.self, forKey: .courseId)
        courseTitle = try c.decodeIfPresent(String.self, forKey: .courseTitle)
        courseLength = try c.decodeIfPresent(Double.self, forKey: .courseLength)
        device = try c.decode(WorkoutDevice.self, forKey: .device)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        workoutPlanId = try c.decodeIfPresent(String.self, forKey: .workoutPlanId)
        workoutPlanName = try? c.decodeIfPresent(String.self, forKey: .workoutPlanName)
        paceTarget = try? c.decodeIfPresent(Double.self, forKey: .paceTarget)
        trainingProgram = try? c.decodeIfPresent(ProgramSessionRef.self, forKey: .trainingProgram)
        weather = try? c.decodeIfPresent(SceneWeather.self, forKey: .weather)
        season = try? c.decodeIfPresent(SceneSeason.self, forKey: .season)
        raceId = try c.decodeIfPresent(String.self, forKey: .raceId)
        serverId = try c.decodeIfPresent(String.self, forKey: .serverId)
    }
}

public struct WorkoutSummary: Codable, Equatable, Sendable {
    /// Geruderte Distanz dieser Einheit (m)
    public var distance: Double
    /// Reine Ruderzeit ohne Pausen (s)
    public var activeDuration: TimeInterval
    /// Start bis Ende einschliesslich Pausen (s)
    public var totalDuration: TimeInterval
    /// s pro 500 m, 0 = unbekannt
    public var averagePace: TimeInterval
    /// m/s
    public var averageSpeed: Double
    public var averageStrokeRate: Double
    public var strokeCount: Int
    public var averagePower: Int
    public var maxPower: Int
    public var calories: Int
    public var averageHeartRate: Int?
    public var maxHeartRate: Int?
    /// Sekunden je Pulszone 0…5 (siehe HeartRateZones), nil ohne Puls
    public var heartRateZoneSeconds: [Double]?
    public var completedCourse: Bool
    public var pauseCount: Int

    public init(distance: Double, activeDuration: TimeInterval, totalDuration: TimeInterval, averagePace: TimeInterval,
                averageSpeed: Double, averageStrokeRate: Double, strokeCount: Int, averagePower: Int, maxPower: Int,
                calories: Int, averageHeartRate: Int?, maxHeartRate: Int?, heartRateZoneSeconds: [Double]?,
                completedCourse: Bool, pauseCount: Int) {
        self.distance = distance
        self.activeDuration = activeDuration
        self.totalDuration = totalDuration
        self.averagePace = averagePace
        self.averageSpeed = averageSpeed
        self.averageStrokeRate = averageStrokeRate
        self.strokeCount = strokeCount
        self.averagePower = averagePower
        self.maxPower = maxPower
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.heartRateZoneSeconds = heartRateZoneSeconds
        self.completedCourse = completedCourse
        self.pauseCount = pauseCount
    }
}

/// Ein Punkt der Zeitreihe (ca. 1 Hz)
public struct WorkoutSample: Codable, Equatable, Sendable {
    /// Sekunden seit Start (Uhrzeit, einschliesslich Pausen)
    public var time: TimeInterval
    /// Distanz seit Start (m)
    public var distance: Double
    /// s pro 500 m, 0 = unbekannt
    public var pace: TimeInterval
    public var strokeRate: Int
    public var power: Int
    public var heartRate: Int?

    enum CodingKeys: String, CodingKey {
        case time = "t", distance = "d", pace = "p", strokeRate = "spm", power = "w", heartRate = "hr"
    }

    public init(time: TimeInterval, distance: Double, pace: TimeInterval, strokeRate: Int, power: Int, heartRate: Int?) {
        self.time = time
        self.distance = distance
        self.pace = pace
        self.strokeRate = strokeRate
        self.power = power
        self.heartRate = heartRate
    }
}

/// Zwischenzeit je 500 m (der letzte Split kann kürzer sein)
public struct SplitTime: Codable, Equatable, Sendable, Identifiable {
    /// 1, 2, 3 …
    public var index: Int
    /// Distanz am Ende des Splits (m)
    public var endDistance: Double
    /// Länge des Splits (m), normalerweise 500
    public var length: Double
    /// Dauer des Splits (s, Ruderzeit)
    public var duration: TimeInterval
    public var averageStrokeRate: Double
    public var averagePower: Int
    public var averageHeartRate: Int?

    public var id: Int { index }
    /// s pro 500 m
    public var pace: TimeInterval { length > 0 ? duration / length * 500 : 0 }

    public init(index: Int, endDistance: Double, length: Double, duration: TimeInterval, averageStrokeRate: Double,
                averagePower: Int, averageHeartRate: Int?) {
        self.index = index
        self.endDistance = endDistance
        self.length = length
        self.duration = duration
        self.averageStrokeRate = averageStrokeRate
        self.averagePower = averagePower
        self.averageHeartRate = averageHeartRate
    }
}
