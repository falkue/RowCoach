import XCTest
@testable import RowCoachKit

final class StrokePhaseTrackerTests: XCTestCase {
    func testNoCatchMeansNil() {
        let t = StrokePhaseTracker()
        XCTAssertNil(t.phase(at: 10, strokeRate: 22))
    }

    func testPhaseFollowsCatchAndMeasuredDurations() {
        var t = StrokePhaseTracker()
        t.update(driveTime: 0.8, recoveryTime: 1.6)
        t.update(state: .recovery, at: 9.0)
        t.update(state: .driving, at: 10.0)          // Wasserfassen
        let share = StrokePhaseTracker.visualDriveShare(strokeRate: 25)
        XCTAssertEqual(t.phase(at: 10.0, strokeRate: 25)!, 0, accuracy: 1e-9)
        XCTAssertEqual(t.phase(at: 10.4, strokeRate: 25)!, share / 2, accuracy: 1e-9)   // Mitte Durchzug
        XCTAssertEqual(t.phase(at: 10.8, strokeRate: 25)!, share, accuracy: 1e-9)       // Endzug
        XCTAssertEqual(t.phase(at: 11.6, strokeRate: 25)!, share + 0.5 * (1 - share), accuracy: 1e-9)
        // länger als ein Schlag ohne neues Wasserfassen: verharrt kurz vor 1
        XCTAssertEqual(t.phase(at: 13.0, strokeRate: 25)!, 0.995, accuracy: 1e-9)
        // nach 6 s ohne Schlag: kein Takt mehr
        XCTAssertNil(t.phase(at: 16.5, strokeRate: 25))
    }

    func testRepeatedDrivingStateDoesNotMoveCatch() {
        var t = StrokePhaseTracker()
        t.update(state: .driving, at: 10.0)
        t.update(state: .driving, at: 10.1)          // derselbe Zustand im nächsten Status-Paket
        XCTAssertEqual(t.lastCatch, 10.0)
    }

    func testImplausibleDurationsIgnored() {
        var t = StrokePhaseTracker()
        t.update(driveTime: 0.05, recoveryTime: 30)
        XCTAssertEqual(t.driveTime, 0.8)
        XCTAssertEqual(t.recoveryTime, 1.9)
    }
}
