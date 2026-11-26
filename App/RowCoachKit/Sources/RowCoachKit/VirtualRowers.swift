import Foundation

/// Geschlossene Bahn eines virtuellen Ruderers rund um die eigene Strecke.
///
/// - Hinfahrt: Mittellinie mit seitlichem Versatz `outM`, Rückfahrt mit `backM` (positiv = links der Hinfahrt,
///   `backM > outM`), beide wie die eigene Rückfahrt über die Mittellinie gelegt.
/// - Wende und Start: je ein Halbkreis mit Radius ρ = (backM − outM) / 2 um die Mitte (outM + backM) / 2. An der
///   Wende liegt er an derselben Stelle wie der grosse Bogen der eigenen „Birnenkehre“ (`CourseTrack`), am Start ganz
///   hinter der Startlinie (`startBehind`), weil die eigene Fahrt dort ohne Runden geradeaus beginnt und endet, mit
///   Runden die Startkehre fährt (`LapTrack`). So kreuzen sich konzentrische Bahnen (gleiche Mitte, Radien im Abstand
///   ≥ 8 m) nie und bleiben ≥ 8 m von der eigenen Bahn (tools/coursebuilder/lanes.py prüft Ufer, Pfeiler, Abstände).
/// - Parameter `w` = Meter entlang der Bahn (0 … `loopLength`, zyklisch), 0 = Scheitel des Starthalbkreises.
///   `u` = zugehörige Ruderdistanz der eigenen Strecke (0 … 2L, zyklisch); auf den Geraden gilt w ↔ u 1 : 1,
///   in den Halbkreisen wird linear umgerechnet.
/// - Alle Ruderer fahren die Bahn in derselben Richtung wie das eigene Boot. Gegenverkehr entsteht dadurch, dass ein
///   Ruderer auf der anderen Seite der Strecke unterwegs ist (er kommt auf der Rückfahrt entgegen).
///
/// Offene Linien (`Form.open`: Strecken ohne Wende sowie `spec.open` auf schmalen Strecken mit Wende) und Ringe
/// (`Form.ring`: Rundkurse) haben keine Wende: eine Linie mit Versatz `outM` (+ Ausweichstellen), vorwärts (wie die
/// Hinfahrt) oder `reverse` (vom Ziel zum Start).
/// - offen: w = 0 … `loopLength` = L + 2·`openExtension`, die Linie reicht gerade verlängert `openExtension` m über
///   Start und Ziel hinaus; am Ende springt w zurück an den Anfang, beide Punkte liegen ≥ 500 m von jeder Stelle der
///   Strecke (ausser Sichtweite). So fahren Ruderer über das Streckenende hinaus und kommen später von weit hinten wieder.
/// - Ring: w = 0 … L zyklisch (s = w bzw. L − w), die Runden schliessen nahtlos an.
/// - `u` (für Hasen und Schiffe) wie auf einer Strecke mit Wende: vorwärts u = s, `reverse` u = 2L − s (wie eine
///   Rückfahrt).
public struct RowerLane: Sendable {
    public enum Form: Sendable, Equatable {
        /// geschlossene Bahn rund um die eigene (Hinfahrt, Wende, Rückfahrt, Startkehre)
        case closed
        /// offene Linie ohne Wende (über Start und Ziel hinaus verlängert)
        case open
        /// geschlossener Ring eines Rundkurses
        case ring
    }

    public let spec: RowerLaneSpec
    public let oneWay: Double
    /// Länge der Bahn (m)
    public let loopLength: Double
    public let form: Form
    /// offene Linie bzw. Ring in Gegenrichtung (vom Ziel zum Start)
    public let reverse: Bool

    private let line: Centerline
    private let half: Double          // halbe Wendelänge der eigenen Bahn (Ruderdistanz)
    private let ac: Double            // Abstand Wendebeginn → Mitte des grossen Bogens
    private let rho: Double
    private let lc: Double
    private let straight: Double      // Länge einer Geraden (L − 2·half)
    private let loop: Double          // Wendeschlaufe samt Zu- und Abfahrt (2·ac + π·ρ)
    private let startApproach: Double // Zufahrt zum Starthalbkreis ab s = half (half + startBehind)
    private let startLoop: Double     // Startschlaufe samt Zu- und Abfahrt (2·startApproach + π·ρ)
    private let turnOut: Double       // Versatz an Wende und Start (Halbkreise)
    private let turnBack: Double
    private let ramp: Double          // Übergang Gerade ↔ Wendeversatz (m)

    /// Der Starthalbkreis liegt ganz hinter der Startlinie (Mitte so viele Meter vor s = 0): Ohne Runden beginnt und
    /// endet die eigene Fahrt geradeaus bei s = 0 (Hin- bzw. Rückfahrtlinie), mit Runden fährt sie dort die
    /// Startkehre (s ≈ 9 … 40 m). Beides bleibt so ≥ 8 m vom Halbkreis entfernt.
    public static let startBehind = 10.0
    /// Verlängerung offener Linien über Start und Ziel hinaus (m, mehr als `VirtualRowers.visibleRange`)
    public static let openExtension = 500.0

    /// nil, wenn die Strecke zu kurz ist (geschlossene Bahn: auch ohne Wende oder mit backM ≤ outM).
    public init?(spec: RowerLaneSpec, track: CourseTrack) {
        if track.course.turns == 0 || spec.open == true {
            self.init(line: spec, track: track)
        } else {
            self.init(closed: spec, track: track)
        }
    }

    private init?(closed spec: RowerLaneSpec, track: CourseTrack) {
        let tOut = spec.turnOutM ?? spec.outM, tBack = spec.turnBackM ?? spec.backM
        guard track.course.turns > 0, spec.backM > spec.outM, tBack > tOut else { return nil }
        let L = track.oneWayLength
        let D = abs(track.returnOffset)
        let R = track.turnRadius
        guard R > 0, L > 0 else { return nil }
        let al = acos(min(1, max(-1, (D / (2 * R) + 1) / 2)))
        let h = min(R * (Double.pi + 4 * al) / 2, L)
        guard L > 2 * h else { return nil }
        self.spec = spec
        oneWay = L
        line = Centerline(course: track.course)
        half = h
        ac = 2 * R * sin(al)
        turnOut = tOut
        turnBack = tBack
        rho = (tBack - tOut) / 2
        lc = (tBack + tOut) / 2
        straight = L - 2 * h
        ramp = min(80, straight / 2)
        loop = 2 * ac + Double.pi * rho
        startApproach = h + Self.startBehind
        startLoop = 2 * startApproach + Double.pi * rho
        loopLength = 2 * straight + loop + startLoop
        form = .closed
        reverse = false
    }

