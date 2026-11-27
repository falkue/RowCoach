import Foundation

// Bot-Feld für Demo und Tests grosser Rennen (`-demoRace 300` später in der App): N Bots mit realistischer
// Tempoverteilung um ein Bezugstempo, Anlauf, Ermüdung, Schwankung und Endspurt. Deterministisch (Saat), nur
// Foundation. `RaceBotTransport` spielt das Feld wie ein Server mit Nachbarschafts-Abo und Übersicht ab.

/// Kleiner deterministischer Zufallsgenerator (SplitMix64), gleich auf allen Plattformen
public struct RaceRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// gleichverteilt in [0, 1)
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// normalverteilt (Box-Muller)
    public mutating func normal(mean: Double = 0, sd: Double = 1) -> Double {
        let u1 = max(unit(), 1e-12), u2 = unit()
        return mean + sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// Ein Bot: Grundtempo und Verlauf
public struct RaceBot: Equatable, Sendable {
    public var participant: RaceParticipant
    /// Grundtempo (s/500 m) nach dem Anlauf
    public var basePace: TimeInterval
    /// Ermüdung: so viele Sekunden je 500 m langsamer pro 500 m gefahrener Strecke
    public var fatigue: Double
    /// Endspurt auf den letzten `sprintDistance` m: so viele Sekunden je 500 m schneller
    public var sprint: Double
    /// Schwankung des Tempos (± s/500 m), Periode und Phase
    public var wobble: Double
    public var wobblePeriod: TimeInterval
    public var wobblePhase: Double
    /// Schlagzahl beim Grundtempo; sie folgt dem Tempo (≈ 1 Schlag/min je 2 s/500 m) und steigt bei Zwischenspurts
    public var strokeRate: Int
    /// Zwischenspurts („Power 10/20“): Rennzeiten, in denen der Bot 3 s/500 m schneller und 3 Schläge höher fährt
    public var pushes: [ClosedRange<Double>] = []
}

/// Ein Feld von Bots. Der Verlauf wird beim Anlegen in 1-s-Schritten vorausberechnet (300 Bots × 15 min ≈ 2 MB).
public struct RaceBotField: Sendable {
    public struct Config: Equatable, Sendable {
        public var count: Int
        /// Bezugstempo (s/500 m), z. B. das eigene
        public var referencePace: TimeInterval = 120
        /// Streuung um das Bezugstempo (Standardabweichung, s/500 m)
        public var spread: Double = 6
        /// Anteil deutlich Schneller bzw. Langsamer (zusätzlich 6–15 s/500 m)
        public var fastShare: Double = 0.08
        public var slowShare: Double = 0.12
        /// Ermüdung je Bot gleichverteilt in diesem Bereich (s/500 m je 500 m)
        public var fatigue: ClosedRange<Double> = 0.2...1.6
        public var sprint: ClosedRange<Double> = 1...5
        public var sprintDistance: Double = 250
        /// Zieldistanz (Distanzrennen); nil = ohne Ziel
        public var finishDistance: Double? = 2000
        /// Anlauf: in dieser Zeit von 40 % auf volles Tempo
        public var rampUp: TimeInterval = 12
        /// längste vorausberechnete Dauer (s)
        public var maxDuration: TimeInterval = 900
        public var seed: UInt64 = 1
        /// erste Bahn der Bots (die eigene Bahn ist meist 1)
        public var firstLane = 2

        public init(count: Int, referencePace: TimeInterval = 120, finishDistance: Double? = 2000, seed: UInt64 = 1) {
            self.count = max(count, 0)
            self.referencePace = referencePace
            self.finishDistance = finishDistance
            self.seed = seed
        }
    }

    public let config: Config
    public let bots: [RaceBot]
    /// Distanz und Schlagzahl je Bot und Sekunde
    private let track: [[Double]]
    private let rates: [[UInt8]]
    private let finishTimes: [TimeInterval?]

    public init(config: Config) {
        self.config = config
        var rng = RaceRandom(seed: config.seed)
        var bots: [RaceBot] = []
        bots.reserveCapacity(config.count)
        for i in 0..<config.count {
            var pace = rng.normal(mean: config.referencePace, sd: config.spread)
            let r = rng.unit()
            if r < config.fastShare { pace -= 6 + 9 * rng.unit() } else if r > 1 - config.slowShare { pace += 6 + 9 * rng.unit() }
            pace = min(max(pace, 85), 200)
            let f = config.fatigue.lowerBound + (config.fatigue.upperBound - config.fatigue.lowerBound) * rng.unit()
            let s = config.sprint.lowerBound + (config.sprint.upperBound - config.sprint.lowerBound) * rng.unit()
            let id = String(format: "bot-%03d", i + 1)
            let p = RaceParticipant(id: id, displayName: "Bot \(i + 1)", lane: config.firstLane + i, source: .bot)
            var pushes: [ClosedRange<Double>] = []
            for _ in 0..<(1 + Int(rng.unit() * 3)) {
                let start = 40 + rng.unit() * max(config.referencePace * 4 - 100, 60)
                pushes.append(start...(start + 10 + 15 * rng.unit()))
            }
            bots.append(RaceBot(participant: p, basePace: pace, fatigue: f, sprint: s, wobble: 0.5 + 1.5 * rng.unit(),
                                wobblePeriod: 30 + 60 * rng.unit(), wobblePhase: rng.unit() * 2 * .pi,
                                strokeRate: Int((24 + (120 - pace) * 0.25).rounded()), pushes: pushes))
        }
        self.bots = bots
        let n = Int(config.maxDuration.rounded(.up))
        var track: [[Double]] = []
        var rates: [[UInt8]] = []
        var finishes: [TimeInterval?] = []
        track.reserveCapacity(bots.count)
        for b in bots {
            var d = 0.0
            var row = [Double](repeating: 0, count: n + 1)
            var rateRow = [UInt8](repeating: UInt8(b.strokeRate), count: n + 1)
            var finish: TimeInterval?
            for t in stride(from: 1, through: n, by: 1) {
                let v = Self.speed(bot: b, config: config, time: Double(t) - 0.5, distance: d)
                let next = d + v
                if finish == nil, let fd = config.finishDistance, next >= fd {
                    finish = Double(t - 1) + (v > 0 ? (fd - d) / v : 0)
                }
                let pace = Self.pace(bot: b, config: config, time: Double(t) - 0.5, distance: d)
                let spm = Double(b.strokeRate) + (b.basePace - pace) * 0.5
                    + (b.pushes.contains { $0.contains(Double(t)) } ? 1.5 : 0)
                rateRow[t - 1] = UInt8(min(max(spm.rounded(), 16), 48))
                d = config.finishDistance.map { min(next, $0) } ?? next
                row[t] = d
            }
            rateRow[n] = rateRow[max(n - 1, 0)]
            track.append(row)
            rates.append(rateRow)
            finishes.append(finish)
        }
        self.track = track
        self.rates = rates
        finishTimes = finishes
    }

    /// Feld aus vorausberechneten Verläufen (z. B. virtuelle Teilnehmende, `RaceBotField(virtual:…)`)
    init(config: Config, bots: [RaceBot], track: [[Double]], rates: [[UInt8]], finishTimes: [TimeInterval?]) {
        self.config = config
        self.bots = bots
        self.track = track
        self.rates = rates
        self.finishTimes = finishTimes
    }

    public var participants: [RaceParticipant] { bots.map(\.participant) }

    /// Tempo (s/500 m) eines Bots zur Zeit und Distanz
    public static func pace(bot b: RaceBot, config: Config, time: TimeInterval, distance d: Double) -> TimeInterval {
        var pace = b.basePace + b.fatigue * d / 500 + b.wobble * sin(2 * .pi * time / b.wobblePeriod + b.wobblePhase)
        if let fd = config.finishDistance, fd - d <= config.sprintDistance { pace -= b.sprint }
        if b.pushes.contains(where: { $0.contains(time) }) { pace -= 3 }
        return max(pace, 80)
    }

    static func speed(bot b: RaceBot, config: Config, time: TimeInterval, distance d: Double) -> Double {
        let ramp = config.rampUp > 0 ? min(0.4 + 0.6 * time / config.rampUp, 1) : 1
        return 500 / pace(bot: b, config: config, time: time, distance: d) * ramp
    }

    /// Distanz, Geschwindigkeit und Zielstatus eines Bots zur Rennzeit
    public func position(of i: Int, at raceTime: TimeInterval) -> (distance: Double, speed: Double, finished: Bool, finishTime: TimeInterval?) {
        let row = track[i]
        let t = min(max(raceTime, 0), Double(row.count - 1))
        if let ft = finishTimes[i], raceTime >= ft { return (row[row.count - 1], 0, true, ft) }
        let k = min(Int(t), row.count - 2)
        let f = t - Double(k)
        let d = row[k] + (row[k + 1] - row[k]) * f
        return (d, row[k + 1] - row[k], false, nil)
    }

    /// Schlagzahl zur Rennzeit
    public func strokeRate(of i: Int, at raceTime: TimeInterval) -> Int {
        let row = rates[i]
        return Int(row[min(max(Int(raceTime), 0), row.count - 1)])
    }

    public func frame(of i: Int, raceId: String, seq: Int, raceTime: TimeInterval, sentAt: TimeInterval) -> LiveFrame {
        let p = position(of: i, at: raceTime)
        let b = bots[i]
        let pace = p.speed > 0 ? 500 / p.speed : 0
        return LiveFrame(participantId: b.participant.id, raceId: raceId, seq: seq, sentAt: sentAt, raceTime: max(raceTime, 0),
                         distance: p.distance, pace: p.finished ? 0 : pace,
                         strokeRate: p.finished ? 0 : strokeRate(of: i, at: raceTime),
                         finished: p.finished, finishTime: p.finishTime)
    }

    /// Alle Bots als Planer-Eingabe (volle Genauigkeit), z. B. für Tests
    public func members(at raceTime: TimeInterval, marked: Set<String> = []) -> [RaceFieldMember] {
        bots.indices.map { i in
            let p = position(of: i, at: raceTime)
            let id = bots[i].participant.id
            return RaceFieldMember(id: id, distance: p.distance, speed: p.speed, strokeRate: p.finished ? 0 : strokeRate(of: i, at: raceTime),
                                   finished: p.finished, source: bots[i].participant.source, precise: true, marked: marked.contains(id))
        }
    }
}

/// Spielt ein `RaceBotField` wie ein Server ab: volle Frames (`rate`/s) nur für die abonnierten ids
/// (`setInterest`; ohne Abo die `defaultNeighbours` nächsten zur zuletzt gesendeten eigenen Distanz) und jede
/// Sekunde eine Übersicht über alle. Rennzeit wie `GhostRaceTransport` über `raceTime`.
public final class RaceBotTransport: RaceTransport, @unchecked Sendable {
    public let field: RaceBotField
    public let rate: Double
    public let defaultNeighbours: Int
    public let frames: AsyncStream<LiveFrame>
    public let roster: AsyncStream<[RaceParticipant]>
    public let fieldSnapshots: AsyncStream<RaceFieldSnapshot>
    private let framesContinuation: AsyncStream<LiveFrame>.Continuation
    private let rosterContinuation: AsyncStream<[RaceParticipant]>.Continuation
    private let fieldContinuation: AsyncStream<RaceFieldSnapshot>.Continuation
    private let raceTime: @Sendable () -> TimeInterval?
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var interest: Set<String>?
    private var myFrame: LiveFrame?
    private var rosterIndex = RaceRosterIndex(participants: [])
    private var seq = 0
    private var fieldSeq = 0

    public init(field: RaceBotField, rate: Double = 2.5, defaultNeighbours: Int = 16,
                raceTime: @escaping @Sendable () -> TimeInterval?) {
        self.field = field
        self.rate = max(rate, 0.5)
        self.defaultNeighbours = defaultNeighbours
        self.raceTime = raceTime
        (frames, framesContinuation) = AsyncStream.makeStream(of: LiveFrame.self, bufferingPolicy: .bufferingNewest(256))
        (roster, rosterContinuation) = AsyncStream.makeStream(of: [RaceParticipant].self, bufferingPolicy: .bufferingNewest(8))
        (fieldSnapshots, fieldContinuation) = AsyncStream.makeStream(of: RaceFieldSnapshot.self, bufferingPolicy: .bufferingNewest(2))
    }

    public func join(race: Race, as participant: RaceParticipant) async throws -> [RaceParticipant] {
        let list = ([participant] + field.participants).sorted { ($0.lane, $0.id) < ($1.lane, $1.id) }
        lock.withLock { rosterIndex = RaceRosterIndex(participants: list) }
        rosterContinuation.yield(list)
        let t = Task { [weak self] in
            var lastField = -Double.infinity
            while !Task.isCancelled {
                guard let self else { return }
                if let rt = self.raceTime(), rt >= 0 {
                    let now = Date().timeIntervalSince1970
                    for f in self.tick(raceId: race.id, raceTime: rt, sentAt: now) { self.framesContinuation.yield(f) }
                    if rt - lastField >= 1 {
                        lastField = rt
                        self.fieldContinuation.yield(self.snapshot(raceId: race.id, raceTime: rt, sentAt: now))
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / self.rate))
            }
        }
        lock.withLock { task?.cancel(); task = t }
        return list
    }

    /// Frames eines Takts (nur abonnierte bzw. nächste); öffentlich für Tests ohne Zeitablauf
    public func tick(raceId: String, raceTime rt: TimeInterval, sentAt: TimeInterval) -> [LiveFrame] {
        let (ids, s) = lock.withLock { () -> (Set<String>?, Int) in seq += 1; return (interest, seq) }
        let wanted = ids ?? nearest(raceTime: rt)
        var out: [LiveFrame] = []
        for i in field.bots.indices where wanted.contains(field.bots[i].participant.id) {
            out.append(field.frame(of: i, raceId: raceId, seq: s, raceTime: rt, sentAt: sentAt))
        }
        return out
    }

    /// Übersicht über alle zur Rennzeit; öffentlich für Tests ohne Zeitablauf
    public func snapshot(raceId: String, raceTime rt: TimeInterval, sentAt: TimeInterval) -> RaceFieldSnapshot {
        var latest: [String: LiveFrame] = [:]
        latest.reserveCapacity(field.bots.count + 1)
        for i in field.bots.indices {
            latest[field.bots[i].participant.id] = field.frame(of: i, raceId: raceId, seq: 0, raceTime: rt, sentAt: sentAt)
        }
        let (index, me, s) = lock.withLock { () -> (RaceRosterIndex, LiveFrame?, Int) in
            fieldSeq += 1
            return (rosterIndex, myFrame, fieldSeq)
        }
        if let me { latest[me.participantId] = me }
        return RaceFieldSnapshot.build(raceId: raceId, seq: s, sentAt: sentAt, raceTime: rt, roster: index, latest: latest)
    }

    private func nearest(raceTime rt: TimeInterval) -> Set<String> {
        let d = lock.withLock { myFrame?.distance } ?? 0
        let sorted = field.bots.indices.sorted { abs(field.position(of: $0, at: rt).distance - d) < abs(field.position(of: $1, at: rt).distance - d) }
        return Set(sorted.prefix(defaultNeighbours).map { field.bots[$0].participant.id })
    }

    public func setInterest(_ interest: RaceInterest) async {
        lock.withLock { self.interest = interest.fullIds }
    }

    public func publish(_ frame: LiveFrame) async throws {
        lock.withLock { myFrame = frame }
    }

    public func serverTime() async throws -> TimeInterval { Date().timeIntervalSince1970 }

    public func leave() async {
        lock.withLock { task?.cancel(); task = nil }
        framesContinuation.finish()
        rosterContinuation.finish()
        fieldContinuation.finish()
    }
}
