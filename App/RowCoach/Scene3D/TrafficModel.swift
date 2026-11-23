import Foundation
import QuartzCore
import RowCoachKit

/// Einstellungen für „Leben auf dem Wasser“ (Einstellungen → Rudern)
enum TrafficSettings {
    /// Andere Boote auf dem Wasser (Standard an)
    static let enabledKey = "traffic.enabled"
    /// Dichte: "low" (wenig) oder "normal"
    static let densityKey = "traffic.density"

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Dichte aus den Einstellungen; Startargument `-demoTraffic dense` (bzw. `low`, `normal`) hat Vorrang und
    /// schaltet den Verkehr auch ein, wenn er in den Einstellungen aus ist (für Screenshots).
    static var density: TrafficDensity? {
        if let demo = UserDefaults.standard.string(forKey: "demoTraffic"), let d = TrafficDensity(rawValue: demo) {
            return d
        }
        guard enabled else { return nil }
        return TrafficDensity(rawValue: UserDefaults.standard.string(forKey: densityKey) ?? "") ?? .normal
    }

    /// Fester Startwert bei `-demoTraffic`, damit Screenshots reproduzierbar sind
    static var demoSeed: UInt64? { UserDefaults.standard.string(forKey: "demoTraffic") != nil ? 2026 : nil }
}

/// Verkehr einer Fahrt: virtuelle Ruderer und Schiffe (Planung in RowCoachKit). Wird je Fahrt neu angelegt
/// (`RowingView`), bekommt von dort Distanz und Ruderzeit und wird pro Bild von der Szene (`TrafficSystem`)
/// fortgeschrieben. Der Navigator liest die zuletzt berechneten Zustände.
@MainActor
final class TrafficModel {
    let course: Course
    let density: TrafficDensity
    let seed: UInt64

    private var rowers: VirtualRowers
    private var vessels: VesselTraffic
    private let startTime: CFTimeInterval
    private let lapLength: Double
    /// Bezugstempo, solange noch kein eigenes Durchschnittstempo vorliegt (m/s)
    private let referenceSpeed: Double

    private var distance = 0.0
    private var distanceTime: CFTimeInterval = 0
    private var averageSpeed = 0.0
    private var rowing = false
    private var lastPlan: CFTimeInterval = -1

    /// zuletzt berechnete Zustände (Szenenkoordinaten)
    private(set) var rowerStates: [RowerState] = []
    private(set) var vesselStates: [VesselState] = []

    /// nil, wenn der Verkehr ausgeschaltet ist
    static func make(course: Course, paceTarget: Double?, best2k: Double) -> TrafficModel? {
        guard let density = TrafficSettings.density else { return nil }
        let pace = paceTarget.flatMap { $0 > 0 ? $0 : nil } ?? PaceLine.defaultPace(best2k: best2k)
        let seed = TrafficSettings.demoSeed ?? UInt64(Date().timeIntervalSince1970 * 1000)
        return TrafficModel(course: course, density: density, seed: seed, referenceSpeed: 500 / pace)
    }

    init(course: Course, density: TrafficDensity, seed: UInt64, referenceSpeed: Double) {
        self.course = course
        self.density = density
        self.seed = seed
        self.referenceSpeed = referenceSpeed > 0 ? referenceSpeed : 3.8
        let track = CourseTrack(course: course)
        lapLength = track.totalLength
        rowers = VirtualRowers(course: course, density: density, seed: seed, track: track)
        vessels = VesselTraffic(course: course, density: density, seed: seed)
        startTime = CACurrentMediaTime()
    }

    /// Stand der Fahrt (aus der Session): geruderte Distanz, Ruderzeit, rudert gerade
    func observe(distance: Double, activeTime: TimeInterval, rowing: Bool) {
        self.distance = distance
        distanceTime = CACurrentMediaTime()
        self.rowing = rowing
        averageSpeed = activeTime > 30 && distance > 50 ? distance / activeTime : 0
    }

    /// Durchschnittstempo für die Tempi der anderen (m/s)
    private var ownSpeed: Double { averageSpeed > 0.8 ? averageSpeed : referenceSpeed }

    /// Pro Bild: Planung (2× pro Sekunde) und Zustände. `boatX/boatZ/heading` = angezeigtes eigenes Boot.
    func step(now: CFTimeInterval, boatX: Double, boatZ: Double, heading: Double) {
        let t = now - startTime
        // Distanz zwischen den Updates der Session vorausrechnen (nur beim Rudern)
        let extra = rowing ? min(max(now - distanceTime, 0), 1.0) * ownSpeed : 0
        let d = distance + extra
        let u = lapLength > 0 ? Laps.split(distance: d, lapLength: lapLength).distanceInLap : d
        let own = OwnBoat(u: u, x: boatX, z: boatZ, heading: heading, speed: ownSpeed)
        if t - lastPlan >= 0.5 || lastPlan < 0 {
            lastPlan = t
            rowers.update(time: t, own: own)
            vessels.update(time: t, own: own, rowers: rowers.trackPositions(at: t))
        }
        rowerStates = rowers.states(at: t, own: own)
        vesselStates = vessels.states(at: t)
    }
}