    /// Offene Linie bzw. Ring (siehe oben); `half` = halbe Wendelänge der eigenen Bahn (nur Strecken mit Wende, für
    /// `VirtualRowers.turnAhead`), sonst 0.
    private init?(line spec: RowerLaneSpec, track: CourseTrack) {
        let L = track.oneWayLength
        guard L > 0, track.course.pathXZ.count >= 2 else { return nil }
        var h = 0.0
        if track.course.turns > 0 {
            let D = abs(track.returnOffset), R = track.turnRadius
            guard R > 0 else { return nil }
            let al = acos(min(1, max(-1, (D / (2 * R) + 1) / 2)))
            h = min(R * (Double.pi + 4 * al) / 2, L)
            guard L > 2 * h else { return nil }
        }
        self.spec = spec
        oneWay = L
        line = Centerline(course: track.course)
        form = track.course.turns == 0 && track.course.isLoop ? .ring : .open
        reverse = spec.reverse ?? false
        half = h
        ac = 0
        rho = 0
        lc = spec.outM
        straight = L
        ramp = 0
        loop = 0
        startApproach = 0
        startLoop = 0
        turnOut = spec.outM
        turnBack = spec.outM
        loopLength = form == .ring ? L : L + 2 * Self.openExtension
    }

    /// halbe Wendelänge der eigenen Bahn (Ruderdistanz): Wende = [L − half, L + half], Startkehre = [2L − half, half]
    public var turnHalfLength: Double { half }

    /// Ruderdistanz der eigenen Strecke (zyklisch, 0 … 2L) → Bahnparameter w
    public func w(fromU uIn: Double) -> Double {
        switch form {
        case .closed: break
        case .open: return reverse ? uIn - oneWay + Self.openExtension : uIn + Self.openExtension
        case .ring: return Self.mod(reverse ? uIn - oneWay : uIn, oneWay)
        }
        let L = oneWay, h = half
        let u = Self.mod(uIn, 2 * L)
        let a = startLoop / 2, b = a + straight, c = b + loop, d = c + straight
        if u < h { return a * (u / h) }
        if u < L - h { return a + (u - h) }
        if u < L + h { return b + loop * (u - (L - h)) / (2 * h) }
        if u < 2 * L - h { return c + (u - (L + h)) }
        return d + startLoop / 2 * (u - (2 * L - h)) / h
    }

    /// Bahnparameter auf der Hinfahrt bei s, auch im letzten Stück der Startschlaufe (s ≥ half − startApproach), wo die
    /// Bahn schon geradeaus auf dem Wendeversatz liegt (für die Startverteilung: Ruderer wirklich vor dem Boot)
    public func w(forOutS s: Double) -> Double {
        if form != .closed { return w(atS: s) }
        return s >= half ? w(fromU: s) : startLoop / 2 + (s - half)
    }

    /// Offene Linie bzw. Ring: Bahnparameter an der Stelle s der Mittellinie (m ab Start der Hinfahrt, offen auch
    /// ausserhalb 0 … L), unabhängig von der Fahrtrichtung
    public func w(atS s: Double) -> Double {
        switch form {
        case .closed: return w(forOutS: s)
        case .open: return Self.mod(reverse ? oneWay + Self.openExtension - s : s + Self.openExtension, loopLength)
        case .ring: return Self.mod(reverse ? oneWay - s : s, oneWay)
        }
    }

    /// Offene Linie bzw. Ring: Stelle auf der Mittellinie bei w (offen −E … L + E, Ring 0 … L)
    public func s(atW wIn: Double) -> Double {
        let w = Self.mod(wIn, loopLength)
        switch form {
        case .closed: return u(fromW: w)
        case .open: return reverse ? oneWay + Self.openExtension - w : w - Self.openExtension
        case .ring: return reverse ? oneWay - w : w
        }
    }

    /// Abstand der Stelle u vor der Stelle `from` (entlang der Strecke, positiv = voraus): Strecken mit Wende und
    /// offene Linien zyklisch über 2L (−L … L), Ringe über L (−L/2 … L/2)
    public func along(_ u: Double, from ownU: Double) -> Double {
        if form == .ring { return Self.mod(u - ownU + oneWay / 2, oneWay) - oneWay / 2 }
        return Self.mod(u - ownU + oneWay, 2 * oneWay) - oneWay
    }

    /// Bahnparameter w → Ruderdistanz der eigenen Strecke (0 … 2L; offene Linien vorwärts −E … L + E, rückwärts
    /// L − E … 2L + E)
    public func u(fromW wIn: Double) -> Double {
        if form != .closed {
            let s = s(atW: wIn)
            return reverse ? 2 * oneWay - s : s
        }
        let L = oneWay, h = half
        let w = Self.mod(wIn, loopLength)
        let a = startLoop / 2, b = a + straight, c = b + loop, d = c + straight
        if w < a { return h * w / a }
        if w < b { return h + (w - a) }
        if w < c { return (L - h) + 2 * h * (w - b) / loop }
        if w < d { return (L + h) + (w - c) }
        return (2 * L - h) + h * (w - d) / (loopLength - d)
    }

    /// Position (Szenenkoordinaten) und Fahrtrichtung (wie `TrackPose.heading`) bei w
    public func pose(atW wIn: Double) -> (x: Double, z: Double, heading: Double) {
        if form != .closed { return linePose(s: s(atW: wIn)) }
        let L = oneWay, h = half
        let w = Self.mod(wIn, loopLength)
        let a = startLoop / 2, b = a + straight, c = b + loop, d = c + straight
        let r: (Double, Double, Double, Double)
        if w < a || w >= d {
            // Starthalbkreis (Rahmen am Ende der Rückfahrt bzw. Beginn der Hinfahrt, s = half)
            let g = w < a ? a + w : w - d
            r = startArc(g, frame: line.sample(at: h))
        } else if w < b {
            r = straightPose(s: h + (w - a), out: true)
        } else if w < c {
            r = turnLoop(w - b, frame: line.sample(at: L - h))
        } else {
            r = straightPose(s: (L - h) - (w - c), out: false)
        }
        return (r.0, r.1, atan2(-r.2, -r.3))
    }

    /// Seitlicher Versatz auf den Geraden: nah (`outM`/`backM`), vor Wende und Start weich (über `ramp` m) auf den
    /// Wendeversatz. So ist die Bahn bei s = half und s = L − half genau auf dem Versatz der Halbkreise.
    public func lateral(s: Double, out: Bool) -> Double {
        if form != .closed { return lineLateral(s: s) }
        let L = oneWay, h = half
        let d = min(s - h, (L - h) - s)
        let x = ramp > 0 ? min(max(d / ramp, 0), 1) : 1
        let weight = 1 - x * x * (3 - 2 * x)          // 1 an den Enden, 0 in der Mitte
        let bumps = (out ? spec.outBumps : spec.backBumps) ?? []
        let extra = bumps.reduce(0) { $0 + $1.offset(at: s) }
        return (out ? spec.outM + (turnOut - spec.outM) * weight : spec.backM + (turnBack - spec.backM) * weight) + extra
    }

