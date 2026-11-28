import XCTest
import RowCoachKit
@testable import RowCoachServerCore

/// Server-Logik ohne Netz: Plausibilität, Festschreiben (virtuelle bitgleich zur App), Auffüllen mit Rotation,
/// Aggregator (gleicher Kurzindex wie auf den Geräten), Takt-Entscheidungen, REST-Werte, Ereignisstrom.
final class RaceServerTests: XCTestCase {
    static let pool: VirtualRowerPool = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/RowCoach/Resources/virtual-rowers-v1.bin")
        return (try? VirtualRowerPool.decode(Data(contentsOf: url))) ?? VirtualRowerPool.generate()
    }()

    let t0: TimeInterval = 1_800_000_000

    func race(fill: OnlineRaceFill = .none, max: Int = 8, startsAt: TimeInterval? = nil) -> OnlineRace {
        OnlineRace(id: "r1", title: "T", courseId: "rhein-basel", target: .distance(1000), startsAt: startsAt ?? t0,
                   maxParticipants: max, createdBy: "a", seed: 99, fill: fill, fillLevel: 450)
    }

    func frame(_ id: String, _ seq: Int, t: Double, d: Double, pace: Double = 120, fin: Double? = nil) -> LiveFrame {
        LiveFrame(participantId: id, raceId: "r1", seq: seq, sentAt: 0, raceTime: t, distance: d, pace: fin == nil ? pace : 0,
                  strokeRate: 24, finished: fin != nil, finishTime: fin)
    }

    /// gleichmässiger, ehrlicher Lauf über 1000 m bei 2:00/500 m (Frames alle 5 s, Ziel bei 240 s)
    func honest(_ id: String) -> [LiveFrame] {
        var out = (0..<48).map { frame(id, $0 + 1, t: Double($0) * 5, d: Double($0) * 5 * 500 / 120) }
        out.append(frame(id, 49, t: 240, d: 1000, fin: 240))
        return out
    }

    // MARK: Plausibilität

    func testJudgeAcceptsHonestRun() {
        let v = RaceJudge().check(id: "a", frames: honest("a"), claimed: OnlineRaceResult(id: "a", distance: 1000, time: 240, finished: true),
                                  target: .distance(1000))
        XCTAssertTrue(v.valid, "\(v.flags)")
        XCTAssertEqual(v.result?.time, 240)
        XCTAssertEqual(v.flags, [])
    }

    func testJudgeFlagsManipulation() {
        let j = RaceJudge()
        // Tempo schneller als 1:10
        var fast = honest("a")
        fast[10].pace = 60
        XCTAssertTrue(j.check(id: "a", frames: fast, claimed: nil, target: .distance(1000)).flags.contains("pace"))
        // Sprung: 40 m mehr als vorausgesagt binnen 5 s
        var jump = honest("a")
        for i in 20..<jump.count - 1 { jump[i].distance += 40 }
        XCTAssertTrue(j.check(id: "a", frames: jump, claimed: nil, target: .distance(1000)).flags.contains("jump"))
        // rückwärts
        var back = honest("a")
        back[30].distance = back[29].distance - 10
        XCTAssertTrue(j.check(id: "a", frames: back, claimed: nil, target: .distance(1000)).flags.contains("backwards"))
        // Zielzeit unmöglich schnell (1000 m in 100 s)
        var quick = Array(honest("a").prefix(5))
        quick.append(frame("a", 6, t: 100, d: 1000, fin: 100))
        XCTAssertTrue(j.check(id: "a", frames: quick, claimed: nil, target: .distance(1000)).flags.contains("pace"))
        // Meldung weicht von den Frames ab: nur Hinweis, die Frames zählen
        let mm = j.check(id: "a", frames: honest("a"), claimed: OnlineRaceResult(id: "a", distance: 1000, time: 200, finished: true),
                         target: .distance(1000))
        XCTAssertEqual(mm.flags, ["mismatch"])
        XCTAssertTrue(mm.valid)
        XCTAssertEqual(mm.result?.time, 240)
        // ohne Frames nur „unverified“
        let none = j.check(id: "a", frames: [], claimed: OnlineRaceResult(id: "a", distance: 800, time: nil, finished: false),
                           target: .distance(1000))
        XCTAssertEqual(none.flags, ["unverified"])
        XCTAssertTrue(none.valid)
    }

    // MARK: Festschreiben

    func testFinalizeRanksAndMatchesDeviceSimulation() {
        let r = race(fill: .client, startsAt: t0)
        let entries = [OnlineRaceEntry(id: "a", displayName: "A", joinedAt: t0 - 100),
                       OnlineRaceEntry(id: "b", displayName: "B", joinedAt: t0 - 90),
                       OnlineRaceEntry(id: "c", displayName: "C", joinedAt: t0 - 80)]
        var slowB = honest("b").map { f -> LiveFrame in var f = f; f.raceTime *= 1.05; if f.finished { f.finishTime = 252 }; return f }
        slowB[slowB.count - 1].raceTime = 252
        var cheatC = honest("c")
        cheatC[12].pace = 50
        let results = RaceFinalizer.finalize(race: r, entries: entries, frames: ["a": honest("a"), "b": slowB, "c": cheatC],
                                             claimed: [], pool: Self.pool)
        let minimum = TournamentFieldFiller.minimumField(tournamentId: "r1", seed: 99)
        XCTAssertEqual(results.count, minimum, "alle echten und virtuellen")
        XCTAssertTrue(results.allSatisfy { !$0.provisional })
        XCTAssertEqual(results.map(\.place), Array(1...minimum))
        let byId = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        XCTAssertLessThan(byId["a"]!.place!, byId["b"]!.place!)
        XCTAssertEqual(byId["c"]!.place, minimum, "verworfen: ans Ende, ohne Zeit")
        XCTAssertNil(byId["c"]!.time)
        XCTAssertTrue(byId["c"]!.flags.contains("pace"))
        // virtuelle: dieselbe Zielzeit wie auf dem Gerät (RaceLiveTransport / VirtualTournamentRace)
        let device = OnlineRoster.filled(entries, race: r, pool: Self.pool)
        let deviceRace = VirtualTournamentRace(race: r.race, startsAt: r.startsAt, field: device.field!)
        for run in deviceRace.runs {
            XCTAssertEqual(byId[run.rowerId]?.time, run.finishTime, "bitgleich: \(run.rowerId)")
            XCTAssertEqual(byId[run.rowerId]?.source, .virtual)
        }
    }

    // MARK: Auffüllen

    func testServerFillUsesRotationAndEqualsClientWithoutHistory() async throws {
        let r = race(fill: .server, startsAt: t0)
        let humans = [OnlineRaceEntry(id: "a", displayName: "A", joinedAt: t0 - 100)]
        let fresh = ServerFieldFill.entries(race: r, humans: humans, pool: Self.pool, history: VirtualRowerHistory())
        // ohne Verlauf dasselbe Feld wie das Auffüllen auf dem Gerät
        var clientRace = r
        clientRace.fill = .client
        let client = OnlineRoster.filled(humans, race: clientRace, pool: Self.pool).participants.filter(\.isVirtual)
        XCTAssertEqual(fresh.entries.map(\.id), client.map(\.id))
        XCTAssertEqual(fresh.entries.map(\.lane), client.map(\.lane))
        // als Anmeldungen geschrieben ergibt sich auf dem Gerät dieselbe Liste
        let roster = OnlineRoster.participants(humans + fresh.entries)
        XCTAssertEqual(roster.map(\.id), ["a"] + client.map(\.id))

        let store = InMemoryRaceServerStore()
        store.races["r1"] = r
        store.entryStore["r1"] = ["a": humans[0]]
        let server = RaceServer(store: store, pool: Self.pool, log: ServerLog { _ in }, clock: { 1_800_000_000 - 30 })
        try await server.fill(r)
        XCTAssertEqual(store.entryStore["r1"]!.values.filter { $0.source == .virtual }.count, fresh.entries.count)
        XCTAssertEqual(store.history.lastRaced.count, fresh.entries.count, "Rotation fortgeschrieben")
        // nächstes Rennen am selben Tag: niemand doppelt
        var r2 = r
        r2.id = "r2"
        r2.startsAt = t0 + 3600
        let next = ServerFieldFill.entries(race: r2, humans: humans, pool: Self.pool, history: store.history)
        XCTAssertTrue(Set(next.entries.map(\.id)).isDisjoint(with: Set(fresh.entries.map(\.id))))
    }

    // MARK: Aggregator

    func testAggregatorCoreHashAndDeltas() {
        let r = race(fill: .client, max: 100, startsAt: t0)
        let entries = (0..<3).map { OnlineRaceEntry(id: "h\($0)", displayName: "H\($0)", joinedAt: t0 - 100 + Double($0)) }
        var core = FieldAggregatorCore(race: r, entries: entries, pool: Self.pool)
        let device = RaceRosterIndex(participants: OnlineRoster.filled(entries, race: r, pool: Self.pool).participants)
        XCTAssertEqual(core.roster.hash, device.hash, "Gerät und Aggregator: gleicher Kurzindex")
        XCTAssertFalse(core.receive(uid: "fremd", wire: RaceLiveWire.encode(frame("fremd", 1, t: 1, d: 3))))
        XCTAssertTrue(core.receive(uid: "h0", wire: RaceLiveWire.encode(frame("h0", 1, t: 1, d: 4))))
        XCTAssertFalse(core.receive(uid: "h0", wire: RaceLiveWire.encode(frame("h0", 1, t: 1, d: 4))), "alte Nummer")
        let first = core.tick(serverNow: t0 + 1)
        XCTAssertEqual(first?.isDelta, false, "beim Start voll")
        XCTAssertEqual(first?.entries.count, core.participants.count - 2, "alle virtuellen + h0 (h1, h2 ohne Frame)")
        XCTAssertNil(core.tick(serverNow: t0 + 3), "Delta erst nach 10 s")
        let delta = core.tick(serverNow: t0 + 11)
        XCTAssertEqual(delta?.isDelta, true)
        XCTAssertFalse(core.allHumansDone(serverNow: t0 + 20))
        XCTAssertTrue(core.allHumansDone(serverNow: t0 + r.maxDuration + 1))
    }

    func testAggregateJobWritesFieldAndFinalizes() async throws {
        let r = race(max: 100, startsAt: t0 - 300)
        let store = InMemoryRaceServerStore()
        store.races["r1"] = r
        store.entryStore["r1"] = ["a": OnlineRaceEntry(id: "a", displayName: "A", joinedAt: t0 - 1000)]
        store.streamFrames = honest("a").map { ("a", RaceLiveWire.encode($0)) }
        let server = RaceServer(store: store, pool: Self.pool, log: ServerLog { _ in }, clock: { 1_800_000_000 })
        try await server.aggregate(raceId: "r1", tickInterval: 0.01)
        XCTAssertFalse(store.fields.isEmpty)
        XCTAssertTrue(store.fields[0].1, "erste Übersicht voll (fieldFull)")
        XCTAssertEqual(store.resultStore["r1"]?["a"]?.time, 240)
        XCTAssertEqual(store.resultStore["r1"]?["a"]?.provisional, false)
        XCTAssertEqual(store.races["r1"]?.status, .finished)
    }

    // MARK: Takt

    func testTickPlanner() {
        var r = race(fill: .server, max: 8, startsAt: t0)
        XCTAssertEqual(TickPlanner.actions(race: r, serverNow: t0 - 600, hasVirtualEntries: false, entitlementsChecked: false,
                                           allHumansFinished: false), [])
        XCTAssertEqual(TickPlanner.actions(race: r, serverNow: t0 - 59, hasVirtualEntries: false, entitlementsChecked: false,
                                           allHumansFinished: false), [.checkEntitlements, .fill, .goLive(startAggregator: false)])
        r.status = .live
        XCTAssertEqual(TickPlanner.actions(race: r, serverNow: t0 + 60, hasVirtualEntries: true, entitlementsChecked: true,
                                           allHumansFinished: false), [])
        XCTAssertEqual(TickPlanner.actions(race: r, serverNow: t0 + 300, hasVirtualEntries: true, entitlementsChecked: true,
                                           allHumansFinished: true), [.finalize])
        var big = race(max: 30, startsAt: t0)
        big.maxParticipants = 200   // vom Server angelegtes grosses Rennen
        XCTAssertEqual(TickPlanner.actions(race: big, serverNow: t0 - 100, hasVirtualEntries: false, entitlementsChecked: true,
                                           allHumansFinished: false), [.goLive(startAggregator: true)])
        big.status = .live
        XCTAssertEqual(TickPlanner.actions(race: big, serverNow: t0 + big.maxDuration + 1, hasVirtualEntries: false,
                                           entitlementsChecked: true, allHumansFinished: true), [], "der Aggregator schreibt fest")
        XCTAssertEqual(TickPlanner.actions(race: big, serverNow: t0 + big.maxDuration + 601, hasVirtualEntries: false,
                                           entitlementsChecked: true, allHumansFinished: true), [.finalize])
    }

    func testTickEndToEndSmallField() async throws {
        let r = race(startsAt: t0 - 400)
        let store = InMemoryRaceServerStore()
        store.races["r1"] = r
        store.entryStore["r1"] = ["a": OnlineRaceEntry(id: "a", displayName: "A", joinedAt: t0 - 1000),
                                  "b": OnlineRaceEntry(id: "b", displayName: "B", joinedAt: t0 - 900)]
        store.frames["r1"] = ["a": RaceLiveWire.encode(honest("a").last!),
                              "b": RaceLiveWire.encode(frame("b", 70, t: 250, d: 1000, fin: 250))]
        store.resultStore["r1"] = ["a": OnlineRaceResult(id: "a", distance: 1000, time: 240, finished: true)]
        let server = RaceServer(store: store, pool: Self.pool, log: ServerLog { _ in }, clock: { 1_800_000_000 })
        try await server.tick()
        XCTAssertEqual(store.races["r1"]?.status, .finished)
        XCTAssertEqual(store.resultStore["r1"]?["a"]?.place, 1)
        XCTAssertEqual(store.resultStore["r1"]?["b"]?.place, 2)
        XCTAssertEqual(store.resultStore["r1"]?["b"]?.provisional, false)
        XCTAssertTrue(store.flags["r1"]?.contains("entitlementsChecked") ?? false)
    }

    func testEntitlementPolicy() async throws {
        XCTAssertTrue(EntitlementPolicy().allows(nil, at: Date()), "Platzhalter: alle")
        let p = EntitlementPolicy(enforce: true)
        XCTAssertFalse(p.allows(nil, at: Date()))
        XCTAssertTrue(p.allows(EntitlementStatus(entitlement: .races, active: true), at: Date()))
        XCTAssertFalse(p.allows(EntitlementStatus(entitlement: .races, active: true, expiresAt: Date(timeIntervalSince1970: 0)), at: Date()))
        let store = InMemoryRaceServerStore()
        store.races["r1"] = race()
        store.entryStore["r1"] = ["a": OnlineRaceEntry(id: "a", displayName: "A"), "b": OnlineRaceEntry(id: "b", displayName: "B")]
        store.entitlementStore["a"] = EntitlementStatus(entitlement: .races, active: true)
        let server = RaceServer(store: store, pool: nil, log: ServerLog { _ in })
        server.entitlements = p
        try await server.checkEntitlements(race(), entries: Array(store.entryStore["r1"]!.values))
        XCTAssertEqual(Set(store.entryStore["r1"]!.keys), ["a"])
    }

    // MARK: REST

    func testFirestoreValues() {
        let doc = race().document
        let (fields, times) = FirestoreREST.fields(doc)
        XCTAssertEqual(times, ["createdAt"])
        let back = fields.compactMapValues { ($0 as? [String: Any]).map(FirestoreREST.decode) }
        // über JSON (wie auf dem Draht)
        let json = try! JSONSerialization.data(withJSONObject: ["name": "projects/p/databases/(default)/documents/races/r1", "fields": fields])
        let parsed = FirestoreREST.document(try! JSONSerialization.jsonObject(with: json) as! [String: Any])!
        XCTAssertEqual(parsed.id, "r1")
        var expected = race()
        expected.createdAt = nil
        XCTAssertEqual(OnlineRace(id: "r1", document: parsed.doc), expected)
        XCTAssertEqual(back["seed"], .int(99))
        XCTAssertEqual(FirestoreREST.decode(["timestampValue": "2027-01-15T10:00:00Z"]).timestamp,
                       ISO8601DateFormatter().date(from: "2027-01-15T10:00:00Z")!.timeIntervalSince1970)
    }

    func testEventStreamParser() {
        var p = RTDBEventParser()
        let w = RaceLiveWire.encode(frame("a", 3, t: 10, d: 41))
        let all = "event: put\ndata: {\"path\":\"/\",\"data\":{\"a\":{\"b\":\"\(w.b)\",\"n\":3,\"at\":1800000000000}}}\n\n"
        let one = "event: put\ndata: {\"path\":\"/b\",\"data\":{\"b\":\"\(w.b)\",\"n\":4,\"at\":1800000001000}}\n\nevent: keep-alive\ndata: null\n\n"
        // in Stücken wie aus dem Netz
        var events = p.feed(String(all.prefix(20)))
        events += p.feed(String(all.dropFirst(20)) + String(one.prefix(30)))
        events += p.feed(String(one.dropFirst(30)))
        XCTAssertEqual(events.map(\.name), ["put", "put", "keep-alive"])
        let f1 = RTDBEventParser.frames(events[0])
        XCTAssertEqual(f1.map(\.0), ["a"])
        XCTAssertEqual(f1.first?.1.n, 3)
        let f2 = RTDBEventParser.frames(events[1])
        XCTAssertEqual(f2.map(\.0), ["b"])
        XCTAssertEqual(f2.first?.1.at ?? 0, 1_800_000_001, accuracy: 1e-6)
        XCTAssertTrue(RTDBEventParser.frames(events[2]).isEmpty)
    }
}
