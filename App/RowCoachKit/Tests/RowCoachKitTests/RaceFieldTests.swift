import XCTest
@testable import RowCoachKit

// Grosse Felder: Übersicht, Nachbarschafts-Abo, Bot-Feld, Szenen-Planer (docs/MULTIPLAYER.md, „Grosse Felder“)

private func roster(_ n: Int) -> [RaceParticipant] {
    (0..<n).map { RaceParticipant(id: String(format: "u%03d", $0), displayName: "R\($0)", lane: $0 + 1) }
}

final class RaceFieldSnapshotTests: XCTestCase {
    func testBinaryRoundTripAndQuantisation() throws {
        let r = RaceRosterIndex(participants: roster(3))
        let s = RaceFieldSnapshot(raceId: "r1", seq: 42, sentAt: 1000.5, raceTime: 123.456, rosterHash: r.hash, entries: [
            RaceFieldEntry(index: 0, distance: 1234.567, pace: 118.34, strokeRate: 28),
            RaceFieldEntry(index: 1, distance: 2000, pace: 0, strokeRate: 0, finished: true),
            RaceFieldEntry(index: 2, distance: 10.04, pace: 130, strokeRate: 70, stale: true),
        ])
        let b = s.encodeBinary()
        XCTAssertEqual(b.count, RaceFieldSnapshot.headerBytes + 3 * RaceFieldSnapshot.bytesPerEntry)
        let d = try XCTUnwrap(RaceFieldSnapshot.decodeBinary(b, raceId: "r1", sentAt: 1000.5))
        XCTAssertEqual(d.seq, 42)
        XCTAssertEqual(d.raceTime, 123.46, accuracy: 1e-9)
        XCTAssertEqual(d.rosterHash, r.hash)
        XCTAssertEqual(d.entries[0].distance, 1234.6, accuracy: 1e-9)
        XCTAssertEqual(d.entries[0].pace, 118.3, accuracy: 1e-9)
        XCTAssertEqual(d.entries[0].strokeRate, 28)
        XCTAssertTrue(d.entries[1].finished)
        XCTAssertEqual(d.entries[2].strokeRate, 63, "Schlagzahl auf 6 Bit begrenzt")
        XCTAssertTrue(d.entries[2].stale)
        // JSON wie in der Realtime Database
        let json = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(RaceFieldSnapshot.self, from: json)
        XCTAssertEqual(back.entries.count, 3)
        XCTAssertEqual(back.raceId, "r1")
        XCTAssertNil(RaceFieldSnapshot.decodeBinary([2, 0, 0], raceId: "r", sentAt: 0))
    }

    func testByteBudgetFor300() {
        let r = RaceRosterIndex(participants: roster(300))
        let entries = (0..<300).map { RaceFieldEntry(index: $0, distance: Double($0) * 6.7, pace: 120, strokeRate: 26) }
        let s = RaceFieldSnapshot(raceId: "r", seq: 1, sentAt: 0, raceTime: 300, rosterHash: r.hash, entries: entries)
        XCTAssertEqual(s.encodeBinary().count, 2415)
        XCTAssertEqual(s.wireBytes, 3220)
        XCTAssertLessThanOrEqual(Double(s.wireBytes) / 300, 11, "≤ 11 Byte je Teilnehmendem auf dem Draht")
        let json = try! JSONEncoder().encode(s)
        XCTAssertLessThan(json.count, 3300)
        // Datenmenge je Gerät: ohne Nachbarschaft ~110 KB/s, mit K = 16 und Übersicht < 10 KB/s
        let b = RaceDataBudget()
        XCTAssertEqual(b.naiveDownload(participants: 300), 112_125, accuracy: 1)
        let mine = b.download(participants: 300, neighbours: 16)
        XCTAssertLessThan(mine, 10_000)
        XCTAssertGreaterThan(b.naiveDownload(participants: 300) / mine, 11)
    }

