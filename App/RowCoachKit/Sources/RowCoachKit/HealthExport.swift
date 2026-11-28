import Foundation

// Trainings in den Gesundheitsspeicher des Systems schreiben: Apple Health (iOS, HealthService in der App) und
// Health Connect (Android, androidx.health.connect). Beide bekommen dieselben, plattformneutralen Daten aus
// `HealthWorkoutExport`; die Hülle der jeweiligen Plattform übersetzt sie 1:1 in ihre Typen und fragt die
// Freigabe beim Nutzer an (Schalter „Gesundheitsdaten schreiben“ in den Einstellungen, standardmässig aus).
//
// Zuordnung (siehe docs/HEALTH.md):
// | Inhalt              | Apple Health                              | Health Connect                                   |
// |---------------------|-------------------------------------------|--------------------------------------------------|
// | Training            | HKWorkout .rowing, indoor                 | ExerciseSessionRecord EXERCISE_TYPE_ROWING_MACHINE |
// | Distanz             | distanceRowing (Summen je Abschnitt)      | DistanceRecord (je Abschnitt)                    |
// | Energie             | activeEnergyBurned                        | ActiveCaloriesBurnedRecord                       |
// | Puls                | heartRate (Einzelwerte)                   | HeartRateRecord (Samples)                        |
// | Leistung            | – (nur Metadaten)                         | PowerRecord (Samples, W)                         |
// | Tempo               | – (Metadaten)                             | SpeedRecord (Samples, m/s)                       |
// | Anstrengung 1–10    | workoutEffortScore / estimated…           | – (nur in RowCoach; Notiz im Titel/Bemerkung)    |
// | Strecke (Route)     | HKWorkoutRoute (virtuell verortet)        | ExerciseRoute nur für echte Ausfahrten – entfällt |
// | Kennung             | HKMetadataKeyExternalUUID                 | Metadata.clientRecordId                          |

/// Plattformneutraler Inhalt eines Trainings für den Gesundheitsspeicher
public struct HealthWorkoutExport: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public var date: Date
        public var value: Double
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Abschnitt mit Distanz und Energie (Summe im Zeitraum)
    public struct Interval: Equatable, Sendable {
        public var start: Date
        public var end: Date
        public var meters: Double
        public var kilocalories: Double
    }

    /// stabile Kennung (Trainings-ID): verhindert Doppeleinträge beim Nachtragen
    public var clientRecordId: String
    /// zählt hoch, wenn RowCoach dasselbe Training neu schreibt (Health Connect: clientRecordVersion)
    public var clientRecordVersion: Int64
    public var start: Date
    public var end: Date
    public var title: String
    public var notes: String?
    public var totalMeters: Double
    public var totalKilocalories: Double
    public var intervals: [Interval]
    public var heartRate: [Sample]
    public var power: [Sample]
    /// m/s
    public var speed: [Sample]
    public var effortScore: Int?
    public var estimatedEffortScore: Int?
    public var indoor: Bool { true }
}

public enum HealthExportRule {
    /// Simulator- und Demofahrten gehen nie in einen Gesundheitsspeicher
    public static func shouldExport(_ record: WorkoutRecord) -> Bool {
        record.header.device.source != .simulator && !record.isDemo && record.summary.distance > 0
    }
}

