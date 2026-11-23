import Foundation

/// Eine Ruderstrecke aus einem Kartenpaket (`courses/<id>/course.json`, erzeugt von tools/coursebuilder/export.py).
/// Das Format ist bewusst offen und versioniert. Später kennen auch RowServer dieselben Pakete, damit alle
/// Teilnehmenden eines Rennens dieselbe Strecke sehen.
public struct Course: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var region: String
    /// Pfad der Szene relativ zum Kartenordner, mit Platzhalter `{quality}` (z. B. "zuerichsee-unteres-becken/scene-{quality}.usdz")
    public var scene: String
    public var qualities: [String]
    public var oneWayM: Double
    public var totalM: Double
    public var turns: Int
    public var originLV95: [Double]
    public var lakeLevelM: Double
    /// Mittellinie der Hinfahrt in Szenenkoordinaten [x, z] (Meter; x = Ost, z = −Nord), Abstand ca. 2 m
    public var pathXZ: [[Double]]
    public var attribution: String
    /// Kleine genordete Luftbildkarte für den Navigator (optional; erzeugt von tools/coursebuilder/minimap.py)
    public var minimap: Minimap?

    /// Bild relativ zum Streckenordner und sein Ausschnitt in Szenenkoordinaten [xmin, zmin, xmax, zmax];
    /// x nach rechts, z (= −Nord) nach unten.
    public struct Minimap: Codable, Equatable, Sendable {
        public var image: String
        public var boundsXZ: [Double]
        enum CodingKeys: String, CodingKey { case image, boundsXZ = "bounds_xz" }
        public init(image: String, boundsXZ: [Double]) { self.image = image; self.boundsXZ = boundsXZ }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, region, scene, qualities, turns, attribution, minimap
        case oneWayM = "one_way_m", totalM = "total_m", originLV95 = "origin_lv95"
        case lakeLevelM = "lake_level_m", pathXZ = "path_xz"
    }

    public init(id: String, title: String, region: String = "", scene: String = "", qualities: [String] = [],
                oneWayM: Double, totalM: Double, turns: Int = 1, originLV95: [Double] = [], lakeLevelM: Double = 0,
                pathXZ: [[Double]], attribution: String = "", minimap: Minimap? = nil) {
        self.id = id
        self.title = title
        self.region = region
        self.scene = scene
        self.qualities = qualities
        self.oneWayM = oneWayM
        self.totalM = totalM
        self.turns = turns
        self.originLV95 = originLV95
        self.lakeLevelM = lakeLevelM
        self.pathXZ = pathXZ
        self.attribution = attribution
        self.minimap = minimap
    }

    public func scenePath(quality: String) -> String { scene.replacingOccurrences(of: "{quality}", with: quality) }

    /// Liest eine `course.json`.
    public static func decode(_ data: Data) throws -> Course {
        try JSONDecoder().decode(Course.self, from: data)
    }

    /// Gerade Teststrecke ab (0, 0) in Richtung `heading` (0 = Norden/−z), Punktabstand 2 m, mit einer Wende.
    /// Für Tests und als eingebaute Strecke, wenn kein Kartenpaket vorhanden ist.
    public static func straight(id: String = "teststrecke", title: String = "Teststrecke",
                                oneWay: Double = 1000, heading: Double = 0) -> Course {
        let n = max(Int((oneWay / 2).rounded()), 1)
        let dx = -sin(heading), dz = -cos(heading)
        let pts = (0...n).map { i -> [Double] in
            let s = oneWay * Double(i) / Double(n)
            return [dx * s, dz * s]
        }
        return Course(id: id, title: title, region: "Ohne Landschaft", oneWayM: oneWay, totalM: 2 * oneWay,
                      turns: 1, pathXZ: pts)
    }
}

/// Lage des Boots auf der Strecke zu einer geruderten Distanz.
public struct TrackPose: Equatable, Sendable {
    /// Szenenkoordinaten (Meter), y = 0 ist die Wasseroberfläche
    public var x: Double
    public var z: Double
    /// Fahrtrichtung als Winkel um die y-Achse (rad); 0 = Blick in −z (Norden), positiv = gegen den Uhrzeigersinn
    /// (von oben gesehen). Richtungsvektor = (−sin heading, −cos heading) in (x, z).
    public var heading: Double
    /// 0 = Hinfahrt, 1 = Rückfahrt (Wechsel in der Mitte der Wende)
    public var leg: Int
    /// 0…1 über die ganze Strecke
    public var progress: Double
    public var remaining: Double
    public var finished: Bool

    public init(x: Double, z: Double, heading: Double, leg: Int, progress: Double, remaining: Double, finished: Bool) {
        self.x = x
        self.z = z
        self.heading = heading
        self.leg = leg
        self.progress = progress
        self.remaining = remaining
        self.finished = finished
    }
}

