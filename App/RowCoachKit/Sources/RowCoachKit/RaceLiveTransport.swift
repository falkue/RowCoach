import Foundation

// Transport für Online-Rennen (docs/MULTIPLAYER.md, „Umsetzung Firebase“). Die ganze Logik liegt hier im Kit und ist
// ohne Firebase testbar; die App liefert nur zwei dünne Anbindungen:
// - `RaceLiveBackend`  → Realtime Database (Frames, Anwesenheit, Übersicht, Serverzeit),
// - `RaceDirectory`    → Firestore (Rennen, Anmeldungen, Ergebnisse).
// Für Tests und die Demo ohne Server gibt es `InMemoryRaceLiveHub` und `InMemoryRaceDirectory`.

/// Laufendes Abo; `cancel()` beendet es (mehrfach aufrufbar)
public protocol RaceLiveObservation: Sendable {
    func cancel()
}

/// Realtime Database eines Rennens (Pfade: `RaceLiveWire`)
public protocol RaceLiveBackend: AnyObject, Sendable {
    /// Serverzeit − Gerätezeit (s), Firebase: `/.info/serverTimeOffset`
    func serverTimeOffset() async throws -> TimeInterval
    /// `members/{raceId}/{uid}` setzen und Anwesenheit `live/{raceId}/online/{uid}` mit onDisconnect → entfernt
    func joinLive(raceId: String, uid: String) async throws
    /// Anwesenheit entfernen (der letzte Frame bleibt für die Wertung liegen)
    func leaveLive(raceId: String, uid: String) async
    func readFrame(raceId: String, uid: String) async throws -> RaceWireFrame?
    func writeFrame(raceId: String, uid: String, frame: RaceWireFrame) async throws
    /// ein Listener je uid (Nachbarschafts-Abo); meldet den aktuellen Stand sofort und dann jede Änderung
    func observeFrame(raceId: String, uid: String,
                      onChange: @escaping @Sendable (RaceWireFrame?) -> Void) -> any RaceLiveObservation
    func observePresence(raceId: String, onChange: @escaping @Sendable (Set<String>) -> Void) -> any RaceLiveObservation
    /// Übersicht des Aggregators (`live/{raceId}/field`, Delta), nur grosse Felder
    func observeField(raceId: String, onChange: @escaping @Sendable (RaceFieldSnapshot) -> Void) -> any RaceLiveObservation
    /// volle Übersicht (`live/{raceId}/fieldFull`), einmal beim Beitritt
    func readFieldFull(raceId: String) async throws -> RaceFieldSnapshot?
}

public enum RaceDirectoryError: Error, Equatable, Sendable {
    case notSignedIn
    case notFound
    case registrationClosed
    case raceFull
    case notAllowed
    case invalid(String)
    case network(String)
    case server(String)
}

/// Rennen, Anmeldungen und Ergebnisse (Firestore)
public protocol RaceDirectory: AnyObject, Sendable {
    /// kommende öffentliche Rennen (Start ≥ jetzt − Renndauer), nach Start sortiert
    func upcoming(serverNow: TimeInterval, limit: Int) async throws -> [OnlineRace]
    func race(id: String) async throws -> OnlineRace?
    func raceId(inviteCode: String) async throws -> String?
    /// legt an (id wird vergeben) und für private Rennen den Einladungscode
    func create(_ race: OnlineRace, inviteCode: String?) async throws -> OnlineRace
    func cancel(raceId: String) async throws
    func entries(raceId: String) async throws -> [OnlineRaceEntry]
    func register(raceId: String, entry: OnlineRaceEntry) async throws
    func unregister(raceId: String, uid: String) async throws
    func observeEntries(raceId: String, onChange: @escaping @Sendable ([OnlineRaceEntry]) -> Void) -> any RaceLiveObservation
    func submitResult(raceId: String, result: OnlineRaceResult) async throws
    func observeResults(raceId: String, onChange: @escaping @Sendable ([OnlineRaceResult]) -> Void) -> any RaceLiveObservation
}

/// Wen hört ein Gerät (ein Listener je uid)? Kleinfeld: alle echten; grosses Feld: das Abo des Planers (ohne Abo die
/// ersten `neighbours` nach Bahn, bis der Planer das erste Mal entscheidet). Virtuelle nie über das Netz.
public enum RaceLiveSubscriptions {
    public static func desired(humans: [String], me: String, smallField: Bool, interest: RaceInterest?,
                               neighbours: Int = 16) -> Set<String> {
        let others = humans.filter { $0 != me }
        if smallField { return Set(others) }
        if let ids = interest?.fullIds { return Set(others.filter { ids.contains($0) }) }
        return Set(others.prefix(neighbours))
    }

