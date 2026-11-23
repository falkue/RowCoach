import Foundation

/// Fahrlinie eines Schiffs als Polylinie mit Bogenlänge.
public struct VesselPath: Sendable {
    public let spec: VesselLaneSpec
    public let length: Double
    private let xs: [Double], zs: [Double], cum: [Double]

    public init?(spec: VesselLaneSpec) {
        let p = spec.pointsXZ.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil }
        guard p.count >= 2 else { return nil }
        var c: [Double] = [0]
        for i in 1..<p.count { c.append(c[i - 1] + hypot(p[i].0 - p[i - 1].0, p[i].1 - p[i - 1].1)) }
        guard let total = c.last, total > 1 else { return nil }
        self.spec = spec
        xs = p.map(\.0)
        zs = p.map(\.1)
        cum = c
        length = total
    }

    /// Punkt und Fahrtrichtung bei s Metern ab Linienanfang; `forward` = in Richtung der Punkte
    public func pose(at sIn: Double, forward: Bool) -> (x: Double, z: Double, heading: Double) {
        let s = min(max(sIn, 0), length)
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] <= s { lo = mid } else { hi = mid }
        }
        let seg = cum[hi] - cum[lo]
        let u = seg > 0 ? (s - cum[lo]) / seg : 0
        var dx = xs[hi] - xs[lo], dz = zs[hi] - zs[lo]
        if !forward { dx = -dx; dz = -dz }
        return (xs[lo] + (xs[hi] - xs[lo]) * u, zs[lo] + (zs[hi] - zs[lo]) * u, atan2(-dx, -dz))
    }
}

/// Eine Fahrt eines Schiffs auf einer Linie
public struct VesselTrip: Equatable, Sendable {
    public let id: Int
    public let kind: VesselKind
    /// Index in `VesselTraffic.paths`
    public let lane: Int
    public let forward: Bool
    /// Startzeit (s) und Tempo (m/s)
    public let start: Double
    public let speed: Double

    /// Meter ab Linienanfang zur Zeit t (bei `forward == false` vom Linienende her)
    public func along(at t: Double, length: Double) -> Double {
        let d = speed * (t - start)
        return forward ? d : length - d
    }
}

/// Anzeigezustand eines Schiffs
public struct VesselState: Equatable, Sendable {
    public var id: Int
    public var kind: VesselKind
    public var x: Double
    public var z: Double
    public var heading: Double
    public var speed: Double
    /// 0 … 1: an den Linienenden ein- und ausgeblendet (je 60 m)
    public var fade: Double
}

/// Plant die Schiffe einer Fahrt (Konzept Abschnitt 16).
///
/// - Je Schiffsart ein eigener Takt (`VesselKind.interval`, mal `density.vesselIntervalFactor` und geteilt durch den
///   Faktor `density` aus course.json): zusammen etwa ein Schiff alle 2–6 Minuten, grosse seltener; in Basel ein
///   Rheinschiff alle 8–15 Minuten.
/// - Nur auf den Linien aus dem Kartenpaket (`VesselLaneSpec`, alle im Wasser): kleine Schiffe ab 40 m Abstand zur
///   eigenen Bahn, grosse ab 80 m, Fähren nur auf Querlinien, Rheinschiffe nie quer, andere grosse Schiffe nur auf
///   Querlinien ab 600 m Länge.
/// - Je Linie höchstens ein Schiff gleichzeitig; eine neue Fahrt beginnt nur, wenn sie keinem anderen Schiff näher
///   als die halben Längen + 30 m kommt (z. B. Fähre und Rheinschiff).
/// - Querlinien kreuzen die Strecke: Ein Schiff fährt nur los, wenn es die Bahn (± Mindestabstand + halbe Länge)
///   gekreuzt hat, bevor das eigene Boot auf 300 m herankommt (mit 30 % Reserve auf das Tempo), und solange kein
///   virtueller Ruderer in die Kreuzung fährt. Sonst wird der Start um 20–40 s verschoben.
/// - Deterministisch aus dem Startwert und den Eingaben.
public struct VesselTraffic: Sendable {
    public let paths: [VesselPath]
    public let kinds: [VesselKind]
    public private(set) var trips: [VesselTrip] = []

