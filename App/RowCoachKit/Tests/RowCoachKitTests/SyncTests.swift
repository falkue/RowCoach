import XCTest
@testable import RowCoachKit

// Tests der Synchronisation (docs/SYNC.md): Uhr, Binärform, Serverform, Konfliktregeln und Engine.

private func makeRecord(id: UUID = UUID(), start: Double = 1_800_000_000, minutes: Int = 30,
                        effort: WorkoutEffort? = nil, hr: Bool = true) -> WorkoutRecord {
    let n = minutes * 60
    let samples = (0..<n).map { i in
        WorkoutSample(time: Double(i) + 0.137, distance: Double(i) * 4.12, pace: 121.37 + Double(i % 7) * 0.5,
                      strokeRate: 20 + i % 5, power: 180 + i % 40, heartRate: hr ? 120 + i % 30 : nil)
    }
    let header = WorkoutHeader(startDate: Date(timeIntervalSince1970: start),
                               endDate: Date(timeIntervalSince1970: start + Double(n)),
                               courseId: "rotsee", courseTitle: "Rotsee", courseLength: 2000,
                               device: WorkoutDevice(source: .pm5, pm5Name: "PM5 123"), appVersion: "0.2.0")
    let summary = WorkoutSummary(distance: Double(n) * 4.12, activeDuration: Double(n), totalDuration: Double(n),
                                 averagePace: 121.4, averageSpeed: 4.12, averageStrokeRate: 22, strokeCount: n / 3,
                                 averagePower: 200, maxPower: 260, calories: 300, averageHeartRate: 140,
                                 maxHeartRate: 170, heartRateZoneSeconds: [0, 10, 20, 30, 0, 0],
                                 completedCourse: true, pauseCount: 0)
    let splits = [SplitTime(index: 1, endDistance: 500, length: 500, duration: 121.4, averageStrokeRate: 22,
                            averagePower: 200, averageHeartRate: 140)]
    return WorkoutRecord(id: id, header: header, summary: summary, samples: samples, splits: splits,
                         rrIntervals: hr ? (0..<n).map { 0.8 + Double($0 % 10) * 0.0123 } : nil, effort: effort)
}

final class HybridClockTests: XCTestCase {
    func testOrderingAndEncodingAgree() {
        let a = HybridTimestamp(wallMillis: 1000, counter: 5, node: "aaa")
        let b = HybridTimestamp(wallMillis: 1000, counter: 12, node: "aaa")
        let c = HybridTimestamp(wallMillis: 1001, counter: 0, node: "aaa")
        let d = HybridTimestamp(wallMillis: 1001, counter: 0, node: "bbb")
        let sorted = [d, c, b, a]
        XCTAssertEqual(sorted.sorted(), [a, b, c, d])
        XCTAssertEqual(sorted.map(\.encoded).sorted(), [a, b, c, d].map(\.encoded))
        XCTAssertEqual(HybridTimestamp(encoded: b.encoded), b)
        XCTAssertNil(HybridTimestamp(encoded: "kaputt"))
        XCTAssertNil(HybridTimestamp(encoded: "0000000000001000-00005-a/b"))
        XCTAssertLessThan(HybridTimestamp.initial(node: "zzz"), a)
    }

    func testTickIsMonotonicWhenWallClockGoesBack() {
        var clock = HybridLogicalClock(node: "dev1")
        let t1 = clock.tick(now: Date(timeIntervalSince1970: 100))
        let t2 = clock.tick(now: Date(timeIntervalSince1970: 50)) // Uhr springt zurück
        let t3 = clock.tick(now: Date(timeIntervalSince1970: 100))
        XCTAssertLessThan(t1, t2)
        XCTAssertLessThan(t2, t3)
    }

    func testObserveMovesPastRemote() {
        var clock = HybridLogicalClock(node: "dev1")
        let remote = HybridTimestamp(wallMillis: 500_000, counter: 7, node: "dev2")
        clock.observe(remote, now: Date(timeIntervalSince1970: 100))
        let next = clock.tick(now: Date(timeIntervalSince1970: 100))
        XCTAssertGreaterThan(next, remote)
        // Zeitstempel weit in der Zukunft werden gekappt
        var c2 = HybridLogicalClock(node: "dev1")
        c2.observe(HybridTimestamp(wallMillis: 9_000_000_000_000, node: "bad"), now: Date(timeIntervalSince1970: 100))
        XCTAssertLessThanOrEqual(c2.last.wallMillis, 100_000 + 86_400_000)
    }
}