    /// Offene Linie bzw. Ring: Versatz `outM` plus Ausweichstellen (auf Ringen auch über die Naht bei s = 0 hinweg)
    private func lineLateral(s: Double) -> Double {
        let bumps = spec.outBumps ?? []
        if form == .ring {
            return spec.outM + bumps.reduce(0) { $0 + $1.offset(at: s) + $1.offset(at: s - oneWay) + $1.offset(at: s + oneWay) }
        }
        return spec.outM + bumps.reduce(0) { $0 + $1.offset(at: s) }
    }

    /// Offene Linie bzw. Ring: Punkt bei s (Ring zyklisch, offen gerade verlängert), Richtung aus dem Verlauf
    private func linePose(s: Double) -> (x: Double, z: Double, heading: Double) {
        func at(_ v: Double) -> (x: Double, z: Double) {
            let q = form == .ring ? Self.mod(v, oneWay) : v
            return line.point(at: q, lateral: lineLateral(s: q))
        }
        let p = at(s), p0 = at(s - 0.5), p1 = at(s + 0.5)
        var dx = p1.x - p0.x, dz = p1.z - p0.z
        let l = hypot(dx, dz)
        if l > 1e-9 { dx /= l; dz /= l } else {
            let t = line.sample(at: form == .ring ? Self.mod(s, oneWay) : s)
            dx = t.tx; dz = t.tz
        }
        if reverse { dx = -dx; dz = -dz }
        return (p.x, p.z, atan2(-dx, -dz))
    }

    /// Punkt und Fahrtrichtung auf einer Geraden (Richtung aus dem Verlauf, auch im Übergang)
    private func straightPose(s: Double, out: Bool) -> (Double, Double, Double, Double) {
        let p = line.point(at: s, lateral: lateral(s: s, out: out))
        let p0 = line.point(at: s - 0.5, lateral: lateral(s: s - 0.5, out: out))
        let p1 = line.point(at: s + 0.5, lateral: lateral(s: s + 0.5, out: out))
        var dx = p1.x - p0.x, dz = p1.z - p0.z
        let l = hypot(dx, dz)
        if l > 1e-9 { dx /= l; dz /= l } else { let t = line.sample(at: s); dx = t.tx; dz = t.tz }
        return out ? (p.x, p.z, dx, dz) : (p.x, p.z, -dx, -dz)
    }

    /// Halbkreis an der Wende; g = 0 … loop ab Wendebeginn auf der Hinfahrtbahn
    private func turnLoop(_ g: Double, frame f: Centerline.Sample) -> (Double, Double, Double, Double) {
        let nx = f.tz, nz = -f.tx                     // links der Hinfahrt
        let al: Double, l: Double, dx: Double, dz: Double
        if g < ac {
            al = g; l = turnOut; dx = f.tx; dz = f.tz
        } else if g < ac + Double.pi * rho {
            let th = (g - ac) / rho
            al = ac + rho * sin(th); l = lc - rho * cos(th)
            dx = cos(th) * f.tx + sin(th) * nx; dz = cos(th) * f.tz + sin(th) * nz
        } else {
            al = ac - (g - ac - Double.pi * rho); l = turnBack; dx = -f.tx; dz = -f.tz
        }
        return (f.x + f.tx * al + nx * l, f.z + f.tz * al + nz * l, dx, dz)
    }

    /// Halbkreis am Start; g = 0 … startLoop ab Ende der Rückfahrtbahn (bei s = half), Mitte bei s = −startBehind
    private func startArc(_ g: Double, frame f: Centerline.Sample) -> (Double, Double, Double, Double) {
        let nx = f.tz, nz = -f.tx
        let A = startApproach
        let al: Double, l: Double, dx: Double, dz: Double
        if g < A {
            al = -g; l = turnBack; dx = -f.tx; dz = -f.tz
        } else if g < A + Double.pi * rho {
            let th = (g - A) / rho
            al = -A - rho * sin(th); l = lc + rho * cos(th)
            dx = -cos(th) * f.tx - sin(th) * nx; dz = -cos(th) * f.tz - sin(th) * nz
        } else {
            al = -A + (g - A - Double.pi * rho); l = turnOut; dx = f.tx; dz = f.tz
        }
        return (f.x + f.tx * al + nx * l, f.z + f.tz * al + nz * l, dx, dz)
    }

    static func mod(_ a: Double, _ m: Double) -> Double {
        guard m > 0, a.isFinite else { return 0 }
        let r = a.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }
}

/// Polylinie mit Bogenlänge (Zufahrten der Stege)
public struct TrafficPolyline: Sendable {
    public let length: Double
    private let xs: [Double], zs: [Double], cum: [Double]

    public init?(_ points: [[Double]]) {
        let p = points.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil }
        guard p.count >= 2 else { return nil }
        var c: [Double] = [0]
        for i in 1..<p.count { c.append(c[i - 1] + hypot(p[i].0 - p[i - 1].0, p[i].1 - p[i - 1].1)) }
        guard let total = c.last, total > 0.5 else { return nil }
        xs = p.map(\.0)
        zs = p.map(\.1)
        cum = c
        length = total
    }

    public func pose(at sIn: Double) -> (x: Double, z: Double, heading: Double) {
        let s = min(max(sIn, 0), length)
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] <= s { lo = mid } else { hi = mid }
        }
        let seg = cum[hi] - cum[lo]
        let u = seg > 0 ? (s - cum[lo]) / seg : 0
        let dx = xs[hi] - xs[lo], dz = zs[hi] - zs[lo]
        return (xs[lo] + dx * u, zs[lo] + dz * u, atan2(-dx, -dz))
    }

    public var start: (x: Double, z: Double) { (xs[0], zs[0]) }
}

/// Steg mit Ein- und Ausfahrt zu einer Bahn
public struct RowerDock: Sendable {
    public let spec: RowerDockSpec
    public let enter: TrafficPolyline
    public let exit: TrafficPolyline
}

