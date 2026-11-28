import Foundation
import RowCoachKit

/// Ein-/Ausgabe des Servers. Umsetzung: `GoogleRaceServerStore` (Firestore- und Realtime-Database-REST mit dem
/// Dienstkonto des Cloud-Run-Jobs, Admin-Rechte → Regeln gelten nicht); Tests: `InMemoryRaceServerStore`.
public protocol RaceServerStore: AnyObject, Sendable {
    /// Rennen mit Start in [from, to], Status geplant oder live
    func activeRaces(startsFrom from: TimeInterval, to: TimeInterval) async throws -> [OnlineRace]
    func race(id: String) async throws -> OnlineRace?
    func entries(raceId: String) async throws -> [OnlineRaceEntry]
    func results(raceId: String) async throws -> [OnlineRaceResult]
    func writeEntries(raceId: String, _ entries: [OnlineRaceEntry]) async throws
    func removeEntry(raceId: String, uid: String) async throws
    func writeResults(raceId: String, _ results: [OnlineRaceResult]) async throws
    /// Status und Server-Felder (z. B. `entitlementsChecked`, `finalizedAt`) des Rennens setzen
    func updateRace(raceId: String, status: OnlineRaceStatus?, fields: RaceDocument) async throws
    func raceFlag(raceId: String, _ name: String) async throws -> Bool
    func virtualHistory() async throws -> VirtualRowerHistory
    func saveVirtualHistory(_ h: VirtualRowerHistory) async throws
    func entitlement(uid: String) async throws -> EntitlementStatus?
    /// letzte Frames aller (`live/{raceId}/f`)
    func lastFrames(raceId: String) async throws -> [String: RaceWireFrame]
    func writeField(raceId: String, _ s: RaceFieldSnapshot, full: Bool) async throws
    /// alle Frame-Änderungen als Strom (uid, Frame), solange bis abgebrochen
    func frameStream(raceId: String) -> AsyncThrowingStream<(String, RaceWireFrame), Error>
    /// Aggregator-Job für ein Rennen starten (Cloud Run Jobs: Ausführung mit Argumenten)
    func startAggregator(raceId: String) async throws
}

public struct ServerLog: Sendable {
    public var write: @Sendable (String) -> Void
    public init(_ write: @escaping @Sendable (String) -> Void = { print($0) }) { self.write = write }
    public func callAsFunction(_ s: String) { write(s) }
}

/// Die Aufgaben des Servers. `tick` läuft minütlich (Cloud Scheduler → Cloud-Run-Job), `aggregate` je grossem
/// Rennen als eigene Ausführung über die ganze Renndauer.
public final class RaceServer: @unchecked Sendable {
    public let store: RaceServerStore
    public let pool: VirtualRowerPool?
    public var judge = RaceJudge()
    public var entitlements = EntitlementPolicy()
    public let log: ServerLog
    public let clock: @Sendable () -> TimeInterval

    public init(store: RaceServerStore, pool: VirtualRowerPool?, log: ServerLog = ServerLog(),
                clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.pool = pool
        self.log = log
        self.clock = clock
    }

    // MARK: Takt

    /// Alle Rennen im Fenster (Start vor bis zu 4 h … in 10 min) einen Schritt weiter
    public func tick() async throws {
        let now = clock()
        let races = try await store.activeRaces(startsFrom: now - 4 * 3600 - TickPlanner.aggregatorGrace, to: now + 600)
        log("Takt: \(races.count) Rennen im Fenster")
        for r in races {
            do { try await step(r, now: now) } catch { log("Rennen \(r.id): Fehler \(error)") }
        }
    }