final class SampleCodecTests: XCTestCase {
    func testRoundTripQuantized() throws {
        let r = makeRecord(minutes: 60)
        let data = SampleCodec.encode(samples: r.samples, rr: r.rrIntervals)
        let back = try SampleCodec.decode(data)
        XCTAssertEqual(back.samples, r.samples.map(SampleCodec.quantized))
        XCTAssertEqual(back.rr!.count, r.rrIntervals!.count)
        for (a, b) in zip(back.rr!, r.rrIntervals!) { XCTAssertEqual(a, b, accuracy: 0.0005) }
        // Grössenbudget: eine Stunde deutlich unter 100 KB (JSON wäre ca. 250 KB)
        XCTAssertLessThan(data.count, 100_000)
        let json = try JSONEncoder().encode(r.samples)
        XCTAssertLessThan(data.count * 3, json.count)
    }

    func testWithoutHeartRateAndEmpty() throws {
        let r = makeRecord(minutes: 1, hr: false)
        let back = try SampleCodec.decode(SampleCodec.encode(samples: r.samples, rr: nil))
        XCTAssertNil(back.rr)
        XCTAssertTrue(back.samples.allSatisfy { $0.heartRate == nil })
        let empty = try SampleCodec.decode(SampleCodec.encode(samples: [], rr: nil))
        XCTAssertTrue(empty.samples.isEmpty)
    }

    func testCorruptDataThrowsInsteadOfCrashing() {
        let data = SampleCodec.encode(samples: makeRecord(minutes: 2).samples, rr: nil)
        XCTAssertThrowsError(try SampleCodec.decode(data.prefix(data.count / 2)))
        XCTAssertThrowsError(try SampleCodec.decode(Data([1, 2, 3])))
        XCTAssertThrowsError(try SampleCodec.decode(Data([0x52, 0x53, 9])))
        XCTAssertThrowsError(try SampleCodec.decode(Data([0x52, 0x53, 1] + [UInt8](repeating: 0xFF, count: 20))))
    }

    func testThinningKeepsEnds() {
        let s = makeRecord(minutes: 1).samples
        let t = SampleCodec.thinned(s, step: 7)
        XCTAssertEqual(t.first, s.first)
        XCTAssertEqual(t.last, s.last)
        XCTAssertLessThan(t.count, s.count / 6 + 2)
    }
}

final class RideWireTests: XCTestCase {
    func testRoundTripInline() throws {
        let effort = WorkoutEffort(estimate: 6, estimateBasis: "heartRate", userScore: 7, ratedAt: Date(timeIntervalSince1970: 1_800_001_000))
        let r = makeRecord(effort: effort)
        let clock = HybridTimestamp(wallMillis: 1_800_001_000_000, node: "dev1")
        let wire = try RideWireCodec.encode(SyncRide(record: r, effortClock: clock))
        XCTAssertNotNil(wire.blob)
        XCTAssertTrue(wire.chunks.isEmpty)
        XCTAssertLessThan(wire.approximateDocumentBytes, 900_000)
        XCTAssertFalse(wire.recordJSON!.contains("\"samples\":[{"))
        let back = try RideWireCodec.decode(wire)
        var expected = r
        expected.samples = r.samples.map(SampleCodec.quantized)
        expected.rrIntervals = back.record?.rrIntervals
        XCTAssertEqual(back.record, expected)
        XCTAssertEqual(back.effortClock, clock)
        XCTAssertEqual(back.effort, effort)
    }

    func testLongRideIsChunked() throws {
        // 12 h mit 1 Hz und RR: zu gross fürs Hauptdokument
        let r = makeRecord(minutes: 12 * 60)
        let wire = try RideWireCodec.encode(SyncRide(record: r, effortClock: nil))
        let total = wire.chunks.reduce(0) { $0 + $1.count } + (wire.blob?.count ?? 0)
        if total > SyncSchema.inlineBlobBudget {
            XCTAssertNil(wire.blob)
            XCTAssertGreaterThan(wire.chunks.count, 1)
            XCTAssertTrue(wire.chunks.allSatisfy { $0.count <= SyncSchema.chunkSize })
        }
        let back = try RideWireCodec.decode(wire)
        XCTAssertEqual(back.record?.samples.count, r.samples.count)
        XCTAssertNil(wire.thinned)
    }