/// Ein virtueller Ruderer. Tempo = Faktor seiner Bahn × eigenes Durchschnittstempo, mit leichter Schwankung
/// (± 1,5–3 %, Periode 40–90 s). Alle Ruderer einer Bahn haben denselben Faktor, ihr Abstand bleibt also gleich.
public struct VirtualRower: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// auf der Bahn; `w` = Bahnparameter
        case lane
        /// Einfahrt vom Steg; `w` = Meter auf der Zufahrt
        case entering(dock: Int)
        /// Ausfahrt zum Steg; `w` = Meter auf der Zufahrt
        case leaving(dock: Int)
    }

    public let id: Int
    public let lane: Int
    public let factor: Double
    public let wobble: Double
    public let wobblePeriod: Double
    public let wobblePhase: Double
    /// Farbe (Trikot, Blätter) als Index in die Palette der Szene
    public let colorIndex: Int
    /// Gast: steigt an einem Steg ein und nach `plannedMeters` wieder aus
    public let plannedMeters: Double?
    public internal(set) var phase: Phase
    public internal(set) var w: Double
    public internal(set) var rowed: Double = 0
    public internal(set) var strokePhase: Double
    /// „Hase“ auf der innersten Bahn (nil = normaler Ruderer)
    public internal(set) var hare: Hare? = nil

    /// Ablauf eines Hasen: von hinten aufholen (×1,35), 12–18 m voraus im eigenen Tempo mitfahren (×0,995–1,005),
    /// dann davonziehen (×1,35) und ab 470 m voraus (ausser Sicht) aus dem Spiel gehen
    public struct Hare: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case approach, pace, leave }
        public var phase: Phase
        /// Abstand voraus, ab dem er mitfährt (m)
        public var target: Double
        public var paceSeconds: Double
        public var paceFactor: Double
        /// aktueller Tempofaktor (weich nachgeführt, Zeitkonstante 6 s)
        public var current: Double
        public var paceUntil: Double?
        public var since: Double
        /// Nachfolger schon angefordert (beim Davonziehen bzw. Ausscheiden)
        public var handed: Bool = false

        /// langsamer Hase (×0,86–0,92): man holt ihn ein, er zieht seitlich vorbei und geht hinter der Kamera aus
        /// dem Spiel
        public var isSlow: Bool { paceFactor < 0.98 }
    }

    public var isGuest: Bool { plannedMeters != nil }

    /// Tempofaktor zur Zeit t (bezogen auf das eigene Durchschnittstempo)
    public func speedFactor(at t: Double) -> Double {
        if let h = hare { return h.current }
        return factor * (1 + wobble * sin(2 * Double.pi / wobblePeriod * t + wobblePhase))
    }

    /// Schlagzahl aus dem Tempo (18–32/min), je Ruderer leicht verschieden
    public func strokeRate(speed: Double) -> Int {
        min(max(Int((18 + (speed - 3) * 6).rounded()) + id % 3 - 1, 18), 32)
    }
}

/// Anzeigezustand eines virtuellen Ruderers
public struct RowerState: Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var z: Double
    public var heading: Double
    public var strokeRate: Int
    public var strokePhase: Double
    public var colorIndex: Int
    /// Abstand zum eigenen Boot (m)
    public var distance: Double
}

/// Lage des eigenen Boots
public struct OwnBoat: Equatable, Sendable {
    /// Ruderdistanz auf der Strecke (zyklisch 0 … 2L; bei Runden = Distanz in der Runde)
    public var u: Double
    public var x: Double
    public var z: Double
    public var heading: Double
    /// Durchschnittstempo (m/s)
    public var speed: Double

    public init(u: Double, x: Double, z: Double, heading: Double, speed: Double) {
        self.u = u
        self.x = x
        self.z = z
        self.heading = heading
        self.speed = speed
    }
}

/// Die virtuellen Ruderer einer Fahrt (Falk, 24.11.2026): Sie sind von Anfang an da und bleiben, statt aufzutauchen
/// und zu verschwinden, und sollen oft gross vor und neben einem zu sehen sein.
///
/// - Beim Start sind `density.rowersPer4km` Ruderer (wenig 4, normal 6, dense 9, je 4 km Strecke; mind. 2) unterwegs,
///   reihum auf den Bahnen ausser der innersten, der erste der zweiten 20–80 m voraus. Bei nur einer Bahn gibt es keine
///   Bahnruderer: die Bahn gehört den Hasen (andere Ruderer kommen dort nur als Gäste von den Stegen).
///   Alle rudern die Runde wie man selbst und bleiben die ganze Fahrt.
/// - Tempo je Bahn fest, nach Nähe zur eigenen Bahn: zweite ×1,08–1,16, dritte ×0,80–0,86 (weitere 0,96–1,04 /
///   1,16–1,24); je Ruderer ± 1,5–3 %. Auf derselben Bahn bleibt der Abstand gleich (keine Kollision).
/// - Die innerste Bahn (auf den Geraden ca. 9 m neben der eigenen) gehört den Hasen: gleich zu Beginn fährt einer
///   20–25 m voraus mit (immer ein Mitfahrer); danach kommt `density.hareInterval` nach dem Davonziehen bzw.
///   Ausscheiden des vorigen der nächste von hinter der Kamera (×1,35). Mitfahrer (×0,995–1,005) bleiben
///   `density.harePace` 17–22 m voraus (im Bild ca. 21–24 m vor dem Boot, Peilung von der Kamera ca. −17…−21°) und
///   ziehen dann davon (ab 470 m voraus und ausser Sicht aus dem Spiel); langsame (×0,86–0,92;
///   normal 25 %, dense 15 %) holt man ein, sie ziehen seitlich vorbei. Wer überholt ist und mehr als ca. 105° hinter
///   der Blickrichtung liegt, geht sofort aus dem Spiel (holt nie wieder auf).
///   Höchstens einer holt auf oder fährt mit. Mitfahrer ziehen 60 m vor Wende und Startkehre davon; neue Hasen nur
///   ab 300 m vor der Wende.
/// - Gäste: Gibt es Stege (`rower_docks`), steigt alle `density.guestInterval` Sekunden einer ein (höchstens
///   `density.maxGuests` zugleich): Ausfahrt vom Steg auf die Bahn, 1–3 Runden, dann bei der nächsten Gelegenheit
///   Ausfahrt zu einem Steg seiner Bahn. Die Zufahrt führt zur Bahn, die dem Ufer am nächsten liegt (lanes.py), kreuzt
///   also keine andere Ruderer-Bahn. Ein- und Ausfahrt nur, wenn das eigene Boot ≥ 250 m (entlang der Strecke, Hin-
///   und Rückfahrt) und Ruderer anderer Bahnen ≥ 80 m entfernt sind und auf der eigenen Bahn eine Lücke von ≥ 120 m
///   frei ist.
/// - Python-Nachbau (tools/traffic_sim, Zürich Utoquai mit den echten Bahnen, 4 m/s, 20 min, 4 Startwerte): Anteil der
///   Zeit mit einem Ruderer 8–30 m vor der Kamera bei ≤ 32° Peilung: wenig 45–57 %, normal 60–67 % (Startwert 2026,
///   0–10 min: 64 %), dense 62–68 %; auf der geraden Teststrecke (60 min) 49 / 55 / 62 %.
/// - Deterministisch: gleicher Startwert und gleiche Eingaben → gleiche Ruderer.
/// - Strecken ohne Wende und schmale Strecken (offene Linien, Ringe; siehe `RowerLane`): Die Hasen fahren auf der
///   nächsten Linie gleicher Richtung (auf schmalen Strecken mit Wende je Richtung eine eigene, `backHareLane`), die
///   Bahnruderer reihum auf den übrigen Linien (Gegenverkehr und weitere gleicher Richtung), `rowersPer4km` je 4 km
///   Linienlänge. one_way: Mitfahrer ziehen 60 m vor dem Ziel davon; beginnt eine neue Runde wieder am Start, wird die
///   Szene dort neu besetzt (wie beim Start der Fahrt). Rundkurs: keine Wende, die Lagen laufen zyklisch weiter.
///   Stege gibt es nur für geschlossene Bahnen.
public struct VirtualRowers: Sendable {
    public let lanes: [RowerLane]
    public let docks: [RowerDock]
    public let density: TrafficDensity
    /// Tempofaktor je Bahn
    public let laneFactors: [Double]
    /// innerste Bahn (am nächsten an der eigenen): leicht langsamer, dazu die Hasen (offene Linien: die nächste gleicher
    /// Richtung wie die Hinfahrt)
    public let innerLane: Int?
    /// Bahn der Hasen auf der Rückfahrt: geschlossene Bahnen wie `innerLane`, offene Linien die nächste in Gegenrichtung
    /// (nur Strecken mit Wende)
    public let backHareLane: Int?
    public private(set) var rowers: [VirtualRower] = []
    /// Zahl der Ruderer, die die ganze Fahrt bleiben (0 bei nur einer Bahn)
    public let residentCount: Int
    /// Versatz der eigenen Rückfahrt (m)
    private let returnOffset: Double
    /// one_way mit offenen Linien: jede Runde beginnt wieder am Start (die Szene springt), dann neu besetzen
    private let restartsAtStart: Bool
    private var lastOwnU: Double?

