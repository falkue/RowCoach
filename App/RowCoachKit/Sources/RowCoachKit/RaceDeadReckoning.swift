import Foundation

// Dead Reckoning für grosse Rennen: Sender und Empfänger rechnen dieselbe Voraussage (letzter Frame + Tempo);
// gesendet wird nur, wenn sie nicht mehr stimmt. Dazu die seltenere Übersicht (Delta alle 5 s, voll alle 30 s), das
// kompakte Binärformat der Frames und das Kostenmodell. Messung und Begründung: docs/MULTIPLAYER.md, „Dead Reckoning“.

/// Gemeinsame Voraussage von Sender, Empfänger und Aggregator
public enum RaceDeadReckoning {
    /// Distanz zur Rennzeit `t` aus dem letzten Frame: Distanz + Geschwindigkeit (aus dem Tempo) × Zeit, im Ziel bzw.
    /// an der Ziellinie stehen bleibend
    public static func predict(_ f: LiveFrame, at t: TimeInterval, finishDistance: Double? = nil) -> Double {
        if f.finished { return f.distance }
        let d = f.distance + f.speed * max(t - f.raceTime, 0)
        return finishDistance.map { min(d, $0) } ?? d
    }
}

/// Wann der Sender einen Frame schickt (ersetzt `RacePublishThrottle` in grossen Feldern).
///
/// - Abweichung der wahren Distanz von der Voraussage aus dem zuletzt gesendeten Frame > `threshold`,
/// - Tempo-Sprung ≥ `paceJump` s/500 m oder Schlagzahl-Sprung ≥ `strokeRateJump` (der Empfänger zeichnet die
///   Ruderbewegung aus der Schlagzahl),
/// - Lebenszeichen alle `heartbeat` s,
/// - im Ziel sofort (mit exakter Zielzeit, unabhängig von der Näherung),
/// - zwischen zwei Frames mindestens `minInterval` s.
/// Präzisionsmodus (`precision`): in den letzten `precisionZone` m mit einem anderen Boot in ± `precisionRange` m
/// (optional auch bei knappem Überholen) spätestens alle `precisionHeartbeat` s, bei Abweichung > `precisionThreshold`
/// schon nach `precisionMinInterval` s – also 1–2 Frames/s.
public struct RaceDeadReckoningPublisher: Equatable, Sendable {
    public var threshold: Double = 4
    public var heartbeat: TimeInterval = 20
    public var minInterval: TimeInterval = 1
    public var paceJump: TimeInterval = 4
    public var strokeRateJump = 2
    public var finishDistance: Double?
    public var precisionZone: Double = 250
    public var precisionRange: Double = 30
    public var precisionThreshold: Double = 0.5
    public var precisionMinInterval: TimeInterval = 0.5
    public var precisionHeartbeat: TimeInterval = 1
    /// auch beim knappen Überholen (< diese Distanz, sich annähernd) dichter senden; nil = aus (Standard, siehe Doku)
    public var closeOvertakeRange: Double?
    public var closeOvertakeClosing: Double = 0.2

    /// Grund des letzten Sendens (Protokoll, Messung)
    public enum Reason: String, Sendable, CaseIterable {
        case first, finish, precision, deviation, pace, strokeRate, heartbeat
    }

    public private(set) var last: LiveFrame?
    public private(set) var lastReason: Reason?
    private var lastSentLocal: TimeInterval = -.infinity

    public init(threshold: Double = 4, heartbeat: TimeInterval = 20, finishDistance: Double? = nil) {
        self.threshold = threshold
        self.heartbeat = heartbeat
        self.finishDistance = finishDistance
    }

    /// Voraussage aus dem zuletzt gesendeten Frame (wie beim Empfänger)
    public func predicted(at raceTime: TimeInterval) -> Double? {
        last.map { RaceDeadReckoning.predict($0, at: raceTime, finishDistance: finishDistance) }
    }

