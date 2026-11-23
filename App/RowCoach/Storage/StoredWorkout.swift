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
        payload = (try? record.jsonData()) ?? Data()
    }

    /// Vollständiges Training (nil, falls die Daten beschädigt sind)
    var record: WorkoutRecord? { try? WorkoutRecord(jsonData: payload) }
}