    func testRosterIndexStableAndHashDetectsDifferentLists() {
        let a = RaceRosterIndex(participants: roster(5).reversed())
        let b = RaceRosterIndex(participants: roster(5))
        XCTAssertEqual(a.ids, b.ids)
        XCTAssertEqual(a.hash, b.hash)
        XCTAssertNotEqual(RaceRosterIndex(participants: roster(4)).hash, b.hash)
        XCTAssertEqual(b.index(of: "u003"), 3)
        XCTAssertEqual(b.id(at: 4), "u004")
        XCTAssertNil(b.id(at: 5))
    }

    func testBuildExtrapolatesAndMarksStale() {
        let list = roster(3)
        let r = RaceRosterIndex(participants: list)
        let latest = [
            "u000": LiveFrame(participantId: "u000", raceId: "r", seq: 1, sentAt: 0, raceTime: 99, distance: 400, pace: 125, strokeRate: 26),
            "u001": LiveFrame(participantId: "u001", raceId: "r", seq: 1, sentAt: 0, raceTime: 90, distance: 350, pace: 125, strokeRate: 26),
            "x": LiveFrame(participantId: "x", raceId: "r", seq: 1, sentAt: 0, raceTime: 99, distance: 1, pace: 125, strokeRate: 26),
        ]
        let s = RaceFieldSnapshot.build(raceId: "r", seq: 1, sentAt: 0, raceTime: 100, roster: r, latest: latest)
        XCTAssertEqual(s.entries.count, 2, "Unbekannte fehlen")
        XCTAssertEqual(s.entries[0].distance, 404, accuracy: 1e-9)
        XCTAssertFalse(s.entries[0].stale)
        XCTAssertEqual(s.entries[1].distance, 362, accuracy: 1e-9, "höchstens 3 s vorausgerechnet")
        XCTAssertTrue(s.entries[1].stale)
    }

    func testTrackerRejectsOldAndForeignSnapshots() {
        let list = roster(3)
        var t = RaceFieldTracker(participants: list)
        let r = RaceRosterIndex(participants: list)
        let s1 = RaceFieldSnapshot(raceId: "r", seq: 2, sentAt: 0, raceTime: 10, rosterHash: r.hash,
                                   entries: [RaceFieldEntry(index: 1, distance: 40, pace: 125, strokeRate: 24)])
        XCTAssertTrue(t.receive(s1, receivedLocal: 0))
        var old = s1; old.seq = 1
        XCTAssertFalse(t.receive(old, receivedLocal: 0))
        var foreign = s1; foreign.seq = 3; foreign.rosterHash &+= 1
        XCTAssertFalse(t.receive(foreign, receivedLocal: 0))
        XCTAssertEqual(t.rosterMismatches, 1)
        let st = t.states(atRaceTime: 12)
        XCTAssertEqual(st.count, 1)
        XCTAssertEqual(st[0].id, "u001")
        XCTAssertEqual(st[0].distance, 48, accuracy: 1e-9)
        XCTAssertEqual(t.states(atRaceTime: 100)[0].distance, 56, accuracy: 1e-9, "höchstens 4 s vorausgerechnet")
        XCTAssertTrue(t.states(atRaceTime: 12, exclude: "u001").isEmpty)
    }

    func testBuckets() {
        let b = RaceBuckets(size: 50)
        XCTAssertEqual(b.bucket(for: 0), 0)
        XCTAssertEqual(b.bucket(for: 149.9), 2)
        XCTAssertEqual(b.buckets(around: 500, ahead: 100, behind: 50), 9...12)
        XCTAssertEqual(b.buckets(around: 10), 0...2)
    }
}

final class RaceTransportFieldTests: XCTestCase {
    func testDefaultsKeepOldTransportsWorking() async throws {
        let ghost = GhostRaceTransport(ghosts: [], raceTime: { nil })
        var n = 0
        for await _ in ghost.fieldSnapshots { n += 1 }
        XCTAssertEqual(n, 0, "Standard: leerer, sofort beendeter Strom")
        await ghost.setInterest(RaceInterest(fullIds: ["a"]))
        await ghost.leave()
    }

