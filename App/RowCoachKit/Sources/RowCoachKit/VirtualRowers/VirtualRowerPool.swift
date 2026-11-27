import Foundation

// Virtuelle Teilnehmende für Turniere (Freigabe Falk 27.11.2026, transparente Variante: immer gekennzeichnet).
// Ein fester, versionierter Pool erfundener Ruderer: Vorname aus offenen Listen, Land, Erscheinung, Leistungsprofil,
// Rennstil, Tagesform, saisonale Form, Zuverlässigkeit, bevorzugte Tageszeit. Keine echten Personen, keine Nachnamen.
// Regeln, Quellen und Server-Plan: docs/MULTIPLAYER.md „Virtuelle Teilnehmende“. Nur Foundation.

/// Ein virtueller Ruderer des Pools (alle Werte so gerundet, wie sie in der Pool-Datei stehen)
public struct VirtualRacer: Equatable, Hashable, Sendable, Identifiable {
    /// Leistungsverteilung und Namensliste (Concept2-Rangliste Männer bzw. Frauen). Wird nie angezeigt; die
    /// Erscheinung ist davon unabhängig (`RowerAppearance.random(seed:)`).
    public enum Group: UInt8, Sendable { case m = 0, w = 1 }

    /// Rennstil: Verlauf des Tempos über das Rennen
    public enum Style: UInt8, Sendable, CaseIterable {
        /// gleichmässig (leichtes Nachlassen)
        case even = 0
        /// schneller Start, danach etwas langsamer
        case fastStart = 1
        /// verhalten, starker Endspurt
        case finisher = 2
        /// zu schnell angegangen, bricht ein
        case fader = 3
    }

    /// Altersgruppe: 0 = 18–29, 1 = 30–39, 2 = 40–49, 3 = 50–59, 4 = 60–69, 5 = 70+
    public typealias AgeBand = Int

    /// Laufende Nummer im Pool (1 …)
    public var number: Int
    /// stabile Id: „v<Pool-Version>-<Nummer>“, z. B. „v1-0042“
    public var id: String
    public var firstName: String
    /// ISO 3166-1 alpha-2
    public var country: String
    public var group: Group
    public var ageBand: AgeBand
    /// Leistung in Grundform: 2000-m-Zeit (s, auf 0,1 s)
    public var best2k: Double
    /// Exponent des Leistungs-Dauer-Gesetzes P(t) ∝ t^(−b) (klein = Ausdauertyp, gross = Sprinttyp)
    public var exponent: Double
    public var style: Style
    /// Standardabweichung der Tagesform (Anteil der Leistung, 0,012–0,037)
    public var dayForm: Double
    /// Ausschlag der saisonalen Form (Anteil der Leistung; Höhepunkt im Winter der eigenen Halbkugel)
    public var season: Double
    /// Wahrscheinlichkeit, an einem Tag verfügbar zu sein (0,15–1)
    public var reliability: Double
    /// bevorzugte Ortszeit für Rennen (volle Stunde 6–21)
    public var preferredHour: Int
    /// Zeitzone (Normalzeit, Minuten gegenüber UTC) und Sommerzeit-Regel
    public var utcOffsetMinutes: Int
    public var dst: VirtualDSTRule
    public var hemisphere: VirtualHemisphere
    public var flagOnShirt: Bool

    /// Schwellenleistung (W) aus der 2k-Zeit und dem eigenen Exponenten (Leistungs-Dauer-Gesetz wie `ThresholdMath`)
    public var threshold: Double {
        let p2k = VirtualRaceSimulator.watts(pace: best2k / 4)
        return p2k * DetMath.pow(best2k / ThresholdMath.referenceDuration, exponent)
    }

    /// Erscheinung: je Id stabil zufällig aus dem Katalog, dazu die Flagge des Landes (Boot immer, Trikot je Person)
    public func appearance(catalog: AppearanceCatalog = .current) -> RowerAppearance {
        var a = RowerAppearance.random(seed: id, catalog: catalog)
        a.nationality = country
        a.flagOnBoat = true
        a.flagOnShirt = flagOnShirt
        return a
    }

    /// Teilnehmende für ein Rennen (Quelle `.virtual`, Anzeigename = Vorname)
    public func participant(lane: Int, catalog: AppearanceCatalog = .current) -> RaceParticipant {
        RaceParticipant(id: id, displayName: firstName, lane: lane, source: .virtual, appearance: appearance(catalog: catalog))
    }

    /// Ortszeit (Stunden) zur UTC-Zeit `t`
    public func localHour(at t: TimeInterval) -> Double {
        VirtualRowerCountries.localHour(at: t, offsetMinutes: utcOffsetMinutes, dst: dst)
    }