    func testNoisyDayLongRideUsesChunksUnderBudget() throws {
        // 24 h mit stark schwankenden Werten: sicher grösser als das Hauptdokument erlaubt
        var rng = SeededGenerator(seed: "chunks")
        var r = makeRecord(minutes: 1)
        r.samples = (0..<86_400).map { i in
            WorkoutSample(time: Double(i) + Double(rng.next() % 1000) / 1000, distance: Double(rng.next() % 100_000_000) / 100,
                          pace: Double(rng.next() % 100_000) / 100, strokeRate: Int(rng.next() % 60),
                          power: Int(rng.next() % 2000), heartRate: Int(rng.next() % 220))
        }
        r.rrIntervals = (0..<86_400).map { _ in Double(rng.next() % 2000) / 1000 }
        let wire = try RideWireCodec.encode(SyncRide(record: r, effortClock: nil))
        XCTAssertNil(wire.blob)
        XCTAssertGreaterThan(wire.chunks.count, 1)
        XCTAssertLessThanOrEqual(wire.chunks.count, SyncSchema.maxChunks)
        XCTAssertTrue(wire.chunks.allSatisfy { $0.count <= SyncSchema.chunkSize })
        XCTAssertLessThan(wire.approximateDocumentBytes, 900_000)
        let back = try RideWireCodec.decode(wire)
        XCTAssertEqual(back.record?.samples.count, wire.thinned == nil ? r.samples.count : back.record?.samples.count)
        XCTAssertEqual(back.record?.samples.first, SampleCodec.quantized(r.samples[0]))
    }

    func testTombstoneAndNewerSchema() throws {
        let id = UUID()
        let clock = HybridTimestamp(wallMillis: 5, node: "a")
        let wire = try RideWireCodec.encode(.tombstone(id: id, clock: clock))
        XCTAssertTrue(wire.deleted)
        XCTAssertNil(wire.recordJSON)
        XCTAssertNil(wire.blob)
        XCTAssertEqual(try RideWireCodec.decode(wire), .tombstone(id: id, clock: clock))
        var newer = try RideWireCodec.encode(SyncRide(record: makeRecord(minutes: 1), effortClock: nil))
        newer.schemaVersion = SyncSchema.version + 1
        XCTAssertThrowsError(try RideWireCodec.decode(newer)) { e in
            XCTAssertEqual(e as? RideWireCodec.WireError, .newerSchema(SyncSchema.version + 1))
        }
    }
}

final class SyncMergeTests: XCTestCase {
    private func f(_ v: String?, _ wall: Int64, _ node: String = "a") -> SettingField {
        SettingField(value: v, clock: HybridTimestamp(wallMillis: wall, node: node))
    }

    func testSettingsMergeIsCommutativeAssociativeIdempotent() {
        let a = SettingsDocument(fields: ["maxHR": f("185", 10), "restHR": f("55", 30)])
        let b = SettingsDocument(fields: ["maxHR": f("190", 20, "b"), "best2k": f("420", 5, "b")])
        let c = SettingsDocument(fields: ["restHR": f(nil, 40, "c"), "maxHR": f("180", 15, "c")])
        let ab = SyncMerge.mergeSettings(a, b)
        XCTAssertEqual(ab, SyncMerge.mergeSettings(b, a))
        XCTAssertEqual(SyncMerge.mergeSettings(ab, c), SyncMerge.mergeSettings(a, SyncMerge.mergeSettings(b, c)))
        XCTAssertEqual(SyncMerge.mergeSettings(ab, ab), ab)
        let all = SyncMerge.mergeSettings(ab, c)
        XCTAssertEqual(all.fields["maxHR"]?.value, "190")
        XCTAssertEqual(all.fields["best2k"]?.value, "420")
        XCTAssertEqual(all.fields["restHR"]?.value, nil) // Entfernen ist neuer
        XCTAssertNotNil(all.fields["restHR"])
    }