    func testLoopbackInterestFiltersFramesAndBroadcastsField() async throws {
        let hub = LoopbackRaceHub()
        let race = Race(id: "big", courseId: "c", target: .distance(2000), lanes: 20)
        var transports: [LoopbackRaceTransport] = []
        for p in roster(20) {
            let t = LoopbackRaceTransport(hub: hub)
            _ = try await t.join(race: race, as: p)
            transports.append(t)
        }
        let me = transports[0]
        await me.setInterest(RaceInterest(fullIds: ["u001", "u002"]))
        for (i, t) in transports.enumerated() where i > 0 {
            try await t.publish(LiveFrame(participantId: String(format: "u%03d", i), raceId: "big", seq: 1, sentAt: 0,
                                          raceTime: 10, distance: Double(i) * 5, pace: 120, strokeRate: 26))
        }
        let snap = await hub.broadcastField(raceId: "big", raceTime: 10)
        XCTAssertEqual(snap?.entries.count, 19)
        var it = me.frames.makeAsyncIterator()
        let a = await it.next(), b = await it.next()
        XCTAssertEqual(Set([a?.participantId, b?.participantId].compactMap { $0 }), ["u001", "u002"])
        var fit = me.fieldSnapshots.makeAsyncIterator()
        let f = await fit.next()
        XCTAssertEqual(f?.entries.count, 19)
        var tracker = RaceFieldTracker(participants: roster(20))
        XCTAssertTrue(tracker.receive(try XCTUnwrap(f), receivedLocal: 0))
        XCTAssertEqual(tracker.states(atRaceTime: 10, exclude: "u000").count, 19)
        // u001 bekommt ohne Abo alle anderen 18
        let delivered = await hub.deliveredFrames
        XCTAssertEqual(delivered, 2 + 18 * 18 + 18, "Abo von u000: nur 2 statt 18")
        for t in transports { await t.leave() }
    }

    func testBotTransportNeighbourhoodAndSnapshot() async throws {
        let field = RaceBotField(config: .init(count: 300))
        let tr = RaceBotTransport(field: field, raceTime: { nil })
        let me = RaceParticipant(id: "me", displayName: "Ich", lane: 1)
        let list = try await tr.join(race: Race(id: "r", courseId: "c", target: .distance(2000), lanes: 301), as: me)
        XCTAssertEqual(list.count, 301)
        try await tr.publish(LiveFrame(participantId: "me", raceId: "r", seq: 1, sentAt: 0, raceTime: 120, distance: 480,
                                       pace: 120, strokeRate: 26))
        let near = tr.tick(raceId: "r", raceTime: 120, sentAt: 0)
        XCTAssertEqual(near.count, 16)
        let maxGap = near.map { abs($0.distance - 480) }.max() ?? 0
        let others = field.members(at: 120).map { abs($0.distance - 480) }.sorted()
        XCTAssertEqual(maxGap, others[15], accuracy: 1e-6, "die 16 nächsten")
        await tr.setInterest(RaceInterest(fullIds: ["bot-001", "bot-300"]))
        XCTAssertEqual(Set(tr.tick(raceId: "r", raceTime: 121, sentAt: 0).map(\.participantId)), ["bot-001", "bot-300"])
        let snap = tr.snapshot(raceId: "r", raceTime: 121, sentAt: 0)
        XCTAssertEqual(snap.entries.count, 301)
        var tracker = RaceFieldTracker(participants: list)
        XCTAssertTrue(tracker.receive(snap, receivedLocal: 0))
        XCTAssertEqual(tracker.states(atRaceTime: 121, exclude: "me").count, 300)
        await tr.leave()
    }

