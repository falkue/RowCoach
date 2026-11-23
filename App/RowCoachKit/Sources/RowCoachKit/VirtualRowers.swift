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
public struct RowerLane: Sendable {
    public let spec: RowerLaneSpec
    public let oneWay: Double
    /// Länge der Bahn (m)
    public let loopLength: Double

    private let line: Centerline
    private let half: Double          // halbe Wendelänge der eigenen Bahn (Ruderdistanz)
    private let ac: Double            // Abstand Wendebeginn → Mitte des grossen Bogens
    private let rho: Double
    private let lc: Double
    private let straight: Double      // Länge einer Geraden (L − 2·half)
    private let loop: Double          // Wendeschlaufe samt Zu- und Abfahrt (2·ac + π·ρ)
    private let startApproach: Double // Zufahrt zum Starthalbkreis ab s = half (half + startBehind)
    private let startLoop: Double     // Startschlaufe samt Zu- und Abfahrt (2·startApproach + π·ρ)

    /// Der Starthalbkreis liegt ganz hinter der Startlinie (Mitte so viele Meter vor s = 0): Ohne Runden beginnt und
    /// endet die eigene Fahrt geradeaus bei s = 0 (Hin- bzw. Rückfahrtlinie), mit Runden fährt sie dort die
    /// Startkehre (s ≈ 9 … 40 m). Beides bleibt so ≥ 8 m vom Halbkreis entfernt.
    public static let startBehind = 10.0

    /// nil, wenn die Strecke keine Wende hat oder zu kurz ist.
    public init?(spec: RowerLaneSpec, track: CourseTrack) {
        guard track.course.turns > 0, spec.backM > spec.outM else { return nil }
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
        rho = (spec.backM - spec.outM) / 2
        lc = (spec.backM + spec.outM) / 2
        straight = L - 2 * h
        loop = 2 * ac + Double.pi * rho
        startApproach = h + Self.startBehind
        startLoop = 2 * startApproach + Double.pi * rho
        loopLength = 2 * straight + loop + startLoop
    }

    /// Ruderdistanz der eigenen Strecke (zyklisch, 0 … 2L) → Bahnparameter w
    public func w(fromU uIn: Double) -> Double {
        let L = oneWay, h = half
        let u = Self.mod(uIn, 2 * L)
        let a = startLoop / 2, b = a + straight, c = b + loop, d = c + straight
        if u < h { return a * (u / h) }
        if u < L - h { return a + (u - h) }
        if u < L + h { return b + loop * (u - (L - h)) / (2 * h) }
        if u < 2 * L - h { return c + (u - (L + h)) }
        return d + startLoop / 2 * (u - (2 * L - h)) / h
    }

    /// Bahnparameter w → Ruderdistanz der eigenen Strecke (0 … 2L)
    public func u(fromW wIn: Double) -> Double {
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
        let L = oneWay, h = half
        let w = Self.mod(wIn, loopLength)
        let a = startLoop / 2, b = a + straight, c = b + loop, d = c + straight
        let r: (Double, Double, Double, Double)
        if w < a || w >= d {
            // Starthalbkreis (Rahmen am Ende der Rückfahrt bzw. Beginn der Hinfahrt, s = half)
            let g = w < a ? a + w : w - d
            r = startArc(g, frame: line.sample(at: h))
        } else if w < b {
            let s = h + (w - a)
            let p = line.point(at: s, lateral: spec.outM)
            let t = line.sample(at: s)
            r = (p.x, p.z, t.tx, t.tz)
        } else if w < c {
            r = turnLoop(w - b, frame: line.sample(at: L - h))
        } else {
            let s = (L - h) - (w - c)
            let p = line.point(at: s, lateral: spec.backM)
            let t = line.sample(at: s)
            r = (p.x, p.z, -t.tx, -t.tz)
        }
        return (r.0, r.1, atan2(-r.2, -r.3))
    }

