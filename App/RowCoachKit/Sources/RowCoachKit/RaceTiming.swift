import Foundation

/// Gemeinsame Uhr für Rennen: schätzt den Versatz zwischen Geräte- und Serveruhr aus Rundläufen (wie NTP).
///
/// Ein Rundlauf: Gerät sendet um `sentLocal`, Server antwortet mit seiner Zeit `server`, Antwort trifft um
/// `receivedLocal` ein. Unter der Annahme gleich langer Wege ist der Versatz `server − (sentLocal + receivedLocal) / 2`,
/// mit einem Fehler von höchstens der halben Laufzeit. Verwendet wird der Mittelwert der drei Proben mit der kürzesten
/// Laufzeit aus den letzten `maxSamples` (kurze Rundläufe sind am genauesten, Ausreisser fallen weg).
/// Alle Zeiten in Sekunden; „lokal“ = Geräteuhr (`Date().timeIntervalSince1970`).
public struct RaceClock: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public var offset: TimeInterval
        public var roundTrip: TimeInterval
    }

    /// Serverzeit − lokale Zeit
    public private(set) var offset: TimeInterval
    public private(set) var samples: [Sample] = []
    public let maxSamples: Int

    public init(offset: TimeInterval = 0, maxSamples: Int = 8) {
        self.offset = offset
        self.maxSamples = maxSamples
    }

    /// Kürzeste gemessene Laufzeit (s), nil ohne Messung
    public var bestRoundTrip: TimeInterval? { samples.map(\.roundTrip).min() }
    public var isSynchronized: Bool { !samples.isEmpty }

    public mutating func addSample(sentLocal: TimeInterval, server: TimeInterval, receivedLocal: TimeInterval) {
        let rtt = receivedLocal - sentLocal
        guard rtt >= 0, rtt.isFinite, server.isFinite else { return }
        samples.append(Sample(offset: server - (sentLocal + receivedLocal) / 2, roundTrip: rtt))
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        let best = samples.sorted { $0.roundTrip < $1.roundTrip }.prefix(3)
        offset = best.map(\.offset).reduce(0, +) / Double(best.count)
    }

    public func serverTime(local: TimeInterval) -> TimeInterval { local + offset }
    public func localTime(server: TimeInterval) -> TimeInterval { server - offset }

    /// Sekunden bis zum Start (negativ = Start ist vorbei)
    public func countdown(to serverStart: TimeInterval, local now: TimeInterval) -> TimeInterval {
        serverStart - serverTime(local: now)
    }

    /// Rennzeit seit dem gemeinsamen Start (negativ = noch vor dem Start)
    public func raceTime(start serverStart: TimeInterval, local now: TimeInterval) -> TimeInterval {
        serverTime(local: now) - serverStart
    }
}

/// Wann ein neuer `LiveFrame` gesendet wird: höchstens alle `minInterval` Sekunden, sofort bei einem neuen Schlag
/// oder im Ziel (sofern `minStrokeInterval` vorbei ist), sonst spätestens nach `heartbeat` Sekunden (auch in Pausen,
/// damit die anderen sehen, dass die Verbindung steht).
public struct RacePublishThrottle: Sendable {
    public var minInterval: TimeInterval
    public var minStrokeInterval: TimeInterval
    public var heartbeat: TimeInterval
    private var lastSent: TimeInterval?
    private var lastDistance: Double?

    public init(minInterval: TimeInterval = 0.33, minStrokeInterval: TimeInterval = 0.15, heartbeat: TimeInterval = 1.0) {
        self.minInterval = minInterval
        self.minStrokeInterval = minStrokeInterval
        self.heartbeat = heartbeat
    }

    /// true = jetzt senden (und als gesendet vermerken)
    public mutating func shouldSend(now: TimeInterval, distance: Double, stroke: Bool = false, finished: Bool = false) -> Bool {
        guard let last = lastSent else { return mark(now, distance) }
        let dt = now - last
        if (stroke || finished) && dt >= minStrokeInterval { return mark(now, distance) }
        if dt >= heartbeat { return mark(now, distance) }
        if dt >= minInterval, distance != lastDistance { return mark(now, distance) }
        return false
    }

    private mutating func mark(_ now: TimeInterval, _ distance: Double) -> Bool {
        lastSent = now
        lastDistance = distance
        return true
    }
}

/// Verfolgt einen anderen Teilnehmenden aus seinen `LiveFrame`s und liefert die Distanz für eine Rennzeit.
///
/// - Gezeigt wird mit kleiner Verzögerung (`delay`, Standard 0,4 s): Die Rennzeit des Bildes liegt meist zwischen zwei
///   empfangenen Frames, dort wird linear interpoliert (ruhig, ohne Sprünge bei schwankender Laufzeit).
/// - Liegt sie nach dem letzten Frame (Daten verspätet), wird mit dem Tempo des letzten Frames vorausgerechnet,
///   höchstens `maxExtrapolation` Sekunden; danach bleibt das Boot stehen.
/// - `stale`: seit `staleAfter` Sekunden (lokale Uhr) kein Frame mehr.
/// - Im Ziel steht das Boot auf der Zieldistanz.
public struct RemoteRowerTracker: Sendable {
    public var delay: TimeInterval
    public var maxExtrapolation: TimeInterval
    public var staleAfter: TimeInterval
    public var bufferSize: Int