    @MainActor
    func testRaceLinkReceivesFieldAndMergesMembers() async throws {
        let field = RaceBotField(config: .init(count: 300))
        let tr = RaceBotTransport(field: field, rate: 4, raceTime: { 60 })
        let me = RaceParticipant(id: "me", displayName: "Ich", lane: 1)
        let race = Race(id: "r", courseId: "c", target: .distance(2000), lanes: 301)
        let link = RaceLink(coordinator: RaceCoordinator(race: race, me: me), transports: [tr])
        try await link.connect(clockSamples: 1)
        link.update(raceTime: 60, distance: 250, pace: 120, strokeRate: 26)
        for _ in 0..<30 where link.field.latest == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertNotNil(link.field.latest)
        let members = link.members(raceTime: 60.5, myDistance: 250, mySpeed: 4.17)
        XCTAssertEqual(members.count, 300)
        XCTAssertGreaterThanOrEqual(members.filter(\.precise).count, 16)
        XCTAssertFalse(members.contains { $0.id == "me" })
        await link.disconnect()
    }
}

final class RaceBotFieldTests: XCTestCase {
    func testDeterministicRealisticDistribution() {
        let a = RaceBotField(config: .init(count: 300, referencePace: 120, seed: 7))
        let b = RaceBotField(config: .init(count: 300, referencePace: 120, seed: 7))
        XCTAssertEqual(a.bots, b.bots)
        let paces = a.bots.map(\.basePace)
        let mean = paces.reduce(0, +) / Double(paces.count)
        let sd = (paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count)).squareRoot()
        XCTAssertEqual(mean, 120, accuracy: 3)
        XCTAssertGreaterThan(sd, 5)
        XCTAssertLessThan(sd, 12)
        XCTAssertGreaterThan(paces.filter { $0 < 110 }.count, 5, "einige deutlich schneller")
        XCTAssertGreaterThan(paces.filter { $0 > 130 }.count, 5, "einige deutlich langsamer")
        // Ermüdung: zweite Hälfte im Mittel langsamer als die erste (ohne Endspurt)
        var slower = 0
        for i in a.bots.indices {
            let b = a.bots[i]
            let first = RaceBotField.pace(bot: b, config: a.config, time: 0, distance: 250)
            let second = RaceBotField.pace(bot: b, config: a.config, time: 0, distance: 1500)
            if second > first { slower += 1 }
        }
        XCTAssertGreaterThan(slower, 270)
        // alle kommen an, Zielzeiten plausibel (2000 m in 6–9 min), Ziel hält die Distanz
        let finishes = a.bots.indices.compactMap { a.position(of: $0, at: 900).finishTime }
        XCTAssertEqual(finishes.count, 300)
        XCTAssertGreaterThan(finishes.min()!, 330)
        XCTAssertLessThan(finishes.max()!, 660)
        XCTAssertEqual(a.position(of: 0, at: 899).distance, 2000, accuracy: 1e-9)
        let f = a.frame(of: 0, raceId: "r", seq: 1, raceTime: 899, sentAt: 0)
        XCTAssertTrue(f.finished)
    }
}

final class RaceFrameRateGovernorTests: XCTestCase {
    func testStepsDownFastAndUpSlowly() {
        var g = RaceFrameRateGovernor()
        for t in 0...1 { g.report(fps: 40, now: Double(t)) }
        XCTAssertEqual(g.level, 0, "erst nach 2 s")
        g.report(fps: 40, now: 2.5)
        XCTAssertEqual(g.level, 1)
        g.report(fps: 40, now: 4)
        XCTAssertEqual(g.level, 1, "Abkühlzeit")
        for t in stride(from: 5.0, through: 9, by: 1) { g.report(fps: 40, now: t) }
        XCTAssertEqual(g.level, 2)
        let b = g.apply(to: .a12x)
        XCTAssertEqual(b.full, 4)
        XCTAssertEqual(b.lite, 8)
        XCTAssertEqual(b.impostors, 24)
        for t in stride(from: 10.0, through: 40, by: 1) { g.report(fps: 60, now: t) }
        XCTAssertEqual(g.level, 0)
        var low = RaceFrameRateGovernor()
        for t in stride(from: 0.0, through: 200, by: 1) { low.report(fps: 20, now: t) }
        XCTAssertEqual(low.level, low.maxLevel)
        XCTAssertGreaterThanOrEqual(low.apply(to: .a12x).full, 3)
        XCTAssertGreaterThanOrEqual(low.apply(to: .a12x).lite, 4)
    }
}