    /// Unterschied alt → neu: neu anzumelden, abzumelden
    public static func diff(current: Set<String>, desired: Set<String>) -> (add: Set<String>, remove: Set<String>) {
        (desired.subtracting(current), current.subtracting(desired))
    }
}

/// Anwesenheit und „veraltet“: Wer nicht mehr angemeldet ist (onDisconnect) oder lange nichts geschickt hat, gilt als
/// veraltet – ausser er ist schon im Ziel.
public enum RaceLivePresence {
    public static func isStale(id: String, online: Set<String>?, lastReceivedLocal: TimeInterval?, now: TimeInterval,
                               finished: Bool, staleAfter: TimeInterval = 45) -> Bool {
        if finished { return false }
        if let online, !online.contains(id) { return true }
        guard let t = lastReceivedLocal else { return false }
        return now - t > staleAfter
    }
}

/// `RaceTransport` über `RaceLiveBackend` (+ optional `RaceDirectory` für Änderungen der Teilnehmerliste).
///
/// - Senden: `RaceCoordinator` entscheidet (Dead Reckoning); hier nur Binärframe + Nummer. Die Nummer setzt auf dem
///   letzten Frame in der Datenbank auf (Neustart der App im Rennen: die Regeln verlangen eine wachsende Nummer).
/// - Empfangen: ein Listener je uid nach `RaceLiveSubscriptions`.
/// - Kleinfeld (≤ 30 echte): alle hören alle; die Übersicht rechnet das Gerät selbst aus allen Frames (jede Sekunde),
///   mit „veraltet“ aus der Anwesenheit. Grosses Feld: Übersicht vom Aggregator; kommt 15 s nach dem Start keine,
///   rechnet das Gerät sie aus dem, was es hört.
/// - Virtuelle Teilnehmende senden nichts: jedes Gerät simuliert sie (gleiches Ergebnis überall); volle Frames kommen
///   für die im Abo (bzw. die nächsten), die lokale Übersicht enthält alle.
public final class RaceLiveTransport: RaceTransport, @unchecked Sendable {
    public struct Config: Sendable {
        public var neighbours = 16
        /// Takt der virtuellen Frames (/s)
        public var virtualRate = 2.5
        /// lokale Übersicht alle … s
        public var overviewInterval: TimeInterval = 1
        /// grosses Feld: so lange nach dem Start auf die Übersicht des Aggregators warten (s)
        public var serverFieldWait: TimeInterval = 15
        public var staleAfter: TimeInterval = 45
        public init() {}
    }

    public let onlineRace: OnlineRace
    public let uid: String
    public let config: Config
    public let frames: AsyncStream<LiveFrame>
    public let roster: AsyncStream<[RaceParticipant]>
    public let fieldSnapshots: AsyncStream<RaceFieldSnapshot>

    private let backend: RaceLiveBackend
    private let directory: RaceDirectory?
    private let pool: VirtualRowerPool?
    private let clock: @Sendable () -> TimeInterval
    private let framesContinuation: AsyncStream<LiveFrame>.Continuation
    private let rosterContinuation: AsyncStream<[RaceParticipant]>.Continuation
    private let fieldContinuation: AsyncStream<RaceFieldSnapshot>.Continuation

    private let lock = NSLock()
    private var entries: [OnlineRaceEntry]
    private var offset: TimeInterval = 0
    private var seqBase = 0
    private var participants: [RaceParticipant] = []
    private var humans: [String] = []
    private var virtualField: RaceBotField?
    private var virtualRunIds: [String] = []
    private var listeners: [String: any RaceLiveObservation] = [:]
    private var otherObservations: [any RaceLiveObservation] = []
    private var online: Set<String>?
    private var latest: [String: LiveFrame] = [:]
    private var lastReceived: [String: TimeInterval] = [:]
    private var myLatest: LiveFrame?
    private var interest: RaceInterest?
    private var serverFieldSeen = false
    private var overviewSeq = 0
    private var virtualSeq = 0
    private var loop: Task<Void, Never>?
    private var joined = false
    private var closed = false

    /// - Parameters:
    ///   - initialEntries: Anmeldungen, wie der Warteraum sie zuletzt gesehen hat (danach folgt das Abo)
    ///   - pool: Pool der virtuellen Teilnehmenden (nötig, sobald virtuelle mitfahren)
    ///   - clock: Gerätezeit (s seit 1970)
    public init(race: OnlineRace, uid: String, backend: RaceLiveBackend, directory: RaceDirectory? = nil,
                initialEntries: [OnlineRaceEntry] = [], pool: VirtualRowerPool? = nil, config: Config = Config(),
                clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.onlineRace = race
        self.uid = uid
        self.backend = backend
        self.directory = directory
        self.entries = initialEntries
        self.pool = pool
        self.config = config
        self.clock = clock
        (frames, framesContinuation) = AsyncStream.makeStream(of: LiveFrame.self, bufferingPolicy: .bufferingNewest(512))
        (roster, rosterContinuation) = AsyncStream.makeStream(of: [RaceParticipant].self, bufferingPolicy: .bufferingNewest(4))
        (fieldSnapshots, fieldContinuation) = AsyncStream.makeStream(of: RaceFieldSnapshot.self,
                                                                     bufferingPolicy: .bufferingNewest(2))
    }

