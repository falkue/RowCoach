import Foundation

/// Pulszonen 1…5 (docs/schwelle/SPEC.md, Abschnitt 4.2). Standard ist die Herzfrequenzreserve (Karvonen):
/// Grenze = Ruhepuls + Anteil × (Maximalpuls − Ruhepuls), Zone 1 ab 50 %, Zone 2 ab 60 %, Zone 3 ab 70 %, Zone 4 ab
/// 80 %, Zone 5 ab 90 %. Weitere Modelle: Schwellenpuls (LTHR, Friel: 70/81/90/94/100 %) und Prozent vom Maximalpuls
/// (Concept2: 50/60/70/80/90 %). Darunter Zone 0.
public struct HeartRateZones: Codable, Equatable, Sendable {
    /// Modell der Zonengrenzen
    public enum ModelKind: String, Codable, Sendable, CaseIterable {
        /// Herzfrequenzreserve (Karvonen, wie bisher)
        case reserve
        /// Prozent vom Maximalpuls
        case percentMax
        /// Prozent vom Schwellenpuls
        case lthr
    }

    public var maxHR: Int
    public var restHR: Int
    public var model: ModelKind
    /// Schwellenpuls (nur Modell `lthr`)
    public var lthr: Int?

    /// Untere Grenzen der Zonen 1…5 als Anteil der Herzfrequenzreserve bzw. des Maximalpulses
    public static let fractions: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]
    /// Untere Grenzen der Zonen 1…5 als Anteil des Schwellenpulses (Friel, Radsporttabelle)
    public static let lthrFractions: [Double] = [0.70, 0.81, 0.90, 0.94, 1.00]
    public static let count = 5

    public init(maxHR: Int, restHR: Int) {
        self.maxHR = maxHR
        self.restHR = restHR
        model = .reserve
        lthr = nil
    }

    /// Zonen nach Prozent vom Maximalpuls
    public init(percentMax maxHR: Int, restHR: Int = 55) {
        self.maxHR = maxHR
        self.restHR = restHR
        model = .percentMax
        lthr = nil
    }

    /// Zonen nach Schwellenpuls
    public init(lthr: Int, maxHR: Int = 185, restHR: Int = 55) {
        self.maxHR = maxHR
        self.restHR = restHR
        model = .lthr
        self.lthr = lthr
    }

    enum CodingKeys: String, CodingKey { case maxHR, restHR, model, lthr }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxHR = try c.decode(Int.self, forKey: .maxHR)
        restHR = try c.decode(Int.self, forKey: .restHR)
        lthr = try? c.decodeIfPresent(Int.self, forKey: .lthr)
        let m = (try? c.decodeIfPresent(String.self, forKey: .model)).flatMap { $0 }.flatMap(ModelKind.init(rawValue:))
        model = m == .lthr && lthr == nil ? .reserve : (m ?? .reserve)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(maxHR, forKey: .maxHR)
        try c.encode(restHR, forKey: .restHR)
        if model != .reserve { try c.encode(model.rawValue, forKey: .model) }
        try c.encodeIfPresent(lthr, forKey: .lthr)
    }

    /// Untere Grenze (bpm) der Zone 1…5
    public func lowerBound(zone: Int) -> Int {
        let z = min(max(zone, 1), Self.count)
        switch model {
        case .reserve:
            let reserve = Double(max(maxHR - restHR, 1))
            return Int((Double(restHR) + Self.fractions[z - 1] * reserve).rounded())
        case .percentMax:
            return Int((Self.fractions[z - 1] * Double(maxHR)).rounded())
        case .lthr:
            return Int((Self.lthrFractions[z - 1] * Double(lthr ?? maxHR)).rounded())
        }
    }

    /// 0 = unter Zone 1, sonst 1…5
    public func zone(for bpm: Int) -> Int {
        var z = 0
        for i in 1...Self.count where bpm >= lowerBound(zone: i) { z = i }
        return z
    }

    /// Sekunden je Zone (Index 0…5) aus einer Zeitreihe; jeder Wert gilt bis zum nächsten Zeitpunkt (höchstens 5 s).
    public func secondsPerZone(_ samples: [WorkoutSample]) -> [Double] {
        var out = [Double](repeating: 0, count: Self.count + 1)
        for (i, s) in samples.enumerated() {
            guard let hr = s.heartRate else { continue }
            let next = i + 1 < samples.count ? samples[i + 1].time : s.time + 1
            out[zone(for: hr)] += min(max(next - s.time, 0), 5)
        }
        return out
    }
}