final class RaceScenePlannerTests: XCTestCase {
    func testVisualLanesFromCourseTraffic() {
        var c = Course(id: "c", title: "C", oneWayM: 2000, totalM: 4000, turns: 1, pathXZ: [[0, 0], [0, -2000]])
        c.traffic = CourseTraffic(rowerLanes: TrafficDefaults.rowerLanes)
        let l = RaceVisualLanes.forCourse(c)
        XCTAssertEqual(l.right, 5)
        XCTAssertEqual(l.left, 0, "Gegenbahn links")
        c.traffic = CourseTraffic(rowerLanes: [.line(-9), .line(20, reverse: true)])
        c.turns = 0
        let o = RaceVisualLanes.forCourse(c)
        XCTAssertEqual(o.right, 2)
        XCTAssertEqual(o.left, 1)
        XCTAssertEqual(o.slots.first, 1)
        XCTAssertEqual(o.lateral(slot: 2), -14)
        XCTAssertEqual(o.lateral(slot: -1), 7)
    }

    func testMinSeparation() {
        XCTAssertEqual(RaceScenePlanner.minSeparation(20, -1, 6), 14)
        XCTAssertEqual(RaceScenePlanner.minSeparation(5, -2, 6), 0, "überholt im Horizont")
        XCTAssertEqual(RaceScenePlanner.minSeparation(-30, 0.5, 6), 27)
    }