    // MARK: RaceTransport

    public func join(race: Race, as participant: RaceParticipant) async throws -> [RaceParticipant] {
        guard race.id == onlineRace.id, participant.id == uid else { throw RaceTransportError.notJoined }
        let off = (try? await backend.serverTimeOffset()) ?? 0
        let base = (try? await backend.readFrame(raceId: race.id, uid: uid))?.n ?? 0
        try await backend.joinLive(raceId: race.id, uid: uid)
        lock.withLock {
            offset = off
            seqBase = base
            joined = true
        }
        let list = applyEntries(nil, yield: false)
        rosterContinuation.yield(list)

        var obs: [any RaceLiveObservation] = []
        if let directory {
            obs.append(directory.observeEntries(raceId: race.id) { [weak self] e in _ = self?.applyEntries(e, yield: true) })
        }
        obs.append(backend.observePresence(raceId: race.id) { [weak self] ids in
            self?.lock.withLock { self?.online = ids }
        })
        if !onlineRace.isSmallField {
            obs.append(backend.observeField(raceId: race.id) { [weak self] s in self?.receiveServerField(s) })
            if let full = try? await backend.readFieldFull(raceId: race.id) { receiveServerField(full) }
        }
        lock.withLock { otherObservations = obs }
        startLoop()
        return list
    }

    public func publish(_ frame: LiveFrame) async throws {
        let wire: RaceWireFrame? = lock.withLock {
            guard joined, !closed else { return nil }
            var f = frame
            f.seq = seqBase + frame.seq
            myLatest = f
            return RaceLiveWire.encode(f)
        }
        guard let wire else { throw RaceTransportError.notJoined }
        try await backend.writeFrame(raceId: onlineRace.id, uid: uid, frame: wire)
    }

    public func serverTime() async throws -> TimeInterval {
        clock() + lock.withLock { offset }
    }

    public func setInterest(_ interest: RaceInterest) async {
        lock.withLock { self.interest = interest }
        updateSubscriptions()
    }

    public func leave() async {
        let (obs, listeners, task, wasJoined) = lock.withLock { () -> ([any RaceLiveObservation], [any RaceLiveObservation], Task<Void, Never>?, Bool) in
            closed = true
            let o = otherObservations, l = Array(self.listeners.values), t = loop, j = joined
            otherObservations = []
            self.listeners = [:]
            loop = nil
            joined = false
            return (o, l, t, j)
        }
        task?.cancel()
        for o in obs + listeners { o.cancel() }
        if wasJoined { await backend.leaveLive(raceId: onlineRace.id, uid: uid) }
        framesContinuation.finish()
        rosterContinuation.finish()
        fieldContinuation.finish()
    }

    // MARK: Zustand (öffentlich für Tests und Anzeige)

    /// Teilnehmerliste (echte nach Anmeldung, dann virtuelle)
    public var currentParticipants: [RaceParticipant] { lock.withLock { participants } }
    /// uids, deren Frames gerade abonniert sind
    public var subscribedIds: Set<String> { lock.withLock { Set(listeners.keys) } }
    /// Rennzeit jetzt (Serverzeit − Start)
    public var raceTimeNow: TimeInterval { clock() + lock.withLock { offset } - onlineRace.startsAt }
    /// Läufe der virtuellen (für die Ergebnisliste nach dem Rennen)
    public var virtualRuns: [VirtualRaceRun] {
        lock.withLock { virtualCache }
    }
    private var virtualCache: [VirtualRaceRun] = []

    // MARK: Teilnehmerliste

