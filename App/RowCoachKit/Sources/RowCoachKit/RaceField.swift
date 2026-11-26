import Foundation

// Grosse Felder (100–300 Teilnehmende): kompakte Gesamtübersicht über alle („Feld“) und Wahl der Nachbarschaft, für
// die volle Frames abonniert werden. Nur Foundation; Aufbau, Rechnung und Firebase-Varianten in docs/MULTIPLAYER.md,
// Abschnitt „Grosse Felder“.

/// Kurzindex je Teilnehmendem für die Übersicht: Reihenfolge nach (Bahn, id). Server und Geräte bilden ihn aus
/// derselben Teilnehmerliste; `hash` (FNV-1a über die ids in Indexreihenfolge) erkennt, ob beide dieselbe Liste haben.
public struct RaceRosterIndex: Equatable, Sendable {
    public let ids: [String]
    public let hash: UInt32
    private let positions: [String: Int]

    public init(participants: [RaceParticipant]) {
        let sorted = participants.sorted { ($0.lane, $0.id) < ($1.lane, $1.id) }
        var seen = Set<String>()
        ids = sorted.map(\.id).filter { seen.insert($0).inserted }
        positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        hash = Self.fnv1a(ids)
    }

    public var count: Int { ids.count }
    public func index(of id: String) -> Int? { positions[id] }
    public func id(at index: Int) -> String? { index >= 0 && index < ids.count ? ids[index] : nil }

    static func fnv1a(_ ids: [String]) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for id in ids {
            for b in id.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
            h = (h ^ 0x0A) &* 16_777_619
        }
        return h
    }
}

/// Ein Teilnehmender in der Übersicht (grob: Distanz auf 0,1 m, Tempo auf 0,1 s, Schlagzahl bis 63)
public struct RaceFieldEntry: Equatable, Sendable {
    /// Kurzindex (`RaceRosterIndex`)
    public var index: Int
    /// Distanz (m), auf 0,1 m gerundet
    public var distance: Double
    /// Tempo (s/500 m), auf 0,1 s gerundet, 0 = unbekannt
    public var pace: TimeInterval
    public var strokeRate: Int
    public var finished: Bool
    /// seit einiger Zeit keine Frames mehr (Verbindung weg)
    public var stale: Bool

    public init(index: Int, distance: Double, pace: TimeInterval, strokeRate: Int, finished: Bool = false, stale: Bool = false) {
        self.index = index
        self.distance = distance
        self.pace = pace
        self.strokeRate = strokeRate
        self.finished = finished
        self.stale = stale
    }

    public var speed: Double { pace > 0 && pace.isFinite ? 500 / pace : 0 }
}

/// Gesamtübersicht eines Rennens, ca. 1/s für alle (Firebase: `/live/{raceId}/field`, geschrieben vom Aggregator).
///
/// Auf dem Draht kompakt binär (Base64 in einem JSON-Feld `b`): Kopf 15 Byte (Version 1, seq u32, Rennzeit in
/// 0,01 s u32, Listen-Hash u32, Anzahl u16), je Teilnehmendem 8 Byte: Index u16, Distanz in dm u24, Tempo in 0,1 s
/// u16, 1 Byte Schlagzahl (Bits 0–5) + im Ziel (Bit 6) + veraltet (Bit 7). Big-Endian.
/// 300 Teilnehmende = 2415 Byte binär, 3220 Byte Base64 (≈ 10,7 Byte je Teilnehmendem).
public struct RaceFieldSnapshot: Equatable, Sendable, Codable {
    public var raceId: String
    /// fortlaufende Nummer (ältere werden verworfen)
    public var seq: Int
    /// Erzeugung (Serverzeit, s seit 1970)
    public var sentAt: TimeInterval
    /// Rennzeit, auf die alle Distanzen bezogen sind (s, auf 0,01 s)
    public var raceTime: TimeInterval
    /// `RaceRosterIndex.hash` der Liste, auf die sich die Indizes beziehen
    public var rosterHash: UInt32
    public var entries: [RaceFieldEntry]

    public init(raceId: String, seq: Int, sentAt: TimeInterval, raceTime: TimeInterval, rosterHash: UInt32,
                entries: [RaceFieldEntry]) {
        self.raceId = raceId
        self.seq = seq
        self.sentAt = sentAt
        self.raceTime = raceTime
        self.rosterHash = rosterHash
        self.entries = entries
    }

    public static let headerBytes = 15
    public static let bytesPerEntry = 8

    // MARK: Binärformat

