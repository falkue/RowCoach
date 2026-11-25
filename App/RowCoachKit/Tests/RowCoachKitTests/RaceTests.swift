import XCTest
@testable import RowCoachKit

final class RaceClockTests: XCTestCase {
    func testOffsetFromSymmetricRoundTrip() {
        var c = RaceClock()
        // Server geht 100 s vor, Laufzeit 0,2 s symmetrisch
        c.addSample(sentLocal: 1000, server: 1100.1, receivedLocal: 1000.2)
        XCTAssertEqual(c.offset, 100, accuracy: 1e-9)
        XCTAssertEqual(c.serverTime(local: 1001), 1101, accuracy: 1e-9)
        XCTAssertEqual(c.localTime(server: 1101), 1001, accuracy: 1e-9)
        XCTAssertEqual(c.countdown(to: 1110, local: 1000), 10, accuracy: 1e-9)
        XCTAssertEqual(c.raceTime(start: 1090, local: 1000), 10, accuracy: 1e-9)
    }

    func testShortRoundTripsWin() {
        var c = RaceClock()
        c.addSample(sentLocal: 0, server: 50.05, receivedLocal: 0.1)    // gut: 50
        c.addSample(sentLocal: 10, server: 61.5, receivedLocal: 13)     // schlecht (asymmetrisch): 50
        c.addSample(sentLocal: 20, server: 70.04, receivedLocal: 20.08) // gut: 50
        c.addSample(sentLocal: 30, server: 80.05, receivedLocal: 30.1)  // gut: 50
        c.addSample(sentLocal: 40, server: 95, receivedLocal: 42)       // Ausreisser: 54
        XCTAssertEqual(c.offset, 50, accuracy: 0.01)
        XCTAssertEqual(c.bestRoundTrip ?? 0, 0.08, accuracy: 1e-9)
    }

    func testRejectsNegativeRoundTrip() {
        var c = RaceClock(offset: 3)
        c.addSample(sentLocal: 10, server: 99, receivedLocal: 9)
        XCTAssertEqual(c.offset, 3)
        XCTAssertFalse(c.isSynchronized)
    }
}

final class RacePublishThrottleTests: XCTestCase {
    func testRates() {
        var t = RacePublishThrottle(minInterval: 0.33, minStrokeInterval: 0.15, heartbeat: 1)
        XCTAssertTrue(t.shouldSend(now: 0, distance: 0))
        XCTAssertFalse(t.shouldSend(now: 0.1, distance: 1))
        XCTAssertTrue(t.shouldSend(now: 0.2, distance: 1, stroke: true))
        XCTAssertFalse(t.shouldSend(now: 0.3, distance: 2))
        XCTAssertTrue(t.shouldSend(now: 0.6, distance: 3))
        // keine Bewegung: erst nach dem Herzschlag
        XCTAssertFalse(t.shouldSend(now: 1.0, distance: 3))
        XCTAssertTrue(t.shouldSend(now: 1.61, distance: 3))
    }
}

final class RemoteRowerTrackerTests: XCTestCase {
    private func frame(_ seq: Int, t: Double, d: Double, pace: Double = 125, finished: Bool = false) -> LiveFrame {
        LiveFrame(participantId: "b", raceId: "r", seq: seq, sentAt: t, raceTime: t, distance: d, pace: pace,
                  strokeRate: 24, finished: finished, finishTime: finished ? t : nil)
    }

    func testInterpolatesWithDelay() {
        var tr = RemoteRowerTracker(delay: 0.4)
        tr.receive(frame(1, t: 10, d: 40), receivedLocal: 0)
        tr.receive(frame(2, t: 10.5, d: 42), receivedLocal: 0)
        tr.receive(frame(3, t: 11, d: 44), receivedLocal: 0)
        // Rennzeit 11,15 → gezeigt bei 10,75: Mitte zwischen 42 und 44
        XCTAssertEqual(tr.position(atRaceTime: 11.15)?.distance ?? 0, 43, accuracy: 1e-9)
    }

    func testExtrapolatesFromPaceAndCaps() {
        var tr = RemoteRowerTracker(delay: 0.4, maxExtrapolation: 2)
        tr.receive(frame(1, t: 10, d: 40, pace: 125), receivedLocal: 0)  // 4 m/s
        XCTAssertEqual(tr.position(atRaceTime: 11.4)?.distance ?? 0, 44, accuracy: 1e-9)
        // höchstens 2 s voraus
        XCTAssertEqual(tr.position(atRaceTime: 30)?.distance ?? 0, 48, accuracy: 1e-9)
    }