extension HealthWorkoutExport {
    /// Aus einem gespeicherten Training. `intervalSeconds`: Länge der Abschnitte für Distanz/Energie (Standard 60 s),
    /// `sampleSeconds`: Abstand der Puls-, Leistungs- und Tempowerte (Standard 5 s; Health Connect empfiehlt
    /// wenige, gleichmässige Samples statt jedes Schlags).
    /// `bodyMassKg`: Körpergewicht für die aktive Energie älterer Fahrten ohne festgehaltenen Wert (Standard 75 kg).
    public init?(record: WorkoutRecord, title: String, notes: String? = nil, version: Int64 = 1,
                 intervalSeconds: TimeInterval = 60, sampleSeconds: TimeInterval = 5, bodyMassKg: Double? = nil) {
        guard HealthExportRule.shouldExport(record) else { return nil }
        let start = record.header.startDate
        var end = record.header.endDate
        let lastT = record.samples.last?.time ?? record.summary.totalDuration
        if end <= start { end = start.addingTimeInterval(max(lastT, 1)) }
        clientRecordId = "rowcoach-\(record.id.uuidString)"
        clientRecordVersion = version
        self.start = start
        self.end = end
        self.title = title
        self.notes = notes
        totalMeters = record.summary.distance
        // aktive Energie ohne Ruheanteil (Health: activeEnergyBurned, Health Connect: ActiveCaloriesBurnedRecord),
        // nicht die PM5-Zahl (enthält 300 kcal/h Grundanteil); docs/KALORIEN.md
        totalKilocalories = RowingEnergy.activeKcal(record.summary, bodyMassKg: bodyMassKg)
        effortScore = record.effort?.userScore
        estimatedEffortScore = record.effort?.estimate

        // Abschnitte: Distanz aus den Samples, Energie anteilig zur Distanz
        let samples = record.samples.sorted { $0.time < $1.time }
        var ivs: [Interval] = []
        let total = max(end.timeIntervalSince(start), 1)
        var t0: TimeInterval = 0
        var d0 = 0.0
        while t0 < total - 1e-6 {
            let t1 = min(t0 + intervalSeconds, total)
            let d1 = HealthWorkoutExport.distance(at: t1, samples, final: totalMeters, totalTime: total)
            let meters = max(0, d1 - d0)
            ivs.append(Interval(start: start.addingTimeInterval(t0), end: start.addingTimeInterval(t1), meters: meters,
                                kilocalories: totalMeters > 0 ? totalKilocalories * meters / totalMeters : 0))
            t0 = t1
            d0 = d1
        }
        intervals = ivs.filter { $0.meters > 0 || $0.kilocalories > 0 }

        // Samples ausdünnen (je Zeitfenster der letzte Wert)
        var hr: [Sample] = [], pw: [Sample] = [], sp: [Sample] = []
        var nextT = -Double.infinity
        for s in samples where s.time >= nextT {
            let date = start.addingTimeInterval(s.time)
            if let h = s.heartRate, h > 0 { hr.append(Sample(date: date, value: Double(h))) }
            if s.power > 0 { pw.append(Sample(date: date, value: Double(s.power))) }
            if s.pace > 0 { sp.append(Sample(date: date, value: 500 / s.pace)) }
            nextT = s.time + sampleSeconds
        }
        heartRate = hr
        power = pw
        speed = sp
    }

    private static func distance(at t: TimeInterval, _ s: [WorkoutSample], final: Double, totalTime: TimeInterval) -> Double {
        guard let last = s.last else { return final * min(1, t / totalTime) }
        if t >= last.time { return final }
        var lo = 0, hi = s.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if s[mid].time < t { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return s[0].time > 0 ? s[0].distance * t / s[0].time : s[0].distance }
        let a = s[lo - 1], b = s[lo]
        let f = b.time > a.time ? (t - a.time) / (b.time - a.time) : 1
        return a.distance + (b.distance - a.distance) * f
    }
}

/// Schnittstelle der Plattform-Hülle zum Gesundheitsspeicher (iOS: HealthKit, Android: Health Connect)
public protocol HealthStoreAdapter: Sendable {
    /// Gibt es den Speicher auf diesem Gerät (Android: Health-Connect-App installiert/aktuell)?
    func isAvailable() async -> Bool
    /// Freigabe zum Schreiben anfragen (Systemdialog); true = erteilt
    func requestWriteAuthorization() async -> Bool
    /// Training schreiben; doppelte `clientRecordId` ersetzt den alten Eintrag statt zu doppeln
    func write(_ workout: HealthWorkoutExport) async throws
}