    public private(set) var frames: [LiveFrame] = []
    public private(set) var lastReceivedLocal: TimeInterval?

    public init(delay: TimeInterval = 0.4, maxExtrapolation: TimeInterval = 3, staleAfter: TimeInterval = 5,
                bufferSize: Int = 40) {
        self.delay = delay
        self.maxExtrapolation = maxExtrapolation
        self.staleAfter = staleAfter
        self.bufferSize = bufferSize
    }

    public var latest: LiveFrame? { frames.last }

    /// Neuen Frame aufnehmen; ältere oder doppelte (nach `seq`) werden verworfen. Gibt true zurück, wenn übernommen.
    @discardableResult
    public mutating func receive(_ frame: LiveFrame, receivedLocal: TimeInterval) -> Bool {
        if let last = frames.last, frame.seq <= last.seq { return false }
        frames.append(frame)
        if frames.count > bufferSize { frames.removeFirst(frames.count - bufferSize) }
        lastReceivedLocal = receivedLocal
        return true
    }

    public func isStale(local now: TimeInterval) -> Bool {
        guard let t = lastReceivedLocal else { return true }
        return now - t > staleAfter
    }

    /// Angezeigte Distanz und Schlagzahl zur eigenen Rennzeit `raceTime` (die Verzögerung wird hier abgezogen)
    public func position(atRaceTime raceTime: TimeInterval) -> (distance: Double, strokeRate: Int)? {
        guard let last = frames.last else { return nil }
        if last.finished { return (last.distance, 0) }
        let t = raceTime - delay
        if t >= last.raceTime {
            let ahead = min(t - last.raceTime, maxExtrapolation)
            let speed = last.speed > 0 ? last.speed : derivedSpeed()
            return (last.distance + speed * ahead, last.strokeRate)
        }
        guard let first = frames.first, t > first.raceTime else { return (frames.first?.distance ?? 0, frames.first?.strokeRate ?? 0) }
        // binäre Suche nach dem Intervall [a, b] mit a.raceTime ≤ t < b.raceTime
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if frames[mid].raceTime <= t { lo = mid } else { hi = mid }
        }
        let a = frames[lo], b = frames[hi]
        let span = b.raceTime - a.raceTime
        let f = span > 0 ? (t - a.raceTime) / span : 1
        return (a.distance + (b.distance - a.distance) * f, f < 0.5 ? a.strokeRate : b.strokeRate)
    }

    /// Geschwindigkeit aus den letzten beiden Frames (m/s), wenn das Tempo fehlt
    private func derivedSpeed() -> Double {
        guard frames.count >= 2 else { return 0 }
        let a = frames[frames.count - 2], b = frames[frames.count - 1]
        let dt = b.raceTime - a.raceTime
        return dt > 0 ? max((b.distance - a.distance) / dt, 0) : 0
    }
}

/// Seitliche Lage der anderen Boote relativ zur eigenen Linie (die eigene Linie ist die Mittellinie der Strecke).
///
/// Alle anderen fahren rechts von mir (in Fahrtrichtung), in Bahnreihenfolge mit Abstand `spacing`: so bleiben sie
/// auf Hin- und Rückfahrt auf der Seite, die von der Gegenbahn (12 m links der Hinfahrt, siehe `CourseTrack`)
/// wegliegt, wie die Bahnen des Verkehrs (`RowerLaneSpec`, positiv = links). Mehr als `maxSide` Boote teilen sich
/// die Bahnen abwechselnd (gleiche Bahn, dann versetzt), damit niemand an Land fährt.
public struct RaceLanes: Equatable, Sendable {
    public var spacing: Double
    public var maxSide: Int

    public init(spacing: Double = 7, maxSide: Int = 4) {
        self.spacing = spacing
        self.maxSide = maxSide
    }

    /// Versatz je Teilnehmenden (Meter, positiv = links der Fahrtrichtung) für alle ausser `me`
    public func lateralOffsets(participants: [RaceParticipant], me: String) -> [String: Double] {
        let others = participants.filter { $0.id != me }.sorted { ($0.lane, $0.id) < ($1.lane, $1.id) }
        var out: [String: Double] = [:]
        for (i, p) in others.enumerated() {
            let slot = maxSide > 0 ? i % maxSide + 1 : i + 1
            out[p.id] = -Double(slot) * spacing
        }
        return out
    }
}