    func testExtrapolatesFromFramesWithoutPace() {
        var tr = RemoteRowerTracker(delay: 0)
        tr.receive(frame(1, t: 0, d: 0, pace: 0), receivedLocal: 0)
        tr.receive(frame(2, t: 1, d: 5, pace: 0), receivedLocal: 0)
        XCTAssertEqual(tr.position(atRaceTime: 2)?.distance ?? 0, 10, accuracy: 1e-9)
    }

    func testDropsOldAndDuplicateFrames() {
        var tr = RemoteRowerTracker()
        XCTAssertTrue(tr.receive(frame(5, t: 5, d: 20), receivedLocal: 0))
        XCTAssertFalse(tr.receive(frame(4, t: 4, d: 16), receivedLocal: 0))
        XCTAssertFalse(tr.receive(frame(5, t: 5, d: 20), receivedLocal: 0))
        XCTAssertEqual(tr.frames.count, 1)
    }

    func testStaleAndFinished() {
        var tr = RemoteRowerTracker(staleAfter: 5)
        XCTAssertTrue(tr.isStale(local: 0))
        tr.receive(frame(1, t: 100, d: 1990), receivedLocal: 50)
        XCTAssertFalse(tr.isStale(local: 54))
        XCTAssertTrue(tr.isStale(local: 56))
        tr.receive(frame(2, t: 101, d: 2000, finished: true), receivedLocal: 56)
        XCTAssertEqual(tr.position(atRaceTime: 200)?.distance, 2000)
    }
}

final class RaceLanesTests: XCTestCase {
    func testOthersRightOfMeInLaneOrder() {
        let ps = [RaceParticipant(id: "a", displayName: "A", lane: 3), RaceParticipant(id: "me", displayName: "Ich", lane: 2),
                  RaceParticipant(id: "b", displayName: "B", lane: 1), RaceParticipant(id: "c", displayName: "C", lane: 4)]
        let o = RaceLanes(spacing: 7, maxSide: 2).lateralOffsets(participants: ps, me: "me")
        XCTAssertNil(o["me"])
        XCTAssertEqual(o["b"], -7)
        XCTAssertEqual(o["a"], -14)
        XCTAssertEqual(o["c"], -7)   // dritte Person teilt sich die erste Bahn
    }
}

final class RaceCoordinatorTests: XCTestCase {
    private let race = Race(id: "r1", courseId: "zuerichsee-utoquai", target: .distance(1000))
    private let me = RaceParticipant(id: "me", displayName: "Falk", lane: 2)

    func testStandingsAndGaps() {
        var c = RaceCoordinator(race: race, me: me, tracker: RemoteRowerTracker(delay: 0))
        c.setRoster([me, RaceParticipant(id: "a", displayName: "A", lane: 1), RaceParticipant(id: "b", displayName: "B", lane: 3)])
        c.receive(LiveFrame(participantId: "a", raceId: "r1", seq: 1, sentAt: 0, raceTime: 60, distance: 260, pace: 115,
                            strokeRate: 26), receivedLocal: 0)
        c.receive(LiveFrame(participantId: "b", raceId: "r1", seq: 1, sentAt: 0, raceTime: 60, distance: 230, pace: 130,
                            strokeRate: 22), receivedLocal: 0)
        _ = c.updateLocal(raceTime: 60, distance: 240, pace: 125, strokeRate: 24, local: 0)
        let s = c.states(raceTime: 60, myDistance: 240, mySpeed: 4, local: 0)
        XCTAssertEqual(s.map(\.participant.id), ["a", "b"])
        XCTAssertEqual(s[0].place, 1)
        XCTAssertEqual(s[1].place, 3)
        XCTAssertEqual(s[0].gapMeters, 20, accuracy: 1e-9)
        XCTAssertEqual(s[0].gapSeconds ?? 0, 5, accuracy: 1e-9)
        XCTAssertEqual(s[1].gapMeters, -10, accuracy: 1e-9)
        XCTAssertEqual(c.myPlace(raceTime: 60, myDistance: 240), 2)
        XCTAssertLessThan(s[0].lateral, 0)
    }