    public func encodeBinary() -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(Self.headerBytes + entries.count * Self.bytesPerEntry)
        func put(_ v: UInt64, _ n: Int) { for i in stride(from: n - 1, through: 0, by: -1) { out.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) } }
        func clamp(_ x: Double, _ maxV: UInt64) -> UInt64 { x.isFinite && x > 0 ? min(UInt64(x.rounded()), maxV) : 0 }
        out.append(1)
        put(UInt64(UInt32(clamping: max(seq, 0))), 4)
        put(clamp(raceTime * 100, 0xFFFF_FFFF), 4)
        put(UInt64(rosterHash), 4)
        put(UInt64(min(entries.count, 0xFFFF)), 2)
        for e in entries.prefix(0xFFFF) {
            put(UInt64(min(max(e.index, 0), 0xFFFF)), 2)
            put(clamp(e.distance * 10, 0xFF_FFFF), 3)
            put(clamp(e.pace * 10, 0xFFFF), 2)
            var flags = UInt8(min(max(e.strokeRate, 0), 63))
            if e.finished { flags |= 0x40 }
            if e.stale { flags |= 0x80 }
            out.append(flags)
        }
        return out
    }

    public static func decodeBinary(_ b: [UInt8], raceId: String, sentAt: TimeInterval) -> RaceFieldSnapshot? {
        guard b.count >= headerBytes, b[0] == 1 else { return nil }
        func get(_ at: Int, _ n: Int) -> UInt64 { (0..<n).reduce(UInt64(0)) { ($0 << 8) | UInt64(b[at + $1]) } }
        let count = Int(get(13, 2))
        guard b.count >= headerBytes + count * bytesPerEntry else { return nil }
        var entries: [RaceFieldEntry] = []
        entries.reserveCapacity(count)
        for i in 0..<count {
            let o = headerBytes + i * bytesPerEntry
            let flags = b[o + 7]
            entries.append(RaceFieldEntry(index: Int(get(o, 2)), distance: Double(get(o + 2, 3)) / 10,
                                          pace: Double(get(o + 5, 2)) / 10, strokeRate: Int(flags & 0x3F),
                                          finished: flags & 0x40 != 0, stale: flags & 0x80 != 0))
        }
        return RaceFieldSnapshot(raceId: raceId, seq: Int(get(1, 4)), sentAt: sentAt, raceTime: Double(get(5, 4)) / 100,
                                 rosterHash: UInt32(get(9, 4)), entries: entries)
    }

    // MARK: JSON (wie in der Realtime Database): {"r": raceId, "at": sentAt, "b": Base64}

    enum CodingKeys: String, CodingKey { case raceId = "r", sentAt = "at", payload = "b" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raceId = try c.decode(String.self, forKey: .raceId)
        let sentAt = try c.decode(Double.self, forKey: .sentAt)
        guard let data = Data(base64Encoded: try c.decode(String.self, forKey: .payload)),
              let s = Self.decodeBinary([UInt8](data), raceId: raceId, sentAt: sentAt) else {
            throw DecodingError.dataCorruptedError(forKey: .payload, in: c, debugDescription: "Feld-Übersicht unlesbar")
        }
        self = s
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(raceId, forKey: .raceId)
        try c.encode(sentAt, forKey: .sentAt)
        try c.encode(Data(encodeBinary()).base64EncodedString(), forKey: .payload)
    }

    /// Grösse auf dem Draht (Base64-Nutzlast, ohne JSON-Rahmen)
    public var wireBytes: Int { (encodeBinary().count + 2) / 3 * 4 }

    /// Übersicht aus den letzten Frames aller (Aggregator auf dem Server, Loopback-Hub, Bot-Feld): jede Distanz mit dem
    /// Tempo bis `raceTime` vorausgerechnet (höchstens `maxExtrapolation` s); ältere als `staleAfter` gelten als veraltet.
    public static func build(raceId: String, seq: Int, sentAt: TimeInterval, raceTime: TimeInterval,
                             roster: RaceRosterIndex, latest: [String: LiveFrame], maxExtrapolation: TimeInterval = 3,
                             staleAfter: TimeInterval = 5) -> RaceFieldSnapshot {
        var entries: [RaceFieldEntry] = []
        entries.reserveCapacity(latest.count)
        for (id, f) in latest {
            guard let i = roster.index(of: id) else { continue }
            let age = raceTime - f.raceTime
            let d = f.finished ? f.distance : f.distance + f.speed * min(max(age, 0), maxExtrapolation)
            entries.append(RaceFieldEntry(index: i, distance: d, pace: f.finished ? 0 : f.pace,
                                          strokeRate: f.finished ? 0 : f.strokeRate, finished: f.finished,
                                          stale: !f.finished && age > staleAfter))
        }
        entries.sort { $0.index < $1.index }
        return RaceFieldSnapshot(raceId: raceId, seq: seq, sentAt: sentAt, raceTime: raceTime, rosterHash: roster.hash,
                                 entries: entries)
    }
}

/// Grober Stand eines Teilnehmenden aus der Übersicht, auf eine Rennzeit vorausgerechnet
public struct RaceCoarseState: Equatable, Sendable {
    public var id: String
    public var distance: Double
    public var speed: Double
    public var strokeRate: Int
    public var finished: Bool
    public var stale: Bool
}