    /// Ortskalendertag (Tage seit 1970) zur UTC-Zeit `t`
    public func localDay(at t: TimeInterval) -> Int {
        DetMath.dayIndex(VirtualRowerCountries.localTime(at: t, offsetMinutes: utcOffsetMinutes, dst: dst))
    }
}

/// Fester Pool virtueller Ruderer. Version 1 wird aus einer festen Saat erzeugt (`generate`) und als Datei
/// mitgeliefert (App: `virtual-rowers-v1.bin`, Server: dieselbe Datei). Geladen wird immer die Datei; ein Test prüft,
/// dass der Generator sie bitgenau nachbildet. Ändert sich der Generator, entsteht ein neuer Pool mit neuer Version
/// und neuen Ids – nie still ein anderer Pool unter derselben Version.
public struct VirtualRowerPool: Equatable, Sendable {
    public static let currentVersion = 1
    public static let defaultCount = 5000
    /// Saat von Pool v1 („ROWCOACH“ als ASCII)
    public static let seedV1: UInt64 = 0x524F_5743_4F41_4348
    /// Dateiname im App-Bundle bzw. auf dem Server
    public static func fileName(version: Int = currentVersion) -> String { "virtual-rowers-v\(version).bin" }

    public let version: Int
    public let seed: UInt64
    public let rowers: [VirtualRacer]

    public init(version: Int, seed: UInt64, rowers: [VirtualRacer]) {
        self.version = version
        self.seed = seed
        self.rowers = rowers
    }

    public func rower(id: String) -> VirtualRacer? {
        guard let n = Self.number(of: id, version: version), n >= 1, n <= rowers.count else { return nil }
        return rowers[n - 1]
    }

    /// Nummer aus einer Id „v1-0042“ (nil bei anderer Version oder fremder Id)
    public static func number(of id: String, version: Int) -> Int? {
        let prefix = "v\(version)-"
        guard id.hasPrefix(prefix) else { return nil }
        return Int(id.dropFirst(prefix.count))
    }

    /// Ist das die Id eines virtuellen Teilnehmenden (irgendeiner Pool-Version)?
    public static func isVirtualId(_ id: String) -> Bool {
        guard id.first == "v", let dash = id.firstIndex(of: "-") else { return false }
        return Int(id[id.index(after: id.startIndex)..<dash]) != nil && Int(id[id.index(after: dash)...]) != nil
    }

    // MARK: Verteilungen (Pool v1)

    /// 2000-m-Zeiten der Concept2-Rangliste 2025 (RowErg, alle Gewichts- und Altersklassen, abgerufen 27.11.2026):
    /// Stützstellen (Quantil, Sekunden) der Verteilung; dazwischen linear. Männer: 9561 Einträge, 5 % 6:35,
    /// 25 % 7:13, Median 7:49, 75 % 8:31, 95 % 10:02. Frauen: 2546 Einträge, 2 % 7:15, 25 % 8:07, Median 8:51,
    /// 75 % 9:50, 95 % 12:20. Ränder (0 %, 1 %, 99 %, 100 %) geschätzt.
    static let quantilesM: [(q: Double, t: Double)] = [(0, 350), (0.01, 370), (0.05, 395), (0.25, 433), (0.5, 469),
                                                       (0.75, 511), (0.95, 602), (0.99, 690), (1, 780)]
    static let quantilesW: [(q: Double, t: Double)] = [(0, 400), (0.02, 435), (0.05, 450), (0.25, 487), (0.5, 531),
                                                       (0.75, 590), (0.95, 740), (0.99, 840), (1, 930)]
    /// Anteil der Frauen-Verteilung (Rangliste 2025: 2546 von 12 107 ≈ 21 %; etwas aufgerundet)
    static let shareW = 0.25
    /// Altersgruppen: Anteil und Faktor auf die 2k-Zeit (eigene Schätzung; normiert, damit die Gesamtverteilung
    /// der Rangliste erhalten bleibt)
    static let ageBands: [(weight: Double, factor: Double)] = [(15, 0.96), (17, 0.97), (22, 1.0), (24, 1.03),
                                                               (16, 1.08), (6, 1.15)]
    static let styleWeights: [Double] = [40, 25, 25, 10]

    static func quantile(_ table: [(q: Double, t: Double)], _ u: Double) -> Double {
        for i in 1..<table.count where u <= table[i].q {
            let a = table[i - 1], b = table[i]
            return a.t + (b.t - a.t) * (u - a.q) / (b.q - a.q)
        }
        return table[table.count - 1].t
    }