    func testOwnFinishInterpolatedAndFinishOrder() {
        var c = RaceCoordinator(race: race, me: me, throttle: RacePublishThrottle(minInterval: 0, minStrokeInterval: 0))
        _ = c.updateLocal(raceTime: 239, distance: 996, pace: 120, strokeRate: 24, local: 0)
        let f = c.updateLocal(raceTime: 240, distance: 1004, pace: 120, strokeRate: 24, local: 1)
        XCTAssertEqual(f?.finished, true)
        XCTAssertEqual(f?.distance, 1000)
        XCTAssertEqual(f?.finishTime ?? 0, 239.5, accuracy: 1e-9)
        XCTAssertNil(c.updateLocal(raceTime: 241, distance: 1008, pace: 120, strokeRate: 24, local: 2), "nach dem Ziel nichts mehr")
        // Gegner kommt später an, ist aber „weiter“: Zielzeit zählt
        c.receive(LiveFrame(participantId: "x", raceId: "r1", seq: 1, sentAt: 0, raceTime: 241, distance: 1000, pace: 0,
                            strokeRate: 0, finished: true, finishTime: 240.2), receivedLocal: 0)
        let st = c.standings()
        XCTAssertEqual(st.map(\.participantId), ["me", "x"])
        XCTAssertEqual(st[0].time ?? 0, 239.5, accuracy: 1e-9)
    }

    func testTimeRaceRanksByDistance() {
        let r = Race(id: "t", courseId: "c", target: .time(600))
        var c = RaceCoordinator(race: r, me: me)
        let f = c.updateLocal(raceTime: 600, distance: 2400, pace: 125, strokeRate: 24, local: 0)
        XCTAssertEqual(f?.finished, true)
        c.receive(LiveFrame(participantId: "x", raceId: "t", seq: 1, sentAt: 0, raceTime: 600, distance: 2500, pace: 0,
                            strokeRate: 0, finished: true, finishTime: 600), receivedLocal: 0)
        XCTAssertEqual(c.standings().map(\.participantId), ["x", "me"])
    }

    func testIgnoresOwnAndForeignRaceFrames() {
        var c = RaceCoordinator(race: race, me: me)
        XCTAssertFalse(c.receive(LiveFrame(participantId: "me", raceId: "r1", seq: 1, sentAt: 0, raceTime: 1, distance: 1,
                                           pace: 0, strokeRate: 0), receivedLocal: 0))
        XCTAssertFalse(c.receive(LiveFrame(participantId: "z", raceId: "other", seq: 1, sentAt: 0, raceTime: 1, distance: 1,
                                           pace: 0, strokeRate: 0), receivedLocal: 0))
        XCTAssertTrue(c.receive(LiveFrame(participantId: "z", raceId: "r1", seq: 1, sentAt: 0, raceTime: 1, distance: 1,
                                          pace: 0, strokeRate: 0), receivedLocal: 0))
        XCTAssertTrue(c.roster.contains(where: { $0.id == "z" }), "unbekannter Absender kommt in die Liste")
    }

    func testEligibility() {
        let r = Race(id: "r", courseId: "rhein-basel", courseVersion: 3, target: .distance(2000))
        XCTAssertEqual(RaceEligibility.check(r) { id, v in id == "rhein-basel" && v == 3 }, .ready)
        XCTAssertEqual(RaceEligibility.check(r) { _, _ in false }, .needsCourse(courseId: "rhein-basel", version: 3))
    }

    func testCodableRoundTrip() throws {
        let r = Race(id: "r", tournamentId: "t", courseId: "c", target: .plan("pyramide"), scheduledStart: 123, lanes: 4)
        XCTAssertEqual(try JSONDecoder().decode(Race.self, from: JSONEncoder().encode(r)), r)
        let f = LiveFrame(participantId: "p", raceId: "r", seq: 3, sentAt: 1, raceTime: 2, distance: 3, pace: 120,
                          strokeRate: 24, heartRate: 150)
        let data = try JSONEncoder().encode(f)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"spm\":24"))
        XCTAssertEqual(try JSONDecoder().decode(LiveFrame.self, from: data), f)
    }
}

final class GhostRowerTests: XCTestCase {
    func testReplayInterpolatesAndFinishes() {
        let samples = (0...200).map { WorkoutSample(time: Double($0), distance: Double($0) * 5, pace: 100, strokeRate: 30,
                                                    power: 0, heartRate: nil) }
        let g = GhostRower(participant: RaceParticipant(id: "ghost", displayName: "Bestfahrt", lane: 1, source: .ghost),
                           samples: samples, finishDistance: 500)
        XCTAssertEqual(g.finishTime ?? 0, 100, accuracy: 1e-9)
        let f = g.frame(raceId: "r", seq: 1, raceTime: 10.5, sentAt: 0)
        XCTAssertEqual(f.distance, 52.5, accuracy: 1e-9)
        XCTAssertFalse(f.finished)
        let end = g.frame(raceId: "r", seq: 2, raceTime: 150, sentAt: 0)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.distance, 500)
        XCTAssertEqual(end.finishTime ?? 0, 100, accuracy: 1e-9)
    }

    func testSteadyBot() {
        let g = GhostRower.steady(participant: RaceParticipant(id: "bot", displayName: "Bot", lane: 3, source: .bot),
                                  pace: 125, duration: 600)
        XCTAssertEqual(g.frame(raceId: "r", seq: 1, raceTime: 100, sentAt: 0).distance, 400, accuracy: 1e-9)
    }
}