    func step(_ r: OnlineRace, now: TimeInterval) async throws {
        let entries = try await store.entries(raceId: r.id)
        let frames = r.isSmallField && now >= r.startsAt ? try await store.lastFrames(raceId: r.id) : [:]
        let humans = entries.filter { $0.source != .virtual }
        let finished = !humans.isEmpty && humans.allSatisfy { h in
            frames[h.id].flatMap { RaceLiveWire.decode($0, raceId: r.id, participantId: h.id) }?.finished == true
        }
        let actions = TickPlanner.actions(race: r, serverNow: now,
                                          hasVirtualEntries: entries.contains { $0.source == .virtual },
                                          entitlementsChecked: try await store.raceFlag(raceId: r.id, "entitlementsChecked"),
                                          allHumansFinished: finished)
        for a in actions {
            switch a {
            case .checkEntitlements: try await checkEntitlements(r, entries: humans)
            case .fill: try await fill(r)
            case .goLive(let agg):
                try await store.updateRace(raceId: r.id, status: .live, fields: [:])
                if agg { try await store.startAggregator(raceId: r.id) }
                log("Rennen \(r.id): live\(agg ? ", Aggregator gestartet" : "")")
            case .finalize:
                // ohne Aggregator kennt der Server nur den letzten Frame je Person (die Datenbank überschreibt)
                let last = frames.isEmpty ? try await store.lastFrames(raceId: r.id) : frames
                var history: [String: [LiveFrame]] = [:]
                for (uid, w) in last {
                    if let f = RaceLiveWire.decode(w, raceId: r.id, participantId: uid) { history[uid] = [f] }
                }
                try await finalize(r, history: history)
            }
        }
    }

    // MARK: Aufgaben

    public func checkEntitlements(_ r: OnlineRace, entries: [OnlineRaceEntry]) async throws {
        var removed = 0
        if entitlements.enforce {
            for e in entries {
                let s = try await store.entitlement(uid: e.id)
                if !entitlements.allows(s, at: Date(timeIntervalSince1970: clock())) {
                    try await store.removeEntry(raceId: r.id, uid: e.id)
                    removed += 1
                }
            }
        }
        try await store.updateRace(raceId: r.id, status: nil, fields: ["entitlementsChecked": .bool(true)])
        log("Rennen \(r.id): Abo geprüft (\(entitlements.enforce ? "durchgesetzt" : "Platzhalter, alle erlaubt"), \(removed) entfernt)")
    }

    public func fill(_ r: OnlineRace) async throws {
        guard let pool else { log("Rennen \(r.id): kein Pool, nicht aufgefüllt"); return }
        let humans = try await store.entries(raceId: r.id).filter { $0.source != .virtual }
        var history = try await store.virtualHistory()
        let (virtual, field) = ServerFieldFill.entries(race: r, humans: humans, pool: pool, history: history)
        try await store.writeEntries(raceId: r.id, virtual)
        history.record(virtual.map(\.id), at: r.startsAt)
        try await store.saveVirtualHistory(history)
        log("Rennen \(r.id): Mindestfeld \(field.minimumField), echt \(field.realCount), virtuell \(field.virtualCount)")
    }

    public func finalize(_ r: OnlineRace, history: [String: [LiveFrame]]) async throws {
        let entries = try await store.entries(raceId: r.id)
        let claimed = try await store.results(raceId: r.id)
        let results = RaceFinalizer.finalize(race: r, entries: entries, frames: history, claimed: claimed, pool: pool,
                                             judge: judge)
        try await store.writeResults(raceId: r.id, results)
        try await store.updateRace(raceId: r.id, status: .finished, fields: ["finalizedAt": .serverTimestamp])
        let flagged = results.filter { !$0.flags.isEmpty }.map { "\($0.id): \($0.flags.joined(separator: ","))" }
        log("Rennen \(r.id): \(results.count) Ergebnisse festgeschrieben\(flagged.isEmpty ? "" : ", Hinweise: \(flagged.joined(separator: "; "))")")
    }

    // MARK: Aggregator

    /// Läuft über die ganze Renndauer: Frames hören, Übersicht schreiben (Delta 10 s / Zielzone 5 s, voll beim
    /// Start und alle 300 s), am Ende festschreiben. `tickInterval` = Prüftakt (1 s).
    public func aggregate(raceId: String, tickInterval: TimeInterval = 1) async throws {
        guard let r = try await store.race(id: raceId) else { log("Rennen \(raceId) nicht gefunden"); return }
        let entries = try await store.entries(raceId: raceId)
        let core = Locked(FieldAggregatorCore(race: r, entries: entries, pool: pool))
        log("Aggregator \(raceId): \(core.value.participants.count) Teilnehmende, Start in \(Int(r.startsAt - clock())) s")
        let listener = Task {
            do {
                for try await (uid, w) in store.frameStream(raceId: raceId) { core.mutate { _ = $0.receive(uid: uid, wire: w) } }
            } catch {
                self.log("Aggregator \(raceId): Strom beendet: \(error)")
            }
        }
        defer { listener.cancel() }
        while !Task.isCancelled {
            let now = clock()
            if let s = core.mutate({ $0.tick(serverNow: now) }) {
                try await store.writeField(raceId: raceId, s, full: !s.isDelta)
            }
            if core.value.allHumansDone(serverNow: now) { break }
            try await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
        }
        try await finalize(r, history: core.value.history)
    }
}

