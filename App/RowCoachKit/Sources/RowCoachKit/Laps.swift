import Foundation

/// Runden: Ist ein Training länger als die Strecke, geht es nach der Rückfahrt in einer weiteren Runde weiter.
public enum Laps {
    /// Distanz der Fahrt → (Runde ab 0, Distanz in der Runde). Genau auf einer Rundengrenze beginnt die neue Runde.
    public static func split(distance: Double, lapLength: Double) -> (lap: Int, distanceInLap: Double) {
        guard distance.isFinite, distance > 0 else { return (0, 0) }
        guard lapLength > 0, lapLength.isFinite else { return (0, distance) }
        let lap = Int((distance / lapLength).rounded(.down))
        let inLap = distance - Double(lap) * lapLength
        return (lap, min(max(inLap, 0), lapLength))
    }
}

/// Lage auf der Strecke mit Runde
public struct LapPose: Equatable, Sendable {
    /// Position und Richtung; `progress`, `remaining` und `leg` beziehen sich auf die aktuelle Runde,
    /// `finished` ist immer false (das Ende bestimmt das Training)
    public var pose: TrackPose
    /// Runde ab 0
    public var lap: Int
    public var distanceInLap: Double

    public init(pose: TrackPose, lap: Int, distanceInLap: Double) {
        self.pose = pose
        self.lap = lap
        self.distanceInLap = distanceInLap
    }
}

/// Pose über mehrere Runden auf Basis von `CourseTrack` (der selbst unverändert bleibt).
///
/// Nach der Rückfahrt kommt man versetzt (`returnOffset`) und mit der Gegenrichtung am Start an. Damit die Szene
/// nicht springt, fährt das Boot dort eine zweite Wende: dieselbe „Birnenkehre“ wie am Wendepunkt (gleicher
/// Radius, gleiche Länge), von der Rückfahrtlinie zurück auf die Hinfahrtlinie. Sie liegt symmetrisch um die
/// Rundengrenze: die letzten `turnHalf` Meter einer Runde und die ersten `turnHalf` Meter der nächsten.
/// Position und Richtung sind dabei stetig.
///
/// - `endDistance`: Ist das Ende des Trainings bekannt (reine Distanzprogramme) und liegt es in dieser Runde,
///   fährt das Boot ohne Startwende gerade ins Ziel; liegt es in der Wende am Ende der Hinfahrt (z. B. 2000 m auf
///   einer 2000-m-Strecke), ohne diese Wende. Ohne Angabe wird an jedem Rundenende gewendet.
/// - Strecken ohne Wende (`turns == 0`) nach `Course.resolvedEndBehavior`:
///   - turn: wie eine Strecke mit Wende (`Course.withReturnLeg`): am Ziel die Birnenkehre (Radius
///     `turnRadiusM`), zurück auf der Rückfahrtlinie (`returnOffsetM`, 0 = dieselbe Linie), am Start die Startkehre.
///     Eine Runde = hin und zurück (`lapLength` = 2 × Strecke), `track` ist die Fassung mit Rückfahrt.
///   - loop: jede Runde schliesst an (Rundkurs); liegen Ziel und Start nicht genau aufeinander, wird die Lücke über
///     die letzten `loopBlend` m der Runde stetig überblendet.
///   - fade: jede Runde beginnt wieder am Start; um die Rundengrenze blendet die Szene aus und ein
///     (`fadeOpacity`), der Sprung geschieht im Dunkeln.
public struct LapTrack: Sendable {
    public let track: CourseTrack
    public let endDistance: Double?
    /// halbe Länge der Startwende (m Ruderdistanz)
    public let turnHalf: Double
    /// Verhalten am Rundenende (Strecken mit Wende und Einweg mit Kehre: turn)
    public let endBehavior: Course.EndBehavior

    /// halbe Länge des Aus- und Einblendens bei fade (m Ruderdistanz)
    public static let fadeHalf = 12.0