    private var random: TrafficRandom
    private var lastTime: Double?
    private var lastBase = 1.2
    private var nextGuest: Double?
    private var nextHare: Double?
    private var nextId = 1

    /// Sichtweite: weiter weg werden Ruderer in der Szene geparkt (im Navigator bleiben sie)
    public static let visibleRange = 450.0
    /// Abstände für Ein- und Ausfahrt (m entlang der Strecke)
    public static let dockClearOwn = 250.0
    public static let dockClearRowers = 80.0
    public static let dockLaneGap = 120.0

    public init(course: Course, density: TrafficDensity, seed: UInt64, lanes specs: [RowerLaneSpec]? = nil,
                docks dockSpecs: [RowerDockSpec]? = nil, track: CourseTrack? = nil) {
        let tr = track ?? CourseTrack(course: course)
        let s = specs ?? course.traffic?.rowerLanes
            ?? (course.turns == 0 ? TrafficDefaults.openRowerLanes : TrafficDefaults.rowerLanes)
        // Bahnen und Stege gemeinsam filtern (Stege verweisen über den Index auf die Bahn)
        var laneList: [RowerLane] = []
        var indexMap: [Int: Int] = [:]
        for (i, spec) in s.enumerated() {
            if let lane = RowerLane(spec: spec, track: tr) {
                indexMap[i] = laneList.count
                laneList.append(lane)
            }
        }
        lanes = laneList
        let ds = dockSpecs ?? (specs == nil ? course.traffic?.rowerDocks : nil) ?? []
        docks = ds.compactMap { d in
            guard let li = indexMap[d.lane], laneList[li].form == .closed, let e = TrafficPolyline(d.enterXZ),
                  let x = TrafficPolyline(d.exitXZ) else {
                return nil
            }
            var spec = d
            spec.lane = li
            return RowerDock(spec: spec, enter: e, exit: x)
        }
        self.density = density
        var rnd = TrafficRandom(seed: seed)
        // Bahnen nach Nähe zur eigenen Bahn (Hinfahrt 0, Rückfahrt 12 m) ordnen: die innerste leicht langsamer
        // (×0,90–0,96, man holt sie langsam ein), die nächste schneller, die übernächste deutlich langsamer
        let D = abs(tr.returnOffset)
        let hasTurn = course.turns > 0
        func closeness(_ lane: RowerLane) -> Double {
            switch lane.form {
            case .closed:
                return [lane.spec.outM, lane.spec.backM].map { min(abs($0), abs($0 - D)) }.min() ?? 0
            case .open, .ring:
                // vorwärts: Abstand zur Hinfahrt; Gegenrichtung: zur Rückfahrt (mit Wende) bzw. nie Hasen (ohne)
                if !lane.reverse { return abs(lane.spec.outM) }
                return hasTurn ? abs(lane.spec.outM - D) : 1000 + abs(lane.spec.outM)
            }
        }
        let order = laneList.indices.sorted { closeness(laneList[$0]) < closeness(laneList[$1]) }
        let bands: [ClosedRange<Double>] = [0.90...0.96, 1.08...1.16, 0.80...0.86, 0.96...1.04, 1.16...1.24]
        var f = [Double](repeating: 1, count: laneList.count)
        for (rank, li) in order.enumerated() { f[li] = rnd.uniform(bands[min(rank, bands.count - 1)]) }
        laneFactors = f
        let allClosed = laneList.allSatisfy { $0.form == .closed }
        if allClosed {
            innerLane = order.first
            backHareLane = order.first
        } else {
            innerLane = order.first { laneList[$0].form == .closed || !laneList[$0].reverse }
            backHareLane = hasTurn ? order.first { laneList[$0].form == .closed || laneList[$0].reverse } : nil
        }
        let oneWay = tr.oneWayLength
        if allClosed {
            // nur eine Bahn: sie gehört den Hasen, keine Bahnruderer (Falk 25.11.2026)
            residentCount = laneList.count <= 1 ? 0
                : min(max(Int((Double(density.rowersPer4km) * 2 * oneWay / 4000).rounded()), 2), 12)
        } else {
            // offene Linien: je 4 km Linienlänge (samt Verlängerung); ohne Linie ausser denen der Hasen keine
            let hares = Set([innerLane, backHareLane].compactMap { $0 })
            let others = laneList.indices.filter { !hares.contains($0) }
            let length = others.reduce(0.0) { $0 + laneList[$1].loopLength } / Double(max(others.count, 1))
            residentCount = others.isEmpty ? 0
                : min(max(Int((Double(density.rowersPer4km) * length / 4000).rounded()), 2), 12)
        }
        returnOffset = abs(tr.returnOffset)
        restartsAtStart = !hasTurn && !course.isLoop && laneList.contains { $0.form == .open }
        random = rnd
    }

    /// Bahn der Hasen für die Lage u des eigenen Boots (Rückfahrt: `backHareLane`)
    public func hareLane(at u: Double) -> Int? {
        guard let first = lanes.first, u >= first.oneWay, first.form != .ring else { return innerLane }
        return backHareLane ?? innerLane
    }

    // MARK: - Fortschreiben

