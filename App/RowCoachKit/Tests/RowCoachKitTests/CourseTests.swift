import XCTest
@testable import RowCoachKit

final class CourseTrackTests: XCTestCase {
    /// Gerade Strecke nach Norden (−z), 1000 m hin, 1000 m zurück
    private let north = CourseTrack(course: .straight(oneWay: 1000))

    private func wrap(_ a: Double) -> Double { atan2(sin(a), cos(a)) }

    /// Richtungsvektor aus heading (0 = −z, Drehung um +y)
    private func dir(_ h: Double) -> (x: Double, z: Double) { (-sin(h), -cos(h)) }

    func testLengths() {
        XCTAssertEqual(north.oneWayLength, 1000, accuracy: 1e-9)
        XCTAssertEqual(north.totalLength, 2000, accuracy: 1e-9)
    }

    func testOutboundOnLine() {
        let p0 = north.pose(atDistance: 0)
        XCTAssertEqual(p0.x, 0, accuracy: 1e-9)
        XCTAssertEqual(p0.z, 0, accuracy: 1e-9)
        XCTAssertEqual(wrap(p0.heading), 0, accuracy: 1e-9)
        let p = north.pose(atDistance: 500)
        XCTAssertEqual(p.x, 0, accuracy: 1e-9)
        XCTAssertEqual(p.z, -500, accuracy: 1e-9)
        XCTAssertEqual(wrap(p.heading), 0, accuracy: 1e-9)
        XCTAssertEqual(p.leg, 0)
    }

