import Foundation

// Leben auf dem Wasser (Konzept Abschnitt 16): Datenformat und Grundbausteine für virtuelle Ruderer und Schiffe.
// Die Bahnen kommen aus dem Kartenpaket (course.json, Feld `traffic`, erzeugt von tools/coursebuilder/lanes.py);
// fehlt das Feld, gelten Voreinstellungen je Gebiet (`TrafficDefaults`).

/// Optionales Feld `traffic` in course.json.
public struct CourseTraffic: Codable, Equatable, Sendable {
    /// Schiffsarten des Gewässers (Rohwerte von `VesselKind`; unbekannte werden ignoriert)
    public var vessels: [String]?
    /// Faktor für die Häufigkeit der Schiffe (1 = normal, 0 = keine)
    public var density: Double?
    /// Bahnen der virtuellen Ruderer (seitlicher Versatz zur Hinfahrt)
    public var rowerLanes: [RowerLaneSpec]?
    /// Fahrlinien der Schiffe in Szenenkoordinaten
    public var vesselLanes: [VesselLaneSpec]?
    /// Ein- und Ausstiegsstellen der Ruderer (Bootshaus, Steg, Streckenende) mit Zufahrt zur Bahn
    public var rowerDocks: [RowerDockSpec]?
    /// Abstände zwischen zwei Fahrten je Schiffsart (s, Dichte normal; [von, bis]), statt `VesselKind.interval`
    /// (z. B. viele Segelboote auf der Außenalster)
    public var vesselIntervals: [String: [Double]]?

    enum CodingKeys: String, CodingKey {
        case vessels, density
        case rowerLanes = "rower_lanes", vesselLanes = "vessel_lanes", rowerDocks = "rower_docks"
        case vesselIntervals = "vessel_intervals"
    }

    public init(vessels: [String]? = nil, density: Double? = nil, rowerLanes: [RowerLaneSpec]? = nil,
                vesselLanes: [VesselLaneSpec]? = nil, rowerDocks: [RowerDockSpec]? = nil,
                vesselIntervals: [String: [Double]]? = nil) {
        self.vessels = vessels
        self.density = density
        self.rowerLanes = rowerLanes
        self.vesselLanes = vesselLanes
        self.rowerDocks = rowerDocks
        self.vesselIntervals = vesselIntervals
    }
}

/// Ein- und Ausstieg der Ruderer: Stelle am Ufer (Bootshaus, Steg, Streckenende) und zwei Zufahrten (Szenen-
/// koordinaten, vom Steg zur Bahn bzw. von der Bahn zum Steg; beide treffen die Bahn in Fahrtrichtung tangential).
public struct RowerDockSpec: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    /// Index in `rower_lanes`
    public var lane: Int
    /// Stelle auf der Bahn als Ruderdistanz der eigenen Strecke (0 … 2L): Ende der Einfahrt
    public var joinU: Double
    /// Beginn der Ausfahrt (Standard: `joinU`)
    public var exitU: Double?
    public var enterXZ: [[Double]]
    public var exitXZ: [[Double]]

    enum CodingKeys: String, CodingKey {
        case id, name, lane
        case joinU = "join_u", exitU = "exit_u", enterXZ = "enter_xz", exitXZ = "exit_xz"
    }

    public init(id: String, name: String? = nil, lane: Int, joinU: Double, exitU: Double? = nil, enterXZ: [[Double]],
                exitXZ: [[Double]]) {
        self.id = id
        self.name = name
        self.lane = lane
        self.joinU = joinU
        self.exitU = exitU
        self.enterXZ = enterXZ
        self.exitXZ = exitXZ
    }
}