    @discardableResult
    private func applyEntries(_ new: [OnlineRaceEntry]?, yield: Bool) -> [RaceParticipant] {
        let current = lock.withLock { () -> [OnlineRaceEntry] in
            if let new { entries = new }
            return entries
        }
        var (list, _) = OnlineRoster.filled(current, race: onlineRace, pool: pool)
        if !list.contains(where: { $0.id == uid }) {
            // eigene Anmeldung noch nicht im Abo (eben geschrieben): trotzdem dabei, hinter den anderen echten
            let lane = (list.filter { !$0.isVirtual }.map(\.lane).max() ?? 0) + 1
            list.append(RaceParticipant(id: uid, displayName: "", lane: lane))
        }
        let virtualIds = list.filter(\.isVirtual).map(\.id)
        let needRuns = lock.withLock { virtualIds != virtualRunIds }
        if needRuns {
            var runs: [VirtualRaceRun] = []
            if let pool {
                let context = VirtualRaceContext(raceId: onlineRace.id, startsAt: onlineRace.startsAt, target: onlineRace.target)
                runs = virtualIds.compactMap { id in pool.rower(id: id).map { VirtualRaceSimulator.run($0, context: context) } }
            }
            let field = runs.isEmpty ? nil : RaceBotField(virtual: runs, participants: list,
                                                          finishDistance: onlineRace.target.finishDistance)
            lock.withLock {
                virtualRunIds = virtualIds
                virtualField = field
                virtualCache = runs
            }
        }
        lock.withLock {
            participants = list
            humans = list.filter { !$0.isVirtual }.map(\.id)
        }
        if yield { rosterContinuation.yield(list) }
        updateSubscriptions()
        return list
    }

    // MARK: Abos

    private func updateSubscriptions() {
        let (add, remove, removed): (Set<String>, Set<String>, [any RaceLiveObservation]) = lock.withLock {
            guard joined, !closed else { return ([], [], []) }
            let want = RaceLiveSubscriptions.desired(humans: humans, me: uid, smallField: onlineRace.isSmallField,
                                                     interest: interest, neighbours: config.neighbours)
            let d = RaceLiveSubscriptions.diff(current: Set(listeners.keys), desired: want)
            var gone: [any RaceLiveObservation] = []
            for id in d.remove { if let o = listeners.removeValue(forKey: id) { gone.append(o) } }
            return (d.add, d.remove, gone)
        }
        _ = remove
        for o in removed { o.cancel() }
        for id in add {
            let o = backend.observeFrame(raceId: onlineRace.id, uid: id) { [weak self] w in self?.receive(id, w) }
            let keep = lock.withLock { () -> Bool in
                guard joined, !closed, listeners[id] == nil else { return false }
                listeners[id] = o
                return true
            }
            if !keep { o.cancel() }
        }
    }

    private func receive(_ id: String, _ w: RaceWireFrame?) {
        guard id != uid, let w, let f = RaceLiveWire.decode(w, raceId: onlineRace.id, participantId: id) else { return }
        let fresh = lock.withLock { () -> Bool in
            guard !closed else { return false }
            if let l = latest[id], f.seq <= l.seq { return false }
            latest[id] = f
            lastReceived[id] = clock()
            return true
        }
        if fresh { framesContinuation.yield(f) }
    }

    private func receiveServerField(_ s: RaceFieldSnapshot) {
        lock.withLock { serverFieldSeen = true }
        fieldContinuation.yield(s)
    }

    // MARK: Takt: virtuelle Frames und lokale Übersicht