    /// 300 Bots über ein ganzes 2000-m-Rennen, Planer im Bild-Takt (10/s): Budget, Stabilität, Abstände, Zeit
    func testFullRaceWith300Bots() {
        let field = RaceBotField(config: .init(count: 300, referencePace: 120, seed: 3))
        var planner = RaceScenePlanner(config: .init(budget: .a12x))
        let mySpeed = 500.0 / 121
        let marked: Set<String> = ["bot-010", "bot-200"]
        var calls = 0
        var elapsed: Double = 0
        var maxCall: Double = 0
        var perBoatChanges: [String: Int] = [:]
        var lastTier: [String: RaceRenderTier] = [:]
        var lastLateral: [String: Double] = [:]
        var lateralJumps = 0
        var overlaps = 0
        var minShown = Int.max
        var decisionTime: Double = 0
        var decidingConfig = RaceScenePlanner.Config(budget: .a12x)
        decidingConfig.decisionInterval = 0
        var deciding = RaceScenePlanner(config: decidingConfig)
        var decisions = 0
        let dt = 0.1
        let duration = 480.0
        var t = 0.0
        while t <= duration {
            let members = field.members(at: t, marked: marked)
            let me = RaceSelf(id: "me", distance: min(mySpeed * t, 2000), speed: mySpeed)
            let t0 = DispatchTime.now().uptimeNanoseconds
            let plan = planner.plan(members: members, me: me, now: t)
            let ns = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
            elapsed += ns
            if calls % 5 == 0 {
                // Entscheidungsschritt allein messen: zweiter Planer, der bei jedem Aufruf entscheidet
                let d0 = DispatchTime.now().uptimeNanoseconds
                _ = deciding.plan(members: members, me: me, now: t)
                decisionTime += Double(DispatchTime.now().uptimeNanoseconds - d0) / 1e9
                decisions += 1
            }
            maxCall = max(maxCall, ns)
            calls += 1
            // Budget nie überschritten (Ausblendende zählen mit)
            for tier in [RaceRenderTier.full, .lite, .impostor] {
                XCTAssertLessThanOrEqual(plan.items.filter { $0.tier == tier }.count, plan.budget[tier], "\(tier) bei \(t) s")
            }
            XCTAssertLessThanOrEqual(plan.clusters.count, plan.budget.clusters)
            if t > 30 { minShown = min(minShown, plan.items.filter { $0.tier >= .lite }.count) }
            // Wechsel zählen, seitlich ohne Sprünge
            var seen = Set<String>()
            for item in plan.items {
                seen.insert(item.id)
                if lastTier[item.id] != item.tier { perBoatChanges[item.id, default: 0] += 1 }
                lastTier[item.id] = item.tier
                if let l = lastLateral[item.id], abs(item.lateral - l) > 1.5 * dt + 1e-9 { lateralJumps += 1 }
                lastLateral[item.id] = item.lateral
            }
            for id in Array(lastTier.keys) where !seen.contains(id) {
                perBoatChanges[id, default: 0] += 1
                lastTier[id] = nil
                lastLateral[id] = nil
            }
            // Keine Überlappung: Boote (voll/vereinfacht) auf derselben Zielbahn haben Abstand
            let boats = plan.items.filter { $0.tier >= .lite && !$0.fadingOut && abs($0.lateral - $0.lateralTarget) < 0.01 }
            for i in boats.indices {
                for j in boats.indices where j > i && boats[i].visualLane == boats[j].visualLane {
                    if abs(boats[i].distance - boats[j].distance) < 11 { overlaps += 1 }
                }
                if boats[i].visualLane == 0, abs(boats[i].distance - me.distance) < 25 { overlaps += 1 }
            }
            t += dt
        }
        let minutes = duration / 60
        let total = perBoatChanges.values.reduce(0, +)
        let worst = perBoatChanges.values.max() ?? 0
        let meanMs = elapsed / Double(calls) * 1000
        let decisionMs = decisionTime / Double(max(decisions, 1)) * 1000
        print("Planer 300 Bots: \(calls) Aufrufe, Mittel \(String(format: "%.3f", meanMs)) ms, Entscheidung \(String(format: "%.3f", decisionMs)) ms, max \(String(format: "%.2f", maxCall * 1000)) ms; Wechsel \(total) (\(String(format: "%.1f", Double(total) / minutes))/min), max je Boot \(worst); Überlappungen \(overlaps); min. gezeigt \(minShown)")
        XCTAssertLessThan(meanMs, 1, "Planungszeit im Mittel < 1 ms")
        XCTAssertEqual(lateralJumps, 0)
        XCTAssertEqual(overlaps, 0)
        // sehr dichtes Feld (≈ 290 Boote in ± 200 m); jeder Wechsel ist ein weicher Übergang
        XCTAssertLessThan(Double(total) / minutes, 90, "Stufenwechsel pro Minute begrenzt")
        XCTAssertLessThan(Double(worst) / minutes, 3, "kein Boot flackert")
        XCTAssertLessThan(decisionMs, 5, "auch ein Entscheidungsschritt bleibt klein (Debug-Build)")
        XCTAssertGreaterThan(minShown, 10, "Umfeld bleibt besetzt")
        XCTAssertEqual(planner.tierChanges > 0, true)
    }

