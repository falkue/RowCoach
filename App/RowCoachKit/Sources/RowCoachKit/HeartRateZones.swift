import Foundation

/// Pulszonen nach der Herzfrequenzreserve (Karvonen): Grenze = Ruhepuls + Anteil × (Maximalpuls − Ruhepuls).
/// Zone 1 ab 50 %, Zone 2 ab 60 %, Zone 3 ab 70 %, Zone 4 ab 80 %, Zone 5 ab 90 %. Darunter Zone 0.
public struct HeartRateZones: Codable, Equatable, Sendable {
    public var maxHR: Int
    public var restHR: Int

    /// Untere Grenzen der Zonen 1…5 als Anteil der Herzfrequenzreserve
    public static let fractions: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]
    public static let count = 5

    public init(maxHR: Int, restHR: Int) {
        self.maxHR = maxHR
        self.restHR = restHR
    }

    /// Untere Grenze (bpm) der Zone 1…5
    public func lowerBound(zone: Int) -> Int {
        let z = min(max(zone, 1), Self.count)
        let reserve = Double(max(maxHR - restHR, 1))
        return Int((Double(restHR) + Self.fractions[z - 1] * reserve).rounded())
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
