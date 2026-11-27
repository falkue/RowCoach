import Foundation

/// Wann welche virtuelle Person zuletzt gefahren ist (Rotation). Der Server führt sie zentral; in der App für die
/// Demo aus der eigenen Rangliste (`RaceRankingBook.virtualHistory`).
public struct VirtualRowerHistory: Codable, Equatable, Sendable {
    /// letzter Rennstart je Id (UTC, Sekunden seit 1970)
    public var lastRaced: [String: TimeInterval]
    /// Anzahl Rennen je Id
    public var raceCount: [String: Int]
    /// Rennstarts der letzten 14 Tage je Id (für die Obergrenze je Woche)
    public var recent: [String: [TimeInterval]]

    public init(lastRaced: [String: TimeInterval] = [:], raceCount: [String: Int] = [:],
                recent: [String: [TimeInterval]] = [:]) {
        self.lastRaced = lastRaced
        self.raceCount = raceCount
        self.recent = recent
    }

    public mutating func record(_ ids: [String], at t: TimeInterval) {
        for id in ids {
            lastRaced[id] = max(lastRaced[id] ?? -.infinity, t)
            raceCount[id, default: 0] += 1
            var list = (recent[id] ?? []).filter { t - $0 < 14 * 86400 }
            list.append(t)
            recent[id] = list
        }
    }

    /// Rennen in den 7 Tagen vor `t`
    public func racesInWeek(_ id: String, before t: TimeInterval) -> Int {
        (recent[id] ?? []).filter { $0 <= t && t - $0 < 7 * 86400 }.count
    }
}

/// Ergebnis des Auffüllens: Teilnehmerliste (echte zuerst, dann virtuelle) und die gewählten virtuellen Personen
public struct TournamentField: Equatable, Sendable {
    /// gewürfelte Mindestgrösse des Feldes (45…387)
    public var minimumField: Int
    public var participants: [RaceParticipant]
    public var virtualRowers: [VirtualRacer]
    public var realCount: Int

    public var virtualCount: Int { virtualRowers.count }
    public var total: Int { participants.count }
}

/// Füllt ein Turnierfeld mit virtuellen Teilnehmenden auf (docs/MULTIPLAYER.md „Virtuelle Teilnehmende“):
/// 1. Mindestfeld: je Turnier eine gleichverteilte Zahl 45…387 aus Turnier-Id und Saat (Server und Geräte gleich).
/// 2. Weniger echte Anmeldungen → mit virtuellen bis zur Zahl auffüllen; mehr echte → keine virtuellen.
/// 3. Nur Personen, bei denen es Ortszeit 06:00–22:00 ist (07–21 Uhr bevorzugt, Randstunden geringer gewichtet).
/// 4. Gewichtet nach Niveau (um die echten Teilnehmenden bzw. die Leistungsklasse), Zuverlässigkeit (verfügbar an
///    diesem Ortstag), bevorzugter Tageszeit und „wann zuletzt gefahren“ (nie zweimal am selben Ortstag).
/// Alles deterministisch aus Turnier, Rennen, Saat und Verlauf.
public enum TournamentFieldFiller {
    public struct Config: Equatable, Sendable {
        public var minField = 45
        public var maxField = 387
        /// erlaubte Ortszeit [von, bis) in Stunden und bevorzugtes Fenster (volles Gewicht)
        public var allowedHours: ClosedRange<Double> = 6...22
        public var preferredHours: ClosedRange<Double> = 7...21
        /// Gewicht in den Randstunden (06–07, 21–22 Uhr)
        public var edgeWeight = 0.3
        /// Zusatzgewicht nahe der bevorzugten Stunde der Person (± 2 h)
        public var habitBonus = 0.6
        /// Breite der Niveau-Gewichtung (Standardabweichung auf der 2k-Zeit, s); mindestens so breit wie die
        /// Streuung der echten Teilnehmenden
        public var levelWidth = 30.0
        /// Niveau ohne echte Werte (2k-Zeit, s); nil = Median des Pools
        public var defaultLevel: Double?
        /// harte Leistungsklasse (2k-Zeit von…bis, s); nil = alle
        public var levelClass: ClosedRange<Double>?
        /// „zuletzt gefahren“: volles Gewicht erst nach so vielen Tagen, direkt danach `recencyFloor`
        public var recencyDays = 7.0
        public var recencyFloor = 0.05
        /// höchstens so viele Rennen je Person in 7 Tagen (gelockert erst, wenn das Feld sonst nicht voll wird)
        public var maxPerWeek = 3

        public init() {}
    }

    /// Mindestfeld: gleichverteilt in `minField…maxField`, deterministisch aus Turnier-Id und Saat
    public static func minimumField(tournamentId: String, seed: UInt64, config: Config = Config()) -> Int {
        let span = UInt64(config.maxField - config.minField + 1)
        var rng = RaceRandom(seed: DetMath.fnv64("field|\(tournamentId)") ^ seed)
        // ohne Modulo-Verzerrung: nur Werte unter dem grössten Vielfachen von `span`
        let limit = UInt64.max - UInt64.max % span
        var x = rng.next()
        while x >= limit { x = rng.next() }
        return config.minField + Int(x % span)
    }