    /// Präzisionsmodus? `neighbours`: Abstand (m, positiv = vor mir) und Annäherung (m/s, positiv = kommt näher)
    public func wantsPrecision(distanceToGo: Double?, neighbours: [(gap: Double, closing: Double)]) -> Bool {
        if let togo = distanceToGo, togo <= precisionZone, neighbours.contains(where: { abs($0.gap) <= precisionRange }) {
            return true
        }
        if let r = closeOvertakeRange {
            return neighbours.contains { abs($0.gap) < r && $0.closing > closeOvertakeClosing }
        }
        return false
    }

    /// true = diesen Frame jetzt senden (und als Grundlage der Voraussage merken). `now` = lokale Uhr.
    public mutating func shouldSend(_ f: LiveFrame, now: TimeInterval, precision: Bool = false) -> Bool {
        guard let l = last else { return mark(f, now, .first) }
        if l.finished { return false }
        if f.finished { return mark(f, now, .finish) }
        let dt = now - lastSentLocal
        let dev = abs(f.distance - RaceDeadReckoning.predict(l, at: f.raceTime, finishDistance: finishDistance))
        if precision {
            if dt >= precisionHeartbeat { return mark(f, now, .precision) }
            if dt >= precisionMinInterval && dev > precisionThreshold { return mark(f, now, .precision) }
        }
        guard dt >= minInterval else { return false }
        if dev > threshold { return mark(f, now, .deviation) }
        if l.pace > 0, f.pace > 0, abs(f.pace - l.pace) >= paceJump { return mark(f, now, .pace) }
        if (l.pace > 0) != (f.pace > 0) { return mark(f, now, .pace) }
        if abs(f.strokeRate - l.strokeRate) >= strokeRateJump { return mark(f, now, .strokeRate) }
        if dt >= heartbeat { return mark(f, now, .heartbeat) }
        return false
    }

    private mutating func mark(_ f: LiveFrame, _ now: TimeInterval, _ reason: Reason) -> Bool {
        last = f
        lastSentLocal = now
        lastReason = reason
        return true
    }
}

/// Erzeugt die Übersicht seltener: alle `interval` s nur die Einträge, deren Stand von der Voraussage aus dem zuletzt
/// verteilten Eintrag um mehr als `threshold` m abweicht (oder deren Ziel-/Veraltet-Status, Tempo oder Schlagzahl sich
/// änderte), und alle `fullEvery` s eine volle Übersicht (für neu Hinzugekommene und als Abgleich). Läuft im
/// Aggregator-Dienst, im Loopback-Hub oder in Tests.
///
/// Standard (gemessen, docs/MULTIPLAYER.md): Delta alle 10 s mit Schwelle 8 m, in den letzten `finishZone` m alle
/// `finishZoneInterval` s mit 1 m;
/// volle Übersicht alle 300 s für alle, dazu liest jedes Gerät sie beim Beitritt einmal (eigener Knoten ohne Abo).
public struct RaceFieldAggregator: Sendable {
    public var interval: TimeInterval = 10
    public var fullEvery: TimeInterval = 300
    public var threshold: Double = 8
    public var finishZone: Double = 250
    public var finishZoneThreshold: Double = 1
    /// Takt für Einträge in der Zielzone (kürzer als `interval`); nil = wie `interval`
    public var finishZoneInterval: TimeInterval? = 5
    public var paceJump: TimeInterval = 3
    public var strokeRateJump = 3
    /// ohne Frame seit so vielen Sekunden Rennzeit gilt ein Boot als veraltet
    public var staleAfter: TimeInterval = 45
    public var finishDistance: Double?

    private struct Sent { var entry: RaceFieldEntry; var at: TimeInterval }
    public private(set) var latest: [String: LiveFrame] = [:]
    private var sent: [String: Sent] = [:]
    private var lastTick: TimeInterval?
    private var lastZoneTick: TimeInterval?
    private var lastFull: TimeInterval?
    private var seq = 0