    /// heading 0 = Blick nach −z; nach Osten (+x) ist eine Drehung um +y von −90°.
    func testHeadingConvention() {
        let east = CourseTrack(course: .straight(oneWay: 1000, heading: -Double.pi / 2))
        let p = east.pose(atDistance: 100)
        XCTAssertEqual(p.x, 100, accuracy: 1e-6)
        XCTAssertEqual(p.z, 0, accuracy: 1e-6)
        XCTAssertEqual(wrap(p.heading), -Double.pi / 2, accuracy: 1e-9)
        let d = dir(p.heading)
        XCTAssertEqual(d.x, 1, accuracy: 1e-9)
        XCTAssertEqual(d.z, 0, accuracy: 1e-9)
        // nach Westen: +90° (gegen den Uhrzeigersinn von oben)
        let west = CourseTrack(course: .straight(oneWay: 1000, heading: Double.pi / 2))
        XCTAssertEqual(wrap(west.pose(atDistance: 100).heading), Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(west.pose(atDistance: 100).x, -100, accuracy: 1e-6)
    }

    /// Rückfahrt liegt in ihrer Fahrtrichtung rechts versetzt (Nord hin → Süd zurück → Westseite).
    func testReturnOffsetRightOfTravel() {
        let out = north.pose(atDistance: 500)
        let back = north.pose(atDistance: 1500)
        XCTAssertEqual(back.x, -12, accuracy: 1e-9)
        XCTAssertEqual(back.z, -500, accuracy: 1e-9)
        XCTAssertEqual(abs(wrap(back.heading)), Double.pi, accuracy: 1e-9)
        XCTAssertEqual(back.leg, 1)
        let d = dir(back.heading)
        let right = (x: -d.z, z: d.x)
        let v = (x: back.x - out.x, z: back.z - out.z)
        XCTAssertEqual(v.x * right.x + v.z * right.z, 12, accuracy: 1e-6)
    }

    func testNegativeOffsetOtherSide() {
        let t = CourseTrack(course: .straight(oneWay: 1000), returnOffset: -12)
        XCTAssertEqual(t.pose(atDistance: 1500).x, 12, accuracy: 1e-9)
    }

    /// Wende: Position und Richtung stetig, Richtung dreht nie sprunghaft.
    func testTurnIsSmooth() {
        assertSmooth(north, step: 0.25, maxJumpFactor: 1.001, maxHeadingStep: 0.03)
        XCTAssertEqual(north.turnRadius, 13.0, accuracy: 0.1)
    }

    func testTurnGeometry() {
        // Mitte der Wende: quer zur Strecke, Richtung Rückfahrtseite (Westen = +90°)
        let mid = north.pose(atDistance: 1000)
        XCTAssertEqual(wrap(mid.heading), Double.pi / 2, accuracy: 1e-6)
        XCTAssertEqual(mid.x, -6, accuracy: 1e-6)
        // Die Kehre bleibt innerhalb der Linie (nicht über den Endpunkt hinaus) und nah an der Strecke
        var maxNorth = -Double.infinity, maxEast = -Double.infinity, minEast = Double.infinity
        var d = 960.0
        while d <= 1040 {
            let p = north.pose(atDistance: d)
            maxNorth = max(maxNorth, -p.z); maxEast = max(maxEast, p.x); minEast = min(minEast, p.x)
            d += 0.25
        }
        XCTAssertLessThanOrEqual(maxNorth, 1000)
        XCTAssertLessThan(maxEast, 10)
        XCTAssertGreaterThan(minEast, -25)
        // Ausserhalb der Wende ist alles wieder auf den Linien
        XCTAssertEqual(north.pose(atDistance: 960).x, 0, accuracy: 1e-9)
        XCTAssertEqual(north.pose(atDistance: 1040).x, -12, accuracy: 1e-9)
    }

    func testSemicircleWhenBlendSmall() {
        let t = CourseTrack(course: .straight(oneWay: 1000), returnOffset: 12, turnBlend: 0)
        XCTAssertEqual(t.turnRadius, 6, accuracy: 1e-9)
        assertSmooth(t, step: 0.25, maxJumpFactor: 1.001, maxHeadingStep: 0.05)
        XCTAssertEqual(t.pose(atDistance: 1500).x, -12, accuracy: 1e-9)
    }

    func testProgressRemainingFinished() {
        let half = north.pose(atDistance: 1000)
        XCTAssertEqual(half.progress, 0.5, accuracy: 1e-12)
        XCTAssertEqual(half.remaining, 1000, accuracy: 1e-9)
        XCTAssertFalse(half.finished)
        XCTAssertEqual(half.leg, 0)
        XCTAssertEqual(north.pose(atDistance: 1000.5).leg, 1)

        let end = north.pose(atDistance: 2000)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.progress, 1, accuracy: 1e-12)
        XCTAssertEqual(end.remaining, 0, accuracy: 1e-12)
        XCTAssertEqual(end.x, -12, accuracy: 1e-9)
        XCTAssertEqual(end.z, 0, accuracy: 1e-9)

        let over = north.pose(atDistance: 2500)
        XCTAssertTrue(over.finished)
        XCTAssertEqual(over.progress, 1, accuracy: 1e-12)
        XCTAssertEqual(over.x, end.x, accuracy: 1e-9)

        let before = north.pose(atDistance: -10)
        XCTAssertEqual(before.progress, 0)
        XCTAssertEqual(before.remaining, 2000, accuracy: 1e-9)
        XCTAssertFalse(before.finished)

        let nan = north.pose(atDistance: .nan)
        XCTAssertEqual(nan.progress, 0)
        XCTAssertFalse(nan.x.isNaN)
    }