/// Rechnet geruderte Distanz in Position und Richtung auf der Strecke um (hin, Wende, zurück).
///
/// - Hinfahrt: auf der Mittellinie `pathXZ`.
/// - Rückfahrt: dieselbe Linie, `returnOffset` Meter versetzt, und zwar rechts in Fahrtrichtung der Rückfahrt
///   (= links der Hinfahrt). Negativer Versatz legt die Rückfahrt auf die andere Seite.
/// - Wende: belegt die Distanz [L − turnBlend, L + turnBlend] um den Wendepunkt L. Das Boot fährt eine
///   „Birnenkehre“ aus drei Kreisbögen mit gleichem Radius (kurz weg, grosser Bogen, zurück auf die Rückfahrtlinie).
///   Position und Richtung sind dabei stetig; die Richtung dreht gleichmässig mit 1/Radius pro Meter.
///   Der Radius ergibt sich aus `turnBlend` (Standard 40 m → ca. 13 m Radius); ist `turnBlend` kleiner als ein
///   Halbkreis mit Durchmesser `returnOffset` erlaubt, wird der Halbkreis verwendet.
/// - Die Gesamtlänge entspricht `course.oneWayM` (bzw. der Linienlänge, falls 0) mal 2. Kleine Abweichungen
///   zwischen Linienlänge und `oneWayM` werden proportional verteilt.
/// - `turns == 0`: Strecke nur in eine Richtung, ohne Wende.
public struct CourseTrack: Sendable {
    public let course: Course
    public let returnOffset: Double
    public let turnBlend: Double
    /// Tatsächlicher Radius der Wendebögen (m)
    public let turnRadius: Double
    /// Länge einer Richtung (m Ruderdistanz)
    public let oneWayLength: Double
    /// Länge der ganzen Strecke (m Ruderdistanz)
    public let totalLength: Double

    private struct V: Sendable { var x: Double; var z: Double }

    private let pts: [V]
    private let cum: [Double]
    /// geglättete Tangenten an den Stützpunkten (Mittel der angrenzenden Segmente)
    private let tangents: [V]
    private let geoLength: Double
    /// halbe Wendelänge in Ruderdistanz (Wende = [L − turnHalf, L + turnHalf])
    private let turnHalf: Double
    private let turnAlpha: Double
    private let hasTurn: Bool

    public init(course: Course, returnOffset: Double = 12, turnBlend: Double = 40) {
        self.course = course
        self.returnOffset = returnOffset
        self.turnBlend = turnBlend

        let p = course.pathXZ.compactMap { $0.count >= 2 ? V(x: $0[0], z: $0[1]) : nil }
        var c: [Double] = [0]
        if p.count >= 2 {
            for i in 1..<p.count { c.append(c[i - 1] + hypot(p[i].x - p[i - 1].x, p[i].z - p[i - 1].z)) }
        }
        pts = p
        cum = c
        geoLength = c.last ?? 0

        // Tangenten je Stützpunkt
        var seg: [V] = []
        if p.count >= 2 {
            for i in 1..<p.count {
                let dx = p[i].x - p[i - 1].x, dz = p[i].z - p[i - 1].z
                let l = hypot(dx, dz)
                seg.append(l > 1e-9 ? V(x: dx / l, z: dz / l) : (seg.last ?? V(x: 0, z: -1)))
            }
        }
        var t: [V] = []
        if seg.isEmpty {
            t = p.map { _ in V(x: 0, z: -1) }
        } else {
            for i in 0..<p.count {
                let a = seg[max(i - 1, 0)], b = seg[min(i, seg.count - 1)]
                let sx = a.x + b.x, sz = a.z + b.z
                let l = hypot(sx, sz)
                t.append(l > 1e-9 ? V(x: sx / l, z: sz / l) : b)
            }
        }
        tangents = t

        let L = course.oneWayM > 0 ? course.oneWayM : geoLength
        oneWayLength = L
        hasTurn = course.turns > 0
        totalLength = hasTurn ? 2 * L : L

        // Wenderadius aus der gewünschten halben Wendelänge bestimmen
        let D = abs(returnOffset)
        func alpha(_ r: Double) -> Double { r > 0 ? acos(min(1, max(-1, (D / (2 * r) + 1) / 2))) : 0 }
        func half(_ r: Double) -> Double { r * (Double.pi + 4 * alpha(r)) / 2 }
        var r = D / 2
        if hasTurn, turnBlend > half(r) {
            var lo = r, hi = max(r, 1)
            while half(hi) < turnBlend { hi *= 2 }
            for _ in 0..<60 {
                let mid = (lo + hi) / 2
                if half(mid) < turnBlend { lo = mid } else { hi = mid }
            }
            r = (lo + hi) / 2
        }
        turnRadius = r
        turnAlpha = alpha(r)
        turnHalf = hasTurn ? min(half(r), L) : 0
    }

    // MARK: Geometrie

