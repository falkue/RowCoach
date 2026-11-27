import Foundation

/// Bedingungen eines Rennens für die Simulation virtueller Teilnehmender
public struct VirtualRaceContext: Equatable, Sendable {
    public var raceId: String
    /// Start (UTC, Sekunden seit 1970): Saison und Tagesform
    public var startsAt: TimeInterval
    public var target: RaceTarget
    /// längste Dauer der Simulation (s), auch für Distanzrennen (Sicherheitsgrenze)
    public var maxDuration: TimeInterval

    public init(raceId: String, startsAt: TimeInterval, target: RaceTarget, maxDuration: TimeInterval = 3 * 3600) {
        self.raceId = raceId
        self.startsAt = startsAt
        self.target = target
        self.maxDuration = maxDuration
    }

    /// Zieldistanz (m) bzw. nil
    public var finishDistance: Double? { if case .distance(let m) = target { return m } else { return nil } }
    /// Zeitlimit (s) eines Zeitrennens bzw. nil
    public var timeLimit: TimeInterval? { if case .time(let s) = target { return s } else { return nil } }
}

/// Verlauf eines virtuellen Teilnehmenden in einem Rennen: Distanz und Schlagzahl je Sekunde, Ergebnis.
/// Auf allen Geräten und auf dem Server bitgenau gleich (`DetMath`, feste Reihenfolge).
public struct VirtualRaceRun: Equatable, Sendable {
    public var rowerId: String
    /// Form an diesem Tag (Faktor auf die Leistung) und mittleres Tempo (s/500 m)
    public var formFactor: Double
    public var meanPace: Double
    /// Distanz (m) zu jeder vollen Sekunde ab dem Start
    public var track: [Double]
    public var rates: [UInt8]
    /// Zielzeit (s, auf die Millisekunde) bei Distanzrennen
    public var finishTime: TimeInterval?
    /// Distanz am Ende (Zeitrennen: beim Zeitlimit, auf den Dezimeter)
    public var finalDistance: Double

    public var finished: Bool { finishTime != nil }
}

/// Rennsimulation je virtueller Person und Rennen: Leistung aus 2k-Zeit und Leistungs-Dauer-Gesetz, Tagesform
/// (normalverteilt, selten ein schlechter Tag), saisonale Form (Höhepunkt Mitte Februar im Norden bzw. Mitte August
/// im Süden, als Dreieckskurve), Rennstil (Verlauf des Tempos), kleine Schwankungen, Anlauf. Zufall aus Rennen und
/// Person (`raceId|rowerId`), also gleich auf allen Geräten.
public enum VirtualRaceSimulator {
    /// Watt aus Tempo (Concept2): W = 2,80 / (p/500)³ (nur Grundrechenarten)
    public static func watts(pace: Double) -> Double {
        guard pace > 0 else { return 0 }
        let x = pace / 500
        return 2.80 / (x * x * x)
    }

    /// Tempo (s/500 m) aus Watt
    public static func pace(watts: Double) -> Double {
        guard watts > 0 else { return 0 }
        return 500 * DetMath.cbrt(2.80 / watts)
    }

    /// Saisonfaktor −1 … 1 (1 = Höhepunkt der Form) für den Tag
    public static func seasonPhase(days: Int, hemisphere: VirtualHemisphere) -> Double {
        let c = DetMath.civil(days: days)
        let doy = days - DetMath.days(year: c.year, month: 1, day: 1)
        let peak = hemisphere == .south ? 227 : 45
        let x = Double((doy - peak + 365 * 2) % 365) / 365
        let dist = min(x, 1 - x)
        return 1 - 4 * dist
    }

    /// Mittlere Leistung (W) über `duration` s bei Formfaktor `form`
    static func power(_ r: VirtualRacer, duration: Double, form: Double) -> Double {
        let p2k = watts(pace: r.best2k / 4)
        return p2k * form * DetMath.pow(max(duration, 30) / r.best2k, -r.exponent)
    }

