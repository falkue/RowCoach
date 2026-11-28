import XCTest
@testable import RowCoachKit

/// Strecken ohne Wende im Training: Kehre am Ziel und Rückfahrt (turn), Runde (loop), Ausblenden (fade)
final class EndBehaviorTests: XCTestCase {
    /// Gerade Einweg-Strecke nach Norden (−z), 1000 m, Punktabstand 2 m
    private func oneWay(_ length: Double = 1000, offset: Double? = nil, radius: Double? = nil,
                        behavior: Course.EndBehavior? = nil) -> Course {
        var c = Course.straight(id: "einweg", oneWay: length)
        c.turns = 0
        c.totalM = length
        c.returnOffsetM = offset
        c.turnRadiusM = radius
        c.endBehavior = behavior
        return c
    }

    private func angle(_ a: Double, _ b: Double) -> Double { atan2(sin(a - b), cos(a - b)) }

    /// über drei Runden stetig in Position und Richtung
    private func assertContinuous(_ laps: LapTrack, laps count: Double = 3, step: Double = 0.25,
                                  file: StaticString = #filePath, line: UInt = #line) {
        var prev = laps.pose(atDistance: 0)
        var d = step
        while d <= count * laps.lapLength {
            let p = laps.pose(atDistance: d)
            XCTAssertLessThanOrEqual(hypot(p.x - prev.x, p.z - prev.z), step + 0.01, "Sprung bei \(d) m",
                                     file: file, line: line)
            XCTAssertLessThan(abs(angle(p.heading, prev.heading)), 0.08, "Richtungssprung bei \(d) m",
                              file: file, line: line)
            prev = p
            d += step
        }
    }

    func testDefaultIsTurnWithReturnLeg() {
        let c = oneWay()
        XCTAssertEqual(c.resolvedEndBehavior, .turn)
        XCTAssertEqual(c.withReturnLeg.turns, 1)
        XCTAssertEqual(c.withReturnLeg.totalM, 2000)
        let laps = LapTrack(course: c)
        XCTAssertEqual(laps.endBehavior, .turn)
        XCTAssertEqual(laps.lapLength, 2000, accuracy: 1e-9, "eine Runde = hin und zurück")
        XCTAssertGreaterThan(laps.turnHalf, 0)
        // freies Rudern bleibt Einweg (endet am Ziel)
        XCTAssertEqual(CourseTrack(course: c).totalLength, 1000, accuracy: 1e-9)
    }

    /// Kehre am Ziel und Startkehre: kein Sprung, Rückfahrt in Gegenrichtung 12 m links
    func testOneWayTurnIsContinuousAndReturnsWithOffset() {
        let laps = LapTrack(course: oneWay())
        assertContinuous(laps)
        let back = laps.lapPose(atDistance: 1500)
        XCTAssertEqual(back.lap, 0)
        XCTAssertEqual(back.pose.leg, 1)
        // Station 500 m, links der Hinfahrt (Norden → links = Westen = −x)
        XCTAssertEqual(back.pose.z, -500, accuracy: 1e-6)
        XCTAssertEqual(back.pose.x, -12, accuracy: 1e-6)
        XCTAssertEqual(abs(angle(back.pose.heading, 0)), Double.pi, accuracy: 1e-6, "Gegenrichtung")
        // zweite Runde wieder auf der Hinfahrtlinie in Hinfahrtrichtung
        let again = laps.lapPose(atDistance: 2500)
        XCTAssertEqual(again.lap, 1)
        XCTAssertEqual(again.pose.x, 0, accuracy: 1e-6)
        XCTAssertEqual(again.pose.z, -500, accuracy: 1e-6)
        XCTAssertEqual(angle(again.pose.heading, 0), 0, accuracy: 1e-6)
        XCTAssertFalse(again.pose.finished)
    }