    /// Ruderer fortschreiben (Startverteilung beim ersten Aufruf), Gäste ein- und aussteigen lassen.
    /// `t` = Sekunden seit Beginn (monoton).
    public mutating func update(time t: Double, own: OwnBoat) {
        guard !lanes.isEmpty else { return }
        if restartsAtStart, let lu = lastOwnU, own.u < lu - lanes[0].oneWay / 2 {
            // one_way: neue Runde am Start, die Szene springt – neu besetzen wie beim Start der Fahrt
            rowers.removeAll()
            lastTime = nil
        }
        lastOwnU = own.u
        let base = max(own.speed, 1.2)
        guard let last = lastTime else {
            placeInitial(own: own, time: t)
            lastTime = t
            lastBase = base
            nextGuest = t + random.uniform(density == .dense ? 20...60 : 60...150)
            nextHare = t + random.uniform(density == .dense ? 5...15 : 20...60)
            return
        }
        let dt = min(max(t - last, 0), 5)
        lastTime = t
        lastBase = base
        var finished = Set<Int>()
        for i in rowers.indices {
            var r = rowers[i]
            let v = base * r.speedFactor(at: t)
            r.strokePhase += dt * Double(r.strokeRate(speed: v)) / 60
            r.strokePhase -= r.strokePhase.rounded(.down)
            switch r.phase {
            case .lane:
                let lane = lanes[r.lane]
                let uBefore = lane.u(fromW: r.w)
                var hareGone = false, hareBehind = false
                if var h = r.hare {
                    // Hase: Abstand voraus (entlang der Strecke, positiv = vor dem eigenen Boot)
                    let ahead = lane.along(uBefore, from: own.u)
                    let slow = h.isSlow
                    // Mitfahrer ziehen kurz vor Wende und Startkehre davon: in den Halbkreisen passt die Ruderdistanz
                    // nicht mehr zur Bogenlänge der Bahn, „gleiches Tempo“ hiesse dort zurückfallen
                    if h.phase != .leave && !slow && Self.turnAhead(own.u, lane: lane, before: 60) { h.phase = .leave }
                    // rechtzeitig vom Aufholtempo auf das Mitfahrtempo gehen: der Rest der Verzögerung (Zeitkonstante
                    // 6 s) trägt ihn noch (current − paceFactor) · Tempo · 6 m weiter
                    let target = max(h.target, lateralTarget(lane: lane, own: own))
                    if h.phase == .approach && ahead + (h.current - h.paceFactor) * base * 6 >= target {
                        h.phase = .pace
                        h.paceUntil = t + h.paceSeconds
                    }
                    if h.phase == .pace, !slow, let until = h.paceUntil, t >= until { h.phase = .leave }
                    if h.phase == .leave && !h.handed {
                        h.handed = true
                        handOver(time: t)
                    }
                    let goal = h.phase == .pace ? h.paceFactor : 1.35
                    h.current += (goal - h.current) * min(dt / 6, 1)
                    r.hare = h
                    hareGone = (h.phase == .leave && ahead > Self.visibleRange + 20) || t - h.since > 900
                    // überholt (Mitfahrer oder langsamer): hinter dem Boot und ausser Sicht → sofort aus dem Spiel
                    // (nicht während der eigenen Wende bzw. Startkehre: dort dreht die Kamera schnell)
                    hareBehind = h.phase != .approach && ahead < 0 && !Self.nearTurn(own.u, lane: lane, before: 0)
                }
                let v = base * r.speedFactor(at: t)
                r.w += v * dt
                r.rowed += v * dt
                if hareGone || hareBehind {
                    // aus dem Spiel nur ausser Sicht, geprüft an der neuen Lage (gleiche Zeit wie das eigene Boot):
                    // davongezogen bzw. zu alt: deutlich hinter der Kamera (> 120°, ≥ 20 m) oder weiter als 450 m;
                    // überholt: mehr als ca. 105° von der Blickrichtung, egal wie nah
                    let hp = lane.pose(atW: r.w)
                    if (hareGone && Self.isHidden(x: hp.x, z: hp.z, own: own, minDistance: 20, cosMax: -0.5))
                        || (hareBehind && Self.isHidden(x: hp.x, z: hp.z, own: own, minDistance: 0, cosMax: -0.26)) {
                        finished.insert(r.id)
                        if r.hare?.handed == false { handOver(time: t) }
                    }
                }
                if let planned = r.plannedMeters, r.rowed >= planned,
                   let d = exitDock(for: r, uBefore: uBefore, uAfter: lane.u(fromW: r.w), own: own) {
                    // schon ein Stück über die Ausfahrstelle hinaus: so weit auf der Ausfahrt beginnen
                    let exitU = docks[d].spec.exitU ?? docks[d].spec.joinU
                    let over = RowerLane.mod(lane.u(fromW: r.w) - exitU, 2 * lane.oneWay)
                    r.phase = .leaving(dock: d)
                    r.w = min(over, 5)
                }
            case .entering(let d):
                r.w += 0.7 * v * dt
                if r.w >= docks[d].enter.length {
                    r.phase = .lane
                    r.w = lanes[r.lane].w(fromU: docks[d].spec.joinU) + (r.w - docks[d].enter.length)
                }
            case .leaving(let d):
                r.w += 0.7 * v * dt
                if r.w >= docks[d].exit.length { finished.insert(r.id) }
            }
            rowers[i] = r
        }
        if !finished.isEmpty { rowers.removeAll { finished.contains($0.id) } }
        if let due = nextHare, t >= due {
            if spawnHare(time: t, own: own) {
                nextHare = t + 30
            } else {
                nextHare = t + random.uniform(3...6)
            }
        }
        if let due = nextGuest, t >= due {
            if spawnGuest(time: t, own: own) {
                nextGuest = t + random.uniform(density.guestInterval)
            } else {
                nextGuest = t + random.uniform(20...40)
            }
        }
    }

    /// Anzeigezustände zur Zeit t (zwischen zwei `update` vorausgerechnet)
    public func states(at t: Double, own: OwnBoat) -> [RowerState] {
        let dt = max(t - (lastTime ?? t), 0)
        return rowers.map { r in
            let v = lastBase * r.speedFactor(at: t)
            let p: (x: Double, z: Double, heading: Double)
            switch r.phase {
            case .lane: p = lanes[r.lane].pose(atW: r.w + v * dt)
            case .entering(let d): p = docks[d].enter.pose(at: r.w + 0.7 * v * dt)
            case .leaving(let d): p = docks[d].exit.pose(at: r.w + 0.7 * v * dt)
            }
            let phase = r.strokePhase + dt * Double(r.strokeRate(speed: v)) / 60
            return RowerState(id: r.id, x: p.x, z: p.z, heading: p.heading, strokeRate: r.strokeRate(speed: v),
                              strokePhase: phase - phase.rounded(.down), colorIndex: r.colorIndex,
                              distance: hypot(p.x - own.x, p.z - own.z))
        }
    }

    /// Lage der Ruderer auf der Bahn als Ruderdistanz der eigenen Strecke (für Querfahrten der Schiffe)
    public func trackPositions(at t: Double) -> [(u: Double, speed: Double)] {
        rowers.compactMap { r in
            guard r.phase == .lane else { return nil }
            return (lanes[r.lane].u(fromW: r.w), lastBase * r.speedFactor(at: t))
        }
    }

    // MARK: - Startverteilung