/// Bahn eines virtuellen Ruderers: Hinfahrt mit seitlichem Versatz `outM`, Rückfahrt mit `backM` (Meter, positiv =
/// Seite der eigenen Rückfahrt, also links der Hinfahrt; `backM > outM`). An Wende und Start verbindet je ein
/// Halbkreis beide Linien (siehe `RowerLane`). Mit `turnOutM`/`turnBackM` liegt die Bahn auf den Geraden näher an der
/// eigenen (z. B. 9 m) und weicht nur vor Wende und Start auf diese Werte aus (Halbkreis mit genug Abstand zur eigenen
/// Wende).
///
/// Offene Linie (`open`, auf Strecken ohne Wende immer): nur eine Linie mit Versatz `outM` (+ `outBumps`), ohne Wende;
/// `backM` wird ignoriert (lanes.py schreibt `backM = outM`, ältere App-Versionen verwerfen die Bahn daher). Die
/// Ruderer fahren über das Streckenende hinaus weiter. `reverse`: Fahrtrichtung vom Ziel zum Start (Gegenverkehr auf
/// one_way-Strecken und Rundkursen, auf schmalen Strecken mit Wende die Linie der Rückfahrt).
public struct RowerLaneSpec: Codable, Equatable, Sendable {
    public var outM: Double
    public var backM: Double
    public var turnOutM: Double?
    public var turnBackM: Double?
    /// Ausweichstellen der Hin- bzw. Rückfahrtlinie (z. B. an Brückenpfeilern), siehe `LaneBump`
    public var outBumps: [LaneBump]?
    public var backBumps: [LaneBump]?
    /// offene Linie ohne Wende (siehe oben)
    public var open: Bool?
    /// offene Linie in Gegenrichtung (vom Ziel zum Start)
    public var reverse: Bool?

    enum CodingKeys: String, CodingKey {
        case outM = "out_m", backM = "back_m", turnOutM = "turn_out_m", turnBackM = "turn_back_m"
        case outBumps = "out_bumps", backBumps = "back_bumps", open, reverse
    }

    public init(outM: Double, backM: Double, turnOutM: Double? = nil, turnBackM: Double? = nil,
                outBumps: [LaneBump]? = nil, backBumps: [LaneBump]? = nil, open: Bool? = nil, reverse: Bool? = nil) {
        self.outM = outM
        self.backM = backM
        self.turnOutM = turnOutM
        self.turnBackM = turnBackM
        self.outBumps = outBumps
        self.backBumps = backBumps
        self.open = open
        self.reverse = reverse
    }

    /// Offene Linie mit Versatz `lateral` (positiv = links der Fahrtrichtung der Hinfahrt)
    public static func line(_ lateral: Double, reverse: Bool = false, bumps: [LaneBump]? = nil) -> RowerLaneSpec {
        RowerLaneSpec(outM: lateral, backM: lateral, outBumps: bumps, open: true, reverse: reverse ? true : nil)
    }
}

/// Weiche seitliche Verschiebung einer Ruderer-Bahn um `d` Meter (positiv = links der Hinfahrt) bei s = `s` (m ab Start
/// der Hinfahrt), mit Kosinusfenster der halben Breite `w`: d · ½ · (1 + cos(π · (s − s₀) / w)) für |s − s₀| < w.
public struct LaneBump: Codable, Equatable, Sendable {
    public var s: Double
    public var d: Double
    public var w: Double

    public init(s: Double, d: Double, w: Double) {
        self.s = s
        self.d = d
        self.w = w
    }

    public func offset(at x: Double) -> Double {
        guard w > 0, abs(x - s) < w else { return 0 }
        return d * 0.5 * (1 + cos(Double.pi * (x - s) / w))
    }
}

/// Fahrlinie für Schiffe (Polylinie in Szenenkoordinaten, Wasser mit Abstand zum Ufer).
public struct VesselLaneSpec: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// seitlich parallel zur Strecke
        case parallel
        /// weit draussen („am Horizont“, ≥ 300 m)
        case far
        /// quer über das Gewässer; kreuzt die Strecke
        case cross
        /// Segelrevier: Linien quer durch die Wasserfläche, ≥ 60 m von der Strecke (nur Segel- und Tretboote)
        case sail
    }

    /// Stelle, an der eine Querlinie die Hinfahrt kreuzt: `s` = m ab Start der Hinfahrt, `at` = m ab Linienanfang
    public struct Crossing: Codable, Equatable, Sendable {
        public var s: Double
        public var at: Double
        public init(s: Double, at: Double) { self.s = s; self.at = at }
    }

    public var id: String
    public var kind: Kind
    /// kleinster Abstand zur eigenen Bahn (Hin-, Rückfahrt, Wenden), m; 0 bei Querlinien
    public var minDistM: Double
    /// kleinster Abstand zum Ufer, m
    public var shoreM: Double?
    public var pointsXZ: [[Double]]
    public var cross: [Crossing]?

    enum CodingKeys: String, CodingKey {
        case id, kind, cross
        case minDistM = "min_dist_m", shoreM = "shore_m", pointsXZ = "points_xz"
    }

    public init(id: String, kind: Kind, minDistM: Double, shoreM: Double? = nil, pointsXZ: [[Double]],
                cross: [Crossing]? = nil) {
        self.id = id
        self.kind = kind
        self.minDistM = minDistM
        self.shoreM = shoreM
        self.pointsXZ = pointsXZ
        self.cross = cross
    }
}

