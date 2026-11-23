import XCTest
@testable import RowCoachKit

final class CheckpointTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func record(samples: [WorkoutSample], distance: Double = 120, interrupted: Bool? = nil) -> WorkoutRecord {
        let header = WorkoutHeader(startDate: t0, endDate: t0.addingTimeInterval(60), courseId: "teststrecke",
                                   courseTitle: "Teststrecke", courseLength: 2000, device: WorkoutDevice(source: .pm5))
        let summary = WorkoutSummary(distance: distance, activeDuration: 58, totalDuration: 60, averagePace: 120,
                                     averageSpeed: 2, averageStrokeRate: 24, strokeCount: 24, averagePower: 180,
                                     maxPower: 250, calories: 9, averageHeartRate: 130, maxHeartRate: 140,
                                     heartRateZoneSeconds: nil, completedCourse: false, pauseCount: 0)
        return WorkoutRecord(header: header, summary: summary, samples: samples, splits: [], interrupted: interrupted)
    }

    private func samples(count: Int, speed: Double = 2, power: Int = 180) -> [WorkoutSample] {
        (0..<count).map { i in
            WorkoutSample(time: Double(i), distance: Double(i) * speed, pace: 125, strokeRate: 24, power: power,
                          heartRate: 120 + i % 10)
        }
    }

    // MARK: Sicherungspunkt

    func testCheckpointRoundTrip() throws {
        let rec = record(samples: samples(count: 41))
        let cp = WorkoutCheckpoint(record: rec, savedAt: t0.addingTimeInterval(41), healthRecording: true)
        XCTAssertEqual(cp.startDate, t0)
        XCTAssertEqual(cp.courseId, "teststrecke")
        XCTAssertEqual(cp.distance, 120)
        let back = try WorkoutCheckpoint(jsonData: cp.jsonData())
        XCTAssertEqual(back, cp)
        XCTAssertTrue(back.healthRecording)
    }

    func testInterruptedRecord() {
        let rec = record(samples: samples(count: 41))   // letztes Sample bei 40 s
        let cp = WorkoutCheckpoint(record: rec, savedAt: t0.addingTimeInterval(45), healthRecording: false)
        let r = cp.interruptedRecord()
        XCTAssertEqual(r.interrupted, true)
        XCTAssertTrue(r.isInterrupted)
        XCTAssertFalse(r.summary.completedCourse)
        XCTAssertEqual(r.header.endDate, t0.addingTimeInterval(40))
        XCTAssertEqual(r.summary.totalDuration, 40, accuracy: 1e-9)
        XCTAssertEqual(r.summary.activeDuration, 40, accuracy: 1e-9)   // auf die Gesamtzeit begrenzt
        XCTAssertEqual(r.id, rec.id)
    }

    func testInterruptedRecordWithoutSamples() {
        let cp = WorkoutCheckpoint(record: record(samples: []), savedAt: t0.addingTimeInterval(12), healthRecording: false)
        XCTAssertEqual(cp.interruptedRecord().header.endDate, t0.addingTimeInterval(12))
    }

    /// Knapper Sicherungspunkt nur mit dem Training: fehlende Metadaten kommen aus dem Training.
    func testCheckpointWithoutMetadataDecodes() throws {
        let rec = record(samples: samples(count: 5))
        let recJSON = String(data: try rec.jsonData(), encoding: .utf8)!
        let json = "{\"record\":\(recJSON)}"
        let cp = try WorkoutCheckpoint(jsonData: Data(json.utf8))
        XCTAssertEqual(cp.formatVersion, 1)
        XCTAssertEqual(cp.startDate, t0)
        XCTAssertEqual(cp.savedAt, rec.header.endDate)
        XCTAssertEqual(cp.courseTitle, "Teststrecke")
        XCTAssertEqual(cp.distance, 120)
        XCTAssertFalse(cp.healthRecording)
        XCTAssertEqual(cp.record, rec)
    }

    /// Alte Trainings-JSONs (vor dem Feld `interrupted`) bleiben lesbar.
    func testOldRecordJSONWithoutInterruptedDecodes() throws {
        let rec = record(samples: samples(count: 3))
        var obj = try JSONSerialization.jsonObject(with: rec.jsonData()) as! [String: Any]
        XCTAssertNil(obj["interrupted"], "nil wird nicht geschrieben")
        obj.removeValue(forKey: "interrupted")
        let back = try WorkoutRecord(jsonData: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.interrupted)
        XCTAssertFalse(back.isInterrupted)
        XCTAssertEqual(back.samples, rec.samples)

        let marked = record(samples: [], interrupted: true)
        XCTAssertEqual(try WorkoutRecord(jsonData: marked.jsonData()).interrupted, true)
    }

    // MARK: Abschnitte für Apple Health

    func testBlocksSumAndBoundaries() {
        // 0…59 s, 2 m/s, gleiche Leistung
        let s = samples(count: 60)
        let blocks = WorkoutIncrements.blocks(samples: s, totalDistance: 120, totalEnergy: 12)
        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks.first?.start, 0)
        XCTAssertEqual(blocks.first?.end, 9)
        XCTAssertEqual(blocks[1].start, 9)
        XCTAssertEqual(blocks[1].end, 19)
        XCTAssertEqual(blocks.last?.end, 59)
        for (a, b) in zip(blocks, blocks.dropFirst()) { XCTAssertEqual(a.end, b.start) }
        // 118 m aus der Zeitreihe + 2 m Rest im letzten Abschnitt
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.distance }, 120, accuracy: 1e-9)
        XCTAssertEqual(blocks[1].distance, 20, accuracy: 1e-9)
        XCTAssertEqual(blocks.last!.distance, 22, accuracy: 1e-9)
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.energy }, 12, accuracy: 1e-9)
        // Energie nach Arbeit: erster Abschnitt 9 s, die anderen 10 s
        XCTAssertEqual(blocks[0].energy, 12 * 9 / 59, accuracy: 1e-9)
        XCTAssertEqual(blocks[1].energy, 12 * 10 / 59, accuracy: 1e-9)
    }

    func testBlocksSkipPauses() {
        // 0…19 s rudern, 20…49 s Pause (Distanz bleibt, Leistung 0), 50…59 s rudern
        var s: [WorkoutSample] = []
        var d = 0.0
        for i in 0..<60 {
            let rowing = i < 20 || i >= 50
            if i > 0, rowing { d += 2 }
            s.append(WorkoutSample(time: Double(i), distance: d, pace: rowing ? 125 : 0, strokeRate: rowing ? 24 : 0,
                                   power: rowing ? 200 : 0, heartRate: nil))
        }
        let blocks = WorkoutIncrements.blocks(samples: s, totalDistance: d, totalEnergy: 6)
        XCTAssertEqual(blocks.count, 3)      // 0–9, 9–19, 49–59 (Pausenblöcke fallen weg)
        XCTAssertEqual(blocks[2].start, 49)
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.distance }, d, accuracy: 1e-9)
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.energy }, 6, accuracy: 1e-9)
    }

    func testBlocksWithoutPowerUseDistance() {
        let s = samples(count: 21, power: 0)
        let blocks = WorkoutIncrements.blocks(samples: s, totalDistance: 40, totalEnergy: 4)
        XCTAssertEqual(blocks.count, 3)   // 0–9, 9–19, 19–20
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.energy }, 4, accuracy: 1e-9)
        XCTAssertEqual(blocks[0].energy, 4 * blocks[0].distance / 40, accuracy: 1e-9)
    }

    func testBlocksEmptyAndUnsorted() {
        XCTAssertEqual(WorkoutIncrements.blocks(samples: [], totalDistance: 0, totalEnergy: 0), [])
        let onlyTotals = WorkoutIncrements.blocks(samples: [], totalDistance: 100, totalEnergy: 5)
        XCTAssertEqual(onlyTotals.count, 1)
        XCTAssertEqual(onlyTotals[0].distance, 100)
        XCTAssertEqual(onlyTotals[0].energy, 5, accuracy: 1e-9)
        let s = samples(count: 30)
        XCTAssertEqual(WorkoutIncrements.blocks(samples: s.reversed(), totalDistance: 58, totalEnergy: 3),
                       WorkoutIncrements.blocks(samples: s, totalDistance: 58, totalEnergy: 3))
    }
}