    private let loops: Bool
    private let radius: Double
    private let alpha: Double
    /// Beginn der Startwende auf der Rückfahrtlinie und Fahrtrichtung dort
    private let startX: Double, startZ: Double
    private let tx: Double, tz: Double
    /// Richtung zur Hinfahrtlinie (Einheitsvektor)
    private let nx: Double, nz: Double
    /// loop mit Lücke: Versatz Ziel → Start und Richtungsunterschied, Länge der Überblendung
    private let gapX: Double, gapZ: Double, gapHeading: Double
    public let loopBlend: Double

    public var lapLength: Double { track.totalLength }

    public init(track base: CourseTrack, endDistance: Double? = nil) {
        let behavior = base.course.resolvedEndBehavior
        endBehavior = behavior
        let track: CourseTrack
        if base.course.turns == 0 && behavior == .turn {
            track = CourseTrack(course: base.course.withReturnLeg, returnOffset: base.returnOffset,
                                turnBlend: base.turnBlend)
        } else {
            track = base
        }
        self.track = track
        self.endDistance = endDistance.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        let L = track.oneWayLength
        let R = track.turnRadius
        let a = track.turnAngle
        radius = R
        alpha = a
        let half = track.turnHalfLength
        let canLoop = track.course.turns > 0 && R > 0 && half > 0 && L >= 2 * half && track.totalLength > 0
        loops = canLoop
        turnHalf = canLoop ? half : 0
        let p = track.pose(atDistance: track.totalLength - (canLoop ? half : 0))
        startX = p.x
        startZ = p.z
        let dx = -sin(p.heading), dz = -cos(p.heading)
        tx = dx
        tz = dz
        // wie in CourseTrack: Normale zur Seite, auf die gewendet wird (bei positivem Versatz links)
        let sign: Double = track.returnOffset < 0 ? -1 : 1
        nx = dz * sign
        nz = -dx * sign
        if track.course.turns == 0 && behavior == .loop && L > 0 {
            let s0 = track.pose(atDistance: 0), s1 = track.pose(atDistance: L)
            gapX = s0.x - s1.x
            gapZ = s0.z - s1.z
            gapHeading = atan2(sin(s0.heading - s1.heading), cos(s0.heading - s1.heading))
            loopBlend = hypot(gapX, gapZ) > 0.05 || abs(gapHeading) > 1e-3 ? min(60, L / 4) : 0
        } else {
            gapX = 0
            gapZ = 0
            gapHeading = 0
            loopBlend = 0
        }
    }

    public init(course: Course, endDistance: Double? = nil) {
        self.init(track: CourseTrack(course: course), endDistance: endDistance)
    }

    /// Strecke ohne Wende, die am Ziel ausblendet (`fade`)
    public var fades: Bool { track.course.turns == 0 && endBehavior == .fade }

    public func pose(atDistance d: Double) -> TrackPose { lapPose(atDistance: d).pose }

    public func lapPose(atDistance d: Double) -> LapPose {
        let L2 = lapLength
        let (lap, s) = Laps.split(distance: d, lapLength: L2)
        if loops {
            if lap >= 1 && s < turnHalf {
                return LapPose(pose: startTurn(q: turnHalf + s, lap: lap, s: s), lap: lap, distanceInLap: s)
            }
            if s > L2 - turnHalf && turnsAfter(lap: lap) {
                return LapPose(pose: startTurn(q: s - (L2 - turnHalf), lap: lap, s: s), lap: lap, distanceInLap: s)
            }
            let L = track.oneWayLength
            if s > L - turnHalf, s < L + turnHalf, endsInOuterTurn(lap: lap) {
                return LapPose(pose: straightOn(s: s), lap: lap, distanceInLap: s)
            }
        }
        var p = track.pose(atDistance: s)
        p.finished = false
        if loopBlend > 0, s > L2 - loopBlend {
            // Rundkurs mit Lücke: stetig auf den Start der nächsten Runde zu
            let u = (s - (L2 - loopBlend)) / loopBlend
            let w = u * u * (3 - 2 * u)
            p.x += gapX * w
            p.z += gapZ * w
            p.heading += gapHeading * w
        }
        return LapPose(pose: p, lap: lap, distanceInLap: s)
    }