    /// Halbkreis an der Wende; g = 0 … loop ab Wendebeginn auf der Hinfahrtbahn
    private func turnLoop(_ g: Double, frame f: Centerline.Sample) -> (Double, Double, Double, Double) {
        let nx = f.tz, nz = -f.tx                     // links der Hinfahrt
        let al: Double, l: Double, dx: Double, dz: Double
        if g < ac {
            al = g; l = spec.outM; dx = f.tx; dz = f.tz
        } else if g < ac + Double.pi * rho {
            let th = (g - ac) / rho
            al = ac + rho * sin(th); l = lc - rho * cos(th)
            dx = cos(th) * f.tx + sin(th) * nx; dz = cos(th) * f.tz + sin(th) * nz
        } else {
            al = ac - (g - ac - Double.pi * rho); l = spec.backM; dx = -f.tx; dz = -f.tz
        }
        return (f.x + f.tx * al + nx * l, f.z + f.tz * al + nz * l, dx, dz)
    }

    /// Halbkreis am Start; g = 0 … startLoop ab Ende der Rückfahrtbahn (bei s = half), Mitte bei s = −startBehind
    private func startArc(_ g: Double, frame f: Centerline.Sample) -> (Double, Double, Double, Double) {
        let nx = f.tz, nz = -f.tx
        let A = startApproach
        let al: Double, l: Double, dx: Double, dz: Double
        if g < A {
            al = -g; l = spec.backM; dx = -f.tx; dz = -f.tz
        } else if g < A + Double.pi * rho {
            let th = (g - A) / rho
            al = -A - rho * sin(th); l = lc + rho * cos(th)
            dx = -cos(th) * f.tx - sin(th) * nx; dz = -cos(th) * f.tz - sin(th) * nz
        } else {
            al = -A + (g - A - Double.pi * rho); l = spec.outM; dx = f.tx; dz = f.tz
        }
        return (f.x + f.tx * al + nx * l, f.z + f.tz * al + nz * l, dx, dz)
    }

    static func mod(_ a: Double, _ m: Double) -> Double {
        guard m > 0, a.isFinite else { return 0 }
        let r = a.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }
}

/// Ein virtueller Ruderer: Bahn, Tempo mit leichter natürlicher Schwankung, eigener Schlagtakt und Trikotfarbe.
/// Die Lage ist eine geschlossene Funktion der Zeit (`w(at:)`), damit Szene und Navigator dasselbe zeigen.
public struct VirtualRower: Equatable, Sendable {
    public let id: Int
    /// Index der Bahn in `VirtualRowers.lanes`
    public let lane: Int
    /// Grundtempo (m/s)
    public let speed: Double
    /// Bahnparameter zur Zeit `t0`
    public let w0: Double
    public let t0: Double
    /// Tempo schwankt um ± wobble (Anteil) mit der Periode `wobblePeriod`
    public let wobble: Double
    public let wobblePeriod: Double
    public let wobblePhase: Double
    public let strokeRate: Int
    public let strokeOffset: Double
    /// Farbe (Trikot, Blätter) als Index in die Palette der Szene (0 … 5)
    public let colorIndex: Int

    /// zurückgelegte Meter auf der Bahn seit t0 (ohne Umlauf)
    public func travelled(at t: Double) -> Double {
        let om = 2 * Double.pi / wobblePeriod
        return speed * (t - t0) - speed * wobble / om * (cos(om * t + wobblePhase) - cos(om * t0 + wobblePhase))
    }

    /// momentanes Tempo (m/s)
    public func speed(at t: Double) -> Double {
        speed * (1 + wobble * sin(2 * Double.pi / wobblePeriod * t + wobblePhase))
    }

