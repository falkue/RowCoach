import XCTest
@testable import RowCoachKit

final class RelativeCounterTests: XCTestCase {
    func testBaselineResetAndJump() {
        var c = RelativeCounter()
        XCTAssertEqual(c.update(1234, limit: 50), 0)       // Grundlinie
        XCTAssertEqual(c.update(1240, limit: 50), 6)
        XCTAssertEqual(c.update(0, limit: 50), 0)          // Neustart am PM5
        XCTAssertEqual(c.update(8, limit: 50), 8)
        XCTAssertEqual(c.update(5008, limit: 50), 0)       // unplausibler Sprung
        XCTAssertEqual(c.update(5010, limit: 50), 2)
        XCTAssertEqual(c.update(3, limit: 50), 3)          // Neustart, schon 3 m gerudert
        XCTAssertEqual(c.total, 19, accuracy: 1e-9)
    }
}

final class RowingSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func snap(_ distance: Double, strokes: Int, spm: Int = 24, power: Int = 200, hr: Int? = 140,
                      pace: Double = 125, calories: Int = 0) -> RowingSnapshot {
        var s = RowingSnapshot()
        s.distance = distance
        s.strokeCount = strokes
        s.strokeRate = spm
        s.power = power
        s.heartRate = hr
        s.pace = pace
        s.calories = calories
        return s
    }

    /// Fährt mit 4 m/s (2:05 /500 m), alle 0,5 s ein Update, alle 2,5 s ein Schlag.
    /// `offset` = Meter, die der PM5 schon auf der Uhr hat.
    private struct Driver {
        var session: RowingSession
        var raw: Double
        var strokes: Int
        var t: TimeInterval = 0
        var n = 0
        var events: [RowingEvent] = []
        let t0: Date

        mutating func row(seconds: Double, make: (Double, Int) -> RowingSnapshot) {
            let steps = Int((seconds / 0.5).rounded())
            for _ in 0..<steps {
                t += 0.5; n += 1
                raw += 2
                if n % 5 == 0 { strokes += 1 }
                events += session.update(make(raw, strokes), at: t0.addingTimeInterval(t))
            }
        }

        mutating func idle(seconds: Double, make: (Double, Int) -> RowingSnapshot) {
            let steps = Int((seconds / 0.5).rounded())
            for _ in 0..<steps {
                t += 0.5
                events += session.update(make(raw, strokes), at: t0.addingTimeInterval(t))
            }
        }
    }

    private func driver(oneWay: Double = 1000, offset: Double = 0, pauseAfter: TimeInterval = 6) -> Driver {
        var d = Driver(session: RowingSession(track: CourseTrack(course: .straight(oneWay: oneWay)), pauseAfter: pauseAfter),
                       raw: offset, strokes: 17, t0: t0)
        // erster Snapshot = Grundlinie
        d.events += d.session.update(snap(offset, strokes: 17), at: t0)
        return d
    }

    func testBaselineIgnoresMetersOnClock() {
        var s = RowingSession(track: CourseTrack(course: .straight(oneWay: 1000)))
        XCTAssertEqual(s.update(snap(1234, strokes: 50), at: t0), [])
        XCTAssertEqual(s.state, .ready)
        XCTAssertEqual(s.distance, 0)
        XCTAssertEqual(s.update(snap(1234, strokes: 50), at: t0.addingTimeInterval(1)), [])
        XCTAssertEqual(s.state, .ready)
        let e = s.update(snap(1236, strokes: 51), at: t0.addingTimeInterval(2))
        XCTAssertEqual(e, [.started])
        XCTAssertEqual(s.state, .rowing)
        XCTAssertEqual(s.distance, 2, accuracy: 1e-9)
        XCTAssertEqual(s.startDate, t0.addingTimeInterval(2))
    }

    func testPM5ResetDuringSession() {
        var d = driver(offset: 1234)
        d.row(seconds: 30) { self.snap($0, strokes: $1) }
        let before = d.session.distance
        XCTAssertEqual(before, 120, accuracy: 1e-9)
        // Neustart am PM5: Distanz und Schläge springen auf 0
        d.raw = 0; d.strokes = 0
        d.events += d.session.update(snap(0, strokes: 0), at: t0.addingTimeInterval(d.t + 0.5)); d.t += 0.5
        XCTAssertEqual(d.session.distance, before, accuracy: 1e-9)
        d.row(seconds: 5) { self.snap($0, strokes: $1) }
        XCTAssertEqual(d.session.distance, before + 20, accuracy: 1e-9)
        XCTAssertEqual(d.session.state, .rowing)
    }

    func testImplausibleJumpIgnored() {
        var d = driver()
        d.row(seconds: 10) { self.snap($0, strokes: $1) }
        let before = d.session.distance
        d.raw += 5000
        d.idle(seconds: 0.5) { self.snap($0, strokes: $1) }
        XCTAssertEqual(d.session.distance, before, accuracy: 1e-9)
        d.row(seconds: 1) { self.snap($0, strokes: $1) }
        XCTAssertEqual(d.session.distance, before + 4, accuracy: 1e-9)
    }

    func testPauseAndResume() {
        var d = driver(pauseAfter: 6)
        d.row(seconds: 20) { self.snap($0, strokes: $1) }
        XCTAssertEqual(d.session.state, .rowing)
        let active = d.session.activeTime
        d.events = []
        d.idle(seconds: 5) { self.snap($0, strokes: $1) }
        XCTAssertEqual(d.session.state, .rowing, "noch keine Pause nach 5 s")
        d.idle(seconds: 15) { self.snap($0, strokes: $1) }
        XCTAssertEqual(d.session.state, .paused)
        XCTAssertEqual(d.events, [.paused])
        XCTAssertEqual(d.session.pauseCount, 1)
        // Während der Pause steht die Ruderzeit
        let pausedActive = d.session.activeTime
        XCTAssertLessThan(pausedActive - active, 8)
        d.idle(seconds: 10) { self.snap($0, strokes: $1) }
        XCTAssertEqual(d.session.activeTime, pausedActive, accuracy: 1e-9)
        // Nächster Schlag: weiter
        d.events = []
        d.strokes += 1
        d.raw += 2
        d.t += 0.5
        d.events += d.session.update(snap(d.raw, strokes: d.strokes), at: t0.addingTimeInterval(d.t))
        XCTAssertEqual(d.events, [.resumed])
        XCTAssertEqual(d.session.state, .rowing)
    }

    func testSplitsTurnAndFinish() {
        var d = driver(oneWay: 1000, offset: 777)
        d.row(seconds: 600) { self.snap($0, strokes: $1) }
        let s = d.session
        XCTAssertEqual(s.state, .finished)
        XCTAssertTrue(s.isFinished)
        XCTAssertTrue(s.completedCourse)
        XCTAssertEqual(s.distance, 2000, accuracy: 1e-9)
        XCTAssertEqual(s.remaining, 0)
        XCTAssertTrue(s.pose.finished)
        XCTAssertEqual(d.events.filter { $0 == .started }.count, 1)
        XCTAssertEqual(d.events.filter { $0 == .turnReached }.count, 1)
        XCTAssertEqual(d.events.filter { $0 == .finished }.count, 1)
        XCTAssertEqual(d.events.last, .finished)

        XCTAssertEqual(s.splits.count, 4)
        for (i, sp) in s.splits.enumerated() {
            XCTAssertEqual(sp.index, i + 1)
            XCTAssertEqual(sp.length, 500, accuracy: 1e-9)
            XCTAssertEqual(sp.endDistance, Double(i + 1) * 500, accuracy: 1e-9)
            XCTAssertEqual(sp.duration, 125, accuracy: 1.0)
            XCTAssertEqual(sp.pace, 125, accuracy: 1.0)
            XCTAssertEqual(sp.averagePower, 200)
            XCTAssertEqual(sp.averageHeartRate, 140)
        }
        XCTAssertEqual(s.activeTime, 500, accuracy: 1.0)
        XCTAssertEqual(s.averagePace, 125, accuracy: 0.5)
        XCTAssertEqual(s.averageStrokeRate, 24, accuracy: 0.5)
        XCTAssertEqual(s.averagePower, 200)
        XCTAssertEqual(s.averageHeartRate, 140)
        // Zeitreihe ca. 1 Hz
        XCTAssertGreaterThan(s.samples.count, 490)
        XCTAssertLessThan(s.samples.count, 510)
        XCTAssertEqual(s.samples.last?.distance ?? 0, 2000, accuracy: 0.1)

        // Nach dem Ziel ändert sich nichts mehr
        var after = s
        XCTAssertEqual(after.update(snap(d.raw + 100, strokes: d.strokes + 5), at: t0.addingTimeInterval(d.t + 10)), [])
        XCTAssertEqual(after.distance, 2000)
    }

    func testManualFinishKeepsPartialSplit() {
        var d = driver()
        d.row(seconds: 175) { self.snap($0, strokes: $1) }  // 700 m
        XCTAssertEqual(d.session.distance, 700, accuracy: 1e-9)
        let e = d.session.finish(at: t0.addingTimeInterval(d.t + 1))
        XCTAssertEqual(e.last, .finished)
        XCTAssertEqual(d.session.state, .finished)
        XCTAssertFalse(d.session.completedCourse)
        XCTAssertEqual(d.session.splits.count, 2)
        XCTAssertEqual(d.session.splits[1].length, 200, accuracy: 1e-9)
        XCTAssertEqual(d.session.splits[1].pace, 125, accuracy: 1.0)
    }

    func testRecordRoundTrip() throws {
        var d = driver(oneWay: 250)
        d.row(seconds: 60) { self.snap($0, strokes: $1, calories: Int($0 / 20)) }
        d.session.record(rrIntervals: [0.42, 0.43, 5.0])   // 5 s ist unplausibel und fällt weg
        d.row(seconds: 90) { self.snap($0, strokes: $1, calories: Int($0 / 20)) }
        d.session.record(rrIntervals: [0.5])                // nach dem Ziel: ignoriert
        XCTAssertEqual(d.session.state, .finished)
        let zones = HeartRateZones(maxHR: 185, restHR: 55)
        let rec = d.session.makeRecord(device: WorkoutDevice(source: .simulator), zones: zones,
                                       workoutPlanId: "plan-1", weather: .clear, season: .summer)
        XCTAssertEqual(rec.formatVersion, WorkoutRecord.currentFormatVersion)
        XCTAssertEqual(rec.header.courseId, "teststrecke")
        XCTAssertEqual(rec.header.courseLength, 500)
        XCTAssertEqual(rec.summary.distance, 500, accuracy: 1e-9)
        XCTAssertTrue(rec.summary.completedCourse)
        XCTAssertEqual(rec.summary.calories, 25)
        XCTAssertEqual(rec.rrIntervals, [0.42, 0.43])
        XCTAssertEqual(rec.splits.count, 1)
        // 140 bpm: Zone 2 (ab 55 + 0,6 × 130 = 133, Zone 3 erst ab 146)
        XCTAssertEqual(zones.zone(for: 140), 2)
        let zoneSeconds = try XCTUnwrap(rec.summary.heartRateZoneSeconds)
        XCTAssertEqual(zoneSeconds.count, 6)
        XCTAssertGreaterThan(zoneSeconds[2], 100)

        let data = try rec.jsonData()
        let back = try WorkoutRecord(jsonData: data)
        XCTAssertEqual(back, rec)
        XCTAssertEqual(back.header.workoutPlanId, "plan-1")
        XCTAssertEqual(back.header.season, .summer)
    }

    func testUnknownSceneVariantDecodesAsNil() throws {
        let json = """
        {"startDate": 0, "endDate": 10, "device": {"source": "pm5"}, "weather": "tornado", "season": "winter"}
        """
        let h = try JSONDecoder().decode(WorkoutHeader.self, from: Data(json.utf8))
        XCTAssertNil(h.weather)
        XCTAssertEqual(h.season, .winter)
        XCTAssertNil(h.raceId)
    }
}