    /// Ein Pulk um mich und einer, der mich überholt: der Überholende bleibt voll, bis er 40 m weg ist
    func testOvertakerStaysFullThroughPack() {
        var planner = RaceScenePlanner(config: .init(budget: .a12x))
        let v = 4.0
        var t = 0.0
        var checked = 0
        var passed = false
        while t < 200 {
            let myD = 500 + v * t
            var members: [RaceFieldMember] = []
            // dichter Pulk: 40 Boote ± 40 m mit meinem Tempo
            for k in 0..<40 {
                members.append(RaceFieldMember(id: "pack\(k)", distance: myD - 40 + Double(k) * 2, speed: v, precise: true))
            }
            // weiter Feld vorne und hinten
            for k in 0..<259 {
                members.append(RaceFieldMember(id: "far\(k)", distance: myD - 400 + Double(k) * 6, speed: v))
            }
            let oD = 450 + 4.6 * t
            members.append(RaceFieldMember(id: "overtaker", distance: oD, speed: 4.6, precise: true))
            let plan = planner.plan(members: members, me: RaceSelf(id: "me", distance: myD, speed: v), now: t)
            let gap = oD - myD
            if gap > 0 { passed = true }
            let o = plan.items.first { $0.id == "overtaker" }
            // ab „gleich überholt“ (25 m hinter mir) bis 40 m vor mir, nach einer Entscheidung Verzögerung
            if gap >= -24, gap <= 39 {
                XCTAssertEqual(o?.tier, .full, "bei Abstand \(gap) m")
                XCTAssertEqual(o?.priority, .overtaking)
                checked += 1
            }
            for tier in [RaceRenderTier.full, .lite] {
                XCTAssertLessThanOrEqual(plan.items.filter { $0.tier == tier }.count, plan.budget[tier])
            }
            if gap > 80 { XCTAssertNotEqual(o?.tier, .full) }
            t += 0.25
        }
        XCTAssertTrue(passed)
        XCTAssertGreaterThan(checked, 100)
    }

    func testSummaryPlaceGapsLeadersHistogramAndInterest() {
        var cfg = RaceScenePlanner.Config(budget: .a12x)
        cfg.courseLength = 2000
        cfg.interestCount = 12
        var planner = RaceScenePlanner(config: cfg)
        // 299 andere, je 5 m: 142 vor mir
        let me = RaceSelf(id: "me", distance: 1000, speed: 4)
        let members = (0..<299).map { k -> RaceFieldMember in
            let d = k < 142 ? 1000 + Double(142 - k) * 5 : 1000 - Double(k - 141) * 5
            return RaceFieldMember(id: String(format: "b%03d", k), distance: d, speed: 4, marked: k == 200)
        }
        let plan = planner.plan(members: members, me: me, now: 0)
        let s = plan.summary
        XCTAssertEqual(s.place, 143)
        XCTAssertEqual(s.total, 300)
        XCTAssertEqual(s.ahead?.id, "b141")
        XCTAssertEqual(s.ahead?.gapMeters, 5)
        XCTAssertEqual(s.ahead?.gapSeconds ?? 0, 1.25, accuracy: 1e-9)
        XCTAssertEqual(s.behind?.gapMeters, -5)
        XCTAssertEqual(s.packAhead, 5)
        XCTAssertEqual(s.packBehind, 5)
        XCTAssertEqual(s.leaders.map(\.id), ["b000", "b001", "b002"])
        XCTAssertEqual(s.leaders.first?.place, 1)
        XCTAssertEqual(s.marked.first?.id, "b200")
        XCTAssertEqual(s.marked.first?.place, 202)
        XCTAssertEqual(s.histogram.count, 40)
        XCTAssertEqual(s.histogram.reduce(0, +), 300)
        XCTAssertTrue(plan.interestChanged)
        XCTAssertEqual(plan.interest.fullIds?.count, 12)
        XCTAssertTrue(plan.interest.fullIds!.contains("b141"))
        XCTAssertFalse(plan.clusters.isEmpty, "ausgeblendete vorne als Pulk")
        // Nachbarschaft: höchstens alle 2 s neu
        let again = planner.plan(members: members.map { var m = $0; m.distance += 30; return m }, me: me, now: 0.6)
        XCTAssertFalse(again.interestChanged)
    }