    /// Erwartete Zeit (s) für eine Distanz bei Formfaktor `form`
    public static func expectedTime(_ r: VirtualRacer, distance: Double, form: Double = 1) -> Double {
        var t = r.best2k * distance / 2000
        for _ in 0..<40 {
            let p = pace(watts: power(r, duration: t, form: form))
            let next = distance / 500 * p
            if abs(next - t) < 1e-9 { return next }
            t = next
        }
        return t
    }

    /// Tempo-Abweichung (s/500 m) je Stil über den Anteil x (0…1) des Rennens, vor der Normierung
    static func styleOffset(_ s: VirtualRacer.Style, _ x: Double) -> Double {
        switch s {
        case .even: return 0.6 * (x - 0.5)
        case .fastStart: return (x < 0.12 ? -3.0 : 0.5) + 0.8 * (x - 0.5)
        case .finisher: return x > 0.85 ? -3.5 : 0.6
        case .fader: return x < 0.25 ? -2.0 : 4.5 * (x - 0.25) / 0.75
        }
    }

    /// Mittelwert der Stil-Abweichung (für die Normierung, 200 Stützstellen)
    static func styleMean(_ s: VirtualRacer.Style) -> Double {
        var sum = 0.0
        for i in 0..<200 { sum += styleOffset(s, (Double(i) + 0.5) / 200) }
        return sum / 200
    }

    /// Formfaktor des Tages (Saison × Tagesform)
    public static func form(_ r: VirtualRacer, context: VirtualRaceContext) -> Double {
        var rng = RaceRandom(seed: DetMath.fnv64("\(context.raceId)|\(r.id)"))
        _ = rng.next()
        let day = DetMath.dayIndex(context.startsAt)
        let season = 1 + r.season * seasonPhase(days: day, hemisphere: r.hemisphere)
        var daily = 1 + r.dayForm * DetMath.normal(&rng)
        if rng.unit() < 0.04 { daily -= 0.03 + 0.05 * rng.unit() }
        return season * min(max(daily, 0.8), 1.15)
    }

    public static func run(_ r: VirtualRacer, context: VirtualRaceContext) -> VirtualRaceRun {
        var rng = RaceRandom(seed: DetMath.fnv64("\(context.raceId)|\(r.id)|run"))
        let form = form(r, context: context)
        // mittleres Tempo: Distanzrennen über die erwartete Zeit, Zeitrennen über das Zeitlimit
        let meanPace: Double
        let scale: Double  // Länge, auf die sich der Stil bezieht (m bzw. s)
        if let d = context.finishDistance {
            meanPace = 500 * expectedTime(r, distance: d, form: form) / d
            scale = d
        } else {
            let limit = context.timeLimit ?? 1800
            meanPace = pace(watts: power(r, duration: limit, form: form))
            scale = limit
        }
        let styleMean = styleMean(r.style)
        let wobble = 0.4 + 0.8 * rng.unit()
        let period = 25 + 55 * rng.unit()
        let phase = rng.unit() * 6.283_185_307_179_586
        // Anlauf: in 10 s von 40 % auf volles Tempo; der Verlust (≈ 3 s) ist Teil der erwarteten Zeit und wird
        // mit einem etwas schnelleren Grundtempo ausgeglichen
        let ramp = 10.0
        let rampLoss = 0.3 * ramp
        let total = context.finishDistance.map { $0 / 500 * meanPace } ?? scale
        let base = meanPace * (total - rampLoss) / total
        let baseRate = min(max(24 + (120 - meanPace) * 0.25, 18), 36)
        let limit = context.timeLimit ?? context.maxDuration
        let steps = Int(limit.rounded(.up))
        var track: [Double] = [0]
        var rates: [UInt8] = []
        track.reserveCapacity(min(steps, 4000) + 1)
        var d = 0.0
        var finish: TimeInterval?
        for t in 1...max(steps, 1) {
            let tm = Double(t) - 0.5
            let x = context.finishDistance != nil ? d / scale : tm / scale
            let off = styleOffset(r.style, min(max(x, 0), 1)) - styleMean
            let p = max(base + off + wobble * DetMath.sin(6.283_185_307_179_586 * tm / period + phase), 70)
            let k = min(0.4 + 0.6 * tm / ramp, 1)
            let v = 500 / p * k
            let spm = baseRate + (meanPace - p) * 0.5
            rates.append(UInt8(min(max(spm.rounded(), 16), 48)))
            if let fd = context.finishDistance, d + v >= fd {
                finish = ((Double(t - 1) + (fd - d) / v) * 1000).rounded() / 1000
                d = fd
                track.append(d)
                break
            }
            d += v
            track.append(d)
        }
        rates.append(rates.last ?? UInt8(baseRate))
        let final = context.finishDistance != nil && finish != nil ? d : (d * 10).rounded(.down) / 10
        return VirtualRaceRun(rowerId: r.id, formFactor: form, meanPace: meanPace, track: track, rates: rates,
                              finishTime: finish, finalDistance: final)
    }

