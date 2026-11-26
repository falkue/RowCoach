import Foundation

// Kompakte Binärform der Zeitreihe einer Fahrt für den Server (docs/SYNC.md, „Grössenbudget“). Nur Foundation,
// keine Kompressionsbibliothek (auf Linux/Android fehlt `NSData.compressed`): Spalten mit Differenzen,
// ZigZag und Varint. Eine Stunde (3600 Punkte) braucht so ca. 30–40 KB statt ca. 250 KB JSON.
//
// Format 1:
//   "RS" 0x01 | varint n | Spalte Zeit (ms) | Distanz (cm) | Tempo (cs/500 m) | Schlagzahl | Leistung | Puls+1 (0 = keiner)
//   | varint m | RR-Intervalle (ms)
//   Jede Spalte: n ZigZag-Varints der Differenz zum Vorwert (erster Wert gegen 0).
// Auflösung: Zeit 1 ms, Distanz 1 cm, Tempo 0,01 s – feiner als der PM5 liefert (0,1 m, 0,01 s).

public enum SampleCodec {
    public static let formatVersion: UInt8 = 1
    static let magic: [UInt8] = [0x52, 0x53] // "RS"
    /// Obergrenze beim Lesen (Schutz vor beschädigten Daten): 48 h bei 1 Hz
    public static let maxSamples = 172_800
    public static let maxRR = 400_000

    public enum CodecError: Error, Equatable {
        case badHeader, unsupportedVersion(UInt8), truncated, tooLarge, overflow
    }

    // MARK: Schreiben

    public static func encode(samples: [WorkoutSample], rr: [Double]?) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(samples.count * 10 + (rr?.count ?? 0) * 2 + 16)
        out += magic
        out.append(formatVersion)
        putVarint(UInt64(samples.count), &out)
        column(samples.map { q($0.time, 1000) }, &out)
        column(samples.map { q($0.distance, 100) }, &out)
        column(samples.map { q($0.pace, 100) }, &out)
        column(samples.map { Int64($0.strokeRate) }, &out)
        column(samples.map { Int64($0.power) }, &out)
        column(samples.map { $0.heartRate.map { Int64($0) + 1 } ?? 0 }, &out)
        let rrValues = rr ?? []
        putVarint(UInt64(rrValues.count), &out)
        column(rrValues.map { q($0, 1000) }, &out)
        return Data(out)
    }

    /// Wert auf ganze Einheiten runden (nicht endliche Werte werden 0)
    static func q(_ v: Double, _ scale: Double) -> Int64 {
        let x = (v * scale).rounded()
        guard x.isFinite, abs(x) < 9e15 else { return 0 }
        return Int64(x)
    }

    static func column(_ values: [Int64], _ out: inout [UInt8]) {
        var prev: Int64 = 0
        for v in values {
            let (d, o) = v.subtractingReportingOverflow(prev)
            putVarint(zigzag(o ? 0 : d), &out)
            prev = o ? prev : v
        }
    }

    static func zigzag(_ v: Int64) -> UInt64 { UInt64(bitPattern: (v << 1) ^ (v >> 63)) }
    static func unzigzag(_ u: UInt64) -> Int64 { Int64(bitPattern: u >> 1) ^ -Int64(bitPattern: u & 1) }

    static func putVarint(_ value: UInt64, _ out: inout [UInt8]) {
        var v = value
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
    }

    // MARK: Lesen

    public static func decode(_ data: Data) throws -> (samples: [WorkoutSample], rr: [Double]?) {
        var r = Reader(bytes: [UInt8](data))
        guard r.bytes.count >= 3, r.bytes[0] == magic[0], r.bytes[1] == magic[1] else { throw CodecError.badHeader }
        r.pos = 2
        let version = try r.byte()
        guard version == formatVersion else { throw CodecError.unsupportedVersion(version) }
        let n = try r.varint()
        guard n <= UInt64(maxSamples) else { throw CodecError.tooLarge }
        let count = Int(n)
        let time = try r.column(count), dist = try r.column(count), pace = try r.column(count)
        let spm = try r.column(count), power = try r.column(count), hr = try r.column(count)
        var samples = [WorkoutSample]()
        samples.reserveCapacity(count)
        for i in 0..<count {
            samples.append(WorkoutSample(time: Double(time[i]) / 1000, distance: Double(dist[i]) / 100,
                                         pace: Double(pace[i]) / 100, strokeRate: clampInt(spm[i]),
                                         power: clampInt(power[i]), heartRate: hr[i] > 0 ? clampInt(hr[i] - 1) : nil))
        }
        let m = try r.varint()
        guard m <= UInt64(maxRR) else { throw CodecError.tooLarge }
        let rrInts = try r.column(Int(m))
        return (samples, m == 0 ? nil : rrInts.map { Double($0) / 1000 })
    }

    static func clampInt(_ v: Int64) -> Int { Int(max(Int64(Int32.min), min(Int64(Int32.max), v))) }

    struct Reader {
        let bytes: [UInt8]
        var pos = 0

        mutating func byte() throws -> UInt8 {
            guard pos < bytes.count else { throw CodecError.truncated }
            defer { pos += 1 }
            return bytes[pos]
        }

        mutating func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let b = try byte()
                guard shift < 64 else { throw CodecError.overflow }
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
            }
        }

        mutating func column(_ n: Int) throws -> [Int64] {
            var out = [Int64]()
            out.reserveCapacity(n)
            var prev: Int64 = 0
            for _ in 0..<n {
                let (v, o) = prev.addingReportingOverflow(SampleCodec.unzigzag(try varint()))
                guard !o else { throw CodecError.overflow }
                out.append(v)
                prev = v
            }
            return out
        }
    }

    // MARK: Ausdünnen

    /// Jeden `step`-ten Punkt behalten (erster und letzter immer). Nur für extrem lange Fahrten, die sonst das
    /// Grössenbudget sprengen.
    public static func thinned(_ samples: [WorkoutSample], step: Int) -> [WorkoutSample] {
        guard step > 1, samples.count > 2 else { return samples }
        var out = [WorkoutSample]()
        for (i, s) in samples.enumerated() where i % step == 0 { out.append(s) }
        if let last = samples.last, out.last != last { out.append(last) }
        return out
    }

    /// Werte so runden, wie sie nach dem Hin- und Rückweg aussehen (für Vergleiche in Tests und beim Abgleich)
    public static func quantized(_ s: WorkoutSample) -> WorkoutSample {
        WorkoutSample(time: Double(q(s.time, 1000)) / 1000, distance: Double(q(s.distance, 100)) / 100,
                      pace: Double(q(s.pace, 100)) / 100, strokeRate: s.strokeRate, power: s.power, heartRate: s.heartRate)
    }
}