    static func pick(_ weights: [Double], _ u: Double) -> Int {
        var total = 0.0
        for w in weights { total += w }
        var x = u * total
        for (i, w) in weights.enumerated() {
            if x < w { return i }
            x -= w
        }
        return weights.count - 1
    }

    /// Erzeugt einen Pool aus der Saat (nur Grundrechenarten, auf allen Plattformen gleich). Jede Person hat einen
    /// eigenen Zufallsstrom aus Saat und Nummer.
    public static func generate(version: Int = currentVersion, count: Int = defaultCount,
                                seed: UInt64 = seedV1) -> VirtualRowerPool {
        let countries = VirtualRowerCountries.all.filter { c in
            guard let n = VirtualRowerNames.names(c.code) else { return false }
            return n.female.count >= 3 && n.male.count >= 3
        }
        let countryWeights = countries.map(\.weight)
        var ageNorm = 0.0, ageTotal = 0.0
        for a in ageBands { ageNorm += a.weight * a.factor; ageTotal += a.weight }
        ageNorm /= ageTotal
        var rowers: [VirtualRacer] = []
        rowers.reserveCapacity(count)
        for n in 1...max(count, 1) {
            var rng = RaceRandom(seed: seed ^ (UInt64(n) &* 0x9E37_79B9_7F4A_7C15))
            _ = rng.next()
            let c = countries[pick(countryWeights, rng.unit())]
            let zone = c.zones[pick(c.zones.map(\.share), rng.unit())]
            let group: VirtualRacer.Group = rng.unit() < shareW ? .w : .m
            let names = VirtualRowerNames.names(c.code)!
            let list = group == .w ? names.female : names.male
            let name = list[Int(rng.next() % UInt64(list.count))]
            let band = pick(ageBands.map(\.weight), rng.unit())
            let raw = quantile(group == .w ? quantilesW : quantilesM, rng.unit()) * ageBands[band].factor / ageNorm
            let best2k = Self.q2k(min(max(raw, 330), 1100))
            let b = Self.qExponent(0.10 + 0.10 * (rng.unit() + rng.unit()) / 2)
            let style = VirtualRacer.Style(rawValue: UInt8(pick(styleWeights, rng.unit())))!
            let dayForm = Self.qPermil(0.012 + 0.025 * rng.unit())
            var season = 0.01 + 0.035 * rng.unit()
            if c.hemisphere == .tropic { season *= 0.3 }
            let reliability = Self.qUnit(0.15 + 0.85 * max(rng.unit(), rng.unit()))
            // Tageszeit: morgens 6–8 (30 %), Mittag 11–13 (15 %), Abend 17–20 (45 %), spät 21 (10 %)
            let slot = pick([30, 15, 45, 10], rng.unit())
            let hours = [[6, 7, 8], [11, 12, 13], [17, 18, 19, 20], [21]][slot]
            let hour = hours[Int(rng.next() % UInt64(hours.count))]
            let shirt = rng.unit() < 0.5
            rowers.append(VirtualRacer(number: n, id: id(version: version, number: n), firstName: name, country: c.code,
                                       group: group, ageBand: band, best2k: best2k, exponent: b, style: style,
                                       dayForm: dayForm, season: Self.qPermil(season), reliability: reliability,
                                       preferredHour: hour, utcOffsetMinutes: zone.offsetMinutes, dst: zone.dst,
                                       hemisphere: c.hemisphere, flagOnShirt: shirt))
        }
        return VirtualRowerPool(version: version, seed: seed, rowers: rowers)
    }

    static func id(version: Int, number: Int) -> String {
        let digits = String(number)
        return "v\(version)-" + String(repeating: "0", count: max(4 - digits.count, 0)) + digits
    }

    // Rundung wie in der Datei
    static func q2k(_ t: Double) -> Double { (t * 10).rounded() / 10 }
    static func qExponent(_ b: Double) -> Double { 0.08 + Double(Int(((b - 0.08) / 0.0005).rounded())) * 0.0005 }
    static func qPermil(_ x: Double) -> Double { (x * 2000).rounded() / 2000 }
    static func qUnit(_ x: Double) -> Double { (x * 255).rounded() / 255 }

    // MARK: Datei (kompakt, binär)

    public enum FormatError: Error, Equatable {
        case badMagic, unsupportedFormat(Int), truncated, checksum, badRecord(Int)
    }

    static let magic: [UInt8] = Array("RCVP".utf8)
    static let formatVersion: UInt8 = 1