/// Hält die letzte Übersicht auf dem Gerät und rechnet sie auf die Rennzeit des Bildes voraus.
public struct RaceFieldTracker: Sendable {
    public private(set) var roster: RaceRosterIndex
    public private(set) var latest: RaceFieldSnapshot?
    public private(set) var lastReceivedLocal: TimeInterval?
    /// verworfene Übersichten, weil die Teilnehmerliste nicht passte (dann Liste neu laden)
    public private(set) var rosterMismatches = 0
    public var maxExtrapolation: TimeInterval

    public init(participants: [RaceParticipant] = [], maxExtrapolation: TimeInterval = 4) {
        roster = RaceRosterIndex(participants: participants)
        self.maxExtrapolation = maxExtrapolation
    }

    public mutating func setRoster(_ participants: [RaceParticipant]) {
        let r = RaceRosterIndex(participants: participants)
        if r != roster { roster = r }
    }

    /// Übersicht aufnehmen; ältere (nach seq) und solche zu einer anderen Teilnehmerliste werden verworfen
    @discardableResult
    public mutating func receive(_ s: RaceFieldSnapshot, receivedLocal: TimeInterval) -> Bool {
        if let l = latest, s.seq <= l.seq { return false }
        guard s.rosterHash == roster.hash else { rosterMismatches += 1; return false }
        latest = s
        lastReceivedLocal = receivedLocal
        return true
    }

    /// Alle Stände zur Rennzeit `raceTime` (ohne `exclude`, z. B. mich)
    public func states(atRaceTime raceTime: TimeInterval, exclude: String? = nil) -> [RaceCoarseState] {
        guard let s = latest else { return [] }
        let dt = min(max(raceTime - s.raceTime, 0), maxExtrapolation)
        var out: [RaceCoarseState] = []
        out.reserveCapacity(s.entries.count)
        for e in s.entries {
            guard let id = roster.id(at: e.index), id != exclude else { continue }
            let v = e.finished || e.stale ? 0 : e.speed
            out.append(RaceCoarseState(id: id, distance: e.distance + v * dt, speed: v, strokeRate: e.strokeRate,
                                       finished: e.finished, stale: e.stale))
        }
        return out
    }
}

/// Wofür ein Gerät volle Frames haben will (Nachbarschafts-Abo). `fullIds == nil` = alle (Verhalten bisher).
public struct RaceInterest: Equatable, Sendable {
    public var fullIds: Set<String>?
    /// eigene Distanz beim Festlegen (für eine Bucket-Umsetzung, siehe `RaceBuckets`)
    public var distance: Double?

    public init(fullIds: Set<String>?, distance: Double? = nil) {
        self.fullIds = fullIds
        self.distance = distance
    }

    public static let everything = RaceInterest(fullIds: nil)

    public func wants(_ id: String) -> Bool { fullIds?.contains(id) ?? true }
}

/// Variante „Buckets“ (bewertet, nicht empfohlen): Frames liegen unter `/live/{raceId}/buckets/{b}/{uid}` mit
/// b = ⌊Distanz / size⌋; ein Gerät abonniert die Buckets um sich.
public struct RaceBuckets: Equatable, Sendable {
    public var size: Double

    public init(size: Double = 50) { self.size = max(size, 1) }

    public func bucket(for distance: Double) -> Int { Int((max(distance, 0) / size).rounded(.down)) }

    /// Buckets im Umkreis (vor mir `ahead` m, hinter mir `behind` m)
    public func buckets(around distance: Double, ahead: Double = 100, behind: Double = 50) -> ClosedRange<Int> {
        bucket(for: distance - behind)...bucket(for: distance + ahead)
    }
}

/// Datenmenge je Gerät (Rechenhilfe für Doku und Tests), Bytes pro Sekunde
public struct RaceDataBudget: Equatable, Sendable {
    /// Bytes je LiveFrame auf dem Draht inkl. Pfad und Protokoll (JSON ≈ 120 + Rahmen ≈ 30)
    public var frameBytes: Double = 150
    public var frameRate: Double = 2.5
    /// Übersichten pro Sekunde
    public var fieldRate: Double = 1
    /// JSON-Rahmen und Protokoll um die Base64-Nutzlast
    public var fieldOverhead: Double = 60

    public init() {}

    /// Empfang je Gerät ohne Nachbarschaft: alle anderen voll
    public func naiveDownload(participants n: Int) -> Double { Double(max(n - 1, 0)) * frameRate * frameBytes }

    /// Empfang je Gerät mit Nachbarschafts-Abo (K volle) und Übersicht für alle
    public func download(participants n: Int, neighbours k: Int) -> Double {
        Double(min(k, max(n - 1, 0))) * frameRate * frameBytes + fieldRate * fieldBytes(participants: n)
    }

    public func fieldBytes(participants n: Int) -> Double {
        let raw = Double(RaceFieldSnapshot.headerBytes + n * RaceFieldSnapshot.bytesPerEntry)
        return (raw / 3).rounded(.up) * 4 + fieldOverhead
    }

    public func upload() -> Double { frameRate * frameBytes }
}
