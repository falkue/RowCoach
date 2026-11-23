import Foundation

/// Sicherungspunkt einer laufenden Fahrt. Die App schreibt ihn etwa alle 10 s (und bei Pause) als JSON-Datei
/// (`active-workout.json` unter Application Support) und löscht ihn beim normalen Ende. Findet die App die Datei beim
/// nächsten Start noch vor, war die Fahrt unterbrochen (Akku leer, App beendet oder abgestürzt): Das Training wird
/// dann aus `record` als unterbrochen in den Verlauf übernommen (`interruptedRecord()`).
///
/// Alle Felder ausser `record` sind beim Lesen optional, damit auch ältere oder knappe Dateien lesbar bleiben.
public struct WorkoutCheckpoint: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// Zeitpunkt des Sicherungspunkts
    public var savedAt: Date
    /// Start der Fahrt (erster Schlag)
    public var startDate: Date
    public var courseId: String?
    public var courseTitle: String?
    /// Länge der Strecke (m)
    public var courseLength: Double?
    /// geruderte Distanz bis zum Sicherungspunkt (m)
    public var distance: Double
    /// true = während der Fahrt lief eine Apple-Health-Aufzeichnung (dann nach der Wiederherstellung nachtragen)
    public var healthRecording: Bool
    /// Stand der Fahrt als Training (Zeitreihe, Splits, Zusammenfassung bis zum Sicherungspunkt)
    public var record: WorkoutRecord

    public init(record: WorkoutRecord, savedAt: Date, healthRecording: Bool) {
        self.formatVersion = Self.currentFormatVersion
        self.savedAt = savedAt
        self.startDate = record.header.startDate
        self.courseId = record.header.courseId
        self.courseTitle = record.header.courseTitle
        self.courseLength = record.header.courseLength
        self.distance = record.summary.distance
        self.healthRecording = healthRecording
        self.record = record
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion, savedAt, startDate, courseId, courseTitle, courseLength, distance, healthRecording, record
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        record = try c.decode(WorkoutRecord.self, forKey: .record)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? record.header.endDate
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? record.header.startDate
        courseId = try c.decodeIfPresent(String.self, forKey: .courseId) ?? record.header.courseId
        courseTitle = try c.decodeIfPresent(String.self, forKey: .courseTitle) ?? record.header.courseTitle
        courseLength = try c.decodeIfPresent(Double.self, forKey: .courseLength) ?? record.header.courseLength
        distance = try c.decodeIfPresent(Double.self, forKey: .distance) ?? record.summary.distance
        healthRecording = try c.decodeIfPresent(Bool.self, forKey: .healthRecording) ?? false
    }

    public func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(WorkoutCheckpoint.self, from: jsonData)
    }

    /// Das Training für den Verlauf: als unterbrochen markiert, Strecke nicht geschafft, Ende = Zeit des letzten
    /// Samples (ohne Samples: Zeitpunkt des Sicherungspunkts).
    public func interruptedRecord() -> WorkoutRecord {
        var r = record
        r.interrupted = true
        r.summary.completedCourse = false
        let start = r.header.startDate
        let end: Date
        if let last = r.samples.last {
            end = start.addingTimeInterval(max(last.time, 0))
        } else {
            end = max(savedAt, start)
        }
        r.header.endDate = end
        let total = max(end.timeIntervalSince(start), 0)
        r.summary.totalDuration = total
        r.summary.activeDuration = min(r.summary.activeDuration, total)
        return r
    }
}
