import XCTest
@testable import RowCoachKit

/// Online-Rennen über Firebase ohne Firebase: Dokumente, Draht, Transport mit In-Memory-Datenbank, Abos,
/// Kleinfeld-Übersicht, Anwesenheit, Auffüllen auf dem Gerät, Ergebnisse (docs/MULTIPLAYER.md „Umsetzung Firebase“).
final class RaceOnlineTests: XCTestCase {
    let t0: TimeInterval = 1_800_000_000

    func makeRace(max: Int = 8, startsIn: TimeInterval = 600, fill: OnlineRaceFill = .none,
                  distance: Double = 1000) -> OnlineRace {
        OnlineRace(id: "r1", title: "Test", courseId: "rhein-basel", courseVersion: 3, target: .distance(distance),
                   startsAt: t0 + startsIn, maxParticipants: max, visibility: .open, createdBy: "a", seed: 4711,
                   fill: fill, fillLevel: 450)
    }

    func entry(_ id: String, at: TimeInterval) -> OnlineRaceEntry {
        OnlineRaceEntry(id: id, displayName: id.uppercased(), appearance: .random(seed: id), joinedAt: at)
    }

    // MARK: Dokumente

    func testRaceDocumentRoundTrip() {
        var r = makeRace()
        r.createdAt = t0
        let back = OnlineRace(id: "r1", document: r.document)
        XCTAssertEqual(back, r)
        XCTAssertEqual(back?.race.scheduledStart, r.startsAt)
        XCTAssertEqual(back?.race.lanes, 8)
        XCTAssertTrue(r.isSmallField)
        // ohne Anlagezeit: Serverzeit-Platzhalter
        XCTAssertEqual(makeRace().document["createdAt"], .serverTimestamp)
        // Zeitrennen
        var tr = makeRace()
        tr.target = .time(1200)
        XCTAssertEqual(OnlineRace(id: "r1", document: tr.document)?.target, .time(1200))
        XCTAssertNil(OnlineRace(id: "x", document: ["title": .string("t")]))
    }

    func testRaceValidationAndPhases() {
        var r = makeRace(startsIn: 600)
        XCTAssertNil(r.validationError(serverNow: t0))
        r.startsAt = t0 + 30
        XCTAssertEqual(r.validationError(serverNow: t0), "tooSoon")
        r.startsAt = t0 + 31 * 86400
        XCTAssertEqual(r.validationError(serverNow: t0), "tooLate")
        r = makeRace(max: 31)
        XCTAssertEqual(r.validationError(serverNow: t0), "participants")
        r = makeRace(distance: 50)
        XCTAssertEqual(r.validationError(serverNow: t0), "distance")

        r = makeRace(startsIn: 600)
        XCTAssertEqual(r.phase(serverNow: t0), .open)
        XCTAssertTrue(r.registrationOpen(serverNow: t0 + 539))
        XCTAssertFalse(r.registrationOpen(serverNow: t0 + 541), "Meldeschluss 60 s vor dem Start")
        XCTAssertEqual(r.phase(serverNow: t0 + 550), .closing)
        XCTAssertEqual(r.phase(serverNow: t0 + 601), .running)
        XCTAssertEqual(r.phase(serverNow: t0 + 600 + r.maxDuration + 1), .over)
        r.status = .cancelled
        XCTAssertEqual(r.phase(serverNow: t0), .over)
    }

    func testInviteCode() {
        var g = RaceRandom(seed: 9)
        let code = RaceInviteCode.make(using: &g)
        XCTAssertTrue(RaceInviteCode.isValid(code))
        XCTAssertEqual(code.count, 8)
        XCTAssertEqual(RaceInviteCode.normalize(" \(code.prefix(4).lowercased())-\(code.suffix(4)) "), code)
        XCTAssertFalse(RaceInviteCode.isValid("ABCD0OIL"), "verwechselbare Zeichen gibt es nicht")
    }