/// Dichte des Verkehrs (Einstellungen „wenig / normal“; `dense` nur für Screenshots über `-demoTraffic dense`).
public enum TrafficDensity: String, Codable, Sendable, CaseIterable {
    case low, normal, dense

    /// Ruderer, die die ganze Fahrt auf einer 4-km-Strecke unterwegs sind (bei anderen Längen anteilig, mind. 2)
    public var rowersPer4km: Int {
        switch self {
        case .low: return 4
        case .normal: return 6
        case .dense: return 9
        }
    }

    /// Abstand zwischen zwei Gästen, die an einem Steg einsteigen und nach ein paar Runden wieder aussteigen (s)
    public var guestInterval: ClosedRange<Double> {
        switch self {
        case .low: return 420...720
        case .normal: return 240...480
        case .dense: return 90...180
        }
    }

    /// Nachschub: so lange nach dem Davonziehen bzw. Ausscheiden eines „Hasen“ kommt der nächste von hinten (s).
    /// Hasen fahren auf der innersten Bahn ca. 20 m vor einem im eigenen Tempo mit (oder langsamer, dann zieht man an
    /// ihnen vorbei)
    public var hareInterval: ClosedRange<Double> {
        switch self {
        case .low: return 120...240
        case .normal: return 10...25
        case .dense: return 5...15
        }
    }

    /// so lange fährt ein Hase vor einem her (s)
    public var harePace: ClosedRange<Double> {
        switch self {
        case .low: return 60...150
        case .normal: return 90...240
        case .dense: return 120...300
        }
    }

    /// höchstens so viele Gäste gleichzeitig
    public var maxGuests: Int {
        switch self {
        case .low: return 1
        case .normal: return 1
        case .dense: return 2
        }
    }

    /// Faktor auf die Abstände zwischen zwei Schiffen
    public var vesselIntervalFactor: Double {
        switch self {
        case .low: return 1.6
        case .normal: return 1
        case .dense: return 0.3
        }
    }
}

/// Schiffsarten (Rohwert = Name in course.json).
public enum VesselKind: String, Codable, Sendable, CaseIterable {
    case motorboot, segelboot, kursschiff, raddampfer, rheinschiff, weidling, faehre, alsterdampfer, tretboot

    /// grosses Schiff (Kursschiff, Raddampfer, Rheinschiff)
    public var isLarge: Bool {
        switch self {
        case .kursschiff, .raddampfer, .rheinschiff, .alsterdampfer: return true
        default: return false
        }
    }

    /// Mindestabstand zur eigenen Bahn (m): kleine Boote 20, Kursschiff und Raddampfer 40, Rheinschiff 50
    public var minDistance: Double {
        switch self {
        case .rheinschiff: return 50
        case .kursschiff, .raddampfer, .alsterdampfer: return 40
        default: return 20
        }
    }

    /// Bevorzugter grösster Abstand (m): kleine Boote passieren in 20–55 m, grosse in 40–90 m (Linien weiter draussen
    /// werden seltener gewählt)
    public var preferredMaxDistance: Double { isLarge ? 90 : 55 }

    /// Länge über alles (m), für Kielwasser und Abstände
    public var length: Double {
        switch self {
        case .motorboot: return 7
        case .segelboot: return 8
        case .kursschiff: return 48
        case .raddampfer: return 62
        case .rheinschiff: return 105
        case .weidling: return 10
        case .faehre: return 11
        case .alsterdampfer: return 25
        case .tretboot: return 4
        }
    }

    /// Geschwindigkeit (m/s)
    public var speedRange: ClosedRange<Double> {
        switch self {
        case .motorboot: return 5...8
        case .segelboot: return 2...3.5
        case .kursschiff: return 5...6
        case .raddampfer: return 4.5...5.5
        case .rheinschiff: return 3...4.5
        case .weidling: return 1.5...2.5
        case .faehre: return 1.0...1.4
        case .alsterdampfer: return 4...5
        case .tretboot: return 1.0...1.5
        }
    }