    public init(interval: TimeInterval = 10, fullEvery: TimeInterval = 300, threshold: Double = 8, finishDistance: Double? = nil) {
        self.interval = interval
        self.fullEvery = fullEvery
        self.threshold = threshold
        self.finishDistance = finishDistance
    }

    public mutating func receive(_ f: LiveFrame) {
        if let l = latest[f.participantId], f.seq <= l.seq { return }
        latest[f.participantId] = f
    }

    /// Übersicht, wenn fällig (sonst nil; ein leeres Delta wird nicht geschrieben)
    public mutating func tick(raceId: String, raceTime t: TimeInterval, sentAt: TimeInterval,
                              roster: RaceRosterIndex) -> RaceFieldSnapshot? {
        let zoneInterval = min(finishZoneInterval ?? interval, interval)
        if let lz = lastZoneTick, t - lz < zoneInterval { return nil }
        lastZoneTick = t
        let outsideDue = lastTick.map { t - $0 >= interval - 1e-9 } ?? true
        if outsideDue { lastTick = t }
        let full = lastFull.map { t - $0 >= fullEvery } ?? true
        if full { lastFull = t }
        var entries: [RaceFieldEntry] = []
        for (id, f) in latest {
            guard let i = roster.index(of: id) else { continue }
            let e = RaceFieldEntry(index: i, distance: RaceDeadReckoning.predict(f, at: t, finishDistance: finishDistance),
                                   pace: f.finished ? 0 : f.pace, strokeRate: f.finished ? 0 : f.strokeRate,
                                   finished: f.finished, stale: !f.finished && t - f.raceTime > staleAfter)
            let inZone = finishDistance.map { $0 - e.distance <= finishZone } ?? false
            if !full && !outsideDue && !inZone { continue }
            if !full, let s = sent[id] {
                var prev = s.entry.distance + (s.entry.finished || s.entry.stale ? 0 : s.entry.speed) * (t - s.at)
                if let fd = finishDistance { prev = min(prev, fd) }
                let zone = finishDistance.map { $0 - e.distance <= finishZone } ?? false
                let changed = abs(e.distance - prev) > (zone ? finishZoneThreshold : threshold) || e.finished != s.entry.finished
                    || e.stale != s.entry.stale || abs(e.strokeRate - s.entry.strokeRate) >= strokeRateJump
                    || abs(e.pace - s.entry.pace) >= paceJump
                if !changed { continue }
            }
            sent[id] = Sent(entry: e, at: t)
            entries.append(e)
        }
        if entries.isEmpty && !full { return nil }
        seq += 1
        entries.sort { $0.index < $1.index }
        return RaceFieldSnapshot(raceId: raceId, seq: seq, sentAt: sentAt, raceTime: t, rosterHash: roster.hash,
                                 entries: entries, isDelta: !full)
    }
}