    func testEntryDocumentAndLanes() {
        let a = entry("a", at: t0 + 5), b = entry("b", at: t0 + 1)
        let back = OnlineRaceEntry(id: "a", document: a.document)
        XCTAssertEqual(back, a)
        XCTAssertNotNil(a.document["appearance"]?.string)
        XCTAssertLessThanOrEqual(a.document["appearance"]?.string?.count ?? 0, OnlineRaceLimits.appearanceMax)
        // Bahn aus der Reihenfolge der Anmeldung; eigene noch ohne Serverzeit kommt ans Ende
        let pending = OnlineRaceEntry(id: "c", displayName: "C")
        let v = OnlineRaceEntry(id: "v1-0007", displayName: "Lea", source: .virtual, lane: 2)
        let list = OnlineRoster.participants([a, pending, v, b])
        XCTAssertEqual(list.map(\.id), ["b", "a", "c", "v1-0007"])
        XCTAssertEqual(list.map(\.lane), [1, 2, 3, 4], "virtuelle nie auf einer Bahn der echten")
        XCTAssertTrue(list[3].isVirtual)
        // Profil → Anmeldung nach der Datenschutzregel (Name gekürzt, nur öffentliche Erscheinung)
        var p = RowerProfile()
        p.displayName = String(repeating: "x", count: 40)
        let mine = OnlineRaceEntry.mine(uid: "u", profile: p)
        XCTAssertEqual(mine.displayName.count, 24)
        XCTAssertEqual(mine.appearance, p.publicAppearance)
    }

    func testResultDocument() {
        let r = OnlineRaceResult(id: "a", distance: 1000, time: 201.2345, finished: true)
        let back = OnlineRaceResult(id: "a", document: r.document)
        XCTAssertEqual(back?.time, 201.235)
        XCTAssertEqual(back?.provisional, true)
        XCTAssertNil(back?.place)
        let f = OnlineRaceResult(id: "b", distance: 1000, time: 210, finished: true, provisional: false, place: 2,
                                 flags: ["pace", "jump"])
        XCTAssertEqual(OnlineRaceResult(id: "b", document: f.document)?.flags, ["pace", "jump"])
    }

    // MARK: Draht

    func testWireRoundTripAndSeq() {
        let f = LiveFrame(participantId: "x", raceId: "r1", seq: 12, sentAt: 0, raceTime: 61.23, distance: 250.4,
                          pace: 118.3, strokeRate: 27, heartRate: 151)
        let w = RaceLiveWire.encode(f)
        XCTAssertEqual(w.b.count, 24)
        XCTAssertEqual(w.n, 12)
        let back = RaceLiveWire.decode(RaceWireFrame(b: w.b, n: 40, at: t0), raceId: "r1", participantId: "uidB")
        XCTAssertEqual(back?.participantId, "uidB", "uid aus dem Pfad")
        XCTAssertEqual(back?.seq, 40, "lesbare Nummer ist massgeblich")
        XCTAssertEqual(back?.distance ?? 0, 250.4, accuracy: 0.05)
        XCTAssertEqual(back?.sentAt, t0)
        var fin = f
        fin.finished = true
        fin.finishTime = 199.987
        let wf = RaceLiveWire.encode(fin)
        XCTAssertEqual(wf.b.count, 32)
        XCTAssertEqual(RaceLiveWire.decode(wf, raceId: "r1", participantId: "u")?.finishTime ?? 0, 199.987, accuracy: 1e-9)
        XCTAssertNil(RaceLiveWire.decode(RaceWireFrame(b: "kaputt", n: 1), raceId: "r1", participantId: "u"))
        // Datenbankwert (n und at in ms)
        let parsed = RaceWireFrame(value: ["b": w.b, "n": NSNumber(value: 7), "at": NSNumber(value: 1_800_000_000_500.0)])
        XCTAssertEqual(parsed?.n, 7)
        XCTAssertEqual(parsed?.at ?? 0, 1_800_000_000.5, accuracy: 1e-6)
    }

    // MARK: Transport