    /// Deckkraft des Ausblendens (0 = klar, 1 = schwarz) bei Distanz d; nur `fade`, sonst immer 0.
    /// Um jede Rundengrenze, an der es weitergeht: in den letzten `fadeHalf` m aus, in den ersten wieder ein.
    public func fadeOpacity(atDistance d: Double) -> Double {
        guard fades, lapLength > 0 else { return 0 }
        let h = Self.fadeHalf
        let (lap, s) = Laps.split(distance: d, lapLength: lapLength)
        var x: Double?
        if lap >= 1 && s < h { x = s / h }
        if s > lapLength - h && turnsAfter(lap: lap) { x = (lapLength - s) / h }
        guard let x else { return 0 }
        // 2 m ganz dunkel, dann weich
        let u = min(max((x * h - 2) / (h - 2), 0), 1)
        return 1 - u * u * (3 - 2 * u)
    }

    /// Wendet das Boot am Ende der Runde `lap` (beginnt eine weitere Runde)?
    private func turnsAfter(lap: Int) -> Bool {
        guard let end = endDistance else { return true }
        return end > Double(lap + 1) * lapLength + 1e-6
    }

    /// Endet das Training in der Wende am Ende der Hinfahrt dieser Runde? Dann geradeaus ins Ziel.
    private func endsInOuterTurn(lap: Int) -> Bool {
        guard let end = endDistance else { return false }
        let e = end - Double(lap) * lapLength
        let L = track.oneWayLength
        return e > L - turnHalf + 1e-6 && e < L + turnHalf - 1e-6
    }

    /// Ohne Wende gerade weiter: auf der Hinfahrtlinie bis L, danach in derselben Richtung (das Training endet hier)
    private func straightOn(s: Double) -> TrackPose {
        let L = track.oneWayLength, L2 = lapLength
        var p: TrackPose
        if s <= L {
            p = track.outbound(atDistance: s)
        } else {
            let e = track.outbound(atDistance: L)
            let over = s - L
            p = TrackPose(x: e.x - sin(e.heading) * over, z: e.z - cos(e.heading) * over, heading: e.heading, leg: 0,
                          progress: 0, remaining: 0, finished: false)
        }
        p.leg = 0
        p.progress = L2 > 0 ? s / L2 : 0
        p.remaining = max(L2 - s, 0)
        p.finished = false
        return p
    }

    /// Pose in der Startwende; q = 0…2·turnHalf Meter ab Wendebeginn auf der Rückfahrtlinie.
    private func startTurn(q rowQ: Double, lap: Int, s: Double) -> TrackPose {
        let R = radius, al = alpha
        let arcLen = R * (Double.pi + 4 * al)
        let q = min(max(rowQ, 0), 2 * turnHalf) / (2 * turnHalf) * arcLen
        let a: Double, l: Double, psi: Double
        if q <= R * al {
            let phi = q / R
            psi = -phi
            a = R * sin(phi); l = -R + R * cos(phi)
        } else if q <= R * (Double.pi + 3 * al) {
            psi = -al + (q - R * al) / R
            let cx = 2 * R * sin(al), cl = R * (2 * cos(al) - 1)
            a = cx + R * sin(psi); l = cl - R * cos(psi)
        } else {
            psi = Double.pi + al - (q - R * (Double.pi + 3 * al)) / R
            let cl = R * (4 * cos(al) - 1)
            a = -R * sin(psi); l = cl + R * cos(psi)
        }
        let x = startX + a * tx + l * nx
        let z = startZ + a * tz + l * nz
        let dx = cos(psi) * tx + sin(psi) * nx
        let dz = cos(psi) * tz + sin(psi) * nz
        let L2 = lapLength
        return TrackPose(x: x, z: z, heading: atan2(-dx, -dz), leg: rowQ < turnHalf ? 1 : 0,
                         progress: L2 > 0 ? s / L2 : 0, remaining: max(L2 - s, 0), finished: false)
    }
}
