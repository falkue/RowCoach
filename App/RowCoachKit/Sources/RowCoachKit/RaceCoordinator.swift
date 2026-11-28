import Foundation

/// Verbindet die eigene Fahrt mit einem Rennen – ohne Netz, ohne Threads, vollständig testbar:
/// - eigener Stand → `LiveFrame` (gedrosselt über `RacePublishThrottle`), den der Aufrufer über den Transport sendet,
/// - empfangene Frames → je Teilnehmendem ein `RemoteRowerTracker`,
/// - `states(...)` → angezeigte Boote (Distanz, Abstand in m und s, Platz, Bahnversatz) und `standings(...)`.
/// Alle Zeiten: lokal = Geräteuhr (s seit 1970), Rennzeit = s seit dem Start. Die Netzanbindung macht `RaceLink`.
public struct RaceCoordinator: Sendable {
    public let race: Race
    public let me: RaceParticipant
    public var clock: RaceClock
    public var lanes: RaceLanes
    public private(set) var roster: [RaceParticipant]
    public private(set) var trackers: [String: RemoteRowerTracker] = [:]
    /// letzter eigener Stand (für Platz und Abstände)
    public private(set) var myLast: LiveFrame?

    private var throttle: RacePublishThrottle
    /// Grosse Felder: Senden nach Dead Reckoning statt fester Rate (nil = `throttle` wie bisher)
    public var deadReckoning: RaceDeadReckoningPublisher?
    private var seq = 0
    private let trackerTemplate: RemoteRowerTracker

    public init(race: Race, me: RaceParticipant, clock: RaceClock = RaceClock(), lanes: RaceLanes = RaceLanes(),
                throttle: RacePublishThrottle = RacePublishThrottle(), tracker: RemoteRowerTracker = RemoteRowerTracker()) {
        self.race = race
        self.me = me
        self.clock = clock
        self.lanes = lanes
        self.throttle = throttle
        self.trackerTemplate = tracker
        self.roster = [me]
    }

    // MARK: Teilnehmende und Empfang

    public mutating func setRoster(_ list: [RaceParticipant]) {
        roster = list.contains(where: { $0.id == me.id }) ? list : list + [me]
        let ids = Set(roster.map(\.id))
        trackers = trackers.filter { ids.contains($0.key) }
    }

    /// Frame eines anderen aufnehmen (eigene werden ignoriert). Unbekannte Absender kommen in die Liste, damit nichts
    /// verloren geht, falls die Teilnehmerliste später eintrifft.
    @discardableResult
    public mutating func receive(_ frame: LiveFrame, receivedLocal: TimeInterval) -> Bool {
        guard frame.participantId != me.id, frame.raceId == race.id else { return false }
        if !roster.contains(where: { $0.id == frame.participantId }) {
            roster.append(RaceParticipant(id: frame.participantId, displayName: frame.participantId,
                                          lane: (roster.map(\.lane).max() ?? 0) + 1))
        }
        var t = trackers[frame.participantId] ?? trackerTemplate
        let ok = t.receive(frame, receivedLocal: receivedLocal)
        trackers[frame.participantId] = t
        return ok
    }

    // MARK: Eigener Stand

    /// Rennzeit für die lokale Uhrzeit, wenn das Rennen einen gemeinsamen Start hat (sonst nil: dann zählt die Zeit
    /// seit dem ersten eigenen Schlag, die der Aufrufer selbst kennt)
    public func raceTime(local now: TimeInterval) -> TimeInterval? {
        race.scheduledStart.map { clock.raceTime(start: $0, local: now) }
    }

    /// Ist das Ziel erreicht? (Distanzrennen: Distanz; Zeitrennen: Zeit; Programm: entscheidet der Aufrufer)
    public func targetReached(raceTime: TimeInterval, distance: Double) -> Bool {
        switch race.target {
        case .distance(let m): return distance >= m - 0.01
        case .time(let s): return raceTime >= s - 0.01
        case .plan: return false
        }
    }

    /// Eigenen Stand übernehmen; liefert einen Frame, wenn jetzt gesendet werden soll (Drossel), sonst nil.
    /// - Parameters:
    ///   - stroke: seit dem letzten Aufruf kam ein neuer Schlag (dann früher senden)
    ///   - finished: im Ziel (z. B. Programm fertig); wird bei Distanz- und Zeitrennen auch selbst erkannt
    public mutating func updateLocal(raceTime: TimeInterval, distance: Double, pace: TimeInterval, strokeRate: Int,
                                     heartRate: Int? = nil, finished: Bool = false, stroke: Bool = false,
                                     local now: TimeInterval) -> LiveFrame? {
        if myLast?.finished == true { return nil }
        var done = finished || targetReached(raceTime: raceTime, distance: distance)
        var d = distance, finishTime: TimeInterval?
        if done {
            if case .distance(let m) = race.target {
                d = min(distance, m)
                finishTime = interpolatedFinish(target: m, raceTime: raceTime, distance: distance)
            } else {
                finishTime = raceTime
            }
        }
        if raceTime < 0 { done = false }
        seq += 1
        let frame = LiveFrame(participantId: me.id, raceId: race.id, seq: seq, sentAt: clock.serverTime(local: now),
                              raceTime: max(raceTime, 0), distance: max(d, 0), pace: pace, strokeRate: strokeRate,
                              heartRate: heartRate, finished: done, finishTime: finishTime)
        myLast = frame
        if var dr = deadReckoning {
            let precision = dr.wantsPrecision(distanceToGo: distanceToGo(frame.distance),
                                              neighbours: neighbours(raceTime: frame.raceTime, distance: frame.distance,
                                                                     speed: frame.speed))
            let send = dr.shouldSend(frame, now: now, precision: precision)
            deadReckoning = dr
            return send ? frame : nil
        }
        guard throttle.shouldSend(now: now, distance: frame.distance, stroke: stroke, finished: done) else { return nil }
        return frame
    }