final class RaceTransportTests: XCTestCase {
    private func collect(_ stream: AsyncStream<LiveFrame>, count: Int) async -> [LiveFrame] {
        var out: [LiveFrame] = []
        for await f in stream {
            out.append(f)
            if out.count >= count { break }
        }
        return out
    }

    func testLoopbackRaceWithThreeParticipants() async throws {
        let hub = LoopbackRaceHub(clockOffset: 42)
        let race = Race(id: "r", courseId: "c", target: .distance(500), lanes: 3)
        let people = (1...3).map { RaceParticipant(id: "p\($0)", displayName: "P\($0)", lane: $0) }
        let ts = people.map { _ in LoopbackRaceTransport(hub: hub) }
        for (t, p) in zip(ts, people) { _ = try await t.join(race: race, as: p) }

        // Uhr: Server geht 42 s vor
        var clock = RaceClock()
        let t0 = Date().timeIntervalSince1970
        let server = try await ts[0].serverTime()
        clock.addSample(sentLocal: t0, server: server, receivedLocal: Date().timeIntervalSince1970)
        XCTAssertEqual(clock.offset, 42, accuracy: 0.05)

        // volle Bahnen: vierte Person wird abgewiesen
        let extra = LoopbackRaceTransport(hub: hub)
        do {
            _ = try await extra.join(race: race, as: RaceParticipant(id: "p4", displayName: "P4", lane: 4))
            XCTFail("Rennen ist voll")
        } catch {
            XCTAssertEqual(error as? RaceTransportError, .raceFull)
        }

        // jede Person sendet zwei Frames; jede empfängt nur die der anderen
        for (i, (t, p)) in zip(ts, people).enumerated() {
            for n in 1...2 {
                try await t.publish(LiveFrame(participantId: p.id, raceId: "r", seq: n, sentAt: 0, raceTime: Double(n),
                                              distance: Double(n * 4 + i), pace: 125, strokeRate: 24))
            }
        }
        let got = await collect(ts[0].frames, count: 4)
        XCTAssertEqual(Set(got.map(\.participantId)), ["p2", "p3"])

        // Koordinator von p1 mit den empfangenen Frames
        var c = RaceCoordinator(race: race, me: people[0], tracker: RemoteRowerTracker(delay: 0))
        c.setRoster(people)
        for f in got { c.receive(f, receivedLocal: 0) }
        let s = c.states(raceTime: 2, myDistance: 8, mySpeed: 4, local: 0)
        XCTAssertEqual(s.map(\.participant.id), ["p3", "p2"])   // p3: 10 m, p2: 9 m
        XCTAssertEqual(s[0].place, 1)

        await ts[1].leave()
        var rosterAfterLeave: [RaceParticipant] = []
        for await l in ts[0].roster {
            rosterAfterLeave = l
            if l.count == 2, !l.contains(where: { $0.id == "p2" }) { break }
        }
        XCTAssertEqual(rosterAfterLeave.map(\.id), ["p1", "p3"])
        for t in ts { await t.leave() }
    }

    func testGhostTransportEmitsFrames() async throws {
        let ghost = GhostRower.steady(participant: RaceParticipant(id: "g", displayName: "Bestfahrt", lane: 1, source: .ghost),
                                      pace: 100, duration: 60)
        let start = Date().timeIntervalSince1970
        let t = GhostRaceTransport(ghosts: [ghost], rate: 20) { Date().timeIntervalSince1970 - start + 10 }
        let roster = try await t.join(race: Race(id: "r", courseId: "c", target: .distance(1000)),
                                      as: RaceParticipant(id: "me", displayName: "Ich", lane: 2))
        XCTAssertEqual(roster.map(\.id), ["g", "me"])
        let frames = await collect(t.frames, count: 3)
        XCTAssertEqual(frames.count, 3)
        XCTAssertGreaterThanOrEqual(frames[0].distance, 50)   // Rennzeit ≥ 10 s bei 5 m/s
        XCTAssertLessThan(frames[0].seq, frames[2].seq)
        await t.leave()
    }