    func testRideTombstoneWinsAndEffortLastWriterWins() {
        let r = makeRecord(minutes: 1, effort: WorkoutEffort(estimate: 5))
        var later = r
        later.effort = WorkoutEffort(estimate: 5, userScore: 8)
        let a = SyncRide(record: r, effortClock: HybridTimestamp(wallMillis: 10, node: "a"))
        let b = SyncRide(record: later, effortClock: HybridTimestamp(wallMillis: 20, node: "b"))
        XCTAssertEqual(SyncMerge.mergeRide(a, b).effort?.userScore, 8)
        XCTAssertEqual(SyncMerge.mergeRide(b, a).effort?.userScore, 8)
        let t = SyncRide.tombstone(id: r.id, clock: HybridTimestamp(wallMillis: 1, node: "c"))
        XCTAssertTrue(SyncMerge.mergeRide(b, t).isTombstone)
        XCTAssertTrue(SyncMerge.mergeRide(t, b).isTombstone)
    }
}

/// Ein simuliertes Gerät: lokaler Speicher, Engine, gemeinsamer Server
private final class Device {
    let store = InMemorySyncStore()
    let engine: SyncEngine
    init(_ node: String, backend: SyncBackend, auth: AuthProvider, enabled: Bool = true) {
        engine = SyncEngine(auth: auth, backend: backend, store: store, node: node, isEnabled: { enabled })
    }

    func sync(_ seconds: Double) async -> SyncEngine.Outcome {
        await engine.sync(now: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }
}

private let googleUser = SyncUser(uid: "u1", email: "falk@example.org", emailVerified: true, providers: ["google.com"])

private func report(_ o: SyncEngine.Outcome, file: StaticString = #filePath, line: UInt = #line) -> SyncEngine.Report {
    guard case .synced(let r) = o else {
        XCTFail("kein Abgleich: \(o)", file: file, line: line)
        return SyncEngine.Report()
    }
    return r
}

final class SyncEngineTests: XCTestCase {
    // Vorgabe Falk: ohne Konto keine Netzanfrage
    func testNoAccountNoRequest() async throws {
        let backend = InMemorySyncBackend()
        let device = Device("a", backend: backend, auth: NoopAuthProvider())
        do { let r0 = makeRecord(minutes: 5); device.store.records[r0.id] = r0 }
        device.store.settings["profile/maxHR"] = "185"
        let outcome = await device.sync(0)
        XCTAssertEqual(outcome, .signedOut)
        await device.engine.noteLocalChanges()
        do {
            try await device.engine.recordConsent(ConsentRecord(kind: .research, granted: true, textVersion: "r1",
                                                                locale: "de", decidedAt: Date()))
            XCTFail("ohne Konto darf nichts gespeichert werden")
        } catch {
            XCTAssertEqual(error as? SyncError, .notSignedIn)
        }
        _ = try? await device.engine.exportServerData()
        _ = try? await device.engine.deleteServerData()
        XCTAssertEqual(backend.requestCount, 0)
        XCTAssertTrue(device.store.ledgers.isEmpty)
    }

    func testSyncOffMeansNoRequestEvenWhenSignedIn() async {
        let backend = InMemorySyncBackend()
        let device = Device("a", backend: backend, auth: InMemoryAuthProvider(signedIn: googleUser), enabled: false)
        do { let r0 = makeRecord(minutes: 5); device.store.records[r0.id] = r0 }
        let outcome = await device.sync(0)
        XCTAssertEqual(outcome, .disabled)
        await device.engine.noteLocalChanges()
        XCTAssertEqual(backend.requestCount, 0)
    }

    func testOfflineDefaultEngine() async {
        let store = InMemorySyncStore()
        do { let r0 = makeRecord(minutes: 1); store.records[r0.id] = r0 }
        let outcome = await SyncEngine.offline(store: store).sync()
        XCTAssertEqual(outcome, .disabled)
        let ent = await NoopEntitlementProvider().status(.races)
        XCTAssertFalse(ent.isActive(at: Date()))
    }

    func testUnverifiedEmailDoesNotPush() async throws {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider()
        _ = try await auth.register(email: "neu@example.org", password: "geheim123")
        let device = Device("a", backend: backend, auth: auth)
        do { let r0 = makeRecord(minutes: 1); device.store.records[r0.id] = r0 }
        let outcome = await device.sync(0)
        XCTAssertEqual(outcome, .notVerified)
        XCTAssertEqual(backend.requestCount, 0)
        auth.verify(email: "neu@example.org")
        do { let rep = report(await device.sync(1)); XCTAssertEqual(rep.pushedRides, 1) }
    }

