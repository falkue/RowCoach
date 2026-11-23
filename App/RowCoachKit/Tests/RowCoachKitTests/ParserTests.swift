import XCTest
@testable import RowCoachKit

final class PM5ParserTests: XCTestCase {
    /// Little-Endian-Hilfen für Testdaten
    private func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private func u24(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF)] }

    func testUUID() {
        XCTAssertEqual(PM5.rowingService, "CE060030-43E5-11E4-916C-0800200C9A66")
        XCTAssertEqual(PM5.Characteristic.generalStatus.uuid, "CE060031-43E5-11E4-916C-0800200C9A66")
    }

    func testGeneralStatus() throws {
        // 12:34.56 = 75456 cs, 2345.6 m = 23456 dm
        let b = u24(75456) + u24(23456) + [1, 0, 1, 1, 2] + u24(2000) + u24(200_000) + [0x80, 120]
        XCTAssertEqual(b.count, 19)
        guard case .generalStatus(let s) = try PM5Parser.parse(characteristic: .generalStatus, bytes: b) else {
            return XCTFail()
        }
        XCTAssertEqual(s.elapsedTime, 754.56, accuracy: 0.001)
        XCTAssertEqual(s.distance, 2345.6, accuracy: 0.001)
        XCTAssertEqual(s.workoutState, .workoutRow)
        XCTAssertEqual(s.rowingState, .active)
        XCTAssertEqual(s.strokeState, .driving)
        XCTAssertEqual(s.totalWorkDistance, 2000)
        XCTAssertEqual(s.workoutDurationType, 0x80)
        XCTAssertEqual(s.dragFactor, 120)
    }

    func testAdditionalStatus1() throws {
        // 4.237 m/s, 24 spm, HR 255 = ungültig, Pace 1:58.00 = 11800 cs
        let b = u24(1000) + u16(4237) + [24, 255] + u16(11800) + u16(12050) + u16(0) + u24(0) + [0]
        XCTAssertEqual(b.count, 17)
        guard case .additionalStatus1(let s) = try PM5Parser.parse(characteristic: .additionalStatus1, bytes: b) else {
            return XCTFail()
        }
        XCTAssertEqual(s.speed, 4.237, accuracy: 0.0001)
        XCTAssertEqual(s.strokeRate, 24)
        XCTAssertNil(s.heartRate)
        XCTAssertEqual(s.currentPace, 118.0, accuracy: 0.001)
        XCTAssertEqual(s.averagePace, 120.5, accuracy: 0.001)
    }

    func testAdditionalStatus2() throws {
        let b = u24(1000) + [2] + u16(210) + u16(85) + u16(11900) + u16(205) + u16(900) + u24(1185) + u24(500)
        XCTAssertEqual(b.count, 20)
        guard case .additionalStatus2(let s) = try PM5Parser.parse(characteristic: .additionalStatus2, bytes: b) else {
            return XCTFail()
        }
        XCTAssertEqual(s.averagePower, 210)
        XCTAssertEqual(s.totalCalories, 85)
        XCTAssertEqual(s.lastSplitTime, 118.5, accuracy: 0.001)
        XCTAssertEqual(s.lastSplitDistance, 500)
    }

    func testStrokeData() throws {
        let b = u24(1000) + u24(1234) + [145, 80] + u16(160) + u16(1050) + u16(2500) + u16(1500) + u16(6000) + u16(321)
        XCTAssertEqual(b.count, 20)
        guard case .strokeData(let s) = try PM5Parser.parse(characteristic: .strokeData, bytes: b) else {
            return XCTFail()
        }
        XCTAssertEqual(s.driveLength, 1.45, accuracy: 0.001)
        XCTAssertEqual(s.driveTime, 0.80, accuracy: 0.001)
        XCTAssertEqual(s.strokeDistance, 10.5, accuracy: 0.001)
        XCTAssertEqual(s.workPerStroke, 600, accuracy: 0.01)
        XCTAssertEqual(s.strokeCount, 321)
    }

    func testAdditionalStrokeData() throws {
        let b = u24(1000) + u16(230) + u16(1100) + u16(321) + u24(420) + u24(2000) + u24(0)
        XCTAssertEqual(b.count, 18)
        guard case .additionalStrokeData(let s) = try PM5Parser.parse(characteristic: .additionalStrokeData, bytes: b) else {
            return XCTFail()
        }
        XCTAssertEqual(s.strokePower, 230)
        XCTAssertEqual(s.strokeCount, 321)
    }

    func testSummary() throws {
        let b = u16(0) + u16(0) + u24(72000) + u24(40000) + [24, 160, 150, 90, 172, 118, 0, 1] + u16(1800)
        XCTAssertEqual(b.count, 20)
        guard case .workoutSummary(let s) = try PM5Parser.parse(characteristic: .workoutSummary, bytes: b) else {
            return XCTFail()
        }
        XCTAssertEqual(s.elapsedTime, 720, accuracy: 0.001)
        XCTAssertEqual(s.distance, 4000, accuracy: 0.001)
        XCTAssertEqual(s.maxHeartRate, 172)
        XCTAssertNil(s.recoveryHeartRate)
        XCTAssertEqual(s.averagePace, 180, accuracy: 0.001)
    }

    func testTooShort() {
        XCTAssertThrowsError(try PM5Parser.parse(characteristic: .generalStatus, bytes: [0, 1, 2]))
    }

    func testSnapshotPrefersStrap() throws {
        var snap = RowingSnapshot()
        snap.apply(strap: HeartRateMeasurement(bpm: 140, sensorContact: true, energyExpended: nil, rrIntervals: []))
        let b = u24(1000) + u16(4000) + [22, 150] + u16(12500) + u16(12500) + u16(0) + u24(0) + [0]
        snap.apply(try PM5Parser.parse(characteristic: .additionalStatus1, bytes: b))
        XCTAssertEqual(snap.heartRate, 140)
        XCTAssertEqual(snap.heartRateSource, .strap)
        XCTAssertEqual(snap.strokeRate, 22)
    }
}

final class HeartRateParserTests: XCTestCase {
    func testUInt8WithRR() {
        // flags: 8-bit HR, contact supported+detected, RR present = 0b0001_0110
        let m = HeartRateParser.parse([0x16, 72, 0x00, 0x04, 0x00, 0x02])
        XCTAssertEqual(m?.bpm, 72)
        XCTAssertEqual(m?.sensorContact, true)
        XCTAssertEqual(m?.rrIntervals.count, 2)
        XCTAssertEqual(m?.rrIntervals[0] ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(m?.rrIntervals[1] ?? 0, 0.5, accuracy: 0.0001)
    }

    func testUInt16() {
        let m = HeartRateParser.parse([0x01, 0x2C, 0x01])
        XCTAssertEqual(m?.bpm, 300)
        XCTAssertNil(m?.sensorContact)
    }

    func testNoContact() {
        let m = HeartRateParser.parse([0x04, 80])
        XCTAssertEqual(m?.sensorContact, false)
    }

    func testFormat() {
        XCTAssertEqual(Format.pace(118.3), "1:58.3")
        XCTAssertEqual(Format.duration(3723), "1:02:03")
        XCTAssertEqual(Format.pace(0), "–:––")
    }
}
