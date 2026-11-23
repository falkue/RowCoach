import XCTest
@testable import RowCoachKit

final class PM5EncoderTests: XCTestCase {
    func testEncodedLengthsMatchParser() throws {
        let packets: [(PM5.Characteristic, [UInt8])] = [
            (.generalStatus, PM5Encoder.generalStatus(elapsed: 1, distance: 2, workoutState: .workoutRow,
                                                      rowingState: .active, strokeState: .driving)),
            (.additionalStatus1, PM5Encoder.additionalStatus1(elapsed: 1, speed: 4, strokeRate: 24, heartRate: nil,
                                                              pace: 125, averagePace: 126)),
            (.additionalStatus2, PM5Encoder.additionalStatus2(elapsed: 1, averagePower: 180, calories: 12)),
            (.strokeData, PM5Encoder.strokeData(elapsed: 1, distance: 2, strokeDistance: 10, driveTime: 0.8,
                                                recoveryTime: 1.7, strokeCount: 3)),
            (.additionalStrokeData, PM5Encoder.additionalStrokeData(elapsed: 1, power: 200, strokeCount: 3)),
        ]
        for (c, b) in packets {
            XCTAssertEqual(b.count, PM5Parser.expectedLength[c], "\(c)")
            XCTAssertNoThrow(try PM5Parser.parse(characteristic: c, bytes: b))
        }
    }

    func testRoundTripValues() throws {
        guard case .generalStatus(let g) = try PM5Parser.parse(
            characteristic: .generalStatus,
            bytes: PM5Encoder.generalStatus(elapsed: 754.56, distance: 2345.6, workoutState: .workoutRow,
                                            rowingState: .active, strokeState: .recovery, dragFactor: 118))
        else { return XCTFail() }
        XCTAssertEqual(g.elapsedTime, 754.56, accuracy: 0.001)
        XCTAssertEqual(g.distance, 2345.6, accuracy: 0.001)
        XCTAssertEqual(g.workoutState, .workoutRow)
        XCTAssertEqual(g.dragFactor, 118)

        guard case .additionalStatus1(let a) = try PM5Parser.parse(
            characteristic: .additionalStatus1,
            bytes: PM5Encoder.additionalStatus1(elapsed: 10, speed: 4.237, strokeRate: 26, heartRate: nil,
                                                pace: 118, averagePace: 120.5))
        else { return XCTFail() }
        XCTAssertEqual(a.speed, 4.237, accuracy: 0.0001)
        XCTAssertEqual(a.strokeRate, 26)
        XCTAssertNil(a.heartRate)
        XCTAssertEqual(a.currentPace, 118, accuracy: 0.001)

        guard case .additionalStrokeData(let s) = try PM5Parser.parse(
            characteristic: .additionalStrokeData,
            bytes: PM5Encoder.additionalStrokeData(elapsed: 10, power: 231, strokeCount: 77))
        else { return XCTFail() }
        XCTAssertEqual(s.strokePower, 231)
        XCTAssertEqual(s.strokeCount, 77)

        let hr = HeartRateParser.parse(PM5Encoder.heartRate(bpm: 152, rrIntervals: [0.4, 0.5]))
        XCTAssertEqual(hr?.bpm, 152)
        XCTAssertEqual(hr?.sensorContact, true)
        XCTAssertEqual(hr?.rrIntervals.count, 2)
        XCTAssertEqual(hr?.rrIntervals[1] ?? 0, 0.5, accuracy: 0.001)
    }
}

final class ErgSimulatorTests: XCTestCase {
    /// Simulator → Bytes → Parser → Snapshot → RowingSession, wie in der App.
    func testSimulatorDrivesSessionToFinish() throws {
        var sim = ErgSimulator(settings: .init(pace: 100, strokeRate: 22), startDistance: 777)
        var snap = RowingSnapshot()
        var session = RowingSession(track: CourseTrack(course: .straight(oneWay: 250)))
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var t: TimeInterval = 0
        var events: [RowingEvent] = []
        var didReset = false
        while t < 400 && !session.isFinished {
            t += 0.25
            if t >= 40 && !didReset {
                sim.resetMonitor()   // Nutzer startet den PM5 mitten in der Fahrt neu
                didReset = true
            }
            let out = sim.step(dt: 0.25)
            for p in out.pm5 { snap.apply(try PM5Parser.parse(characteristic: p.characteristic, bytes: p.bytes)) }
            if let b = out.heartRate, let m = HeartRateParser.parse(b) {
                snap.apply(strap: m)
                session.record(rrIntervals: m.rrIntervals)
            }
            events += session.update(snap, at: t0.addingTimeInterval(t))
        }
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.distance, 500, accuracy: 1e-9)
        XCTAssertEqual(events.filter { $0 == .started }.count, 1)
        XCTAssertFalse(events.contains(.paused))
        XCTAssertEqual(session.splits.count, 1)
        // 5 m/s → 1:40 /500 m; Anlauf des Schwungrads kostet etwas Zeit
        XCTAssertEqual(session.averagePace, 100, accuracy: 3)
        XCTAssertNotNil(session.averageHeartRate)
        XCTAssertFalse(session.rrIntervals.isEmpty)
        XCTAssertGreaterThan(session.strokeCount, 30)
        XCTAssertGreaterThan(session.averagePower, 300)   // 2,8 × 5³ = 350 W
    }

    func testStopRowingLeadsToPause() throws {
        var sim = ErgSimulator(settings: .init(pace: 120, strokeRate: 20))
        var snap = RowingSnapshot()
        var session = RowingSession(track: CourseTrack(course: .straight(oneWay: 1000)), pauseAfter: 6)
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var t: TimeInterval = 0
        var events: [RowingEvent] = []
        func run(_ seconds: Double) throws {
            let end = t + seconds
            while t < end {
                t += 0.25
                let out = sim.step(dt: 0.25)
                for p in out.pm5 { snap.apply(try PM5Parser.parse(characteristic: p.characteristic, bytes: p.bytes)) }
                events += session.update(snap, at: t0.addingTimeInterval(t))
            }
        }
        try run(30)
        XCTAssertEqual(session.state, .rowing)
        sim.settings.rowing = false
        try run(12)
        XCTAssertEqual(session.state, .paused)
        sim.settings.rowing = true
        try run(5)
        XCTAssertEqual(session.state, .rowing)
        XCTAssertEqual(events.filter { $0 == .paused }.count, 1)
        XCTAssertEqual(events.filter { $0 == .resumed }.count, 1)
    }
}