    /// Ergebnisse (vorläufig) aller virtuellen Läufe zusammen mit den echten Ergebnissen, sortiert wie
    /// `RaceCoordinator.standings` (Angekommene nach Zielzeit, dann Distanz; Gleichstand nach id).
    public static func results(runs: [VirtualRaceRun], real: [RaceResult], target: RaceTarget) -> [RaceResult] {
        var timeRace = false
        if case .time = target { timeRace = true }
        var entries: [(id: String, distance: Double, finished: Bool, finishTime: TimeInterval?)] = runs.map {
            ($0.rowerId, $0.finalDistance, timeRace || $0.finished, $0.finishTime)
        }
        for r in real { entries.append((r.participantId, r.distance, r.finished, r.time)) }
        let order = RaceCoordinator.ranking(entries: entries, target: target)
        let byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.enumerated().compactMap { i, id in
            guard let e = byId[id] else { return nil }
            let time: TimeInterval?
            if case .time(let s) = target { time = e.finished ? s : nil } else { time = e.finishTime }
            return RaceResult(participantId: id, place: i + 1, distance: e.distance, time: time, finished: e.finished)
        }
    }
}

extension RaceBotField {
    /// Feld aus virtuellen Teilnehmenden (vorausberechnete Läufe), abspielbar mit `RaceBotTransport`
    public init(virtual runs: [VirtualRaceRun], participants: [RaceParticipant], finishDistance: Double?) {
        var config = Config(count: runs.count, finishDistance: finishDistance)
        config.maxDuration = Double(runs.map { $0.track.count - 1 }.max() ?? 0)
        let byId = Dictionary(participants.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let bots = runs.map { r in
            RaceBot(participant: byId[r.rowerId] ?? RaceParticipant(id: r.rowerId, displayName: r.rowerId, lane: 0,
                                                                    source: .virtual),
                    basePace: r.meanPace, fatigue: 0, sprint: 0, wobble: 0, wobblePeriod: 60, wobblePhase: 0,
                    strokeRate: Int(r.rates.first ?? 24))
        }
        self.init(config: config, bots: bots, track: runs.map(\.track), rates: runs.map(\.rates),
                  finishTimes: runs.map(\.finishTime))
    }
}

/// Ein Rennen mit aufgefülltem Feld: Teilnehmerliste, simulierte Läufe der virtuellen, abspielbares Feld und
/// Ergebnisse. Server und Geräte rechnen dasselbe; das endgültige Ergebnis schreibt der Server fest.
public struct VirtualTournamentRace: Sendable {
    public let race: Race
    public let startsAt: TimeInterval
    public let field: TournamentField
    public let runs: [VirtualRaceRun]

    public init(race: Race, startsAt: TimeInterval, field: TournamentField) {
        self.race = race
        self.startsAt = startsAt
        self.field = field
        let context = VirtualRaceContext(raceId: race.id, startsAt: startsAt, target: race.target)
        runs = field.virtualRowers.map { VirtualRaceSimulator.run($0, context: context) }
    }

    /// Feld der virtuellen Teilnehmenden für `RaceBotTransport`
    public var botField: RaceBotField {
        var finish: Double?
        if case .distance(let m) = race.target { finish = m }
        return RaceBotField(virtual: runs, participants: field.participants, finishDistance: finish)
    }