    /// Schlagphase 0 … 1 (0 = Wasserfassen)
    public func strokePhase(at t: Double) -> Double {
        let p = strokeOffset + t * Double(strokeRate) / 60
        return p - floor(p)
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

/// Lage des eigenen Boots für Sichtprüfungen
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

/// Plant die virtuellen Ruderer einer Fahrt: wer wann wo auftaucht und wieder verschwindet.
///
/// Regeln (Konzept Abschnitt 16, Falk 23.11.2026):
/// - Dichte: höchstens `density.maxRowers` gleichzeitig im Spiel (normal 3, wenig 2), nie mehr als Bahnen; je Bahn
///   nur ein Ruderer, damit sich keine zwei Figuren einholen oder begegnen. In der Szene sind höchstens 4 sichtbar.
/// - Ein neuer Ruderer kommt im Mittel alle `density.rowerSpawnInterval` Sekunden, wenn Platz ist. Drei Fälle:
///   schneller (Tempo × 1,12 … 1,32) und 70–160 m hinter dem eigenen Boot, holt es in 1–6 min ein (45 %);
///   langsamer (× 0,60 … 0,80) und 470–560 m voraus, wird in 5–12 min eingeholt (35 %);
///   Gegenverkehr (× 0,85 … 1,15) 470–560 m voraus auf der anderen Seite (20 %).
///   Daraus ergibt sich bei normalem Tempo etwa alle 3–5 Minuten ein Überholen (Simulation: rund 15 pro Stunde,
///   „wenig“ rund 10).
/// - Tempo bezogen auf das eigene Durchschnittstempo zum Zeitpunkt des Erscheinens, mit ± 2–4 % Schwankung
///   (Periode 40–90 s); Schlagzahl aus dem Tempo (18–32/min) ± 1.
/// - Erscheinen und Verschwinden nur ausserhalb der Sicht: weiter als 450 m weg oder hinter der Kamera
///   (mehr als ca. 107° von der Fahrtrichtung, ≥ 40 m). Aus dem Spiel gehen sie ab 650 m, oder wenn sie sich
///   entfernen und dabei weiter als 470 m weg oder mehr als 180 m hinter dem Boot sind.
/// - Deterministisch: gleicher Startwert und gleiche Eingaben → gleiche Ruderer.
public struct VirtualRowers: Sendable {
    public let lanes: [RowerLane]
    public let density: TrafficDensity
    public private(set) var rowers: [VirtualRower] = []

    private var random: TrafficRandom
    private var nextSpawn: Double?
    private var nextId = 1

    /// Sichtweite: weiter weg ist ein Ruderer in der Szene ausgeblendet
    public static let visibleRange = 450.0
    public static let removeRange = 650.0

    public init(course: Course, density: TrafficDensity, seed: UInt64, lanes specs: [RowerLaneSpec]? = nil,
                track: CourseTrack? = nil) {
        let tr = track ?? CourseTrack(course: course)
        let s = specs ?? course.traffic?.rowerLanes ?? TrafficDefaults.rowerLanes
        lanes = s.compactMap { RowerLane(spec: $0, track: tr) }
        self.density = density
        random = TrafficRandom(seed: seed)
    }

    /// Spawn und Abbau; `t` = Sekunden seit Beginn (monoton).
    public mutating func update(time t: Double, own: OwnBoat) {
        guard !lanes.isEmpty else { return }
        // Abbau
        let gone = Set(rowers.filter { r in
            let st = state(of: r, at: t, own: own)
            if st.distance > Self.removeRange { return true }
            // entfernt sich der Ruderer (Abstand wächst) und ist er ausser Sicht, geht er aus dem Spiel
            let v = r.speed(at: t)
            let rvx = -sin(st.heading) * v - (-sin(own.heading) * own.speed)
            let rvz = -cos(st.heading) * v - (-cos(own.heading) * own.speed)
            let radial = ((st.x - own.x) * rvx + (st.z - own.z) * rvz) / max(st.distance, 1e-6)
            guard radial > 0 else { return false }
            return st.distance >= Self.visibleRange + 20 || Self.isBehind(x: st.x, z: st.z, own: own, minDistance: 180)
        }.map(\.id))
        if !gone.isEmpty { rowers.removeAll { gone.contains($0.id) } }
        if nextSpawn == nil { nextSpawn = t + random.uniform(density == .dense ? 1...3 : 2...6) }
        guard let due = nextSpawn, t >= due else { return }
        let cap = min(density.maxRowers, lanes.count)
        guard rowers.count < cap else {
            nextSpawn = t + 8
            return
        }
        if spawn(at: t, own: own) {
            nextSpawn = t + random.uniform(density.rowerSpawnInterval)
        } else {
            nextSpawn = t + random.uniform(density == .dense ? 1...3 : 2...5)
        }
    }

    /// Testbetrieb (`-demoTrafficAhead`): setzt sofort einen Ruderer `ahead` Meter voraus auf die innerste Bahn,
    /// im eigenen Tempo, damit er auf dem Bildschirm sicher zu sehen ist. Ersetzt einen Ruderer auf dieser Bahn.
    public mutating func placeAhead(time t: Double, own: OwnBoat, ahead: Double = 30) {
        guard !lanes.isEmpty else { return }
        let laneIndex = lanes.indices.min { abs(lanes[$0].spec.backM - lanes[$0].spec.outM) < abs(lanes[$1].spec.backM - lanes[$1].spec.outM) } ?? 0
        rowers.removeAll { $0.lane == laneIndex }
        let r = VirtualRower(id: nextId, lane: laneIndex, speed: max(own.speed, 1.2), w0: lanes[laneIndex].w(fromU: own.u + ahead),
                             t0: t, wobble: 0.02, wobblePeriod: 60, wobblePhase: 0, strokeRate: 22, strokeOffset: 0,
                             colorIndex: 0)
        nextId += 1
        rowers.append(r)
    }

    /// Anzeigezustände aller Ruderer zur Zeit t
    public func states(at t: Double, own: OwnBoat) -> [RowerState] {
        rowers.map { state(of: $0, at: t, own: own) }
    }

    public func state(of r: VirtualRower, at t: Double, own: OwnBoat) -> RowerState {
        let lane = lanes[r.lane]
        let p = lane.pose(atW: r.w0 + r.travelled(at: t))
        return RowerState(id: r.id, x: p.x, z: p.z, heading: p.heading, strokeRate: r.strokeRate,
                          strokePhase: r.strokePhase(at: t), colorIndex: r.colorIndex,
                          distance: hypot(p.x - own.x, p.z - own.z))
    }

    /// Ruderdistanz (eigene Strecke) eines Ruderers zur Zeit t, für Abstandsprüfungen der Schiffe
    public func trackPositions(at t: Double) -> [(u: Double, speed: Double)] {
        rowers.map { r in (lanes[r.lane].u(fromW: r.w0 + r.travelled(at: t)), r.speed) }
    }

    // MARK: - Spawn

    private mutating func spawn(at t: Double, own: OwnBoat) -> Bool {
        let used = Set(rowers.map(\.lane))
        let free = lanes.indices.filter { !used.contains($0) }
        guard !free.isEmpty else { return false }
        let laneIndex = free[random.int(free.count)]
        let lane = lanes[laneIndex]
        let L2 = 2 * lane.oneWay
        let base = max(own.speed, 1.2)
        let kind = random.unit()
        let factor: Double, u: Double
        if kind < 0.45 {
            factor = random.uniform(1.12...1.32)
            u = own.u - random.uniform(70...160)
        } else if kind < 0.80 {
            factor = random.uniform(0.60...0.80)
            u = own.u + random.uniform(470...560)
        } else {
            factor = random.uniform(0.85...1.15)
            u = (L2 - own.u) - random.uniform(470...560)
        }
        let w = lane.w(fromU: u)
        let p = lane.pose(atW: w)
        guard Self.isHidden(x: p.x, z: p.z, own: own) else { return false }
        let speed = base * factor
        let usedColors = Set(rowers.map(\.colorIndex))
        let colors = (0..<6).filter { !usedColors.contains($0) }
        let color = colors.isEmpty ? random.int(6) : colors[random.int(colors.count)]
        let rate = Int((18 + (speed - 3) * 6).rounded()) + random.int(3) - 1
        let r = VirtualRower(id: nextId, lane: laneIndex, speed: speed, w0: w, t0: t,
                             wobble: random.uniform(0.02...0.04), wobblePeriod: random.uniform(40...90),
                             wobblePhase: random.uniform(0...(2 * Double.pi)),
                             strokeRate: min(max(rate, 18), 32), strokeOffset: random.unit(), colorIndex: color)
        nextId += 1
        rowers.append(r)
        return true
    }

    // MARK: - Sicht

    /// Ausserhalb der Sicht: weit weg oder hinter der Kamera
    public static func isHidden(x: Double, z: Double, own: OwnBoat) -> Bool {
        let d = hypot(x - own.x, z - own.z)
        if d >= visibleRange { return true }
        return isBehind(x: x, z: z, own: own, minDistance: 40)
    }

    /// Hinter dem Boot (mehr als ca. 107° von der Fahrtrichtung) und mindestens `minDistance` entfernt
    public static func isBehind(x: Double, z: Double, own: OwnBoat, minDistance: Double) -> Bool {
        let vx = x - own.x, vz = z - own.z
        let d = hypot(vx, vz)
        guard d >= minDistance, d > 0 else { return false }
        let fx = -sin(own.heading), fz = -cos(own.heading)
        return (fx * vx + fz * vz) / d < -0.3
    }
}