    /// Punkt und geglättete Tangente auf der Hinfahrtlinie bei Ruderdistanz s (0…L)
    private func sample(_ s: Double) -> (p: V, t: V) {
        guard pts.count >= 2, geoLength > 0, oneWayLength > 0 else {
            return (pts.first ?? V(x: 0, z: 0), V(x: 0, z: -1))
        }
        let g = min(max(s, 0), oneWayLength) * geoLength / oneWayLength
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] <= g { lo = mid } else { hi = mid }
        }
        let segLen = cum[hi] - cum[lo]
        let u = segLen > 0 ? (g - cum[lo]) / segLen : 0
        let a = pts[lo], b = pts[hi]
        let ta = tangents[lo], tb = tangents[hi]
        var tx = ta.x + (tb.x - ta.x) * u, tz = ta.z + (tb.z - ta.z) * u
        let l = hypot(tx, tz)
        if l > 1e-9 { tx /= l; tz /= l } else { tx = tb.x; tz = tb.z }
        return (V(x: a.x + (b.x - a.x) * u, z: a.z + (b.z - a.z) * u), V(x: tx, z: tz))
    }

    /// Normale zur Rückfahrtseite: links der Hinfahrt = rechts der Rückfahrt (x = Ost, z = −Nord)
    private func returnSide(_ t: V) -> V {
        let sign: Double = returnOffset < 0 ? -1 : 1
        return V(x: t.z * sign, z: -t.x * sign)
    }

    /// Position und Fahrtrichtung (Einheitsvektor) bei Distanz d, d bereits auf [0, total] begrenzt
    private func geometry(_ dd: Double) -> (p: V, dir: V) {
        let L = oneWayLength
        guard hasTurn else {
            let s = sample(dd)
            return (s.p, s.t)
        }
        let D = abs(returnOffset)
        if dd <= L - turnHalf || (turnHalf <= 0 && dd <= L) {
            let s = sample(dd)
            return (s.p, s.t)
        }
        if dd >= L + turnHalf {
            let s = sample(totalLength - dd)
            let n = returnSide(s.t)
            return (V(x: s.p.x + n.x * D, z: s.p.z + n.z * D), V(x: -s.t.x, z: -s.t.z))
        }
        // In der Wende: lokales Koordinatensystem am Wendebeginn (a entlang T0, l zur Rückfahrtseite)
        let s0 = sample(L - turnHalf)
        let n0 = returnSide(s0.t)
        let R = turnRadius, al = turnAlpha
        let arcLen = R * (Double.pi + 4 * al)
        let q = (dd - (L - turnHalf)) / (2 * turnHalf) * arcLen
        let a: Double, l: Double, psi: Double
        if q <= R * al {
            // Bogen 1: kurz von der Rückfahrtseite weg
            let phi = q / R
            psi = -phi
            a = R * sin(phi); l = -R + R * cos(phi)
        } else if q <= R * (Double.pi + 3 * al) {
            // Bogen 2: grosse Kehre zur Rückfahrtseite
            psi = -al + (q - R * al) / R
            let cx = 2 * R * sin(al), cl = R * (2 * cos(al) - 1)
            a = cx + R * sin(psi); l = cl - R * cos(psi)
        } else {
            // Bogen 3: auf die Rückfahrtlinie einschwenken
            psi = Double.pi + al - (q - R * (Double.pi + 3 * al)) / R
            let cl = R * (4 * cos(al) - 1)
            a = -R * sin(psi); l = cl + R * cos(psi)
        }
        let p = V(x: s0.p.x + a * s0.t.x + l * n0.x, z: s0.p.z + a * s0.t.z + l * n0.z)
        let dir = V(x: cos(psi) * s0.t.x + sin(psi) * n0.x, z: cos(psi) * s0.t.z + sin(psi) * n0.z)
        return (p, dir)
    }

    private func clamp(_ d: Double) -> Double {
        guard d.isFinite else { return d == .infinity ? totalLength : 0 }
        return min(max(d, 0), totalLength)
    }

    /// Position ohne Richtung (Szenenkoordinaten x, z).
    public func position(atDistance d: Double) -> (x: Double, z: Double) {
        let g = geometry(clamp(d))
        return (g.p.x, g.p.z)
    }

    public func pose(atDistance d: Double) -> TrackPose {
        let total = totalLength
        let dd = clamp(d)
        let g = geometry(dd)
        // heading 0 = Blick nach −z; Drehung um +y: Richtung (−sin h, −cos h)
        let heading = atan2(-g.dir.x, -g.dir.z)
        return TrackPose(x: g.p.x, z: g.p.z, heading: heading,
                         leg: (!hasTurn || dd <= oneWayLength) ? 0 : 1,
                         progress: total > 0 ? dd / total : 0, remaining: max(total - dd, 0),
                         finished: total > 0 && dd >= total)
    }
}