    /// Ergebnisliste aus den virtuellen Läufen und den Ergebnissen der echten
    public func results(real: [RaceResult]) -> [RaceResult] {
        VirtualRaceSimulator.results(runs: runs, real: real, target: race.target)
    }
}

extension RaceResult {
    /// Eigenes Ergebnis aus einer gespeicherten Fahrt (Rennzeit ab dem ersten Meter; Platz 0 = noch nicht gewertet).
    /// Distanzrennen: Zielzeit, wenn die Fahrt das Ziel erreicht hat; Zeitrennen: Distanz beim Zeitlimit.
    public static func fromSamples(participantId: String, samples: [WorkoutSample], target: RaceTarget) -> RaceResult {
        let s = samples.sorted { $0.time < $1.time }
        let start = s.first { $0.distance > 0 }.map { first -> TimeInterval in
            guard let i = s.firstIndex(of: first), i > 0 else { return first.time }
            return s[i - 1].time
        } ?? 0
        switch target {
        case .distance(let m):
            if let g = GhostRower(participant: RaceParticipant(id: participantId, displayName: "", lane: 0),
                                  samples: s, finishDistance: m).finishTime,
               (s.last?.distance ?? 0) >= m {
                return RaceResult(participantId: participantId, place: 0, distance: m,
                                  time: ((g - start) * 1000).rounded() / 1000, finished: true)
            }
            return RaceResult(participantId: participantId, place: 0, distance: s.last?.distance ?? 0, time: nil,
                              finished: false)
        case .time(let limit):
            let d = s.last { $0.time - start <= limit }?.distance ?? 0
            return RaceResult(participantId: participantId, place: 0, distance: d, time: limit,
                              finished: (s.last?.time ?? 0) - start >= limit)
        case .plan:
            return RaceResult(participantId: participantId, place: 0, distance: s.last?.distance ?? 0,
                              time: s.last.map { $0.time - start }, finished: true)
        }
    }
}

extension VirtualRaceRun {
    /// Gleichmässiger Lauf (z. B. Demo-Boote, die im Turnier echte Teilnehmende vertreten), ohne Anlauf
    public static func steady(id: String, pace: TimeInterval, strokeRate: Int = 24, finishDistance: Double) -> VirtualRaceRun {
        let v = 500 / max(pace, 60)
        let finish = ((finishDistance / v) * 1000).rounded() / 1000
        let n = Int(finish.rounded(.up))
        var track = (0...n).map { min(v * Double($0), finishDistance) }
        if track.count < 2 { track.append(finishDistance) }
        return VirtualRaceRun(rowerId: id, formFactor: 1, meanPace: pace, track: track,
                              rates: [UInt8](repeating: UInt8(min(max(strokeRate, 16), 48)), count: track.count),
                              finishTime: finish, finalDistance: finishDistance)
    }
}

extension VirtualTournamentRace {
    /// Feld aller computergesteuerten Boote dieses Rennens: die virtuellen und zusätzliche Läufe (`extra`, z. B. die
    /// Demo-Boote). Alles in **einem** Transport, damit Teilnehmerliste von Gerät und „Server“ übereinstimmen –
    /// sonst verwirft `RaceFieldTracker` die Übersicht (anderer `rosterHash`) und nur die Nachbarschaft bleibt.
    public func botField(adding extra: [VirtualRaceRun]) -> RaceBotField {
        var finish: Double?
        if case .distance(let m) = race.target { finish = m }
        return RaceBotField(virtual: runs + extra, participants: field.participants, finishDistance: finish)
    }

    /// Rennen ohne Netz mit dem ganzen Feld (Demo-Turnier): ein `RaceBotTransport`, Start mit dem ersten eigenen
    /// Schlag. `me` muss in `field.participants` stehen.
    @MainActor
    public func makeLink(me: RaceParticipant, extra: [VirtualRaceRun] = [], start: RaceStartMark = RaceStartMark(),
                         raceTime: (@Sendable () -> TimeInterval?)? = nil) -> RaceLink {
        let clock = raceTime ?? { start.raceTime(local: Date().timeIntervalSince1970) }
        let transport = RaceBotTransport(field: botField(adding: extra), raceTime: clock)
        return RaceLink(coordinator: RaceCoordinator(race: race, me: me), transports: [transport], start: start)
    }
}