    private mutating func placeInitial(own: OwnBoat, time t: Double) {
        let k = lanes.count
        // Mit mehreren Bahnen gehört die innerste den Hasen; die Bahnruderer verteilen sich reihum auf die anderen.
        var counts = [Int](repeating: 0, count: k)
        let inner = hareLane(at: own.u) ?? innerLane ?? 0
        if k == 1 {
            counts[0] = residentCount
        } else {
            // auch die Hasenlinie der anderen Richtung bleibt frei (offene Linien auf Strecken mit Wende)
            let others = (0..<k).filter { $0 != inner && $0 != backHareLane && $0 != innerLane }
            if !others.isEmpty {
                for i in 0..<residentCount { counts[others[i % others.count]] += 1 }
            }
        }
        var rank = 0
        for li in ([inner] + (0..<k).filter { $0 != inner }) {
            defer { rank += 1 }
            let count = counts[li]
            guard count > 0 else { continue }
            let lane = lanes[li]
            let anchor: Double
            if lane.form != .closed {
                // offene Linien und Ringe: der erste 20–80 m voraus (Gegenverkehr kommt einem dort entgegen), sonst
                // irgendwo auf der Linie
                if rank <= 1 {
                    let au = own.u + (rank == 0 ? random.uniform(20...40) : random.uniform(20...80))
                    let ownS = own.u < lane.oneWay || lane.form == .ring ? own.u : 2 * lane.oneWay - own.u
                    anchor = lane.w(atS: own.u < lane.oneWay || lane.form == .ring ? au : ownS - (au - own.u))
                } else {
                    anchor = random.uniform(0...lane.loopLength)
                }
            } else if rank <= 1 {
                let au = own.u + (rank == 0 ? random.uniform(20...40) : random.uniform(20...80))
                anchor = au < lane.oneWay ? lane.w(forOutS: au) : lane.w(fromU: au)
            } else {
                anchor = lane.w(fromU: random.uniform(0...(2 * lane.oneWay)))
            }
            for j in 0..<count {
                rowers.append(makeRower(lane: li, w: anchor + Double(j) * lane.loopLength / Double(count),
                                        phase: .lane, planned: nil))
            }
        }
        if k >= 1 {
            // innerste Bahn: gleich zu Beginn ein Hase 20–25 m voraus (bei grossem Seitenabstand weiter), der schon
            // mitfährt; am Start liegt die Bahn noch weiter aussen (Übergang)
            let lane = lanes[inner]
            let au = max(own.u + random.uniform(20...25), own.u + lateralTarget(lane: lane, own: own))
            let w = lane.form != .closed ? lane.w(fromU: au) : (au < lane.oneWay ? lane.w(forOutS: au) : lane.w(fromU: au))
            var r = makeRower(lane: inner, w: w, phase: .lane, planned: nil)
            r.hare = newHare(time: t, pacing: true)
            rowers.append(r)
        }
    }

    // MARK: - Hasen

    /// Neuer Hase auf der innersten Bahn, 50–80 m hinter dem eigenen Boot (hinter der Kamera, also ausser Sicht).
    /// Nur wenn kein anderer Hase mitfährt oder aufholt, das Boot nicht in Wende oder Startkehre ist und auf der Bahn
    /// 30 m dahinter bis 930 m davor kein anderer Ruderer ist (der Hase ist schneller und würde ihn sonst einholen).
    private mutating func spawnHare(time t: Double, own: OwnBoat) -> Bool {
        guard let li = hareLane(at: own.u) else { return false }
        if rowers.contains(where: { $0.hare != nil && $0.hare?.phase != .leave }) { return false }
        let lane = lanes[li]
        if Self.nearTurn(own.u, lane: lane, before: 300) { return false }
        let w0 = lane.w(fromU: own.u - random.uniform(50...80))
        for r in rowers where r.lane == li && r.phase == .lane {
            // mit mehreren Bahnen hat die innerste keine Bahnruderer (nur Hasen)
            if r.hare == nil && lanes.count > 1 { continue }
            if r.hare == nil {
                // Bahnruderer: 30 m dahinter bis 930 m davor frei (der Hase ist schneller)
                if RowerLane.mod(r.w - (w0 - 30), lane.loopLength) <= 960 { return false }
            } else {
                // davonziehender Hase: mindestens 60 m voraus (beide fahren dann ×1,35) und keiner bis 1000 m
                // dahinter (er würde den neuen, der dann mitfährt, einholen)
                let dw = RowerLane.mod(r.w - w0, lane.loopLength)
                if dw < 60 || dw > lane.loopLength - 1000 { return false }
            }
        }
        var rower = makeRower(lane: li, w: w0, phase: .lane, planned: nil)
        rower.hare = newHare(time: t)
        rowers.append(rower)
        return true
    }

    /// Neuer Hase: Mitfahrer (×0,99–1,01) oder langsamer (×0,86–0,92; normal 25 %, dense 15 %). `pacing`: fährt schon mit.
    private mutating func newHare(time t: Double, pacing: Bool = false) -> VirtualRower.Hare {
        // der erste (schon mitfahrende) ist immer ein Mitfahrer; die Zufallszahl wird trotzdem gezogen
        // nur eine Bahn (gross seitlich): keine langsamen, sie stünden lange neben einem statt vorn im Bild
        let slow = random.unit() < (density == .dense ? 0.15 : 0.25) && !pacing && lanes.count > 1
        let target = random.uniform(17...22)
        let paceSeconds = random.uniform(density.harePace)
        let paceFactor = slow ? random.uniform(0.86...0.92) : random.uniform(0.995...1.005)
        var h = VirtualRower.Hare(phase: .approach, target: target, paceSeconds: paceSeconds, paceFactor: paceFactor,
                                  current: 1.35, paceUntil: nil, since: t)
        if pacing {
            h.phase = .pace
            h.current = paceFactor
            h.paceUntil = t + paceSeconds
        }
        return h
    }

    /// Liegt die Linie gleicher Richtung weiter als 12 m seitlich (Strecken mit nur einer Bahn), fährt der Hase so weit
    /// vorn, dass er ca. 25° von der Kamera (4,5 m hinter dem Boot) aus liegt, höchstens 45 m von ihr entfernt; sonst 0.
    private func lateralTarget(lane: RowerLane, own: OwnBoat) -> Double {
        let lat = own.u < lane.oneWay ? abs(lane.spec.outM) : abs(lane.spec.backM - returnOffset)
        guard lat > 12 else { return 0 }
        let along = min(lat / tan(25 * Double.pi / 180), max(45 * 45 - lat * lat, 0).squareRoot())
        return along - 4.5
    }

    /// Der Hase zieht davon oder ist überholt: der nächste kommt bald (`density.hareInterval`, normal 10–25 s).
    private mutating func handOver(time t: Double) {
        nextHare = min(nextHare ?? .infinity, t + random.uniform(density.hareInterval))
    }

    /// Wende bzw. Startkehre höchstens `before` m voraus oder das Boot ist darin (nicht: kurz nach dem Start).
    /// one_way: das Ziel (halbe Wendelänge 0); Rundkurs: nie.
    static func turnAhead(_ u: Double, lane: RowerLane, before: Double) -> Bool {
        if lane.form == .ring { return false }
        let L = lane.oneWay, h = lane.turnHalfLength
        return (u >= L - h - before && u <= L + h) || u >= 2 * L - h - before
    }

