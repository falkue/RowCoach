import Foundation

/// Verbindung zu einem Rennen: anmelden, eigene Frames senden, Frames und Teilnehmerliste der anderen empfangen.
///
/// Eine Instanz gehört zu genau einem Teilnehmenden in genau einem Rennen. Die Ströme `frames` und `roster` enden
/// mit `leave()`. `frames` liefert nur Frames der anderen (nie die eigenen).
///
/// Umsetzungen:
/// - `LoopbackRaceTransport`: im Speicher über einen `LoopbackRaceHub` (Tests, mehrere Boote auf einem Gerät).
/// - `GhostRaceTransport`: spielt eine gespeicherte Fahrt als Gegner ab („gegen meine Bestfahrt“).
/// - später `FirebaseRaceTransport` (nicht umgesetzt, siehe docs/MULTIPLAYER.md): Firebase Realtime Database für die
///   Frames (`/races/{raceId}/frames/{participantId}` – nur der letzte Stand, überschrieben), Firestore für Turniere,
///   Teilnehmende und Ergebnisse, Serverzeit über `/.info/serverTimeOffset` bzw. `ServerValue.timestamp`,
///   Anmeldung über Firebase Auth. Swift auf Android würde dieselbe Schnittstelle über das Firebase-Android-SDK
///   (swift-java) erfüllen.
public protocol RaceTransport: Sendable {
    /// Anmelden; liefert die Teilnehmerliste zum Zeitpunkt der Anmeldung
    func join(race: Race, as participant: RaceParticipant) async throws -> [RaceParticipant]
    /// Eigenen Stand senden
    func publish(_ frame: LiveFrame) async throws
    /// Frames der anderen
    var frames: AsyncStream<LiveFrame> { get }
    /// Teilnehmerliste bei jeder Änderung
    var roster: AsyncStream<[RaceParticipant]> { get }
    /// Serverzeit (Sekunden seit 1970) für `RaceClock`
    func serverTime() async throws -> TimeInterval
    func leave() async
}

public enum RaceTransportError: Error, Equatable, Sendable {
    case notJoined
    case raceFull
    case laneTaken(Int)
}

/// Rennen im Speicher: verteilt Frames an alle anderen angemeldeten Transporte desselben Rennens.
public actor LoopbackRaceHub {
    private struct Member {
        let participant: RaceParticipant
        let frames: AsyncStream<LiveFrame>.Continuation
        let roster: AsyncStream<[RaceParticipant]>.Continuation
    }

    private var races: [String: [String: Member]] = [:]
    private var lanes: [String: Int] = [:]
    /// Serverzeit = lokale Zeit + `clockOffset` (zum Testen der Uhrsynchronisation)
    public let clockOffset: TimeInterval

    public init(clockOffset: TimeInterval = 0) {
        self.clockOffset = clockOffset
    }

    func join(race: Race, participant: RaceParticipant, frames: AsyncStream<LiveFrame>.Continuation,
              roster: AsyncStream<[RaceParticipant]>.Continuation) throws -> [RaceParticipant] {
        var members = races[race.id] ?? [:]
        if members[participant.id] == nil {
            guard members.count < race.lanes else { throw RaceTransportError.raceFull }
            if members.values.contains(where: { $0.participant.lane == participant.lane }) {
                throw RaceTransportError.laneTaken(participant.lane)
            }
        }
        lanes[race.id] = race.lanes
        members[participant.id] = Member(participant: participant, frames: frames, roster: roster)
        races[race.id] = members
        broadcastRoster(race.id)
        return list(race.id)
    }

    func publish(_ frame: LiveFrame) throws {
        guard let members = races[frame.raceId], members[frame.participantId] != nil else {
            throw RaceTransportError.notJoined
        }
        for (id, m) in members where id != frame.participantId {
            m.frames.yield(frame)
        }
    }

    func leave(raceId: String, participantId: String) {
        guard var members = races[raceId], let m = members.removeValue(forKey: participantId) else { return }
        m.frames.finish()
        m.roster.finish()
        races[raceId] = members
        broadcastRoster(raceId)
    }

    func now() -> TimeInterval { Date().timeIntervalSince1970 + clockOffset }

    private func list(_ raceId: String) -> [RaceParticipant] {
        (races[raceId] ?? [:]).values.map(\.participant).sorted { $0.lane < $1.lane }
    }

    private func broadcastRoster(_ raceId: String) {
        let l = list(raceId)
        for m in (races[raceId] ?? [:]).values { m.roster.yield(l) }
    }
}

