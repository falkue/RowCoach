import Foundation
import SwiftData
import RowCoachKit

/// Ein Training im lokalen Verlauf (SwiftData). Die Listenfelder sind eigene Spalten; das vollständige
/// `WorkoutRecord` (Zeitreihe, Splits, RR) liegt als JSON in `payload`. So bleibt das Schema stabil,
/// auch wenn das Trainingsformat wächst.
@Model
final class StoredWorkout {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var courseTitle: String?
    var distance: Double
    var duration: Double
    var averagePace: Double
    var averageHeartRate: Int?
    var completedCourse: Bool
    var savedToHealth: Bool
    var simulated: Bool
    /// Fahrt wurde unterbrochen und beim nächsten Start aus dem Sicherungspunkt übernommen.
    /// Mit Standardwert, damit bestehende Verläufe ohne eigene Migration weiter laden.
    var interrupted: Bool = false
    @Attribute(.externalStorage) var payload: Data

    init(record: WorkoutRecord, savedToHealth: Bool = false) {
        id = record.id
        startDate = record.header.startDate
        courseTitle = record.header.courseTitle
        distance = record.summary.distance
        duration = record.summary.activeDuration
        averagePace = record.summary.averagePace
        averageHeartRate = record.summary.averageHeartRate
        completedCourse = record.summary.completedCourse
        self.savedToHealth = savedToHealth
        simulated = record.header.device.source == .simulator
        interrupted = record.isInterrupted
        payload = (try? record.jsonData()) ?? Data()
    }

    /// Vollständiges Training (nil, falls die Daten beschädigt sind)
    var record: WorkoutRecord? { try? WorkoutRecord(jsonData: payload) }
}