/// Kompaktes Binärformat eines `LiveFrame` (statt JSON ≈ 130 Byte): 18 Byte, im Ziel 22 Byte, als Base64-String in der
/// Realtime Database 24 bzw. 32 Zeichen. Version u8 (1), Kurzindex u16 (`RaceRosterIndex`), seq u32, Rennzeit in
/// 0,01 s u32, Distanz in dm u24, Tempo in 0,1 s u16, Schlagzahl 6 Bit + im Ziel (Bit 6), Puls u8 (0 = keiner),
/// im Ziel zusätzlich Zielzeit in 0,001 s u32 (Wertung exakt). Big-Endian. `sentAt` geht nicht mit (Serverzeitstempel
/// des Eintrags genügt).
public enum RaceCompactFrame {
    public static func encode(_ f: LiveFrame, index: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(22)
        func put(_ v: UInt64, _ n: Int) { for i in stride(from: n - 1, through: 0, by: -1) { out.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) } }
        func q(_ x: Double, _ scale: Double, _ maxV: UInt64) -> UInt64 { x.isFinite && x > 0 ? min(UInt64((x * scale).rounded()), maxV) : 0 }
        out.append(1)
        put(UInt64(min(max(index, 0), 0xFFFF)), 2)
        put(UInt64(UInt32(clamping: max(f.seq, 0))), 4)
        put(q(f.raceTime, 100, 0xFFFF_FFFF), 4)
        put(q(f.distance, 10, 0xFF_FFFF), 3)
        put(q(f.pace, 10, 0xFFFF), 2)
        out.append(UInt8(min(max(f.strokeRate, 0), 63)) | (f.finished ? 0x40 : 0))
        out.append(UInt8(min(max(f.heartRate ?? 0, 0), 255)))
        if f.finished { put(q(f.finishTime ?? f.raceTime, 1000, 0xFFFF_FFFF), 4) }
        return out
    }

    public static func decode(_ b: [UInt8], raceId: String, roster: RaceRosterIndex, sentAt: TimeInterval = 0) -> LiveFrame? {
        guard b.count >= 18, b[0] == 1 else { return nil }
        func get(_ at: Int, _ n: Int) -> UInt64 { (0..<n).reduce(UInt64(0)) { ($0 << 8) | UInt64(b[at + $1]) } }
        guard let id = roster.id(at: Int(get(1, 2))) else { return nil }
        let flags = b[16]
        let finished = flags & 0x40 != 0
        guard !finished || b.count >= 22 else { return nil }
        return LiveFrame(participantId: id, raceId: raceId, seq: Int(get(3, 4)), sentAt: sentAt,
                         raceTime: Double(get(7, 4)) / 100, distance: Double(get(11, 3)) / 10, pace: Double(get(14, 2)) / 10,
                         strokeRate: Int(flags & 0x3F), heartRate: b[17] > 0 ? Int(b[17]) : nil, finished: finished,
                         finishTime: finished ? Double(get(18, 4)) / 1000 : nil)
    }

    /// Länge als Base64-String
    public static func wireLength(finished: Bool) -> Int { finished ? 32 : 24 }
}

/// Kostenmodell der Realtime Database (Preise und Grenzen: Firebase „Pricing“/„Realtime Database limits“,
/// abgerufen 26.11.2026). Abgerechnet wird ausgehender Verkehr (Download) inkl. Protokoll; Schreibvorgänge selbst kosten
/// nichts, aber jede Schreibbestätigung geht zurück an den Schreibenden.
public struct RaceCostModel: Equatable, Sendable {
    /// Rahmen je zugestellter Änderung (Pfad, Umschlag, WebSocket) in Byte – Annahme
    public var eventOverhead: Double = 60
    /// Bestätigung je Schreibvorgang an den Schreibenden (Byte) – Annahme
    public var writeAck: Double = 40
    /// USD je GB Download (nach 360 MB/Tag frei)
    public var usdPerGB: Double = 1
    /// Cloud Run, 1 vCPU + 0,5 GiB, als laufende Instanz (USD je Minute; 0,000024 USD je vCPU-s + 0,0000025 je GiB-s)
    public var aggregatorUSDPerMinute: Double = RaceCostModel.aggregatorUSDPerMinute(vCPU: 1, GiB: 0.5)

    public init() {}

    /// Cloud Run je Minute laufender Instanz (ca. 0,000024 USD je vCPU-s, 0,0000025 USD je GiB-s; Preisliste prüfen)
    public static func aggregatorUSDPerMinute(vCPU: Double, GiB: Double) -> Double {
        60 * (vCPU * 0.000024 + GiB * 0.0000025)
    }

    public func usd(downloadBytes: Double, aggregatorMinutes: Double = 0) -> Double {
        downloadBytes / 1e9 * usdPerGB + aggregatorMinutes * aggregatorUSDPerMinute
    }
}
