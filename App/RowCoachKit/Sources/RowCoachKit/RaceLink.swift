import Foundation

/// Netzanbindung eines Rennens auf dem Hauptthread: meldet sich bei allen Transporten an (z. B. Server und
/// Geister zugleich), synchronisiert die Uhr, leitet empfangene Frames und Teilnehmerlisten an den
/// `RaceCoordinator` weiter und sendet den eigenen Stand. Die App ruft `update(...)` mit jedem neuen Messwert auf
/// und liest `states(...)` für Szene und Anzeige.
@MainActor
public final class RaceLink {
    public private(set) var coordinator: RaceCoordinator
    public let transports: [any RaceTransport]
    /// wird nach jeder empfangenen Änderung aufgerufen (Frames, Teilnehmerliste)
    public var onChange: (() -> Void)?
    public private(set) var connected = false
    public private(set) var lastError: String?
    /// Startzeitpunkt (lokal), sobald der erste eigene Stand kam; für Gegner ohne Netz (`GhostRaceTransport`)
    public let start: RaceStartMark

    private var tasks: [Task<Void, Never>] = []
    private let now: @Sendable () -> TimeInterval

    public init(coordinator: RaceCoordinator, transports: [any RaceTransport], start: RaceStartMark = RaceStartMark(),
                now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.coordinator = coordinator
        self.transports = transports
        self.start = start
        self.now = now
    }

    public var race: Race { coordinator.race }
    public var me: RaceParticipant { coordinator.me }

    /// Anmelden, Uhr abgleichen (3 Rundläufe beim ersten Transport), Empfang starten
    public func connect(clockSamples: Int = 3) async throws {
        var roster: [RaceParticipant] = []
        for t in transports {
            let list = try await t.join(race: coordinator.race, as: coordinator.me)
            roster.append(contentsOf: list.filter { p in !roster.contains(where: { $0.id == p.id }) })
        }
        coordinator.setRoster(roster)
        if let first = transports.first {
            for _ in 0..<max(clockSamples, 0) {
                let t0 = now()
                guard let server = try? await first.serverTime() else { break }
                coordinator.clock.addSample(sentLocal: t0, server: server, receivedLocal: now())
            }
        }
        for t in transports {
            tasks.append(Task { [weak self] in
                for await frame in t.frames {
                    guard let self else { return }
                    self.coordinator.receive(frame, receivedLocal: self.now())
                    self.onChange?()
                }
            })
            tasks.append(Task { [weak self] in
                for await list in t.roster {
                    guard let self else { return }
                    self.merge(roster: list)
                    self.onChange?()
                }
            })
        }
        connected = true
    }

    private func merge(roster list: [RaceParticipant]) {
        var all = coordinator.roster
        for p in list {
            if let i = all.firstIndex(where: { $0.id == p.id }) { all[i] = p } else { all.append(p) }
        }
        coordinator.setRoster(all)
    }

    /// Eigenen Stand übernehmen und, wenn die Drossel es erlaubt, an alle Transporte senden
    public func update(raceTime: TimeInterval, distance: Double, pace: TimeInterval, strokeRate: Int,
                       heartRate: Int? = nil, finished: Bool = false, stroke: Bool = false) {
        start.markIfNeeded(local: now() - raceTime)
        guard let frame = coordinator.updateLocal(raceTime: raceTime, distance: distance, pace: pace,
                                                  strokeRate: strokeRate, heartRate: heartRate, finished: finished,
                                                  stroke: stroke, local: now()) else { return }
        guard connected else { return }
        for t in transports {
            Task { [weak self] in
                do { try await t.publish(frame) } catch { self?.lastError = "\(error)" }
            }
        }
    }

    public func states(raceTime: TimeInterval, myDistance: Double, mySpeed: Double) -> [RemoteRowerState] {
        coordinator.states(raceTime: raceTime, myDistance: myDistance, mySpeed: mySpeed, local: now())
    }

    public func disconnect() async {
        for t in tasks { t.cancel() }
        tasks = []
        for t in transports { await t.leave() }
        connected = false
    }
}

/// Lokaler Startzeitpunkt eines Rennens ohne gemeinsamen Start (erster eigener Schlag), threadsicher lesbar –
/// z. B. für `GhostRaceTransport(ghosts:raceTime:)` mit `{ mark.raceTime(local: Date().timeIntervalSince1970) }`.
public final class RaceStartMark: @unchecked Sendable {
    private let lock = NSLock()
    private var startLocal: TimeInterval?

    public init() {}

    public func markIfNeeded(local: TimeInterval) {
        lock.withLock { if startLocal == nil { startLocal = local } }
    }

    public func reset() { lock.withLock { startLocal = nil } }

    /// Rennzeit zur lokalen Uhrzeit, nil vor dem Start
    public func raceTime(local now: TimeInterval) -> TimeInterval? {
        lock.withLock { startLocal.map { now - $0 } }
    }
}