    /// Versatz 0 (Kanal, Brückenbögen): zurück auf derselben Linie, enge Kehre mit festem Radius
    func testReturnOnSameLineWithTightTurn() {
        let laps = LapTrack(course: oneWay(offset: 0, radius: 4.5))
        XCTAssertEqual(laps.track.turnRadius, 4.5, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(laps.turnHalf, CourseTrack.minTurnHalf, "enge Kehre dauert mindestens 2 × 15 m")
        assertContinuous(laps)
        let back = laps.pose(atDistance: 1500)
        XCTAssertEqual(back.x, 0, accuracy: 1e-6)
        XCTAssertEqual(back.z, -500, accuracy: 1e-6)
        XCTAssertEqual(abs(angle(back.heading, 0)), Double.pi, accuracy: 1e-6)
    }

    /// Schmale Strecke: Kehre bleibt in einem schmalen Band (Versatz 6 m, Radius 3 m: Halbkreis ≈ 0 … 6 m links)
    func testNarrowTurnStaysInBand() {
        let laps = LapTrack(course: oneWay(offset: 6, radius: 3))
        assertContinuous(laps)
        var minX = Double.infinity, maxX = -Double.infinity, minZ = Double.infinity
        var d = 1000 - laps.turnHalf
        while d <= 1000 + laps.turnHalf {
            let p = laps.pose(atDistance: d)
            minX = min(minX, p.x); maxX = max(maxX, p.x); minZ = min(minZ, p.z)
            d += 0.5
        }
        XCTAssertLessThanOrEqual(maxX, 0.01)
        XCTAssertGreaterThanOrEqual(minX, -6.01)
        XCTAssertGreaterThanOrEqual(minZ, -1000.01, "nicht über das Streckenende hinaus")
        // Startkehre ebenso
        minX = .infinity; maxX = -.infinity
        d = 2000 - laps.turnHalf
        while d <= 2000 + laps.turnHalf {
            let p = laps.pose(atDistance: d)
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            XCTAssertLessThanOrEqual(p.z, 0.01, "nicht hinter die Startlinie")
            d += 0.5
        }
        XCTAssertLessThanOrEqual(maxX, 0.01)
        XCTAssertGreaterThanOrEqual(minX, -6.01)
    }

    /// Distanzprogramm, das in der aktuellen Richtung endet: ohne Kehre gerade ins Ziel
    func testProgramEndingAtFinishGoesStraight() {
        let laps = LapTrack(course: oneWay(), endDistance: 1000)
        for d in [970.0, 990, 1000] {
            let p = laps.pose(atDistance: d)
            XCTAssertEqual(p.x, 0, accuracy: 1e-6, "bei \(d) m")
            XCTAssertEqual(p.z, -d, accuracy: 1e-6)
            XCTAssertEqual(angle(p.heading, 0), 0, accuracy: 1e-6)
        }
        // 1500 m: Kehre am Ziel, Ende auf der Rückfahrt
        let turning = LapTrack(course: oneWay(), endDistance: 1500).pose(atDistance: 990)
        XCTAssertGreaterThan(hypot(turning.x, turning.z + 990), 0.5)
    }

    /// Start nah am Ziel (U-förmige Runde ohne loop-Feld): bleibt Runde, Lücke stetig überblendet
    func testNearlyClosedCourseStaysLoop() {
        var pts: [[Double]] = []
        for z in stride(from: 0.0, through: 300, by: 2) { pts.append([0, -z]) }
        for x in stride(from: 2.0, through: 100, by: 2) { pts.append([x, -300]) }
        for z in stride(from: -298.0, through: 50, by: 2) { pts.append([100, z]) }
        for x in stride(from: 98.0, through: 30, by: -2) { pts.append([x, 50]) }
        for z in stride(from: 48.0, through: 20, by: -2) { pts.append([30, z]) }
        var c = Course(id: "fast-rund", title: "Fast rund", oneWayM: 0, totalM: 0, turns: 0, pathXZ: pts)
        let len = CourseTrack(course: c).oneWayLength
        c.oneWayM = len
        c.totalM = len
        XCTAssertLessThan(hypot(30, 20), Course.loopGapM)
        XCTAssertEqual(c.resolvedEndBehavior, .loop)
        let laps = LapTrack(course: c)
        XCTAssertEqual(laps.lapLength, len, accuracy: 1e-9)
        XCTAssertGreaterThan(laps.loopBlend, 0)
        var prev = laps.pose(atDistance: len - 100)
        var d = len - 99.75
        while d <= len + 50 {
            let p = laps.pose(atDistance: d)
            XCTAssertLessThan(hypot(p.x - prev.x, p.z - prev.z), 2.5, "Sprung bei \(d) m")
            prev = p
            d += 0.25
        }
        // echter Rundkurs ohne Lücke: keine Überblendung
        var ring = c
        ring.pathXZ.append(pts[0])
        ring.loop = true
        XCTAssertEqual(LapTrack(course: ring).endBehavior, .loop)
    }

    /// Kein Platz zum Wenden: Runde = Strecke, Sprung zum Start im Dunkeln
    func testFadeHidesJump() {
        let laps = LapTrack(course: oneWay(behavior: .fade))
        XCTAssertTrue(laps.fades)
        XCTAssertEqual(laps.lapLength, 1000, accuracy: 1e-9)
        XCTAssertEqual(laps.fadeOpacity(atDistance: 500), 0)
        XCTAssertEqual(laps.fadeOpacity(atDistance: 999.5), 1, accuracy: 1e-9)
        XCTAssertEqual(laps.fadeOpacity(atDistance: 1000.5), 1, accuracy: 1e-9)
        XCTAssertEqual(laps.fadeOpacity(atDistance: 1000 + LapTrack.fadeHalf + 1), 0)
        let after = laps.pose(atDistance: 1000.5)
        XCTAssertEqual(after.z, -0.5, accuracy: 1e-6, "wieder am Start")
        // letzte Runde eines Distanzprogramms: kein Ausblenden am Ende
        XCTAssertEqual(LapTrack(course: oneWay(behavior: .fade), endDistance: 1000).fadeOpacity(atDistance: 999.5), 0)
        // Strecken mit Wende blenden nie aus
        XCTAssertEqual(LapTrack(course: .straight()).fadeOpacity(atDistance: 2000), 0)
    }

    func testDecodingFieldsAndUnknownValue() throws {
        let base = #"{"id":"x","title":"X","region":"","scene":"","qualities":[],"one_way_m":1000,"total_m":1000,"turns":0,"lake_level_m":0,"path_xz":[[0,0],[0,-1000]],"attribution":"a""#
        let c = try Course.decode(Data((base + #","end_behavior":"turn","return_offset_m":-6,"turn_radius_m":3}"#).utf8))
        XCTAssertEqual(c.endBehavior, .turn)
        XCTAssertEqual(c.returnOffsetM, -6)
        XCTAssertEqual(c.turnRadiusM, 3)
        XCTAssertEqual(CourseTrack(course: c.withReturnLeg).returnOffset, -6)
        let u = try Course.decode(Data((base + #","end_behavior":"spirale"}"#).utf8))
        XCTAssertNil(u.endBehavior)
        XCTAssertEqual(u.resolvedEndBehavior, .turn)
    }

    /// Route für Apple Health über mehrere Runden mit Kehren: durchgehende Linie ohne Sprung
    func testRoutePointsAcrossTurnsAreContinuous() {
        var c = oneWay(offset: 0, radius: 4.5)
        c.crs = "EPSG:25833"
        c.origin = [605000, 5343800]
        c.id = "wien-test"
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // 3,5 Runden zu je 2000 m mit 4 m/s, ein Sample je Sekunde
        let samples = (0...1750).map { i in
            WorkoutSample(time: Double(i), distance: Double(i) * 4, pace: 125, strokeRate: 24, power: 200,
                          heartRate: 140)
        }
        let header = WorkoutHeader(startDate: start, endDate: start.addingTimeInterval(1750), courseId: c.id,
                                   courseTitle: c.title, courseLength: c.totalM, device: WorkoutDevice(source: .pm5),
                                   workoutPlanId: "plan")
        let summary = WorkoutSummary(distance: 7000, activeDuration: 1750, totalDuration: 1750, averagePace: 125,
                                     averageSpeed: 4, averageStrokeRate: 24, strokeCount: 700, averagePower: 200,
                                     maxPower: 250, calories: 400, averageHeartRate: 140, maxHeartRate: 160,
                                     heartRateZoneSeconds: nil, completedCourse: true, pauseCount: 0)
        let rec = WorkoutRecord(header: header, summary: summary, samples: samples, splits: [])
        let pts = RoutePoints.make(record: rec, course: c, planEndDistance: 7000)
        XCTAssertGreaterThan(pts.count, 1500)
        for i in 1..<pts.count {
            XCTAssertLessThan(RoutePoints.groundDistance(pts[i - 1], pts[i]), 6, "Sprung bei Punkt \(i)")
        }
        // am Ende der Hinfahrt gewendet: bei 1500 m (Rückfahrt) wieder bei Station 500, Richtung Süden
        let p = pts.first { abs($0.distance - 1500) < 0.01 }
        XCTAssertNotNil(p)
        if let p { XCTAssertEqual(p.course, 180, accuracy: 3) }
    }
}