/// kleiner Behälter mit Sperre (Aggregator: Strom und Takt greifen gleichzeitig zu)
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.withLock { v } }
    func mutate<R>(_ f: (inout T) -> R) -> R { lock.withLock { f(&v) } }
}

// MARK: - Im Speicher (Tests)

public final class InMemoryRaceServerStore: RaceServerStore, @unchecked Sendable {
    private let lock = NSLock()
    public var races: [String: OnlineRace] = [:]
    public var entryStore: [String: [String: OnlineRaceEntry]] = [:]
    public var resultStore: [String: [String: OnlineRaceResult]] = [:]
    public var flags: [String: Set<String>] = [:]
    public var history = VirtualRowerHistory()
    public var entitlementStore: [String: EntitlementStatus] = [:]
    public var frames: [String: [String: RaceWireFrame]] = [:]
    public var fields: [(RaceFieldSnapshot, Bool)] = []
    public var aggregatorsStarted: [String] = []
    /// Frames, die `frameStream` der Reihe nach liefert
    public var streamFrames: [(String, RaceWireFrame)] = []

    public init() {}

    public func activeRaces(startsFrom from: TimeInterval, to: TimeInterval) async throws -> [OnlineRace] {
        lock.withLock { races.values.filter { ($0.status == .scheduled || $0.status == .live) && $0.startsAt >= from && $0.startsAt <= to } }
    }
    public func race(id: String) async throws -> OnlineRace? { lock.withLock { races[id] } }
    public func entries(raceId: String) async throws -> [OnlineRaceEntry] { lock.withLock { Array((entryStore[raceId] ?? [:]).values) } }
    public func results(raceId: String) async throws -> [OnlineRaceResult] { lock.withLock { Array((resultStore[raceId] ?? [:]).values) } }
    public func writeEntries(raceId: String, _ entries: [OnlineRaceEntry]) async throws {
        lock.withLock { for e in entries { entryStore[raceId, default: [:]][e.id] = e } }
    }
    public func removeEntry(raceId: String, uid: String) async throws { _ = lock.withLock { entryStore[raceId]?.removeValue(forKey: uid) } }
    public func writeResults(raceId: String, _ results: [OnlineRaceResult]) async throws {
        lock.withLock { for r in results { resultStore[raceId, default: [:]][r.id] = r } }
    }
    public func updateRace(raceId: String, status: OnlineRaceStatus?, fields f: RaceDocument) async throws {
        lock.withLock {
            if let status { races[raceId]?.status = status }
            for (k, v) in f where v.bool == true { flags[raceId, default: []].insert(k) }
        }
    }
    public func raceFlag(raceId: String, _ name: String) async throws -> Bool { lock.withLock { flags[raceId]?.contains(name) ?? false } }
    public func virtualHistory() async throws -> VirtualRowerHistory { lock.withLock { history } }
    public func saveVirtualHistory(_ h: VirtualRowerHistory) async throws { lock.withLock { history = h } }
    public func entitlement(uid: String) async throws -> EntitlementStatus? { lock.withLock { entitlementStore[uid] } }
    public func lastFrames(raceId: String) async throws -> [String: RaceWireFrame] { lock.withLock { frames[raceId] ?? [:] } }
    public func writeField(raceId: String, _ s: RaceFieldSnapshot, full: Bool) async throws { lock.withLock { fields.append((s, full)) } }
    public func frameStream(raceId: String) -> AsyncThrowingStream<(String, RaceWireFrame), Error> {
        let items = lock.withLock { streamFrames }
        return AsyncThrowingStream { c in
            for i in items { c.yield(i) }
            c.finish()
        }
    }
    public func startAggregator(raceId: String) async throws { lock.withLock { aggregatorsStarted.append(raceId) } }
}