    func testRidesAppendDedupeAndIdempotence() async {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth), b = Device("b", backend: backend, auth: auth)
        let shared = makeRecord(minutes: 2)
        let onlyA = makeRecord(minutes: 3)
        a.store.records[shared.id] = shared
        a.store.records[onlyA.id] = onlyA
        b.store.records[shared.id] = shared // z. B. aus einer Sicherung: gleiche id auf beiden Geräten
        let ra = report(await a.sync(10))
        XCTAssertEqual(ra.pushedRides, 2)
        let rb = report(await b.sync(20))
        XCTAssertEqual(rb.pulledRides, 1)
        XCTAssertEqual(rb.pushedRides, 0) // gleiche Fahrt nur einmal auf dem Server
        XCTAssertEqual(backend.storedRideIds, [shared.id, onlyA.id])
        XCTAssertEqual(Set(b.store.records.keys), [shared.id, onlyA.id])
        XCTAssertEqual(b.store.records[onlyA.id]?.samples.count, onlyA.samples.count)
        // Wiederholung ändert nichts
        let before = backend.storedRideIds.map { backend.storedWire($0) }
        do { let rep = report(await a.sync(30)); XCTAssertEqual(rep, SyncEngine.Report()) }
        do { let rep = report(await b.sync(40)); XCTAssertEqual(rep, SyncEngine.Report()) }
        XCTAssertEqual(backend.storedRideIds.map { backend.storedWire($0) }, before)
        XCTAssertEqual(a.store.records.count, 2)
    }