    func testOneWayCourseWithoutTurn() {
        var c = Course.straight(oneWay: 1000)
        c.turns = 0
        let t = CourseTrack(course: c)
        XCTAssertEqual(t.totalLength, 1000, accuracy: 1e-9)
        let end = t.pose(atDistance: 1000)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.z, -1000, accuracy: 1e-9)
        XCTAssertEqual(end.leg, 0)
    }

    /// Linienlänge und one_way_m weichen leicht ab: die Strecke hat trotzdem genau die angegebene Länge.
    func testLengthFromCourseMetadata() {
        var c = Course.straight(oneWay: 1000)
        c.oneWayM = 1001
        let t = CourseTrack(course: c)
        XCTAssertEqual(t.totalLength, 2002, accuracy: 1e-9)
        XCTAssertEqual(t.pose(atDistance: 900).z, -1000 * 900 / 1001, accuracy: 1e-6)
    }

    // MARK: echte Strecke

    private func loadCourse(_ id: String) throws -> Course {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RowCoachKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // RowCoachKit
            .deletingLastPathComponent()   // App
            .deletingLastPathComponent()   // Projektwurzel
        let url = root.appendingPathComponent("courses/\(id)/course.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Kartenpaket fehlt: \(url.path)")
        }
        return try Course.decode(Data(contentsOf: url))
    }

    func testRealCourseUtoquai() throws {
        let c = try loadCourse("zuerichsee-utoquai")
        XCTAssertEqual(c.id, "zuerichsee-utoquai")
        XCTAssertEqual(c.turns, 1)
        let t = CourseTrack(course: c)
        XCTAssertEqual(t.oneWayLength, 2000, accuracy: 1e-9)
        XCTAssertEqual(t.totalLength, 4000, accuracy: 1e-9)

        let start = t.pose(atDistance: 0)
        XCTAssertEqual(start.x, c.pathXZ[0][0], accuracy: 1e-6)
        XCTAssertEqual(start.z, c.pathXZ[0][1], accuracy: 1e-6)
        // Startrichtung = erstes Segment
        let dx = c.pathXZ[1][0] - c.pathXZ[0][0], dz = c.pathXZ[1][1] - c.pathXZ[0][1]
        XCTAssertEqual(wrap(start.heading - atan2(-dx, -dz)), 0, accuracy: 1e-6)

        // Rückfahrt 12 m rechts in Fahrtrichtung
        let out = t.pose(atDistance: 1000), back = t.pose(atDistance: 3000)
        let d = dir(back.heading)
        let v = (x: back.x - out.x, z: back.z - out.z)
        XCTAssertEqual(v.x * -d.z + v.z * d.x, 12, accuracy: 0.05)
        XCTAssertEqual(hypot(v.x, v.z), 12, accuracy: 0.05)

        // Ziel liegt 12 m neben dem Start
        let end = t.pose(atDistance: 4000)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(hypot(end.x - start.x, end.z - start.z), 12, accuracy: 0.05)

        // Rückfahrt in Gegenrichtung zur Hinfahrt
        XCTAssertEqual(abs(wrap(back.heading - out.heading)), Double.pi, accuracy: 0.05)

        // stetig über die ganze Strecke (Rückfahrt auf Aussenkurven etwas länger)
        assertSmooth(t, step: 0.25, maxJumpFactor: 1.3, maxHeadingStep: 0.03)
    }

    func testRealCourseMythenquai() throws {
        let c = try loadCourse("zuerichsee-mythenquai")
        let t = CourseTrack(course: c)
        XCTAssertEqual(t.totalLength, 4000, accuracy: 1e-9)
        assertSmooth(t, step: 0.5, maxJumpFactor: 1.3, maxHeadingStep: 0.05)
    }

    private func assertSmooth(_ t: CourseTrack, step: Double, maxJumpFactor: Double, maxHeadingStep: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        var prev = t.pose(atDistance: 0)
        var maxJump = 0.0, maxDH = 0.0
        var d = step
        while d <= t.totalLength + 1e-9 {
            let p = t.pose(atDistance: d)
            maxJump = max(maxJump, hypot(p.x - prev.x, p.z - prev.z))
            maxDH = max(maxDH, abs(wrap(p.heading - prev.heading)))
            prev = p
            d += step
        }
        XCTAssertLessThanOrEqual(maxJump, step * maxJumpFactor + 1e-9, "Positionssprung", file: file, line: line)
        XCTAssertLessThanOrEqual(maxDH, maxHeadingStep, "Richtungssprung", file: file, line: line)
    }
}