    /// Eigenes Boot in oder kurz vor Wende bzw. Startkehre (`before` m davor, 40 m danach)?
    static func nearTurn(_ u: Double, lane: RowerLane, before: Double) -> Bool {
        if lane.form == .ring { return false }
        let L = lane.oneWay, h = lane.turnHalfLength
        return (u >= L - h - before && u <= L + h + 40) || u >= 2 * L - h - before || u <= h + 40
    }

    /// Ausser Sicht: weiter als 450 m vom Boot oder hinter der Kamera (4,5 m hinter dem Boot; Winkel zur Blickrichtung
    /// mit cos < `cosMax`, Standard −0,3 ≈ 107°, und mindestens `minDistance` m von der Kamera). Was vor der Kamera
    /// liegt (z. B. ein Hase 10–20 m voraus), gilt nie als verborgen.
    public static func isHidden(x: Double, z: Double, own: OwnBoat, minDistance: Double = 15,
                                cosMax: Double = -0.3) -> Bool {
        if hypot(x - own.x, z - own.z) >= visibleRange { return true }
        let fx = -sin(own.heading), fz = -cos(own.heading)
        let cx = own.x - fx * 4.5, cz = own.z - fz * 4.5
        let vx = x - cx, vz = z - cz
        let d = hypot(vx, vz)
        return d >= minDistance && (vx * fx + vz * fz) / d < cosMax
    }

    private mutating func makeRower(lane: Int, w: Double, phase: VirtualRower.Phase, planned: Double?) -> VirtualRower {
        let used = Set(rowers.map(\.colorIndex))
        let color = (0..<12).first { !used.contains($0) } ?? random.int(12)
        let r = VirtualRower(id: nextId, lane: lane, factor: laneFactors[lane], wobble: random.uniform(0.015...0.03),
                             wobblePeriod: random.uniform(40...90), wobblePhase: random.uniform(0...(2 * Double.pi)),
                             colorIndex: color, plannedMeters: planned, phase: phase, w: w,
                             strokePhase: random.unit())
        nextId += 1
        return r
    }

    // MARK: - Gäste

    private mutating func spawnGuest(time t: Double, own: OwnBoat) -> Bool {
        guard !docks.isEmpty, rowers.filter(\.isGuest).count < density.maxGuests else { return false }
        let d = random.int(docks.count)
        guard dockIsClear(d, own: own, entering: true) else { return false }
        let laps = random.uniform(1...3)
        let lane = docks[d].spec.lane
        rowers.append(makeRower(lane: lane, w: 0, phase: .entering(dock: d), planned: laps * lanes[lane].loopLength))
        return true
    }

    /// Steg, an dem ein Gast jetzt aussteigen kann (er hat die Einfahrstelle gerade passiert), sonst nil
    private func exitDock(for r: VirtualRower, uBefore: Double, uAfter: Double, own: OwnBoat) -> Int? {
        let L2 = 2 * lanes[r.lane].oneWay
        let step = RowerLane.mod(uAfter - uBefore, L2)
        for (i, d) in docks.enumerated() where d.spec.lane == r.lane {
            guard RowerLane.mod((d.spec.exitU ?? d.spec.joinU) - uBefore, L2) <= step else { continue }
            if dockIsClear(i, own: own, ignoring: r.id) { return i }
        }
        return nil
    }

    /// Ein- bzw. Ausfahrt am Steg frei? Eigenes Boot und andere Ruderer weit genug weg, Lücke auf der Bahn.
    /// `entering`: Lücke auf der Bahn für den Zeitpunkt prüfen, an dem der Gast die Bahn erreicht (die anderen fahren
    /// in der Zwischenzeit weiter: Zufahrt mit 70 % des Tempos).
    public func dockIsClear(_ index: Int, own: OwnBoat, ignoring id: Int? = nil, entering: Bool = false) -> Bool {
        let dock = docks[index]
        let lane = lanes[dock.spec.lane]
        let L2 = 2 * lane.oneWay
        func gap(_ a: Double, _ b: Double) -> Double {
            let d = RowerLane.mod(a - b, L2)
            return min(d, L2 - d)
        }
        let points = [dock.spec.joinU, L2 - dock.spec.joinU]
        for p in points where gap(p, own.u) < Self.dockClearOwn { return false }
        // auf der Bahn der Hasen keine Gäste, solange ein Hase unterwegs ist (er ist schneller)
        if dock.spec.lane == innerLane, rowers.contains(where: { $0.hare != nil && $0.id != id }) { return false }
        let joinW = lane.w(fromU: dock.spec.joinU)
        for r in rowers where r.id != id {
            switch r.phase {
            case .entering(let d), .leaving(let d):
                if docks[d].spec.id == dock.spec.id { return false }
            case .lane:
                // Die Zufahrt führt zur Bahn, die dem Ufer am nächsten liegt (lanes.py), kreuzt also keine andere
                // Ruderer-Bahn; zur Sicherheit trotzdem niemand in der Nähe der Einfahrstelle.
                if r.lane != dock.spec.lane, gap(dock.spec.joinU, lanes[r.lane].u(fromW: r.w)) < Self.dockClearRowers {
                    return false
                }
                if r.lane == dock.spec.lane {
                    let ahead = entering ? dock.enter.length / 0.7 : 0
                    let dw = RowerLane.mod(r.w + ahead - joinW, lane.loopLength)
                    if min(dw, lane.loopLength - dw) < Self.dockLaneGap { return false }
                }
            }
        }
        return true
    }

    // MARK: - Testbetrieb

    /// `-demoTrafficAhead`: den Ruderer der innersten Bahn, der der Stelle `ahead` m voraus am nächsten ist, dorthin
    /// setzen (die anderen Ruderer der Bahn bleiben, ihr Abstand ist mindestens eine halbe Lücke).
    public mutating func placeAhead(time t: Double, own: OwnBoat, ahead: Double = 30) {
        guard !lanes.isEmpty else { return }
        if lastTime == nil { update(time: t, own: own) }
        let li = lanes[0].form != .closed ? (hareLane(at: own.u) ?? 0)
            : lanes.indices.min { lanes[$0].spec.backM - lanes[$0].spec.outM < lanes[$1].spec.backM - lanes[$1].spec.outM } ?? 0
        let lane = lanes[li]
        let target = lane.w(fromU: own.u + ahead)
        func dist(_ w: Double) -> Double {
            let d = RowerLane.mod(w - target, lane.loopLength)
            return min(d, lane.loopLength - d)
        }
        if let i = rowers.indices.filter({ rowers[$0].lane == li && rowers[$0].phase == .lane })
            .min(by: { dist(rowers[$0].w) < dist(rowers[$1].w) }) {
            rowers[i].w = target
        } else {
            rowers.append(makeRower(lane: li, w: target, phase: .lane, planned: nil))
        }
    }
}
