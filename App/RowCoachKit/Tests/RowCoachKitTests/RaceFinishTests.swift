import XCTest
@testable import RowCoachKit

/// Rennziel kürzer als die Strecke (Online-Rennen über 500 m auf einer 4-km-Strecke, Mac-Test 28.11.): Ziel der
/// Fahrt, „Bis zum Ziel“, Fortschritt, Zieleinlauf, Zusammenfassung und Platz nach dem Ziel.
final class RaceFinishTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func snap(_ d: Double, strokes: Int) -> RowingSnapshot {
        var s = RowingSnapshot()
        s.distance = d
        s.strokeCount = strokes
        s.strokeRate = 24
        s.power = 200
        s.pace = 125
        return s
    }

    func testSessionFinishesAtRaceDistance() {
        var s = RowingSession(track: CourseTrack(course: .straight(oneWay: 4276)))
        s.setFinishDistance(500)
        XCTAssertEqual(s.targetLength, 500)
        XCTAssertEqual(s.remaining, 500, "„Bis zum Ziel“ = Renndistanz, nicht Streckenlänge")
        var raw = 0.0, strokes = 0, finished = false
        for i in 1...400 where !finished {
            raw += 2
            if i % 5 == 0 { strokes += 1 }
            let events = s.update(snap(raw, strokes: strokes), at: t0.addingTimeInterval(Double(i) * 0.5))
            finished = events.contains(.finished)
        }
        XCTAssertTrue(finished, "Ziel bei 500 m")
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.distance, 500, accuracy: 1e-9)
        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.progress, 1)
        XCTAssertTrue(s.completedCourse)
        let rec = s.makeRecord(device: WorkoutDevice(source: .simulator), zones: nil, raceId: "r1")
        XCTAssertTrue(rec.summary.completedCourse, "Zusammenfassung: Ziel erreicht")
        XCTAssertEqual(rec.header.raceDistance, 500)
        XCTAssertEqual(rec.header.courseLength ?? 0, CourseTrack(course: .straight(oneWay: 4276)).totalLength, accuracy: 1e-9)
        XCTAssertFalse(TrainingSession(record: rec, plan: nil).isFullCourseRun, "keine Bestzeit der ganzen Strecke")
        // Kodierung hin und zurück
        let back = try? JSONDecoder().decode(WorkoutHeader.self, from: JSONEncoder().encode(rec.header))
        XCTAssertEqual(back?.raceDistance, 500)
    }

    func testFinishDistanceOnlyBeforeStartAndShorterThanCourse() {
        var s = RowingSession(track: CourseTrack(course: .straight(oneWay: 1000)))
        s.setFinishDistance(5000)
        XCTAssertNil(s.finishDistance, "länger als die Strecke: Streckenende bleibt Ziel")
        _ = s.update(snap(0, strokes: 0), at: t0)
        _ = s.update(snap(4, strokes: 1), at: t0.addingTimeInterval(1))
        s.setFinishDistance(200)
        XCTAssertNil(s.finishDistance, "nach dem Start nicht mehr")
    }

    func testPlaceAfterFinishByFinishTime() {
        var planner = RaceScenePlanner(config: .init(budget: .a12x))
        // a: voller Frame mit Zielzeit 95 s (vor mir), b: Übersicht „im Ziel“ ohne Zeit, schon vor mir im Ziel,
        // c: noch unterwegs
        var members = [
            RaceFieldMember(id: "a", distance: 500, speed: 0, finished: true, precise: true, finishTime: 95),
            RaceFieldMember(id: "b", distance: 500, speed: 0, finished: true),
            RaceFieldMember(id: "c", distance: 470, speed: 4),
        ]
        var plan = planner.plan(members: members, me: RaceSelf(id: "me", distance: 480, speed: 4), now: 0)
        XCTAssertEqual(plan.summary.place, 3, "vor dem Ziel: hinter allen im Ziel")
        // ich im Ziel mit 100 s; danach kommt d ins Ziel (nur Übersicht, ohne Zeit) – bleibt hinter mir
        members.append(RaceFieldMember(id: "d", distance: 499, speed: 4))
        plan = planner.plan(members: members, me: RaceSelf(id: "me", distance: 500, speed: 0, finished: true, finishTime: 100),
                            now: 1)
        XCTAssertEqual(plan.summary.place, 3, "a (95 s) und b (vor mir im Ziel) vor mir")
        members[3].finished = true
        members[3].distance = 500
        members[2].finished = true
        members[2].distance = 500
        members[2].finishTime = 99   // c mit Zielzeit vor mir (voller Frame kam spät)
        plan = planner.plan(members: members, me: RaceSelf(id: "me", distance: 500, speed: 0, finished: true, finishTime: 100),
                            now: 2)
        XCTAssertEqual(plan.summary.place, 4, "c mit 99 s vor mir, d (nach mir ins Ziel) dahinter")
        XCTAssertEqual(plan.summary.total, 5)
    }
}