    /// Abstand zwischen zwei Fahrten dieser Art (s, Dichte normal)
    public var interval: ClosedRange<Double> {
        switch self {
        case .motorboot: return 240...540
        case .segelboot: return 300...600
        case .kursschiff: return 600...1080
        case .raddampfer: return 840...1320
        case .rheinschiff: return 480...900
        case .weidling: return 360...720
        case .faehre: return 300...540
        case .alsterdampfer: return 600...900
        case .tretboot: return 300...600
        }
    }

    /// Welche Linien diese Art befahren darf
    public func allows(_ lane: VesselLaneSpec) -> Bool {
        switch self {
        case .faehre:
            return lane.kind == .cross
        case .rheinschiff:
            return lane.kind != .cross && lane.minDistM >= minDistance
        case .weidling:
            return lane.kind == .parallel && lane.minDistM >= minDistance
        case .segelboot:
            return lane.kind == .sail || lane.kind == .cross || lane.minDistM >= minDistance
        case .tretboot:
            return lane.kind == .sail || (lane.kind == .parallel && lane.minDistM >= minDistance)
        default:
            return lane.kind == .cross || (lane.kind != .sail && lane.minDistM >= minDistance)
        }
    }
}

/// Voreinstellungen, wenn course.json kein Feld `traffic` hat (Gebiet aus der Kennung der Strecke).
public enum TrafficDefaults {
    public static func vessels(for course: Course) -> [VesselKind] {
        let id = course.id
        if id.hasPrefix("zuerichsee") { return [.kursschiff, .motorboot, .segelboot] }
        if id.hasPrefix("luzern") { return [.raddampfer, .motorboot, .segelboot] }
        if id.hasPrefix("rhein-basel") || id.hasPrefix("basel") { return [.rheinschiff, .faehre, .motorboot] }
        if id.hasPrefix("rhein-stein") || id.hasPrefix("stein") { return [.kursschiff, .weidling, .motorboot] }
        // Berlin und Potsdam: Ausflugsschiffe als Kursschiff, Trainerboote als Motorboot
        if id.hasPrefix("berlin-spree") { return [.kursschiff, .motorboot] }
        if id.hasPrefix("berlin-wannsee") || id.hasPrefix("potsdam") { return [.kursschiff, .segelboot, .motorboot] }
        if id.hasPrefix("berlin-gruenau") { return [.motorboot, .segelboot] }
        // Hamburg Außenalster: Alsterdampfer, viele Segeljollen, Trainer- und Polizeiboote, Tretboote
        if id.hasPrefix("hamburg") { return [.alsterdampfer, .segelboot, .motorboot, .tretboot] }
        return [.motorboot, .segelboot]
    }

    /// Ruderer-Bahnen ohne Angabe: rund um die eigene Bahn, auf den Geraden 9/18/27 m rechts der Hinfahrt und
    /// 10/19/28 m jenseits der Rückfahrt, an Wende und Start auf Halbkreise ausserhalb der eigenen Wende ausweichend
    public static let rowerLanes: [RowerLaneSpec] = [
        RowerLaneSpec(outM: -9, backM: 22, turnOutM: -16, turnBackM: 28),
        RowerLaneSpec(outM: -18, backM: 31, turnOutM: -24, turnBackM: 36),
        RowerLaneSpec(outM: -27, backM: 40, turnOutM: -32, turnBackM: 44),
    ]

    /// Strecken ohne Wende (one_way, Rundkurs) ohne Angabe: Hasen 9 m rechts, Gegenverkehr 20 m links
    public static let openRowerLanes: [RowerLaneSpec] = [.line(-9), .line(20, reverse: true)]

    /// Schiffslinien ohne Angabe: Parallelen zur Hinfahrt auf der Seite der Rückfahrt (nur für Strecken ohne
    /// Kartenpaket sinnvoll, z. B. die gerade Teststrecke auf offenem Wasser).
    public static func vesselLanes(for course: Course) -> [VesselLaneSpec] {
        let line = Centerline(course: course)
        guard line.length > 0 else { return [] }
        func lane(_ id: String, _ kind: VesselLaneSpec.Kind, offset: Double, extend: Double) -> VesselLaneSpec {
            var pts: [[Double]] = []
            let step = 25.0
            var s = -extend
            while s <= line.length + extend + 1e-9 {
                let p = line.point(at: s, lateral: offset)
                pts.append([p.x, p.z])
                s += step
            }
            return VesselLaneSpec(id: id, kind: kind, minDistM: abs(offset) - 12, pointsXZ: pts)
        }
        // ausserhalb der äussersten Standard-Ruderer-Bahn (44 m) mit 20 bzw. 56 m Luft; die eigene Wende reicht bis
        // 19 m auf diese Seite, `minDistM` ist hier der Abstand zur Rückfahrt
        return [lane("p52", .parallel, offset: 64, extend: 400),
                lane("p88", .parallel, offset: 100, extend: 400),
                lane("f450", .far, offset: 462, extend: 800)]
    }
}