    private func startLoop() {
        let interval = 1 / max(config.virtualRate, 0.5)
        let t = Task { [weak self] in
            var lastOverview = -Double.infinity
            while !Task.isCancelled {
                guard let self else { return }
                let rt = self.raceTimeNow
                if rt >= 0 {
                    for f in self.virtualFrames(raceTime: rt) { self.framesContinuation.yield(f) }
                    if rt - lastOverview >= self.config.overviewInterval - 1e-6, self.wantsLocalOverview(raceTime: rt),
                       let s = self.localSnapshot(raceTime: rt) {
                        lastOverview = rt
                        self.fieldContinuation.yield(s)
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        lock.withLock { loop?.cancel(); loop = t }
    }

    /// Lokale Übersicht im Kleinfeld, im grossen Feld nur ohne Aggregator
    public func wantsLocalOverview(raceTime: TimeInterval) -> Bool {
        if onlineRace.isSmallField { return true }
        return lock.withLock { !serverFieldSeen } && raceTime > config.serverFieldWait
    }

    /// Volle Frames der virtuellen im Abo (ohne Abo: die nächsten zur eigenen Distanz)
    public func virtualFrames(raceTime rt: TimeInterval) -> [LiveFrame] {
        let (field, ids, myDistance, seq, sentAt) = lock.withLock { () -> (RaceBotField?, Set<String>?, Double, Int, TimeInterval) in
            virtualSeq += 1
            return (virtualField, interest?.fullIds, myLatest?.distance ?? 0, virtualSeq, clock() + offset)
        }
        guard let field else { return [] }
        var wanted: Set<String>
        if let ids {
            wanted = ids
        } else {
            let near = field.bots.indices
                .map { (field.bots[$0].participant.id, abs(field.position(of: $0, at: rt).distance - myDistance)) }
                .sorted { $0.1 < $1.1 }
                .prefix(config.neighbours)
            wanted = Set(near.map(\.0))
        }
        var out: [LiveFrame] = []
        for i in field.bots.indices where wanted.contains(field.bots[i].participant.id) {
            out.append(field.frame(of: i, raceId: onlineRace.id, seq: seq, raceTime: rt, sentAt: sentAt))
        }
        return out
    }

    /// Übersicht aus allen bekannten Ständen: echte aus ihren letzten Frames (auch ich), virtuelle aus der Simulation;
    /// „veraltet“ aus Anwesenheit und Alter. Kurzindex aus derselben Teilnehmerliste wie `roster`.
    public func localSnapshot(raceTime rt: TimeInterval) -> RaceFieldSnapshot? {
        let state = lock.withLock { () -> (list: [RaceParticipant], latest: [String: LiveFrame], received: [String: TimeInterval], online: Set<String>?, field: RaceBotField?, me: LiveFrame?, sentAt: TimeInterval, seq: Int) in
            overviewSeq += 1
            return (participants, latest, lastReceived, online, virtualField, myLatest, clock() + offset, overviewSeq)
        }
        guard !state.list.isEmpty else { return nil }
        var all = state.latest
        if let me = state.me { all[uid] = me }
        if let field = state.field {
            for i in field.bots.indices {
                let f = field.frame(of: i, raceId: onlineRace.id, seq: state.seq, raceTime: rt, sentAt: state.sentAt)
                all[f.participantId] = f
            }
        }
        let index = RaceRosterIndex(participants: state.list)
        var s = RaceFieldSnapshot.build(raceId: onlineRace.id, seq: state.seq, sentAt: state.sentAt, raceTime: rt,
                                        roster: index, latest: all, maxExtrapolation: config.staleAfter,
                                        staleAfter: .infinity)
        let now = clock()
        let virtual = Set(state.list.filter(\.isVirtual).map(\.id))
        for k in s.entries.indices {
            guard let id = index.id(at: s.entries[k].index), id != uid, !virtual.contains(id) else { continue }
            if RaceLivePresence.isStale(id: id, online: state.online, lastReceivedLocal: state.received[id], now: now,
                                        finished: s.entries[k].finished, staleAfter: config.staleAfter) {
                s.entries[k].stale = true
            }
        }
        return s
    }
}

// MARK: - Im Speicher (Tests, Demo ohne Server)

/// Realtime Database im Speicher, mit den Prüfungen der Regeln: schreiben nur nach `joinLive`, `n` wachsend,
/// Base64-Länge 24 oder 32. Mehrere Transporte (Geräte) teilen sich einen Hub.
public final class InMemoryRaceLiveHub: @unchecked Sendable {
    public enum HubError: Error, Equatable { case notMember, staleSeq, invalid }

    private let lock = NSLock()
    private var frames: [String: RaceWireFrame] = [:]
    private var members: Set<String> = []
    private var online: [String: Set<String>] = [:]
    private var frameObservers: [String: [UUID: @Sendable (RaceWireFrame?) -> Void]] = [:]
    private var presenceObservers: [String: [UUID: @Sendable (Set<String>) -> Void]] = [:]
    private var fieldObservers: [String: [UUID: @Sendable (RaceFieldSnapshot) -> Void]] = [:]
    private var fieldFull: [String: RaceFieldSnapshot] = [:]
    /// Serverzeit − Gerätezeit
    public var offset: TimeInterval
    /// Zählung für Tests
    public private(set) var writes = 0
    public private(set) var subscribes = 0
    public private(set) var unsubscribes = 0

    public init(offset: TimeInterval = 0) { self.offset = offset }

    public func backend() -> RaceLiveBackend { Backend(hub: self) }

    public func activeFrameListeners(raceId: String, uid: String) -> Int {
        lock.withLock { frameObservers[RaceLiveWire.framePath(raceId: raceId, uid: uid)]?.count ?? 0 }
    }

    public func frame(raceId: String, uid: String) -> RaceWireFrame? {
        lock.withLock { frames[RaceLiveWire.framePath(raceId: raceId, uid: uid)] }
    }

    /// Verbindungsabbruch eines Geräts (onDisconnect): Anwesenheit entfernen
    public func disconnect(raceId: String, uid: String) {
        let (ids, obs) = lock.withLock { () -> (Set<String>, [@Sendable (Set<String>) -> Void]) in
            online[raceId, default: []].remove(uid)
            return (online[raceId] ?? [], Array((presenceObservers[raceId] ?? [:]).values))
        }
        for o in obs { o(ids) }
    }

    /// Übersicht wie der Aggregator schreiben
    public func publishField(_ s: RaceFieldSnapshot, full: Bool = false) {
        let obs = lock.withLock { () -> [@Sendable (RaceFieldSnapshot) -> Void] in
            if full { fieldFull[s.raceId] = s }
            return Array((fieldObservers[s.raceId] ?? [:]).values)
        }
        for o in obs { o(s) }
    }

    fileprivate func join(raceId: String, uid: String) {
        let (ids, obs) = lock.withLock { () -> (Set<String>, [@Sendable (Set<String>) -> Void]) in
            members.insert(RaceLiveWire.memberPath(raceId: raceId, uid: uid))
            online[raceId, default: []].insert(uid)
            return (online[raceId] ?? [], Array((presenceObservers[raceId] ?? [:]).values))
        }
        for o in obs { o(ids) }
    }

    fileprivate func write(raceId: String, uid: String, frame: RaceWireFrame) throws {
        let path = RaceLiveWire.framePath(raceId: raceId, uid: uid)
        let obs = try lock.withLock { () -> [@Sendable (RaceWireFrame?) -> Void] in
            guard members.contains(RaceLiveWire.memberPath(raceId: raceId, uid: uid)) else { throw HubError.notMember }
            guard RaceLiveWire.allowedLengths.contains(frame.b.count) else { throw HubError.invalid }
            if let old = frames[path], frame.n <= old.n { throw HubError.staleSeq }
            var f = frame
            f.at = Date().timeIntervalSince1970 + offset
            frames[path] = f
            writes += 1
            return Array((frameObservers[path] ?? [:]).values)
        }
        let stored = lock.withLock { frames[path] }
        for o in obs { o(stored) }
    }

    fileprivate func observeFrame(path: String, _ handler: @escaping @Sendable (RaceWireFrame?) -> Void) -> any RaceLiveObservation {
        let id = UUID()
        let current = lock.withLock { () -> RaceWireFrame? in
            frameObservers[path, default: [:]][id] = handler
            subscribes += 1
            return frames[path]
        }
        if let current { handler(current) }
        return Observation { [weak self] in
            self?.lock.withLock {
                if self?.frameObservers[path]?.removeValue(forKey: id) != nil { self?.unsubscribes += 1 }
            }
        }
    }

    fileprivate func observePresence(raceId: String, _ handler: @escaping @Sendable (Set<String>) -> Void) -> any RaceLiveObservation {
        let id = UUID()
        let current = lock.withLock { () -> Set<String> in
            presenceObservers[raceId, default: [:]][id] = handler
            return online[raceId] ?? []
        }
        handler(current)
        return Observation { [weak self] in _ = self?.lock.withLock { self?.presenceObservers[raceId]?.removeValue(forKey: id) } }
    }

    fileprivate func observeField(raceId: String, _ handler: @escaping @Sendable (RaceFieldSnapshot) -> Void) -> any RaceLiveObservation {
        let id = UUID()
        lock.withLock { fieldObservers[raceId, default: [:]][id] = handler }
        return Observation { [weak self] in _ = self?.lock.withLock { self?.fieldObservers[raceId]?.removeValue(forKey: id) } }
    }

    fileprivate func readFieldFull(raceId: String) -> RaceFieldSnapshot? { lock.withLock { fieldFull[raceId] } }

    private final class Observation: RaceLiveObservation, @unchecked Sendable {
        private let lock = NSLock()
        private var onCancel: (() -> Void)?
        init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
        func cancel() {
            let c = lock.withLock { () -> (() -> Void)? in defer { onCancel = nil }; return onCancel }
            c?()
        }
    }

    private final class Backend: RaceLiveBackend, @unchecked Sendable {
        let hub: InMemoryRaceLiveHub
        init(hub: InMemoryRaceLiveHub) { self.hub = hub }
        func serverTimeOffset() async throws -> TimeInterval { hub.offset }
        func joinLive(raceId: String, uid: String) async throws { hub.join(raceId: raceId, uid: uid) }
        func leaveLive(raceId: String, uid: String) async { hub.disconnect(raceId: raceId, uid: uid) }
        func readFrame(raceId: String, uid: String) async throws -> RaceWireFrame? { hub.frame(raceId: raceId, uid: uid) }
        func writeFrame(raceId: String, uid: String, frame: RaceWireFrame) async throws {
            try hub.write(raceId: raceId, uid: uid, frame: frame)
        }
        func observeFrame(raceId: String, uid: String, onChange: @escaping @Sendable (RaceWireFrame?) -> Void) -> any RaceLiveObservation {
            hub.observeFrame(path: RaceLiveWire.framePath(raceId: raceId, uid: uid), onChange)
        }
        func observePresence(raceId: String, onChange: @escaping @Sendable (Set<String>) -> Void) -> any RaceLiveObservation {
            hub.observePresence(raceId: raceId, onChange)
        }
        func observeField(raceId: String, onChange: @escaping @Sendable (RaceFieldSnapshot) -> Void) -> any RaceLiveObservation {
            hub.observeField(raceId: raceId, onChange)
        }
        func readFieldFull(raceId: String) async throws -> RaceFieldSnapshot? { hub.readFieldFull(raceId: raceId) }
    }
}

/// Firestore-Teil im Speicher mit den Regeln für Rennen: Anlegen prüft `OnlineRace.validationError`, Anmelden nur
/// vor dem Meldeschluss und bis `maxParticipants`, Ergebnisse von Clients nur vorläufig und nur die eigenen.
public final class InMemoryRaceDirectory: RaceDirectory, @unchecked Sendable {
    private let lock = NSLock()
    private var races: [String: OnlineRace] = [:]
    private var codes: [String: String] = [:]
    private var entryStore: [String: [String: OnlineRaceEntry]] = [:]
    private var resultStore: [String: [String: OnlineRaceResult]] = [:]
    private var entryObservers: [String: [UUID: @Sendable ([OnlineRaceEntry]) -> Void]] = [:]
    private var resultObservers: [String: [UUID: @Sendable ([OnlineRaceResult]) -> Void]] = [:]
    private var nextId = 1
    /// angemeldete uid dieses „Geräts“ (nil = abgemeldet)
    public var uid: String?
    /// Serverzeit
    public var now: @Sendable () -> TimeInterval

    public init(uid: String? = "u1", now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.uid = uid
        self.now = now
    }

    /// Zweites „Gerät“ auf denselben Daten
    public func session(uid: String) -> InMemoryRaceDirectory {
        let d = InMemoryRaceDirectory(uid: uid, now: now)
        d.shared = shared ?? self
        return d
    }

    private var shared: InMemoryRaceDirectory?
    private var store: InMemoryRaceDirectory { shared ?? self }

    private func me() throws -> String {
        guard let uid else { throw RaceDirectoryError.notSignedIn }
        return uid
    }

    public func upcoming(serverNow: TimeInterval, limit: Int) async throws -> [OnlineRace] {
        _ = try me()
        let s = store
        return s.lock.withLock {
            s.races.values.filter { $0.visibility == .open && $0.status != .cancelled && $0.startsAt + $0.maxDuration > serverNow }
                .sorted { $0.startsAt < $1.startsAt }.prefix(limit).map { $0 }
        }
    }

    public func race(id: String) async throws -> OnlineRace? {
        _ = try me()
        let s = store
        return s.lock.withLock { s.races[id] }
    }

    public func raceId(inviteCode: String) async throws -> String? {
        _ = try me()
        let s = store
        return s.lock.withLock { s.codes[RaceInviteCode.normalize(inviteCode)] }
    }

    public func create(_ race: OnlineRace, inviteCode: String?) async throws -> OnlineRace {
        let uid = try me()
        guard race.createdBy == uid else { throw RaceDirectoryError.notAllowed }
        if let e = race.validationError(serverNow: now()) { throw RaceDirectoryError.invalid(e) }
        let s = store
        return try s.lock.withLock {
            var r = race
            r.id = "race-\(s.nextId)"
            s.nextId += 1
            r.createdAt = now()
            if let code = inviteCode {
                guard RaceInviteCode.isValid(code), s.codes[code] == nil else { throw RaceDirectoryError.invalid("code") }
                s.codes[code] = r.id
            }
            s.races[r.id] = r
            return r
        }
    }

    public func cancel(raceId: String) async throws {
        let uid = try me()
        let s = store
        try s.lock.withLock {
            guard var r = s.races[raceId] else { throw RaceDirectoryError.notFound }
            guard r.createdBy == uid, now() < r.startsAt else { throw RaceDirectoryError.notAllowed }
            r.status = .cancelled
            s.races[raceId] = r
        }
    }

    public func entries(raceId: String) async throws -> [OnlineRaceEntry] {
        _ = try me()
        let s = store
        return s.lock.withLock { Array((s.entryStore[raceId] ?? [:]).values) }
    }

    public func register(raceId: String, entry: OnlineRaceEntry) async throws {
        let uid = try me()
        guard entry.id == uid, entry.source == .human else { throw RaceDirectoryError.notAllowed }
        let s = store
        let t = now()
        let (list, obs) = try s.lock.withLock { () -> ([OnlineRaceEntry], [@Sendable ([OnlineRaceEntry]) -> Void]) in
            guard let r = s.races[raceId] else { throw RaceDirectoryError.notFound }
            guard r.registrationOpen(serverNow: t) else { throw RaceDirectoryError.registrationClosed }
            var e = s.entryStore[raceId] ?? [:]
            let humans = e.values.filter { $0.source != .virtual }.count
            if e[uid] == nil, humans >= r.maxParticipants { throw RaceDirectoryError.raceFull }
            var new = entry
            new.joinedAt = e[uid]?.joinedAt ?? t
            e[uid] = new
            s.entryStore[raceId] = e
            return (Array(e.values), Array((s.entryObservers[raceId] ?? [:]).values))
        }
        for o in obs { o(list) }
    }

    public func unregister(raceId: String, uid other: String) async throws {
        let uid = try me()
        guard other == uid else { throw RaceDirectoryError.notAllowed }
        let s = store
        let t = now()
        let (list, obs) = try s.lock.withLock { () -> ([OnlineRaceEntry], [@Sendable ([OnlineRaceEntry]) -> Void]) in
            guard let r = s.races[raceId] else { throw RaceDirectoryError.notFound }
            guard t < r.registrationCloses else { throw RaceDirectoryError.registrationClosed }
            s.entryStore[raceId]?[uid] = nil
            return (Array((s.entryStore[raceId] ?? [:]).values), Array((s.entryObservers[raceId] ?? [:]).values))
        }
        for o in obs { o(list) }
    }

    public func observeEntries(raceId: String, onChange: @escaping @Sendable ([OnlineRaceEntry]) -> Void) -> any RaceLiveObservation {
        let s = store, id = UUID()
        let list = s.lock.withLock { () -> [OnlineRaceEntry] in
            s.entryObservers[raceId, default: [:]][id] = onChange
            return Array((s.entryStore[raceId] ?? [:]).values)
        }
        onChange(list)
        return Cancel { _ = s.lock.withLock { s.entryObservers[raceId]?.removeValue(forKey: id) } }
    }

    public func submitResult(raceId: String, result: OnlineRaceResult) async throws {
        let uid = try me()
        guard result.id == uid, result.provisional, result.place == nil else { throw RaceDirectoryError.notAllowed }
        let s = store
        let t = now()
        let (list, obs) = try s.lock.withLock { () -> ([OnlineRaceResult], [@Sendable ([OnlineRaceResult]) -> Void]) in
            guard let r = s.races[raceId] else { throw RaceDirectoryError.notFound }
            guard s.entryStore[raceId]?[uid] != nil, t >= r.startsAt else { throw RaceDirectoryError.notAllowed }
            if let old = s.resultStore[raceId]?[uid], !old.provisional { throw RaceDirectoryError.notAllowed }
            var res = result
            res.submittedAt = t
            s.resultStore[raceId, default: [:]][uid] = res
            return (Array((s.resultStore[raceId] ?? [:]).values), Array((s.resultObservers[raceId] ?? [:]).values))
        }
        for o in obs { o(list) }
    }

    /// Server: endgültiges Ergebnis festschreiben (Tests)
    public func finalize(raceId: String, results: [OnlineRaceResult]) {
        let s = store
        let (list, obs) = s.lock.withLock { () -> ([OnlineRaceResult], [@Sendable ([OnlineRaceResult]) -> Void]) in
            for r in results { s.resultStore[raceId, default: [:]][r.id] = r }
            s.races[raceId]?.status = .finished
            return (Array((s.resultStore[raceId] ?? [:]).values), Array((s.resultObservers[raceId] ?? [:]).values))
        }
        for o in obs { o(list) }
    }

    /// Server: virtuelle Anmeldungen schreiben (Tests)
    public func addServerEntries(raceId: String, _ list: [OnlineRaceEntry]) {
        let s = store
        let (all, obs) = s.lock.withLock { () -> ([OnlineRaceEntry], [@Sendable ([OnlineRaceEntry]) -> Void]) in
            for e in list { s.entryStore[raceId, default: [:]][e.id] = e }
            return (Array((s.entryStore[raceId] ?? [:]).values), Array((s.entryObservers[raceId] ?? [:]).values))
        }
        for o in obs { o(all) }
    }

    public func observeResults(raceId: String, onChange: @escaping @Sendable ([OnlineRaceResult]) -> Void) -> any RaceLiveObservation {
        let s = store, id = UUID()
        let list = s.lock.withLock { () -> [OnlineRaceResult] in
            s.resultObservers[raceId, default: [:]][id] = onChange
            return Array((s.resultStore[raceId] ?? [:]).values)
        }
        onChange(list)
        return Cancel { _ = s.lock.withLock { s.resultObservers[raceId]?.removeValue(forKey: id) } }
    }

    private final class Cancel: RaceLiveObservation, @unchecked Sendable {
        private let lock = NSLock()
        private var action: (() -> Void)?
        init(_ action: @escaping () -> Void) { self.action = action }
        func cancel() {
            let a = lock.withLock { () -> (() -> Void)? in defer { action = nil }; return action }
            a?()
        }
    }
}