    func testEffortConflictLaterChangeWins() async {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth), b = Device("b", backend: backend, auth: auth)
        let r = makeRecord(minutes: 2, effort: WorkoutEffort(estimate: 5))
        a.store.records[r.id] = r
        _ = await a.sync(0)
        _ = await b.sync(1)
        // beide ändern offline die eigene Einschätzung; B später
        a.store.records[r.id]?.effort = WorkoutEffort(estimate: 5, userScore: 6)
        await a.engine.noteLocalChanges(now: Date(timeIntervalSince1970: 1_800_000_100))
        b.store.records[r.id]?.effort = WorkoutEffort(estimate: 5, userScore: 9)
        await b.engine.noteLocalChanges(now: Date(timeIntervalSince1970: 1_800_000_200))
        // B gleicht zuerst ab, A danach – trotzdem gewinnt die spätere Änderung (B)
        do { let rep = report(await b.sync(300)); XCTAssertEqual(rep.pushedEfforts, 1) }
        let ra = report(await a.sync(400))
        XCTAssertEqual(ra.updatedEfforts, 1)
        XCTAssertEqual(ra.pushedEfforts, 0)
        XCTAssertEqual(a.store.records[r.id]?.effort?.userScore, 9)
        _ = await b.sync(500)
        XCTAssertEqual(b.store.records[r.id]?.effort?.userScore, 9)
        XCTAssertEqual(backend.storedRide(r.id)?.effort?.userScore, 9)
    }

    func testDeletionPropagatesAndNeverResurrects() async {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth), b = Device("b", backend: backend, auth: auth)
        let r = makeRecord(minutes: 2)
        a.store.records[r.id] = r
        _ = await a.sync(0)
        _ = await b.sync(1)
        // A löscht; B ändert gleichzeitig die Belastung
        a.store.records[r.id] = nil
        b.store.records[r.id]?.effort = WorkoutEffort(userScore: 4)
        do { let rep = report(await a.sync(10)); XCTAssertEqual(rep.pushedTombstones, 1) }
        XCTAssertNil(backend.storedWire(r.id)?.blob, "Tombstone ohne Trainingsdaten")
        XCTAssertEqual(backend.storedWire(r.id)?.deleted, true)
        let rb = report(await b.sync(20))
        XCTAssertEqual(rb.deletedLocally, 1)
        XCTAssertNil(b.store.records[r.id])
        // ein drittes Gerät bekommt die Fahrt nie
        let c = Device("c", backend: backend, auth: auth)
        do { let rep = report(await c.sync(30)); XCTAssertEqual(rep.pulledRides, 0) }
        XCTAssertTrue(c.store.records.isEmpty)
        // auch erneutes Einfügen auf dem Server wird abgewiesen (Fahrten sind unveränderlich)
        try? await backend.push([.create(SyncRide(record: r, effortClock: nil))])
        XCTAssertEqual(backend.storedWire(r.id)?.deleted, true)
    }

    func testLocalDeleteBeforeUploadSendsNothing() async {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth)
        _ = await a.sync(0)
        let r = makeRecord(minutes: 1)
        a.store.records[r.id] = r
        await a.engine.noteLocalChanges(now: Date(timeIntervalSince1970: 1_800_000_005))
        a.store.records[r.id] = nil
        let rep = report(await a.sync(10))
        XCTAssertEqual(rep.pushedRides + rep.pushedTombstones, 0)
        XCTAssertTrue(backend.storedRideIds.isEmpty)
    }

    func testSettingsFieldwiseMerge() async {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth), b = Device("b", backend: backend, auth: auth)
        a.store.settings["profile/maxHR"] = "185"
        a.store.settings["profile/best2k"] = "430"
        _ = await a.sync(0)
        _ = await b.sync(1)
        XCTAssertEqual(b.store.settings["profile/maxHR"], "185")
        // A ändert den Maximalpuls, B die Bestzeit – beides bleibt
        a.store.settings["profile/maxHR"] = "190"
        await a.engine.noteLocalChanges(now: Date(timeIntervalSince1970: 1_800_000_010))
        b.store.settings["profile/best2k"] = "425"
        await b.engine.noteLocalChanges(now: Date(timeIntervalSince1970: 1_800_000_011))
        _ = await b.sync(20)
        _ = await a.sync(21)
        _ = await b.sync(22)
        for d in [a, b] {
            XCTAssertEqual(d.store.settings["profile/maxHR"], "190")
            XCTAssertEqual(d.store.settings["profile/best2k"], "425")
        }
        // gleiches Feld: spätere Änderung gewinnt, auch wenn sie zuerst hochgeladen wird
        a.store.settings["motivation/goalMinutes"] = "60"
        await a.engine.noteLocalChanges(now: Date(timeIntervalSince1970: 1_800_000_030))
        b.store.settings["motivation/goalMinutes"] = "120"
        await b.engine.noteLocalChanges(now: Date(timeIntervalSince1970: 1_800_000_040))
        _ = await b.sync(50)
        _ = await a.sync(51)
        XCTAssertEqual(a.store.settings["motivation/goalMinutes"], "120")
        // Plan beendet (Feld entfernt) kommt auf dem anderen Gerät an
        a.store.settings["program/active"] = "{\"programId\":\"x\"}"
        _ = await a.sync(60)
        _ = await b.sync(61)
        XCTAssertEqual(b.store.settings["program/active"], "{\"programId\":\"x\"}")
        b.store.settings["program/active"] = nil
        _ = await b.sync(70)
        _ = await a.sync(71)
        XCTAssertNil(a.store.settings["program/active"])
        // unbekannte Schlüssel gehen nicht auf den Server
        a.store.settings["device/pm5"] = "x"
        _ = await a.sync(80)
        XCTAssertNil(backend.storedSettings["device"])
    }

    func testNewDeviceWithDefaultsDoesNotOverwriteServer() async {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth)
        a.store.settings["profile/maxHR"] = "178"
        _ = await a.sync(0)
        // neues Gerät hat schon einen (älteren) Wert gespeichert, bevor es sich anmeldet
        let b = Device("b", backend: backend, auth: auth)
        b.store.settings["profile/maxHR"] = "185"
        b.store.settings["profile/restHR"] = "50"
        let rb = report(await b.sync(1000))
        XCTAssertEqual(b.store.settings["profile/maxHR"], "178", "der Server gewinnt beim ersten Abgleich")
        XCTAssertEqual(rb.pushedSettings, 1) // nur restHR, das der Server nicht kannte
        XCTAssertEqual(backend.storedSettings["profile"]?.fields["restHR"]?.value, "50")
    }

    func testFailureMidwayRecoversWithoutDuplicates() async {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth)
        for i in 0..<3 { let r = makeRecord(start: 1_800_000_000 + Double(i) * 10_000, minutes: 1); a.store.records[r.id] = r }
        backend.failNext = .network("offline")
        let failed = await a.sync(0)
        XCTAssertEqual(failed, .failed(.network("offline")))
        do { let rep = report(await a.sync(10)); XCTAssertEqual(rep.pushedRides, 3) }
        do { let rep = report(await a.sync(20)); XCTAssertEqual(rep.pushedRides, 0) }
        XCTAssertEqual(backend.storedRideIds.count, 3)
    }

    func testUnsyncableRidesStayLocal() async {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth)
        let demo = makeRecord(minutes: 1)
        a.store.records[demo.id] = demo
        a.store.unsyncable.insert(demo.id)
        do { let rep = report(await a.sync(0)); XCTAssertEqual(rep.pushedRides, 0) }
        XCTAssertTrue(backend.storedRideIds.isEmpty)
    }

    func testConsentExportAndDeleteAll() async throws {
        let backend = InMemorySyncBackend()
        let auth = InMemoryAuthProvider(signedIn: googleUser)
        let a = Device("a", backend: backend, auth: auth)
        let r = makeRecord(minutes: 1)
        a.store.records[r.id] = r
        a.store.settings["profile/maxHR"] = "185"
        _ = await a.sync(0)
        let yes = ConsentRecord(kind: .research, granted: true, textVersion: "research-2026-11", locale: "de",
                                decidedAt: Date(timeIntervalSince1970: 1_800_000_000))
        var no = yes
        no.granted = false
        try await a.engine.recordConsent(yes)
        try await a.engine.recordConsent(no)
        XCTAssertEqual(backend.consentLog.map(\.granted), [true, false])
        let export = try await a.engine.exportServerData()
        XCTAssertEqual(export.rides.map(\.id), [r.id])
        XCTAssertEqual(export.consents, [no])
        XCTAssertEqual(export.settings["profile"]?.fields["maxHR"]?.value, "185")
        let json = try export.jsonData()
        XCTAssertNoThrow(try JSONDecoder().decode(SyncExportProbe.self, from: json))
        try await a.engine.deleteServerData()
        XCTAssertTrue(backend.storedRideIds.isEmpty)
        XCTAssertTrue(backend.storedSettings.isEmpty)
        XCTAssertNil(a.store.ledgers["u1"])
        XCTAssertEqual(a.store.records.count, 1, "die Daten auf dem Gerät bleiben")
        // nächster Abgleich lädt wieder hoch
        do { let rep = report(await a.sync(10)); XCTAssertEqual(rep.pushedRides, 1) }
    }

    func testAuthFlows() async throws {
        let auth = InMemoryAuthProvider()
        let user = try await auth.register(email: "A@example.org", password: "geheim123")
        XCTAssertFalse(user.canWrite)
        try await auth.sendEmailVerification()
        XCTAssertEqual(auth.sentVerifications, ["a@example.org"])
        do {
            _ = try await auth.register(email: "a@example.org", password: "anders123")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? SyncError, .emailInUse)
        }
        try await auth.signOut()
        let none = await auth.currentUser()
        XCTAssertNil(none)
        try await auth.sendPasswordReset(email: "a@example.org")
        XCTAssertEqual(auth.sentResets, ["a@example.org"])
        auth.verify(email: "a@example.org")
        let again = try await auth.signIn(email: "a@example.org", password: "geheim123")
        XCTAssertTrue(again.canWrite)
    }

    func testCatalogPathsAreUniqueAndFitRules() {
        let paths = SyncSettingsCatalog.keys.map(\.path)
        XCTAssertEqual(Set(paths).count, paths.count)
        XCTAssertEqual(Set(SyncSettingsCatalog.keys.map(\.localKey)).count, paths.count)
        for k in SyncSettingsCatalog.keys {
            XCTAssertTrue(SyncSettingsCatalog.documents.contains(k.document))
            XCTAssertNil(k.field.range(of: "[^A-Za-z0-9]", options: .regularExpression), k.field)
        }
        // Firestore-Regeln: die Feldlisten dort müssen zum Katalog passen
        XCTAssertEqual(SyncSettingsCatalog.fields(of: "profile"), ["rower", "maxHR", "restHR", "best2k", "weightKg"])
    }
}

/// Nur zum Prüfen, dass der Export gültiges JSON mit den Hauptfeldern ist
private struct SyncExportProbe: Decodable {
    var formatVersion: Int
    var uid: String
}