    /// Rest bis zum Ziel (Distanzrennen), sonst nil
    func distanceToGo(_ distance: Double) -> Double? {
        if case .distance(let m) = race.target { return m - distance }
        return nil
    }

    /// Abstand (positiv = vor mir) und Annäherung (positiv = kommt näher) der verfolgten Boote
    func neighbours(raceTime: TimeInterval, distance: Double, speed: Double) -> [(gap: Double, closing: Double)] {
        trackers.values.compactMap { t in
            guard let p = t.position(atRaceTime: raceTime), let l = t.latest, !l.finished else { return nil }
            let gap = p.distance - distance
            return (gap, gap >= 0 ? speed - l.speed : l.speed - speed)
        }
    }

    /// Zielzeit zwischen dem letzten und dem aktuellen Stand interpoliert
    private func interpolatedFinish(target: Double, raceTime: TimeInterval, distance: Double) -> TimeInterval {
        guard let last = myLast, distance > last.distance, last.distance < target else { return raceTime }
        let f = (target - last.distance) / (distance - last.distance)
        return last.raceTime + (raceTime - last.raceTime) * min(max(f, 0), 1)
    }

    // MARK: Anzeige

    /// Angezeigte Boote der anderen zur eigenen Rennzeit, mit Platz über alle (einschliesslich mir)
    public func states(raceTime: TimeInterval, myDistance: Double, mySpeed: Double, local now: TimeInterval) -> [RemoteRowerState] {
        let offsets = lanes.lateralOffsets(participants: roster, me: me.id)
        var list: [RemoteRowerState] = []
        for p in roster where p.id != me.id {
            guard let t = trackers[p.id], let pos = t.position(atRaceTime: raceTime) else { continue }
            let last = t.latest
            let gap = pos.distance - myDistance
            let speed = mySpeed > 0.5 ? mySpeed : (last?.speed ?? 0)
            list.append(RemoteRowerState(participant: p, distance: pos.distance, strokeRate: pos.strokeRate,
                                         gapMeters: gap, gapSeconds: speed > 0.5 ? gap / speed : nil,
                                         finished: last?.finished ?? false, finishTime: last?.finishTime,
                                         place: 0, stale: t.isStale(local: now), lateral: offsets[p.id] ?? 0))
        }
        let order = Self.ranking(entries: list.map { ($0.participant.id, $0.distance, $0.finished, $0.finishTime) }
                                 + [(me.id, myDistance, myLast?.finished ?? false, myLast?.finishTime)],
                                 target: race.target)
        for i in list.indices { list[i].place = (order.firstIndex(of: list[i].participant.id) ?? 0) + 1 }
        return list.sorted { $0.place < $1.place }
    }

    /// Eigener Platz (1 = vorne)
    public func myPlace(raceTime: TimeInterval, myDistance: Double) -> Int {
        let others = states(raceTime: raceTime, myDistance: myDistance, mySpeed: 0, local: 0)
        let order = Self.ranking(entries: others.map { ($0.participant.id, $0.distance, $0.finished, $0.finishTime) }
                                 + [(me.id, myDistance, myLast?.finished ?? false, myLast?.finishTime)],
                                 target: race.target)
        return (order.firstIndex(of: me.id) ?? 0) + 1
    }

    /// Ergebnisliste aus den letzten bekannten Ständen (vorläufig; das endgültige Ergebnis bestätigt der Server)
    public func standings() -> [RaceResult] {
        var entries: [(String, Double, Bool, TimeInterval?)] = trackers.compactMap { id, t in
            t.latest.map { (id, $0.distance, $0.finished, $0.finishTime) }
        }
        if let m = myLast { entries.append((me.id, m.distance, m.finished, m.finishTime)) }
        let order = Self.ranking(entries: entries, target: race.target)
        let byId = Dictionary(entries.map { ($0.0, $0) }, uniquingKeysWith: { a, _ in a })
        return order.enumerated().compactMap { i, id in
            guard let e = byId[id] else { return nil }
            let time: TimeInterval?
            if case .time(let s) = race.target { time = e.2 ? s : nil } else { time = e.3 }
            return RaceResult(participantId: id, place: i + 1, distance: e.1, time: time, finished: e.2)
        }
    }

    /// Reihenfolge: Distanzrennen – Angekommene nach Zielzeit, dann nach Distanz; sonst nach Distanz.
    /// Gleichstand: nach id (stabil).
    public static func ranking(entries: [(id: String, distance: Double, finished: Bool, finishTime: TimeInterval?)],
                        target: RaceTarget) -> [String] {
        let byDistance: Bool
        if case .distance = target { byDistance = true } else { byDistance = false }
        return entries.sorted { a, b in
            if byDistance {
                switch (a.finished, b.finished) {
                case (true, true):
                    let ta = a.finishTime ?? .infinity, tb = b.finishTime ?? .infinity
                    if ta != tb { return ta < tb }
                case (true, false): return true
                case (false, true): return false
                default: break
                }
            }
            if a.distance != b.distance { return a.distance > b.distance }
            return a.id < b.id
        }.map(\.id)
    }
}