    @MainActor
    func testRaceLinkConnectsAndPublishes() async throws {
        let hub = LoopbackRaceHub()
        let race = Race(id: "r", courseId: "c", target: .distance(1000), lanes: 4)
        let other = LoopbackRaceTransport(hub: hub)
        _ = try await other.join(race: race, as: RaceParticipant(id: "o", displayName: "O", lane: 1))
        let link = RaceLink(coordinator: RaceCoordinator(race: race, me: RaceParticipant(id: "me", displayName: "Ich", lane: 2)),
                            transports: [LoopbackRaceTransport(hub: hub)])
        try await link.connect()
        XCTAssertEqual(Set(link.coordinator.roster.map(\.id)), ["o", "me"])
        link.update(raceTime: 1, distance: 4, pace: 125, strokeRate: 24)
        var received: LiveFrame?
        for await f in other.frames { received = f; break }
        XCTAssertEqual(received?.participantId, "me")
        try await other.publish(LiveFrame(participantId: "o", raceId: "r", seq: 1, sentAt: 0, raceTime: 1, distance: 6,
                                          pace: 125, strokeRate: 24))
        for _ in 0..<50 where link.coordinator.trackers["o"] == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(link.coordinator.trackers["o"])
        await link.disconnect()
        await other.leave()
    }
}

final class RaceStartMarkTests: XCTestCase {
    func testMarksOnce() {
        let m = RaceStartMark()
        XCTAssertNil(m.raceTime(local: 5))
        m.markIfNeeded(local: 100)
        m.markIfNeeded(local: 200)
        XCTAssertEqual(m.raceTime(local: 130), 30)
        m.reset()
        XCTAssertNil(m.raceTime(local: 130))
    }
}

final class RaceLinkGhostTests: XCTestCase {
    /// Ablauf wie in der App (`RowingView.demoRace` + `SessionController.feedRace`): Bots starten mit dem ersten
    /// eigenen Stand und erscheinen danach in `states`.
    @MainActor
    func testDemoRaceFlowShowsBots() async throws {
        let race = Race(id: "demo", courseId: "c", target: .distance(2000), lanes: 3)
        let bots = [
            GhostRower.steady(participant: RaceParticipant(id: "bot-a", displayName: "Anna", lane: 1, source: .bot),
                              pace: 110, duration: 3600, finishDistance: 2000),
            GhostRower.steady(participant: RaceParticipant(id: "bot-b", displayName: "Ben", lane: 3, source: .bot),
                              pace: 130, duration: 3600, finishDistance: 2000),
        ]
        let mark = RaceStartMark()
        let transport = GhostRaceTransport(ghosts: bots, rate: 20) { mark.raceTime(local: Date().timeIntervalSince1970) }
        let link = RaceLink(coordinator: RaceCoordinator(race: race, me: RaceParticipant(id: "me", displayName: "Ich", lane: 2)),
                            transports: [transport], start: mark)
        var changes = 0
        link.onChange = { changes += 1 }
        try await link.connect()
        let start = Date()
        var states: [RemoteRowerState] = []
        for _ in 0..<100 {
            let t = Date().timeIntervalSince(start)
            link.update(raceTime: t, distance: t * 4, pace: 125, strokeRate: 24, stroke: true)
            states = link.states(raceTime: t, myDistance: t * 4, mySpeed: 4)
            if states.count == 2 && t > 0.6 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(states.map(\.participant.displayName).sorted(), ["Anna", "Ben"])
        XCTAssertGreaterThan(changes, 0)
        await link.disconnect()
    }
}

final class RaceTagLayoutTests: XCTestCase {
    func testScaleAndAnchor() {
        let l = RaceTagLayout()
        XCTAssertEqual(l.scale(cameraDistance: 5), 1)
        XCTAssertEqual(l.scale(cameraDistance: 20), 2, accuracy: 1e-9)
        XCTAssertEqual(l.scale(cameraDistance: 400), 4)
        // erste Bahn: genau 1,45 m, egal wie gross die Schrift ist
        XCTAssertEqual(l.anchorHeight(lateral: -7, scale: 4), 1.45, accuracy: 1e-9)
        // zweite Bahn: leicht angehoben, höchstens eine halbe Schrifthöhe × Massstab
        let h = l.anchorHeight(lateral: -14, scale: 4)
        XCTAssertEqual(h, 1.45 + 0.35 * 0.30 * 4, accuracy: 1e-9)
        XCTAssertLessThan(h - 1.45, 0.5 * 0.30 * 4)
        XCTAssertEqual(l.anchorHeight(lateral: -21, scale: 4), 1.45, accuracy: 1e-9)
        XCTAssertEqual(l.slot(lateral: 0), 1)
    }
}
