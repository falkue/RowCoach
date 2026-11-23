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

    enum CodingKeys: String, CodingKey {
        case id, title, region, scene, qualities, turns, attribution
        case oneWayM = "one_way_m", totalM = "total_m", originLV95 = "origin_lv95"
        case lakeLevelM = "lake_level_m", pathXZ = "path_xz"
    }

    public func scenePath(quality: String) -> String { scene.replacingOccurrences(of: "{quality}", with: quality) }
}

/// Lage des Boots auf der Strecke zu einer geruderten Distanz.
public struct TrackPose: Equatable, Sendable {
    /// Szenenkoordinaten (Meter), y = 0 ist die Wasseroberfläche
    public var x: Double
    public var z: Double
    /// Fahrtrichtung als Winkel um die y-Achse (rad); 0 = Blick in −z (Norden), positiv = gegen den Uhrzeigersinn
    public var heading: Double
    /// 0 = Hinfahrt, 1 = Rückfahrt
    public var leg: Int
    /// 0…1 über die ganze Strecke
    public var progress: Double
    public var remaining: Double
    public var finished: Bool
}

/// Rechnet geruderte Distanz in Position und Richtung auf der Strecke um (hin, Wende, zurück).
/// Auf der Rückfahrt liegt die Bahn `returnOffset` Meter seitlich versetzt; in der Wende wird weich übergeblendet.
public struct CourseTrack: Sendable {
    public let course: Course
    public let returnOffset: Double
    public let turnBlend: Double
    private let pts: [(x: Double, z: Double)]
    private let cum: [Double]

    public init(course: Course, returnOffset: Double = 12, turnBlend: Double = 40) {
        self.course = course
        self.returnOffset = returnOffset
        self.turnBlend = turnBlend
        let p = course.pathXZ.map { (x: $0[0], z: $0[1]) }
        var c: [Double] = [0]
        for i in 1..<max(p.count, 1) {
            c.append(c[i - 1] + hypot(p[i].x - p[i - 1].x, p[i].z - p[i - 1].z))
        }
        pts = p
        cum = c
    }

    public var oneWayLength: Double { cum.last ?? 0 }
    public var totalLength: Double { 2 * oneWayLength }

    /// Punkt und Tangente auf der Hinfahrtlinie bei Bogenlänge s
    private func sample(_ s: Double) -> (x: Double, z: Double, dx: Double, dz: Double) {
        guard pts.count >= 2 else { return (pts.first?.x ?? 0, pts.first?.z ?? 0, 0, -1) }
        let s = min(max(s, 0), oneWayLength)
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] <= s { lo = mid } else { hi = mid }
        }
        let seg = cum[hi] - cum[lo]
        let t = seg > 0 ? (s - cum[lo]) / seg : 0
        let a = pts[lo], b = pts[hi]
        let dx = b.x - a.x, dz = b.z - a.z
        let len = max(hypot(dx, dz), 1e-9)
        return (a.x + dx * t, a.z + dz * t, dx / len, dz / len)
    }

    /// Position ohne Richtung: Hinfahrt auf der Linie, Rückfahrt rechts versetzt, Versatz mit Smoothstep
    /// über ±turnBlend um die Wende eingeblendet (ergibt eine weiche Kehre).
    public func position(atDistance d: Double) -> (x: Double, z: Double) {
        let L = oneWayLength, total = totalLength
        let dd = min(max(d, 0), total)
        let s = dd <= L ? dd : total - dd
        let p = sample(s)
        // Anteil des Versatzes: 0 bis (L − blend), steigt bis (L + blend) auf 1
        let t = min(max((dd - (L - turnBlend)) / (2 * turnBlend), 0), 1)
        let w = t * t * (3 - 2 * t)
        // "rechts" relativ zur Hinfahrt = links relativ zur Rückfahrt; Rückfahrt soll rechts in ihrer
        // Fahrtrichtung liegen, also links der Hinfahrt: Normale (dz, −dx) bei x = Ost, z = −Nord
        let nx = p.dz, nz = -p.dx
        return (p.x + nx * returnOffset * w, p.z + nz * returnOffset * w)
    }

    public func pose(atDistance d: Double) -> TrackPose {
        let total = totalLength
        let dd = min(max(d, 0), total)
        let a = position(atDistance: max(dd - 1.5, 0))
        let b = position(atDistance: min(dd + 1.5, total))
        let p = position(atDistance: dd)
        var dx = b.x - a.x, dz = b.z - a.z
        if hypot(dx, dz) < 1e-6 { dx = 0; dz = -1 }
        // heading 0 = Blick nach −z; RealityKit-Drehung um +y
        let heading = atan2(-dx, -dz)
        return TrackPose(x: p.x, z: p.z, heading: heading, leg: dd <= oneWayLength ? 0 : 1,
                         progress: total > 0 ? dd / total : 0, remaining: max(total - dd, 0),
                         finished: total > 0 && dd >= total)
    }
}