    /// Ist die Person zur UTC-Zeit `t` an diesem Ortstag verfügbar? (Zuverlässigkeit als Münzwurf je Tag)
    public static func isAvailable(_ r: VirtualRacer, at t: TimeInterval) -> Bool {
        let day = r.localDay(at: t)
        return DetMath.unit(DetMath.fnv64("avail|\(r.id)|\(day)")) < r.reliability
    }

    /// Gewicht der Ortszeit: 0 ausserhalb 06–22 Uhr, `edgeWeight` in den Randstunden, sonst 1 (+ Gewohnheit)
    public static func timeWeight(_ r: VirtualRacer, at t: TimeInterval, config: Config = Config()) -> Double {
        let h = r.localHour(at: t)
        guard config.allowedHours.contains(h), h < config.allowedHours.upperBound else { return 0 }
        var w = config.preferredHours.contains(h) ? 1.0 : config.edgeWeight
        if abs(h - Double(r.preferredHour) - 0.5) <= 2 { w *= 1 + config.habitBonus }
        return w
    }

    /// Füllt das Feld eines Rennens.
    /// - Parameters:
    ///   - real: angemeldete echte Teilnehmende (Bahnen bleiben, Reihenfolge wie übergeben)
    ///   - realLevels: 2k-Zeiten (s) der echten, soweit bekannt (für das Niveau)
    ///   - startsAt: Start (UTC)
    public static func fill(tournamentId: String, raceId: String, seed: UInt64, real: [RaceParticipant],
                            realLevels: [Double] = [], pool: VirtualRowerPool, startsAt: TimeInterval,
                            history: VirtualRowerHistory = VirtualRowerHistory(), config: Config = Config(),
                            catalog: AppearanceCatalog = .current) -> TournamentField {
        let minimum = minimumField(tournamentId: tournamentId, seed: seed, config: config)
        let need = max(minimum - real.count, 0)
        let chosen = need > 0 ? select(count: need, raceKey: "\(tournamentId)|\(raceId)", seed: seed,
                                       realLevels: realLevels, pool: pool, startsAt: startsAt,
                                       history: history, excluding: Set(real.map(\.id)), config: config) : []
        var lane = (real.map(\.lane).max() ?? 0) + 1
        var list = real
        for r in chosen {
            list.append(r.participant(lane: lane, catalog: catalog))
            lane += 1
        }
        return TournamentField(minimumField: minimum, participants: list, virtualRowers: chosen, realCount: real.count)
    }

    /// Wählt `count` Personen gewichtet ohne Zurücklegen (Schlüssel −ln(u)/w, die kleinsten gewinnen). Reichen die
    /// Kandidaten nicht, wird schrittweise gelockert: erst ohne Verfügbarkeit, dann ohne Niveau-Klasse und
    /// Wochengrenze, zuletzt ohne Zeitfenster. Nie zweimal am selben Ortstag.
    public static func select(count: Int, raceKey: String, seed: UInt64, realLevels: [Double], pool: VirtualRowerPool,
                              startsAt t: TimeInterval, history: VirtualRowerHistory, excluding: Set<String> = [],
                              config: Config = Config()) -> [VirtualRacer] {
        guard count > 0 else { return [] }
        let center: Double
        var width = config.levelWidth
        if realLevels.isEmpty {
            center = config.defaultLevel ?? median(pool.rowers.map(\.best2k))
        } else {
            center = median(realLevels)
            if realLevels.count >= 2 {
                var m = 0.0
                for x in realLevels { m += x }
                m /= Double(realLevels.count)
                var v = 0.0
                for x in realLevels { v += (x - m) * (x - m) }
                width = max(width, 1.2 * (v / Double(realLevels.count - 1)).squareRoot())
            }
        }
        var picked: [VirtualRacer] = []
        var taken = excluding
        for relax in 0..<4 {
            var keyed: [(key: Double, r: VirtualRacer)] = []
            for r in pool.rowers where !taken.contains(r.id) {
                if let last = history.lastRaced[r.id], r.localDay(at: last) == r.localDay(at: t) { continue }
                var w = relax >= 3 ? max(timeWeight(r, at: t, config: config), 0.05) : timeWeight(r, at: t, config: config)
                guard w > 0 else { continue }
                if relax < 1, !isAvailable(r, at: t) { continue }
                if relax < 2, let cls = config.levelClass, !cls.contains(r.best2k) { continue }
                if relax < 2, history.racesInWeek(r.id, before: t) >= config.maxPerWeek { continue }
                let z = (r.best2k - center) / width
                w *= DetMath.exp(-0.5 * z * z) + 0.002
                w *= 0.5 + 0.5 * r.reliability
                if let last = history.lastRaced[r.id] {
                    let days = max(t - last, 0) / 86400
                    let x = min(days / config.recencyDays, 1)
                    w *= config.recencyFloor + (1 - config.recencyFloor) * x * x
                }
                let u = DetMath.unit(DetMath.fnv64("pick|\(raceKey)|\(r.id)") ^ seed)
                keyed.append((-DetMath.ln(max(u, 1e-300)) / w, r))
            }
            keyed.sort { $0.key != $1.key ? $0.key < $1.key : $0.r.number < $1.r.number }
            for k in keyed.prefix(count - picked.count) {
                picked.append(k.r)
                taken.insert(k.r.id)
            }
            if picked.count >= count { break }
        }
        return picked
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 480 }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