/// Transport über einen `LoopbackRaceHub`
public final class LoopbackRaceTransport: RaceTransport, @unchecked Sendable {
    public let hub: LoopbackRaceHub
    public let frames: AsyncStream<LiveFrame>
    public let roster: AsyncStream<[RaceParticipant]>
    private let framesContinuation: AsyncStream<LiveFrame>.Continuation
    private let rosterContinuation: AsyncStream<[RaceParticipant]>.Continuation
    private let lock = NSLock()
    private var joined: (raceId: String, participantId: String)?

    public init(hub: LoopbackRaceHub) {
        self.hub = hub
        (frames, framesContinuation) = AsyncStream.makeStream(of: LiveFrame.self, bufferingPolicy: .bufferingNewest(256))
        (roster, rosterContinuation) = AsyncStream.makeStream(of: [RaceParticipant].self, bufferingPolicy: .bufferingNewest(8))
    }

    public func join(race: Race, as participant: RaceParticipant) async throws -> [RaceParticipant] {
        let list = try await hub.join(race: race, participant: participant, frames: framesContinuation,
                                      roster: rosterContinuation)
        lock.withLock { joined = (race.id, participant.id) }
        return list
    }

    public func publish(_ frame: LiveFrame) async throws {
        try await hub.publish(frame)
    }

    public func serverTime() async throws -> TimeInterval { await hub.now() }

    public func leave() async {
        let j = lock.withLock { () -> (raceId: String, participantId: String)? in
            defer { joined = nil }
            return joined
        }
        if let j {
            await hub.leave(raceId: j.raceId, participantId: j.participantId)
        } else {
            framesContinuation.finish()
            rosterContinuation.finish()
        }
    }
}

/// Eine gespeicherte Fahrt als Gegner: Distanz, Tempo und Schlagzahl zur Rennzeit aus den Messwerten der Fahrt
/// (Zeit seit dem ersten Schlag, linear interpoliert). Nach dem Ende der Fahrt bzw. bei `finishDistance` ist sie im Ziel.
public struct GhostRower: Equatable, Sendable {
    public let participant: RaceParticipant
    public let samples: [WorkoutSample]
    /// Zieldistanz (Distanzrennen); nil = bis zum Ende der Fahrt
    public let finishDistance: Double?

    public init(participant: RaceParticipant, samples: [WorkoutSample], finishDistance: Double? = nil) {
        self.participant = participant
        self.samples = samples.sorted { $0.time < $1.time }
        self.finishDistance = finishDistance
    }

    public init(participant: RaceParticipant, record: WorkoutRecord, finishDistance: Double? = nil) {
        self.init(participant: participant, samples: record.samples, finishDistance: finishDistance)
    }

    /// Gleichmässiges Tempo (Bot): Messwerte jede Sekunde bis `duration`
    public static func steady(participant: RaceParticipant, pace: TimeInterval, strokeRate: Int = 24,
                              duration: TimeInterval, finishDistance: Double? = nil) -> GhostRower {
        let v = pace > 0 ? 500 / pace : 0
        let n = max(Int(duration.rounded(.up)), 1)
        let samples = (0...n).map {
            WorkoutSample(time: Double($0), distance: v * Double($0), pace: pace, strokeRate: strokeRate, power: 0,
                          heartRate: nil)
        }
        return GhostRower(participant: participant, samples: samples, finishDistance: finishDistance)
    }

    /// Rennzeit, zu der die Fahrt `finishDistance` erreicht (nil, wenn nie)
    public var finishTime: TimeInterval? {
        guard let target = finishDistance else { return samples.last?.time }
        guard let i = samples.firstIndex(where: { $0.distance >= target }) else { return nil }
        guard i > 0 else { return samples[i].time }
        let a = samples[i - 1], b = samples[i]
        let f = b.distance > a.distance ? (target - a.distance) / (b.distance - a.distance) : 1
        return a.time + (b.time - a.time) * f
    }

