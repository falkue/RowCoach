import Foundation

// Hybrid Logical Clock für die Synchronisation (docs/SYNC.md, „Konflikte“). Ein Zeitstempel besteht aus
// Wanduhr (ms seit 1970), Zähler und Geräte-Id. Er wächst auf jedem Gerät streng, auch wenn die Uhr zurückspringt,
// und übernimmt beim Empfang den grössten bekannten Stand. Vergleich: Wanduhr, dann Zähler, dann Gerät –
// zwei Geräte erzeugen also nie denselben Zeitstempel, und der Sieger einer Konfliktregel ist überall derselbe.

/// Ein Zeitstempel der Hybrid Logical Clock. Als Text (`encoded`) lexikografisch gleich sortiert wie `<`,
/// damit auch die Firestore-Regeln Zeitstempel vergleichen können („nur neuere Belastung“).
public struct HybridTimestamp: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Millisekunden seit 1970 (0 = „Erststand“, verliert gegen jeden echten Zeitstempel)
    public var wallMillis: Int64
    public var counter: Int
    /// Geräte-Id: 1–16 Zeichen a–z, A–Z, 0–9
    public var node: String

    public static let maxCounter = 99_999

    public init(wallMillis: Int64, counter: Int = 0, node: String) {
        self.wallMillis = max(0, min(wallMillis, 9_999_999_999_999))
        self.counter = max(0, min(counter, Self.maxCounter))
        self.node = HybridTimestamp.sanitizedNode(node)
    }

    /// Stand vor jeder echten Änderung (Wanduhr 0): so markierte Werte verlieren gegen jeden Wert eines anderen
    /// Geräts. Wird beim ersten Abgleich eines Geräts benutzt, damit ein neues Gerät mit Standardwerten die
    /// vorhandenen Einstellungen auf dem Server nicht überschreibt.
    public static func initial(node: String) -> HybridTimestamp { HybridTimestamp(wallMillis: 0, node: node) }

    public static func < (a: HybridTimestamp, b: HybridTimestamp) -> Bool {
        if a.wallMillis != b.wallMillis { return a.wallMillis < b.wallMillis }
        if a.counter != b.counter { return a.counter < b.counter }
        return a.node < b.node
    }

    /// „0001732600000000-00000-ab12cd34“: 16 Stellen Wanduhr, 5 Stellen Zähler, Gerät
    public var encoded: String {
        let w = String(wallMillis), c = String(counter)
        return String(repeating: "0", count: max(0, 16 - w.count)) + w + "-"
            + String(repeating: "0", count: max(0, 5 - c.count)) + c + "-" + node
    }

    public var description: String { encoded }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 16, parts[1].count == 5,
              let w = Int64(parts[0]), let c = Int(parts[1]), w >= 0, c >= 0,
              !parts[2].isEmpty, parts[2].count <= 16,
              parts[2].unicodeScalars.allSatisfy({ HybridTimestamp.nodeCharacters.contains($0) })
        else { return nil }
        wallMillis = w
        counter = c
        node = String(parts[2])
    }

    static let nodeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    static func sanitizedNode(_ s: String) -> String {
        let cleaned = String(s.unicodeScalars.filter { nodeCharacters.contains($0) }.map(Character.init).prefix(16))
        return cleaned.isEmpty ? "x" : cleaned
    }

    /// Neue zufällige Geräte-Id (8 Zeichen)
    public static func randomNode() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
    }
}

extension HybridTimestamp: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let t = HybridTimestamp(encoded: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Ungültiger HLC-Zeitstempel: \(s)"))
        }
        self = t
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(encoded)
    }
}

/// Die Uhr eines Geräts. `tick` für eigene Änderungen, `observe` für empfangene Zeitstempel.
public struct HybridLogicalClock: Codable, Equatable, Sendable {
    public let node: String
    public private(set) var last: HybridTimestamp

    public init(node: String) {
        let n = HybridTimestamp.sanitizedNode(node)
        self.node = n
        last = .initial(node: n)
    }

    static func millis(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded(.down)) }

    /// Zeitstempel für eine eigene Änderung jetzt; immer grösser als alles bisher Gesehene
    public mutating func tick(now: Date = Date()) -> HybridTimestamp {
        let wall = Self.millis(now)
        if wall > last.wallMillis {
            last = HybridTimestamp(wallMillis: wall, counter: 0, node: node)
        } else if last.counter < HybridTimestamp.maxCounter {
            last = HybridTimestamp(wallMillis: last.wallMillis, counter: last.counter + 1, node: node)
        } else {
            last = HybridTimestamp(wallMillis: last.wallMillis + 1, counter: 0, node: node)
        }
        return last
    }

    /// Empfangenen Zeitstempel einrechnen (die nächste eigene Änderung liegt danach)
    public mutating func observe(_ remote: HybridTimestamp, now: Date = Date()) {
        let wall = Self.millis(now)
        // Zeitstempel weit in der Zukunft (falsche Uhr eines Geräts) nur bis 1 Tag über die eigene Uhr übernehmen
        let cappedWall = min(remote.wallMillis, wall + 86_400_000)
        let maxWall = max(wall, last.wallMillis, cappedWall)
        var counter = 0
        if maxWall == last.wallMillis { counter = max(counter, last.counter) }
        if maxWall == cappedWall, cappedWall == remote.wallMillis { counter = max(counter, remote.counter) }
        last = HybridTimestamp(wallMillis: maxWall, counter: counter, node: node)
    }
}