    private let oneWay: Double
    private let intervalFactor: Double
    private var random: TrafficRandom
    private var next: [VesselKind: Double] = [:]
    private var nextId = 1

    /// Abstand zum eigenen Boot, ab dem eine Kreuzung erlaubt ist (m)
    public static let crossingClearance = 300.0

    public init(course: Course, density: TrafficDensity, seed: UInt64, kinds: [VesselKind]? = nil,
                lanes: [VesselLaneSpec]? = nil) {
        let traffic = course.traffic
        let k = kinds ?? traffic?.vessels.map { $0.compactMap(VesselKind.init(rawValue:)) } ?? TrafficDefaults.vessels(for: course)
        let specs = lanes ?? traffic?.vesselLanes ?? TrafficDefaults.vesselLanes(for: course)
        paths = specs.compactMap(VesselPath.init(spec:))
        self.kinds = k.filter { kind in specs.contains { kind.allows($0) } }
        oneWay = CourseTrack(course: course).oneWayLength
        let factor = max(traffic?.density ?? 1, 0)
        intervalFactor = factor > 0 ? density.vesselIntervalFactor / factor : .infinity
        random = TrafficRandom(seed: seed ^ 0x5EA5_5EA5)
    }

    /// Neue Fahrten anlegen, beendete entfernen. `rowers`: Lage der virtuellen Ruderer auf der eigenen Strecke.
    public mutating func update(time t: Double, own: OwnBoat, rowers: [(u: Double, speed: Double)] = []) {
        let paths = self.paths
        trips.removeAll { trip in
            let len = paths[trip.lane].length
            let a = trip.along(at: t, length: len)
            return a < -1 || a > len + 1
        }
        guard intervalFactor.isFinite else { return }
        for (i, kind) in kinds.enumerated() {
            if next[kind] == nil {
                // erstes Schiff: die erste Art bald, die anderen gestaffelt
                next[kind] = t + (i == 0 ? random.uniform(20...70) : random.uniform(0.3...0.8) * kind.interval.upperBound
                                  * intervalFactor)
            }
            guard let due = next[kind], t >= due else { continue }
            if let trip = makeTrip(kind: kind, at: t, own: own, rowers: rowers) {
                trips.append(trip)
                next[kind] = t + random.uniform(kind.interval) * intervalFactor
            } else {
                next[kind] = t + random.uniform(20...40)
            }
        }
    }

    public func states(at t: Double) -> [VesselState] {
        trips.map { trip in
            let path = paths[trip.lane]
            let a = trip.along(at: t, length: path.length)
            let p = path.pose(at: a, forward: trip.forward)
            let fade = min(1, max(0, min(a, path.length - a) / 60))
            return VesselState(id: trip.id, kind: trip.kind, x: p.x, z: p.z, heading: p.heading, speed: trip.speed,
                               fade: fade)
        }
    }

    // MARK: - Planung

    private mutating func makeTrip(kind: VesselKind, at t: Double, own: OwnBoat,
                                   rowers: [(u: Double, speed: Double)]) -> VesselTrip? {
        let busy = Set(trips.map(\.lane))
        // grosse Schiffe queren nur weite Wasserflächen (Querlinie ≥ 600 m), keine Flüsse
        let candidates = paths.indices.filter {
            !busy.contains($0) && kind.allows(paths[$0].spec)
                && !(kind.isLarge && paths[$0].spec.kind == .cross && paths[$0].length < 600)
        }
        guard !candidates.isEmpty else { return nil }
        let lane = candidates[random.int(candidates.count)]
        let forward = random.unit() < 0.5
        let speed = random.uniform(kind.speedRange)
        let trip = VesselTrip(id: nextId, kind: kind, lane: lane, forward: forward, start: t, speed: speed)
        let path = paths[lane]
        if path.spec.kind == .cross,
           !crossingIsClear(trip: trip, path: path, now: t, own: own, rowers: rowers) {
            return nil
        }
        guard keepsClearOfOtherVessels(trip) else { return nil }
        nextId += 1
        return trip
    }