/// Mittellinie der Hinfahrt mit seitlichem Versatz (wie `CourseTrack`, aber über die Enden hinaus gerade
/// verlängert). Versatz positiv = links der Hinfahrt (Seite der Rückfahrt).
public struct Centerline: Sendable {
    public struct Sample: Sendable { public var x, z, tx, tz: Double }

    private let xs: [Double], zs: [Double], cum: [Double]
    private let tangents: [(Double, Double)]
    private let geo: Double
    /// Ruderdistanz einer Richtung (`course.oneWayM` bzw. Linienlänge)
    public let length: Double

    public init(course: Course) {
        let p = course.pathXZ.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil }
        xs = p.map(\.0)
        zs = p.map(\.1)
        var c: [Double] = [0]
        if p.count >= 2 {
            for i in 1..<p.count { c.append(c[i - 1] + hypot(p[i].0 - p[i - 1].0, p[i].1 - p[i - 1].1)) }
        }
        cum = c
        geo = c.last ?? 0
        length = course.oneWayM > 0 ? course.oneWayM : geo
        var seg: [(Double, Double)] = []
        if p.count >= 2 {
            for i in 1..<p.count {
                let dx = p[i].0 - p[i - 1].0, dz = p[i].1 - p[i - 1].1
                let l = hypot(dx, dz)
                seg.append(l > 1e-9 ? (dx / l, dz / l) : (seg.last ?? (0, -1)))
            }
        }
        var t: [(Double, Double)] = []
        for i in 0..<p.count {
            guard !seg.isEmpty else { t.append((0, -1)); continue }
            let a = seg[max(i - 1, 0)], b = seg[min(i, seg.count - 1)]
            let sx = a.0 + b.0, sz = a.1 + b.1
            let l = hypot(sx, sz)
            t.append(l > 1e-9 ? (sx / l, sz / l) : b)
        }
        tangents = t
    }

    /// Punkt und Tangente bei Ruderdistanz s (ausserhalb 0…length gerade verlängert)
    public func sample(at s: Double) -> Sample {
        guard xs.count >= 2, geo > 0, length > 0 else {
            return Sample(x: xs.first ?? 0, z: zs.first ?? 0, tx: 0, tz: -1)
        }
        if s < 0 || s > length {
            let end = sample(at: min(max(s, 0), length))
            let e = s < 0 ? s : s - length
            return Sample(x: end.x + end.tx * e, z: end.z + end.tz * e, tx: end.tx, tz: end.tz)
        }
        let g = s * geo / length
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] <= g { lo = mid } else { hi = mid }
        }
        let segLen = cum[hi] - cum[lo]
        let u = segLen > 0 ? (g - cum[lo]) / segLen : 0
        let ta = tangents[lo], tb = tangents[hi]
        var tx = ta.0 + (tb.0 - ta.0) * u, tz = ta.1 + (tb.1 - ta.1) * u
        let l = hypot(tx, tz)
        if l > 1e-9 { tx /= l; tz /= l } else { tx = tb.0; tz = tb.1 }
        return Sample(x: xs[lo] + (xs[hi] - xs[lo]) * u, z: zs[lo] + (zs[hi] - zs[lo]) * u, tx: tx, tz: tz)
    }

    /// Punkt mit seitlichem Versatz (positiv = links der Hinfahrt, wie `CourseTrack.returnOffset`)
    public func point(at s: Double, lateral: Double) -> (x: Double, z: Double) {
        let p = sample(at: s)
        return (p.x + p.tz * lateral, p.z - p.tx * lateral)
    }
}

/// Kleiner, deterministischer Zufallsgenerator (SplitMix64): gleicher Startwert → gleiche Folge.
public struct TrafficRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// gleichverteilt in [0, 1)
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    public mutating func uniform(_ r: ClosedRange<Double>) -> Double { r.lowerBound + (r.upperBound - r.lowerBound) * unit() }

    public mutating func int(_ n: Int) -> Int { n > 0 ? Int(next() % UInt64(n)) : 0 }
}
