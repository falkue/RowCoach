import XCTest
@testable import RowCoachKit

/// Abstand nach vorne/hinten in der Feld-Anzeige (Mac-Test 27.11.2026: stand immer auf „0 m · 0.0 s“)
final class RaceFieldGapTests: XCTestCase {
    @MainActor
    func testGapsFromBotFieldThroughPlanner() async throws {
        let field = RaceBotField(config: .init(count: 120, referencePace: 120, seed: 3))
        let tr = RaceBotTransport(field: field, rate: 4, raceTime: { 90 })
        let me = RaceParticipant(id: "me", displayName: "Ich", lane: 1)
        let race = Race(id: "r", courseId: "c", target: .distance(2000), lanes: 121)
        let link = RaceLink(coordinator: RaceCoordinator(race: race, me: me), transports: [tr])
        try await link.connect(clockSamples: 1)
        link.update(raceTime: 90, distance: 370, pace: 120, strokeRate: 26)
        for _ in 0..<30 where link.field.latest == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        var planner = RaceScenePlanner()
        let members = link.members(raceTime: 90, myDistance: 370, mySpeed: 4.17)
        let plan = planner.plan(members: members, me: RaceSelf(id: "me", distance: 370, speed: 4.17), now: 10)
        let s = plan.summary
        let ahead = members.map { $0.distance - 370 }.filter { $0 >= 0 }.min()
        let behind = members.map { $0.distance - 370 }.filter { $0 < 0 }.max()
        XCTAssertEqual(s.ahead?.gapMeters ?? -1, ahead ?? -1, accuracy: 1e-9)
        XCTAssertEqual(s.behind?.gapMeters ?? 1, behind ?? 1, accuracy: 1e-9)
        XCTAssertNotEqual(s.ahead?.gapMeters, 0)
        await link.disconnect()
    }

    /// Wie im Demo-Feld der App: Rennzeit läuft, eigener Stand alle 100 ms, Planer im selben Takt
    @MainActor
    func testGapsWhileRacing() async throws {
        final class Clock: @unchecked Sendable { var t: TimeInterval = 0 }
        let clock = Clock()
        let field = RaceBotField(config: .init(count: 60, referencePace: 120, finishDistance: 2000, seed: 5))
        let tr = RaceBotTransport(field: field, rate: 10, raceTime: { clock.t })
        let me = RaceParticipant(id: "me", displayName: "Ich", lane: 1)
        let race = Race(id: "r", courseId: "c", target: .distance(2000), lanes: 61)
        let link = RaceLink(coordinator: RaceCoordinator(race: race, me: me), transports: [tr])
        try await link.connect(clockSamples: 1)
        var planner = RaceScenePlanner()
        var nonZero = 0
        for step in 0..<30 {
            clock.t = 60 + Double(step) * 0.5
            let d = 4.17 * clock.t
            link.update(raceTime: clock.t, distance: d, pace: 120, strokeRate: 26)
            try await Task.sleep(nanoseconds: 60_000_000)
            let members = link.members(raceTime: clock.t, myDistance: d, mySpeed: 4.17)
            let s = planner.plan(members: members, me: RaceSelf(id: "me", distance: d, speed: 4.17),
                                 now: Double(step) * 0.5).summary
            if let a = s.ahead, abs(a.gapMeters) > 0.01 { nonZero += 1 }
        }
        XCTAssertGreaterThan(nonZero, 20)
        await link.disconnect()
    }

    /// In dichten Feldern ist das nächste Boot oft unter 1 m entfernt: Anzeige „gleichauf“ statt „0 m · 0.0 s“
    func testDisplayOfTinyGaps() {
        let field = RaceBotField(config: .init(count: 300, referencePace: 120, finishDistance: 2000, seed: 9))
        let me = 500.0 / 120 * 180
        var planner = RaceScenePlanner()
        let s = planner.plan(members: field.members(at: 180), me: RaceSelf(id: "me", distance: me, speed: 4.17),
                             now: 0).summary
        let ahead = try! XCTUnwrap(s.ahead)
        XCTAssertLessThan(abs(ahead.gapMeters), 1, "300 Boote: das nächste liegt unter 1 m")
        XCTAssertTrue(ahead.isLevel)
        let n = RaceFieldSummary.Neighbour(id: "x", gapMeters: -3.46, gapSeconds: nil)
        XCTAssertFalse(n.isLevel)
        XCTAssertEqual(n.displayMeters.value, 3.5, accuracy: 1e-9)
        XCTAssertEqual(n.displayMeters.decimals, 1)
        XCTAssertEqual(RaceFieldSummary.Neighbour(id: "y", gapMeters: 42.6, gapSeconds: nil).displayMeters.value, 43)
    }
}