    /// Gerät: Transport + Link wie in der App
    @MainActor
    func device(_ uid: String, race: OnlineRace, hub: InMemoryRaceLiveHub, directory: InMemoryRaceDirectory? = nil,
                entries: [OnlineRaceEntry], pool: VirtualRowerPool? = nil, now: @escaping @Sendable () -> TimeInterval) -> RaceLiveTransport {
        RaceLiveTransport(race: race, uid: uid, backend: hub.backend(), directory: directory, initialEntries: entries,
                          pool: pool, clock: now)
    }

    func waitUntil(_ timeout: TimeInterval = 2, _ cond: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond() && Date() < end { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    @MainActor
    func testTwoDevicesExchangeFramesSmallField() async throws {
        let race = makeRace(startsIn: -10)
        let hub = InMemoryRaceLiveHub()
        let entries = [entry("a", at: t0 - 100), entry("b", at: t0 - 90)]
        let now: @Sendable () -> TimeInterval = { 1_800_000_000 }
        let a = device("a", race: race, hub: hub, entries: entries, now: now)
        let b = device("b", race: race, hub: hub, entries: entries, now: now)
        let la = try await a.join(race: race.race, as: RaceParticipant(id: "a", displayName: "A", lane: 1))
        _ = try await b.join(race: race.race, as: RaceParticipant(id: "b", displayName: "B", lane: 2))
        XCTAssertEqual(la.map(\.id), ["a", "b"])
        XCTAssertEqual(a.subscribedIds, ["b"], "Kleinfeld: alle anderen, nie ich")
        XCTAssertEqual(b.subscribedIds, ["a"])

        var received: [LiveFrame] = []
        let reader = Task { for await f in b.frames { received.append(f); if received.count >= 2 { break } } }
        try await a.publish(LiveFrame(participantId: "a", raceId: "r1", seq: 1, sentAt: 0, raceTime: 10, distance: 40,
                                      pace: 120, strokeRate: 24))
        try await a.publish(LiveFrame(participantId: "a", raceId: "r1", seq: 2, sentAt: 0, raceTime: 14, distance: 57,
                                      pace: 119, strokeRate: 25))
        await waitUntil { received.count >= 2 }
        reader.cancel()
        XCTAssertEqual(received.map(\.participantId), ["a", "a"])
        XCTAssertEqual(received.last?.distance ?? 0, 57, accuracy: 0.05)
        XCTAssertEqual(hub.writes, 2)
        await a.leave()
        await b.leave()
        XCTAssertEqual(hub.activeFrameListeners(raceId: "r1", uid: "a"), 0, "leave meldet alle Listener ab")
    }

    @MainActor
    func testSeqContinuesAfterRestart() async throws {
        let race = makeRace(startsIn: -10)
        let hub = InMemoryRaceLiveHub()
        let entries = [entry("a", at: t0 - 100)]
        let now: @Sendable () -> TimeInterval = { 1_800_000_000 }
        let a1 = device("a", race: race, hub: hub, entries: entries, now: now)
        _ = try await a1.join(race: race.race, as: RaceParticipant(id: "a", displayName: "A", lane: 1))
        for s in 1...30 {
            try await a1.publish(LiveFrame(participantId: "a", raceId: "r1", seq: s, sentAt: 0, raceTime: Double(s),
                                           distance: Double(s) * 4, pace: 125, strokeRate: 24))
        }
        await a1.leave()
        // App neu gestartet: der Koordinator zählt wieder ab 1, die Datenbank verlangt > 30
        let a2 = device("a", race: race, hub: hub, entries: entries, now: now)
        _ = try await a2.join(race: race.race, as: RaceParticipant(id: "a", displayName: "A", lane: 1))
        try await a2.publish(LiveFrame(participantId: "a", raceId: "r1", seq: 1, sentAt: 0, raceTime: 40, distance: 160,
                                       pace: 125, strokeRate: 24))
        XCTAssertEqual(hub.frame(raceId: "r1", uid: "a")?.n, 31)
        await a2.leave()
        // ohne Beitritt (keine Mitgliedschaft) lehnt die Datenbank ab – wie die Regeln
        do {
            try await hub.backend().writeFrame(raceId: "r1", uid: "z", frame: RaceLiveWire.encode(
                LiveFrame(participantId: "z", raceId: "r1", seq: 1, sentAt: 0, raceTime: 1, distance: 1, pace: 0, strokeRate: 0)))
            XCTFail("ohne Mitgliedschaft darf niemand schreiben")
        } catch {
            XCTAssertEqual(error as? InMemoryRaceLiveHub.HubError, .notMember)
        }
    }

    @MainActor
    func testInterestChangesListenersInLargeField() async throws {
        let race = makeRace(max: 100, startsIn: -10)
        XCTAssertFalse(race.isSmallField)
        let hub = InMemoryRaceLiveHub()
        let entries = (0..<40).map { entry(String(format: "u%02d", $0), at: t0 - 100 + Double($0)) }
        let me = device("u00", race: race, hub: hub, entries: entries, now: { 1_800_000_000 })
        _ = try await me.join(race: race.race, as: RaceParticipant(id: "u00", displayName: "", lane: 1))
        XCTAssertEqual(me.subscribedIds.count, 16, "ohne Abo die ersten K nach Bahn")
        XCTAssertFalse(me.subscribedIds.contains("u00"))
        await me.setInterest(RaceInterest(fullIds: ["u05", "u07", "u00", "nobody"]))
        XCTAssertEqual(me.subscribedIds, ["u05", "u07"], "nur echte, nie ich, Unbekannte ignoriert")
        let before = hub.unsubscribes
        await me.setInterest(RaceInterest(fullIds: ["u07", "u09"]))
        XCTAssertEqual(me.subscribedIds, ["u07", "u09"])
        XCTAssertEqual(hub.unsubscribes - before, 1, "nur u05 abgemeldet, u07 bleibt")
        XCTAssertEqual(hub.activeFrameListeners(raceId: "r1", uid: "u05"), 0)
        XCTAssertEqual(hub.activeFrameListeners(raceId: "r1", uid: "u09"), 1)
        // Kleinfeld ignoriert das Abo: alle hören alle
        let small = RaceLiveSubscriptions.desired(humans: ["a", "b", "c"], me: "a", smallField: true,
                                                  interest: RaceInterest(fullIds: ["b"]))
        XCTAssertEqual(small, ["b", "c"])
        await me.leave()
    }

    @MainActor
    func testLocalOverviewAndPresence() async throws {
        let race = makeRace(startsIn: -30)
        let hub = InMemoryRaceLiveHub()
        let entries = [entry("a", at: t0 - 100), entry("b", at: t0 - 90), entry("c", at: t0 - 80)]
        let now: @Sendable () -> TimeInterval = { 1_800_000_000 }
        let a = device("a", race: race, hub: hub, entries: entries, now: now)
        let b = device("b", race: race, hub: hub, entries: entries, now: now)
        let c = device("c", race: race, hub: hub, entries: entries, now: now)
        for (t, id) in [(a, "a"), (b, "b"), (c, "c")] {
            _ = try await t.join(race: race.race, as: RaceParticipant(id: id, displayName: id, lane: 1))
        }
        try await a.publish(LiveFrame(participantId: "a", raceId: "r1", seq: 1, sentAt: 0, raceTime: 28, distance: 110,
                                      pace: 125, strokeRate: 24))
        try await b.publish(LiveFrame(participantId: "b", raceId: "r1", seq: 1, sentAt: 0, raceTime: 28, distance: 100,
                                      pace: 130, strokeRate: 22))
        try await c.publish(LiveFrame(participantId: "c", raceId: "r1", seq: 1, sentAt: 0, raceTime: 28, distance: 90,
                                      pace: 140, strokeRate: 20))
        XCTAssertTrue(a.wantsLocalOverview(raceTime: 1), "Kleinfeld: Übersicht immer lokal")
        guard let s = a.localSnapshot(raceTime: 30) else { return XCTFail("keine Übersicht") }
        let index = RaceRosterIndex(participants: a.currentParticipants)
        XCTAssertEqual(s.rosterHash, index.hash)
        XCTAssertEqual(s.entries.count, 3, "alle drei, auch ich")
        let byId = Dictionary(uniqueKeysWithValues: s.entries.map { (index.id(at: $0.index)!, $0) })
        XCTAssertEqual(byId["b"]!.distance, 100 + 500 / 130 * 2, accuracy: 0.11, "auf die Rennzeit vorausgerechnet")
        XCTAssertFalse(byId["c"]!.stale)
        // c verliert die Verbindung (onDisconnect): sofort „veraltet“, nicht erst nach 45 s
        hub.disconnect(raceId: "r1", uid: "c")
        let s2 = a.localSnapshot(raceTime: 31)!
        XCTAssertTrue(s2.entries.first { index.id(at: $0.index) == "c" }!.stale)
        XCTAssertFalse(s2.entries.first { index.id(at: $0.index) == "b" }!.stale)
        // Die Übersicht passt zur Teilnehmerliste des Links (gleicher Hash)
        var tracker = RaceFieldTracker(participants: a.currentParticipants)
        XCTAssertTrue(tracker.receive(s2, receivedLocal: 0))
        XCTAssertEqual(tracker.states(atRaceTime: 31, exclude: "a").count, 2)
        for t in [a, b, c] { await t.leave() }
    }

    func testPresenceRule() {
        XCTAssertTrue(RaceLivePresence.isStale(id: "x", online: ["y"], lastReceivedLocal: 99, now: 100, finished: false))
        XCTAssertFalse(RaceLivePresence.isStale(id: "x", online: ["y"], lastReceivedLocal: 99, now: 100, finished: true),
                       "im Ziel nie veraltet")
        XCTAssertTrue(RaceLivePresence.isStale(id: "x", online: nil, lastReceivedLocal: 0, now: 46, finished: false))
        XCTAssertFalse(RaceLivePresence.isStale(id: "x", online: ["x"], lastReceivedLocal: 50, now: 60, finished: false))
    }

    @MainActor
    func testClientFillIsSameOnAllDevicesAndSimulated() async throws {
        let race = makeRace(startsIn: -5, fill: .client)
        let pool = VirtualRacerTests.pool
        let hub = InMemoryRaceLiveHub()
        let entries = [entry("a", at: t0 - 100), entry("b", at: t0 - 90)]
        let now: @Sendable () -> TimeInterval = { 1_800_000_000 }
        let a = device("a", race: race, hub: hub, entries: entries, pool: pool, now: now)
        let b = device("b", race: race, hub: hub, entries: entries, pool: pool, now: now)
        let la = try await a.join(race: race.race, as: RaceParticipant(id: "a", displayName: "", lane: 1))
        let lb = try await b.join(race: race.race, as: RaceParticipant(id: "b", displayName: "", lane: 2))
        let minimum = TournamentFieldFiller.minimumField(tournamentId: "r1", seed: 4711)
        XCTAssertEqual(la.count, minimum)
        XCTAssertEqual(la, lb, "beide Geräte rechnen dasselbe Feld")
        XCTAssertEqual(la.filter(\.isVirtual).count, minimum - 2)
        XCTAssertEqual(a.subscribedIds, ["b"], "virtuelle nie über das Netz")
        XCTAssertEqual(a.virtualRuns.count, minimum - 2)
        XCTAssertEqual(a.virtualRuns.map(\.finishTime), b.virtualRuns.map(\.finishTime))
        // ohne Abo: die nächsten 16 virtuellen als volle Frames; mit Abo genau diese
        XCTAssertEqual(a.virtualFrames(raceTime: 5).count, 16)
        let pick = Set(la.filter(\.isVirtual).prefix(3).map(\.id))
        await a.setInterest(RaceInterest(fullIds: pick.union(["b"])))
        XCTAssertEqual(Set(a.virtualFrames(raceTime: 5).map(\.participantId)), pick)
        // Übersicht enthält alle virtuellen
        let s = a.localSnapshot(raceTime: 5)!
        XCTAssertEqual(s.entries.count, minimum - 2, "alle virtuellen; a und b ohne Frame noch nicht")
        for t in [a, b] { await t.leave() }
    }

    @MainActor
    func testRaceLinkOverOnlineTransport() async throws {
        let race = makeRace(startsIn: -1)
        let hub = InMemoryRaceLiveHub(offset: 2)
        let entries = [entry("a", at: t0 - 100), entry("b", at: t0 - 90)]
        let now: @Sendable () -> TimeInterval = { 1_800_000_000 }
        let ta = device("a", race: race, hub: hub, entries: entries, now: now)
        let tb = device("b", race: race, hub: hub, entries: entries, now: now)
        var coordA = RaceCoordinator(race: race.race, me: RaceParticipant(id: "a", displayName: "A", lane: 1),
                                     tracker: .deadReckoning(finishDistance: 1000))
        coordA.deadReckoning = RaceDeadReckoningPublisher(finishDistance: 1000)
        let linkA = RaceLink(coordinator: coordA, transports: [ta], now: now)
        let linkB = RaceLink(coordinator: RaceCoordinator(race: race.race, me: RaceParticipant(id: "b", displayName: "B", lane: 2),
                                                          tracker: .deadReckoning(finishDistance: 1000)),
                             transports: [tb], now: now)
        try await linkA.connect()
        try await linkB.connect()
        XCTAssertEqual(linkA.coordinator.clock.offset, 2, accuracy: 1e-9, "Uhr aus dem Serverzeit-Versatz")
        XCTAssertEqual(linkA.coordinator.raceTime(local: 1_800_000_000) ?? 0, 3, accuracy: 0.01)
        linkA.update(raceTime: 3, distance: 12, pace: 120, strokeRate: 24)
        await waitUntil { linkB.coordinator.trackers["a"]?.latest != nil }
        XCTAssertEqual(linkB.coordinator.trackers["a"]?.latest?.distance ?? 0, 12, accuracy: 0.05)
        // Abmeldung eines anderen: einziger Transport → Liste wird ersetzt (Kurzindex wie die Übersicht)
        _ = linkA.coordinator.roster
        await linkA.disconnect()
        await linkB.disconnect()
    }

    // MARK: Verzeichnis

    func testDirectoryRules() async throws {
        let clock = Clock(t0)
        let dirA = InMemoryRaceDirectory(uid: "a", now: { clock.now })
        let dirB = dirA.session(uid: "b")
        var r = makeRace(max: 2, startsIn: 600)
        r.createdBy = "a"
        let created = try await dirA.create(r, inviteCode: "ABCDEFGH")
        let found = try await dirB.raceId(inviteCode: "abcd-efgh")
        XCTAssertEqual(found, created.id)
        try await dirA.register(raceId: created.id, entry: entry("a", at: 0))
        try await dirB.register(raceId: created.id, entry: entry("b", at: 0))
        let dirC = dirA.session(uid: "c")
        do { try await dirC.register(raceId: created.id, entry: entry("c", at: 0)); XCTFail("voll") } catch {
            XCTAssertEqual(error as? RaceDirectoryError, .raceFull)
        }
        // fremde Anmeldung und fremdes Ergebnis sind verboten
        do { try await dirB.register(raceId: created.id, entry: entry("a", at: 0)); XCTFail() } catch {
            XCTAssertEqual(error as? RaceDirectoryError, .notAllowed)
        }
        clock.now = t0 + 545
        do { try await dirB.unregister(raceId: created.id, uid: "b"); XCTFail("Meldeschluss") } catch {
            XCTAssertEqual(error as? RaceDirectoryError, .registrationClosed)
        }
        // Ergebnis erst nach dem Start, nur vorläufig
        do { try await dirB.submitResult(raceId: created.id, result: OnlineRaceResult(id: "b", distance: 0, time: nil, finished: false)); XCTFail() } catch {}
        clock.now = t0 + 900
        try await dirB.submitResult(raceId: created.id, result: OnlineRaceResult(id: "b", distance: 1000, time: 210, finished: true))
        do {
            try await dirB.submitResult(raceId: created.id, result: OnlineRaceResult(id: "b", distance: 1000, time: 200, finished: true,
                                                                                    provisional: false, place: 1))
            XCTFail("endgültig nur der Server")
        } catch {}
        dirA.finalize(raceId: created.id, results: [OnlineRaceResult(id: "b", distance: 1000, time: 210, finished: true,
                                                                     provisional: false, place: 1)])
        do {
            try await dirB.submitResult(raceId: created.id, result: OnlineRaceResult(id: "b", distance: 1000, time: 190, finished: true))
            XCTFail("nach dem Festschreiben nichts mehr ändern")
        } catch {}
        let upcoming = try await dirB.upcoming(serverNow: t0, limit: 10)
        XCTAssertEqual(upcoming.map(\.id), [created.id])
        let signedOut = InMemoryRaceDirectory(uid: nil)
        do { _ = try await signedOut.upcoming(serverNow: t0, limit: 5); XCTFail() } catch {
            XCTAssertEqual(error as? RaceDirectoryError, .notSignedIn)
        }
    }

    // MARK: Ergebnisse

    func testResultsMerge() {
        let roster = [RaceParticipant(id: "a", displayName: "A", lane: 1), RaceParticipant(id: "b", displayName: "B", lane: 2),
                      RaceParticipant(id: "c", displayName: "C", lane: 3),
                      RaceParticipant(id: "v1-0001", displayName: "Lea", lane: 4, source: .virtual)]
        let local = [RaceResult(participantId: "a", place: 1, distance: 1000, time: 200, finished: true),
                     RaceResult(participantId: "b", place: 2, distance: 1000, time: 205, finished: true),
                     RaceResult(participantId: "c", place: 3, distance: 870, time: nil, finished: false)]
        let submitted = [OnlineRaceResult(id: "b", distance: 1000, time: 199.5, finished: true)]
        let v = VirtualRaceRun.steady(id: "v1-0001", pace: 101, finishDistance: 1000)
        let rows = OnlineRaceResults.merge(target: .distance(1000), roster: roster, submitted: submitted, local: local,
                                           virtualRuns: [v])
        XCTAssertEqual(rows.map(\.id), ["b", "a", "v1-0001", "c"], "gemeldete Zeit gilt vor der gesehenen")
        XCTAssertEqual(rows.map(\.status), [.provisional, .estimated, .provisional, .estimated])
        XCTAssertTrue(rows[2].participant.isVirtual)
        XCTAssertFalse(OnlineRaceResults.isFinal(rows))
        // Server schreibt alles fest: seine Plätze gelten
        let final = [OnlineRaceResult(id: "a", distance: 1000, time: 200, finished: true, provisional: false, place: 2),
                     OnlineRaceResult(id: "b", distance: 1000, time: 199.5, finished: true, provisional: false, place: 1),
                     OnlineRaceResult(id: "c", distance: 870, time: nil, finished: false, provisional: false, place: 4,
                                      flags: ["jump"]),
                     OnlineRaceResult(id: "v1-0001", distance: 1000, time: 202, finished: true, provisional: false, place: 3,
                                      source: .virtual)]
        let rows2 = OnlineRaceResults.merge(target: .distance(1000), roster: roster, submitted: final + submitted,
                                            local: local, virtualRuns: [v])
        XCTAssertTrue(OnlineRaceResults.isFinal(rows2))
        XCTAssertEqual(rows2.map(\.id), ["b", "a", "v1-0001", "c"])
        XCTAssertEqual(rows2.last?.flags, ["jump"])
    }

    func testAccess() {
        XCTAssertEqual(OnlineRaceAccess.check(serverConfigured: false, signedIn: true, entitled: true, debugBuild: true), .unavailable)
        XCTAssertEqual(OnlineRaceAccess.check(serverConfigured: true, signedIn: false, entitled: true, debugBuild: true), .needsAccount)
        XCTAssertEqual(OnlineRaceAccess.check(serverConfigured: true, signedIn: true, entitled: false, debugBuild: true), .allowed)
        XCTAssertEqual(OnlineRaceAccess.check(serverConfigured: true, signedIn: true, entitled: false, debugBuild: false),
                       .needsSubscription)
    }
}

private final class Clock: @unchecked Sendable {
    var now: TimeInterval
    init(_ t: TimeInterval) { now = t }
}