    /// Bildrate fällt: das Budget sinkt, und nach dem Ausblenden (≤ 1,5 s) zeigt die Szene nicht mehr als erlaubt
    func testFrameRateFeedbackShrinksBudget() {
        let field = RaceBotField(config: .init(count: 300, referencePace: 120, seed: 5))
        var planner = RaceScenePlanner(config: .init(budget: .standard))
        let v = 500.0 / 121
        var t = 100.0
        var plan: RaceScenePlan?
        func step() {
            plan = planner.plan(members: field.members(at: t), me: RaceSelf(id: "me", distance: v * t, speed: v), now: t)
            t += 0.1
        }
        for _ in 0..<50 { step() }
        XCTAssertEqual(plan?.items.filter { $0.tier == .full }.count, 10)
        var dropAt: Double?
        while t < 120 {
            planner.reportFrameRate(42, now: t)
            if dropAt == nil, planner.governor.level > 0 { dropAt = t }
            step()
            if let d = dropAt, t - d > 1.5 {
                let p = plan!
                XCTAssertLessThanOrEqual(p.items.filter { $0.tier == .full }.count, p.budget.full)
                XCTAssertLessThanOrEqual(p.items.filter { $0.tier == .lite }.count, p.budget.lite)
            }
        }
        XCTAssertNotNil(dropAt)
        XCTAssertLessThan(plan!.budget.full, 10)
        XCTAssertLessThanOrEqual(plan!.items.filter { $0.tier == .full }.count, plan!.budget.full)
    }

    func testFadeInAndOut() {
        var planner = RaceScenePlanner()
        let me = RaceSelf(id: "me", distance: 100, speed: 4)
        let a = RaceFieldMember(id: "a", distance: 120, speed: 4)
        var p = planner.plan(members: [a], me: me, now: 0)
        XCTAssertEqual(p.items.first?.fade, 0)
        p = planner.plan(members: [a], me: me, now: 0.3)
        XCTAssertEqual(p.items.first?.fade ?? 0, 0.5, accuracy: 1e-9)
        p = planner.plan(members: [a], me: me, now: 0.7)
        XCTAssertEqual(p.items.first?.fade, 1)
        XCTAssertEqual(p.items.first?.tier, .full)
        // weit weg: blendet aus (nach Mindestdauer), bleibt bis dahin in der Liste
        var far = a; far.distance = 5000
        _ = planner.plan(members: [a], me: me, now: 4.5)
        p = planner.plan(members: [far], me: me, now: 5)
        XCTAssertEqual(p.items.first?.fadingOut, true)
        p = planner.plan(members: [far], me: me, now: 5.3)
        XCTAssertEqual(p.items.first?.fade ?? 1, 0.5, accuracy: 1e-9)
        p = planner.plan(members: [far], me: me, now: 5.7)
        p = planner.plan(members: [far], me: me, now: 6.2)
        XCTAssertTrue(p.items.isEmpty)
    }

    func testMergePreciseOverCoarse() {
        let p = RaceParticipant(id: "a", displayName: "A", lane: 2, source: .ghost)
        let precise = [RemoteRowerState(participant: p, distance: 101, strokeRate: 24, gapMeters: 1, gapSeconds: nil,
                                        finished: false, finishTime: nil, place: 1, stale: false, lateral: 0)]
        let coarse = [RaceCoarseState(id: "a", distance: 99, speed: 4.1, strokeRate: 24, finished: false, stale: false),
                      RaceCoarseState(id: "b", distance: 50, speed: 4, strokeRate: 22, finished: false, stale: false),
                      RaceCoarseState(id: "me", distance: 100, speed: 4, strokeRate: 22, finished: false, stale: false)]
        let m = RaceFieldMember.merge(precise: precise, coarse: coarse, roster: [p], me: "me", marked: ["b"])
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[0].distance, 101)
        XCTAssertEqual(m[0].speed, 4.1)
        XCTAssertEqual(m[0].source, .ghost)
        XCTAssertTrue(m[0].precise)
        XCTAssertFalse(m[1].precise)
        XCTAssertTrue(m[1].marked)
        let withSpeed = RaceFieldMember.merge(precise: precise, coarse: coarse, roster: [p], me: "me", speeds: ["a": 4.5])
        XCTAssertEqual(withSpeed[0].speed, 4.5)
    }
}