    /// Binärformat: „RCVP“, Formatversion (u8), Pool-Version (u16), Anzahl (u16), Saat (u64), je Person: Land
    /// (2 Byte ASCII), Name (Länge u8 + UTF-8), Bits (Gruppe, Stil, Altersgruppe, Trikotflagge), 2k-Zeit in 0,1 s
    /// (u16), Exponent, Tagesform, Saison, Zuverlässigkeit, Stunde (je u8), Zone in Viertelstunden (i8), Sommerzeit
    /// und Halbkugel (u8); am Ende FNV-1a-64 über alles davor. Zahlen little-endian. ≈ 19 Byte je Person.
    public func encoded() -> Data {
        var out: [UInt8] = Self.magic
        out.append(Self.formatVersion)
        func u16(_ v: Int) { out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF)) }
        func u64(_ v: UInt64) { for i in 0..<8 { out.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) } }
        u16(version)
        u16(rowers.count)
        u64(seed)
        for r in rowers {
            out.append(contentsOf: Array(r.country.utf8.prefix(2)))
            let name = Array(r.firstName.utf8.prefix(255))
            out.append(UInt8(name.count))
            out.append(contentsOf: name)
            var bits = r.group.rawValue & 1
            bits |= (r.style.rawValue & 3) << 1
            bits |= UInt8(r.ageBand & 7) << 3
            if r.flagOnShirt { bits |= 1 << 6 }
            out.append(bits)
            u16(Int((r.best2k * 10).rounded()))
            out.append(UInt8(Int(((r.exponent - 0.08) / 0.0005).rounded())))
            out.append(UInt8(Int((r.dayForm * 2000).rounded())))
            out.append(UInt8(Int((r.season * 2000).rounded())))
            out.append(UInt8(Int((r.reliability * 255).rounded())))
            out.append(UInt8(r.preferredHour))
            out.append(UInt8(bitPattern: Int8(r.utcOffsetMinutes / 15)))
            out.append(r.dst.rawValue | (r.hemisphere.rawValue << 4))
        }
        let h = Self.checksum(out)
        u64(h)
        return Data(out)
    }

    static func checksum(_ bytes: [UInt8]) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in bytes {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    public static func decode(_ data: Data) throws -> VirtualRowerPool {
        let b = [UInt8](data)
        guard b.count >= 4 + 1 + 2 + 2 + 8 + 8 else { throw FormatError.truncated }
        guard Array(b[0..<4]) == magic else { throw FormatError.badMagic }
        guard b[4] == formatVersion else { throw FormatError.unsupportedFormat(Int(b[4])) }
        let body = Array(b[0..<(b.count - 8)])
        var stored: UInt64 = 0
        for i in 0..<8 { stored |= UInt64(b[b.count - 8 + i]) << (8 * UInt64(i)) }
        guard checksum(body) == stored else { throw FormatError.checksum }
        var p = 5
        func u8() throws -> UInt8 {
            guard p < body.count else { throw FormatError.truncated }
            defer { p += 1 }
            return body[p]
        }
        func u16() throws -> Int { let lo = Int(try u8()); return lo | (Int(try u8()) << 8) }
        let version = try u16()
        let count = try u16()
        var seed: UInt64 = 0
        for i in 0..<8 { seed |= UInt64(try u8()) << (8 * UInt64(i)) }
        var rowers: [VirtualRacer] = []
        rowers.reserveCapacity(count)
        for n in 1...max(count, 1) where count > 0 {
            let c0 = try u8(), c1 = try u8()
            let len = Int(try u8())
            guard p + len <= body.count else { throw FormatError.truncated }
            let name = String(decoding: body[p..<(p + len)], as: UTF8.self)
            p += len
            let bits = try u8()
            let t = Double(try u16()) / 10
            let b = 0.08 + Double(try u8()) * 0.0005
            let day = Double(try u8()) / 2000
            let season = Double(try u8()) / 2000
            let rel = Double(try u8()) / 255
            let hour = Int(try u8())
            let zone = Int(Int8(bitPattern: try u8())) * 15
            let dz = try u8()
            guard let style = VirtualRacer.Style(rawValue: (bits >> 1) & 3),
                  let dst = VirtualDSTRule(rawValue: dz & 0x0F),
                  let hemi = VirtualHemisphere(rawValue: dz >> 4) else { throw FormatError.badRecord(n) }
            rowers.append(VirtualRacer(number: n, id: id(version: version, number: n),
                                       firstName: name, country: String(decoding: [c0, c1], as: UTF8.self),
                                       group: (bits & 1) == 1 ? .w : .m, ageBand: Int((bits >> 3) & 7), best2k: t,
                                       exponent: b, style: style, dayForm: day, season: season, reliability: rel,
                                       preferredHour: hour, utcOffsetMinutes: zone, dst: dst, hemisphere: hemi,
                                       flagOnShirt: (bits >> 6) & 1 == 1))
        }
        return VirtualRowerPool(version: version, seed: seed, rowers: rowers)
    }
}
