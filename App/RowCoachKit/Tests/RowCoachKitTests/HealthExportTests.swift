import XCTest
@testable import RowCoachKit

final class HealthExportTests: XCTestCase {
    private func record(source: WorkoutDevice.Source = .pm5, demo: Bool? = nil) -> WorkoutRecord {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // 300 s, gleichmässig 4 m/s, Puls ab 10 s
        let samples = stride(from: 0.0, through: 300, by: 1).map {
            WorkoutSample(time: $0, distance: 4 * $0, pace: 125, strokeRate: 24, power: 180, heartRate: $0 >= 10 ? 140 : nil)
        }
        let summary = WorkoutSummary(distance: 1200, activeDuration: 300, totalDuration: 300, averagePace: 125,
                                     averageSpeed: 4, averageStrokeRate: 24, strokeCount: 120, averagePower: 180,
                                     maxPower: 220, calories: 90, averageHeartRate: 140, maxHeartRate: 150,
                                     heartRateZoneSeconds: nil, completedCourse: false, pauseCount: 0)
        let header = WorkoutHeader(startDate: start, endDate: start.addingTimeInterval(300), device: WorkoutDevice(source: source))
        var r = WorkoutRecord(header: header, summary: summary, samples: samples, splits: [], demo: demo)
        r.effort = WorkoutEffort(estimate: 5, userScore: 6)
        return r
    }

    func testExportMapsTotalsIntervalsAndSamples() throws {
        let e = try XCTUnwrap(HealthWorkoutExport(record: record(), title: "Rudern"))
        XCTAssertEqual(e.intervals.count, 5)
        XCTAssertEqual(e.intervals.reduce(0) { $0 + $1.meters }, 1200, accuracy: 0.5)
        XCTAssertEqual(e.intervals.reduce(0) { $0 + $1.kilocalories }, 90, accuracy: 0.1)
        XCTAssertEqual(e.intervals[0].meters, 240, accuracy: 0.5)
        XCTAssertEqual(e.speed.first?.value ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(e.power.count, 61)                 // alle 5 s
        XCTAssertEqual(e.heartRate.first?.date, e.start.addingTimeInterval(10))
        XCTAssertEqual(e.effortScore, 6)
        XCTAssertEqual(e.estimatedEffortScore, 5)
        XCTAssertTrue(e.clientRecordId.hasPrefix("rowcoach-"))
    }

    func testSimulatorAndDemoAreNeverExported() {
        XCTAssertNil(HealthWorkoutExport(record: record(source: .simulator), title: "x"))
        XCTAssertNil(HealthWorkoutExport(record: record(demo: true), title: "x"))
    }
}