    public func frame(raceId: String, seq: Int, raceTime: TimeInterval, sentAt: TimeInterval) -> LiveFrame {
        let t = max(raceTime, 0)
        if let ft = finishTime, t >= ft {
            let d = finishDistance ?? samples.last?.distance ?? 0
            return LiveFrame(participantId: participant.id, raceId: raceId, seq: seq, sentAt: sentAt, raceTime: t,
                             distance: d, pace: 0, strokeRate: 0, finished: true, finishTime: ft)
        }
        guard let first = samples.first else {
            return LiveFrame(participantId: participant.id, raceId: raceId, seq: seq, sentAt: sentAt, raceTime: t,
                             distance: 0, pace: 0, strokeRate: 0)
        }
        var a = first, b = first
        if let i = samples.firstIndex(where: { $0.time > t }) {
            b = samples[i]
            a = i > 0 ? samples[i - 1] : samples[i]
        } else {
            a = samples[samples.count - 1]
            b = a
        }
        let f = b.time > a.time ? (t - a.time) / (b.time - a.time) : 0
        let d = a.distance + (b.distance - a.distance) * min(max(f, 0), 1)
        let src = f < 0.5 ? a : b
        return LiveFrame(participantId: participant.id, raceId: raceId, seq: seq, sentAt: sentAt, raceTime: t,
                         distance: d, pace: src.pace, strokeRate: src.strokeRate, heartRate: src.heartRate)
    }
}

/// Transport, der Gegner aus gespeicherten Fahrten erzeugt (kein Netz). Die Rennzeit liefert `raceTime`
/// (z. B. die Zeit seit dem ersten eigenen Schlag); ein Hintergrund-Task sendet `rate`-mal pro Sekunde je Gegner einen
/// Frame, sobald die Rennzeit ≥ 0 ist. Eigene Frames werden angenommen und verworfen.
public final class GhostRaceTransport: RaceTransport, @unchecked Sendable {
    public let ghosts: [GhostRower]
    public let rate: Double
    public let frames: AsyncStream<LiveFrame>
    public let roster: AsyncStream<[RaceParticipant]>
    private let framesContinuation: AsyncStream<LiveFrame>.Continuation
    private let rosterContinuation: AsyncStream<[RaceParticipant]>.Continuation
    private let raceTime: @Sendable () -> TimeInterval?
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    /// - Parameter raceTime: aktuelle Rennzeit (s), nil = Rennen hat noch nicht begonnen
    public init(ghosts: [GhostRower], rate: Double = 4, raceTime: @escaping @Sendable () -> TimeInterval?) {
        self.ghosts = ghosts
        self.rate = max(rate, 0.5)
        self.raceTime = raceTime
        (frames, framesContinuation) = AsyncStream.makeStream(of: LiveFrame.self, bufferingPolicy: .bufferingNewest(256))
        (roster, rosterContinuation) = AsyncStream.makeStream(of: [RaceParticipant].self, bufferingPolicy: .bufferingNewest(8))
    }

    public func join(race: Race, as participant: RaceParticipant) async throws -> [RaceParticipant] {
        let list = ([participant] + ghosts.map(\.participant)).sorted { $0.lane < $1.lane }
        rosterContinuation.yield(list)
        let ghosts = self.ghosts, rate = self.rate, raceTime = self.raceTime, out = framesContinuation
        let t = Task {
            var seq = 0
            var done = Set<String>()
            while !Task.isCancelled {
                if let rt = raceTime(), rt >= 0 {
                    seq += 1
                    let now = Date().timeIntervalSince1970
                    for g in ghosts where !done.contains(g.participant.id) {
                        let f = g.frame(raceId: race.id, seq: seq, raceTime: rt, sentAt: now)
                        out.yield(f)
                        if f.finished { done.insert(g.participant.id) }
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / rate))
            }
        }
        lock.withLock { task?.cancel(); task = t }
        return list
    }

    public func publish(_ frame: LiveFrame) async throws {}

    public func serverTime() async throws -> TimeInterval { Date().timeIntervalSince1970 }

    public func leave() async {
        lock.withLock { task?.cancel(); task = nil }
        framesContinuation.finish()
        rosterContinuation.finish()
    }
}
