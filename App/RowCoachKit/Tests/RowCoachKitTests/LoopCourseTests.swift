import XCTest
@testable import RowCoachKit

final class LoopCourseTests: XCTestCase {
    /// Geschlossener Rechteck-Rundkurs (Ende = Start), 1 m abgetastet
    private func loopCourse() -> Course {
        var pts: [[Double]] = []
        for x in 0..<400 { pts.append([Double(x), 0]) }
        for z in 0..<200 { pts.append([400, -Double(z)]) }
        for x in stride(from: 400, to: 0, by: -1) { pts.append([Double(x), -200]) }
        for z in stride(from: 200, through: 0, by: -1) { pts.append([0, -Double(z)]) }
        var c = Course(id: "loop", title: "Loop", oneWayM: 1200, totalM: 1200, turns: 0, pathXZ: pts)
        c.loop = true
        return c
    }

    func testLoopFlagAndLength() {
        let c = loopCourse()
        XCTAssertTrue(c.isLoop)
        XCTAssertEqual(CourseTrack(course: c).totalLength, 1200, accuracy: 0.01)
    }

    func testLapsContinueSeamlesslyOnLoop() {
        let laps = LapTrack(course: loopCourse(), endDistance: 1700)
        let before = laps.pose(atDistance: 1199.5), after = laps.pose(atDistance: 1200.5)
        XCTAssertLessThan(hypot(after.x - before.x, after.z - before.z), 2.0, "kein Sprung an der Rundengrenze")
        XCTAssertEqual(laps.lapPose(atDistance: 1700).lap, 1)
    }
}