final class HeartRateZoneTests: XCTestCase {
    func testKarvonenZones() {
        let z = HeartRateZones(maxHR: 185, restHR: 55)   // Reserve 130
        XCTAssertEqual(z.lowerBound(zone: 1), 120)
        XCTAssertEqual(z.lowerBound(zone: 2), 133)
        XCTAssertEqual(z.lowerBound(zone: 3), 146)
        XCTAssertEqual(z.lowerBound(zone: 4), 159)
        XCTAssertEqual(z.lowerBound(zone: 5), 172)
        XCTAssertEqual(z.zone(for: 100), 0)
        XCTAssertEqual(z.zone(for: 120), 1)
        XCTAssertEqual(z.zone(for: 150), 3)
        XCTAssertEqual(z.zone(for: 200), 5)
    }

    func testSecondsPerZone() {
        let z = HeartRateZones(maxHR: 185, restHR: 55)
        let samples = (0..<10).map { WorkoutSample(time: Double($0), distance: 0, pace: 0, strokeRate: 0, power: 0,
                                                   heartRate: $0 < 5 ? 125 : 165) }
        let s = z.secondsPerZone(samples)
        XCTAssertEqual(s[1], 5, accuracy: 1e-9)
        XCTAssertEqual(s[4], 5, accuracy: 1e-9)
    }
}