    /// Begegnet die neue Fahrt keinem anderen Schiff (Abstand ≥ halbe Längen + 30 m, geprüft alle 5 s)?
    public func keepsClearOfOtherVessels(_ trip: VesselTrip) -> Bool {
        let path = paths[trip.lane]
        let duration = path.length / trip.speed
        var tau = 0.0
        while tau <= duration {
            let t = trip.start + tau
            let p = path.pose(at: trip.along(at: t, length: path.length), forward: trip.forward)
            for other in trips {
                let op = paths[other.lane]
                let a = other.along(at: t, length: op.length)
                guard a >= 0, a <= op.length else { continue }
                let q = op.pose(at: a, forward: other.forward)
                if hypot(p.x - q.x, p.z - q.z) < (trip.kind.length + other.kind.length) / 2 + 30 { return false }
            }
            tau += 5
        }
        return true
    }

    /// Kreuzt das Schiff die Strecke weit genug vor dem eigenen Boot und den Ruderern?
    public func crossingIsClear(trip: VesselTrip, path: VesselPath, now: Double, own: OwnBoat,
                                rowers: [(u: Double, speed: Double)]) -> Bool {
        guard let crossings = path.spec.cross, !crossings.isEmpty else { return true }
        let L2 = 2 * oneWay
        let clear = trip.kind.minDistance + trip.kind.length / 2 + 12
        for c in crossings {
            // Zeitfenster, in dem das Schiff im Bereich der Strecke ist
            let a0 = c.at - clear, a1 = c.at + clear
            let tIn: Double, tOut: Double
            if trip.forward {
                tIn = trip.start + a0 / trip.speed
                tOut = trip.start + a1 / trip.speed
            } else {
                tIn = trip.start + (path.length - a1) / trip.speed
                tOut = trip.start + (path.length - a0) / trip.speed
            }
            let tauIn = max(tIn - now, 0), tauOut = max(tOut - now, 0)
            // eigenes Boot: wo es im Zeitfenster sein kann (70 % … 125 % des Tempos, + 0,3 m/s Reserve)
            let v = max(own.speed, 0.5)
            let lo = 0.7 * v * tauIn, hi = (1.25 * v + 0.3) * tauOut
            for u in [c.s, L2 - c.s] {
                let ahead = RowerLane.mod(u - own.u, L2)
                for r in [ahead, ahead - L2] {
                    // vor dem Bereich: mindestens 300 m Luft (auch wenn das Boot anhält)
                    if r > hi {
                        if r - hi < Self.crossingClearance { return false }
                    } else if r < lo {
                        // hinter dem Bereich (schon vorbei): 120 m; liegt die Kreuzung noch vor dem jetzigen Ort,
                        // muss sie auch für ein anhaltendes Boot 300 m entfernt sein
                        if lo - r < 120 { return false }
                        if r > 0 && r < Self.crossingClearance { return false }
                    } else {
                        return false
                    }
                }
                // virtuelle Ruderer (rudern ohne Pause, 85 … 115 % ihres Tempos): 100 m Abstand
                for rower in rowers {
                    let ra = RowerLane.mod(u - rower.u, L2)
                    let rlo = 0.85 * rower.speed * tauIn, rhi = 1.15 * rower.speed * tauOut
                    for r in [ra, ra - L2] where r > rlo - 100 && r < rhi + 100 {
                        return false
                    }
                }
            }
        }
        return true
    }
}
