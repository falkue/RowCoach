import Foundation
import os
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
        if UserDefaults.standard.bool(forKey: "demoTrafficAhead") { return .normal }
        guard enabled else { return nil }
        return TrafficDensity(rawValue: UserDefaults.standard.string(forKey: densityKey) ?? "") ?? .normal
    }

    /// Fester Startwert bei `-demoTraffic`, damit Screenshots reproduzierbar sind
    static var demoSeed: UInt64? {
        UserDefaults.standard.string(forKey: "demoTraffic") != nil || demoAhead ? 2026 : nil
    }

    /// Startargument `-demoTrafficAhead 1`: sofort ein Kursschiff ca. 150 m voraus (50 m seitlich) und ein Ruderer
    /// 30 m voraus auf der innersten Bahn, für Bildschirmfotos
    static var demoAhead: Bool { UserDefaults.standard.bool(forKey: "demoTrafficAhead") }
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

    /// Protokoll: subsystem com.falkue.RowCoach, Kategorie Traffic
    static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Traffic")
    private var knownRowers: [Int: Double] = [:]       // id → Abstand beim letzten Planen
    private var knownVessels: [Int: VesselKind] = [:]
    private var lastSummary: Double = 0
    private var demoPlaced = !TrafficSettings.demoAhead

    /// zuletzt berechnete Zustände (Szenenkoordinaten)
    private(set) var rowerStates: [RowerState] = []
    private(set) var vesselStates: [VesselState] = []

    /// nil, wenn der Verkehr ausgeschaltet ist
    static func make(course: Course, paceTarget: Double?, best2k: Double) -> TrafficModel? {
        guard let density = TrafficSettings.density else {
            log.info("Verkehr aus (Einstellung „Andere Boote auf dem Wasser“)")
            return nil
        }
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
        let kinds = vessels.kinds.map(\.rawValue).joined(separator: ", ")
        Self.log.info("Verkehr an: \(course.id, privacy: .public), Dichte \(density.rawValue, privacy: .public), \(self.rowers.lanes.count) Ruderer-Bahnen, \(self.vessels.paths.count) Schiffslinien, Schiffe: \(kinds, privacy: .public), Startwert \(seed)")
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
        if !demoPlaced && t >= 1 {
            demoPlaced = true
            rowers.placeAhead(time: t, own: own, ahead: 30)
            vessels.placeAhead(kind: .kursschiff, time: t, own: own, ahead: 150, lateral: 50)
            Self.log.info("Testbetrieb: Ruderer 30 m und Kursschiff 150 m voraus gesetzt (Boot bei \(Int(boatX)), \(Int(boatZ)))")
        }
        if t - lastPlan >= 0.5 || lastPlan < 0 {
            lastPlan = t
            rowers.update(time: t, own: own)
            vessels.update(time: t, own: own, rowers: rowers.trackPositions(at: t))
            rowerStates = rowers.states(at: t, own: own)
            vesselStates = vessels.states(at: t)
            logChanges(t: t, boatX: boatX, boatZ: boatZ, heading: heading)
        } else {
            rowerStates = rowers.states(at: t, own: own)
            vesselStates = vessels.states(at: t)
        }
    }

    /// Spawn und Abbau je Objekt, alle 30 s eine Zusammenfassung
    private func logChanges(t: Double, boatX: Double, boatZ: Double, heading: Double) {
        func bearing(_ x: Double, _ z: Double) -> Int {
            let fx = -sin(heading), fz = -cos(heading)
            let vx = x - boatX, vz = z - boatZ
            return Int(atan2(vx * fz - vz * fx, vx * fx + vz * fz) * 180 / .pi)
        }
        let rowerNow = Dictionary(uniqueKeysWithValues: rowerStates.map { ($0.id, $0.distance) })
        for r in rowerStates where knownRowers[r.id] == nil {
            let b = bearing(r.x, r.z), id = r.id, d = Int(r.distance)
            Self.log.info("Ruderer \(id) erscheint in \(d) m, Peilung \(b)° (0 = voraus, + = links; t = \(Int(t)) s)")
        }
        for (id, d) in knownRowers where rowerNow[id] == nil {
            Self.log.info("Ruderer \(id) verschwindet (zuletzt \(Int(d)) m, t = \(Int(t)) s)")
        }
        knownRowers = rowerNow
        let vesselNow = Dictionary(uniqueKeysWithValues: vesselStates.map { ($0.id, $0.kind) })
        for s in vesselStates where knownVessels[s.id] == nil {
            let d = Int(hypot(s.x - boatX, s.z - boatZ)), b = bearing(s.x, s.z), id = s.id, kind = s.kind.rawValue
            Self.log.info("Schiff \(id) (\(kind, privacy: .public)) fährt los, \(d) m entfernt, Peilung \(b)° (t = \(Int(t)) s)")
        }
        for (id, kind) in knownVessels where vesselNow[id] == nil {
            Self.log.info("Schiff \(id) (\(kind.rawValue, privacy: .public)) am Ziel (t = \(Int(t)) s)")
        }
        knownVessels = vesselNow
        if t - lastSummary >= 30 {
            lastSummary = t
            // im Blickfeld: voraus und höchstens 40° seitlich (Kamera 55° hoch, quer ca. ±35°)
            let fx = -sin(heading), fz = -cos(heading)
            func inView(_ x: Double, _ z: Double) -> Bool {
                let vx = x - boatX, vz = z - boatZ
                let along = vx * fx + vz * fz, left = vx * fz - vz * fx
                return along > 0 && abs(atan2(left, along)) < 40 * .pi / 180
            }
            let rowersInRange = rowerStates.filter { $0.distance < VirtualRowers.visibleRange }
            let vesselsInRange = vesselStates.filter { hypot($0.x - boatX, $0.z - boatZ) < 4000 }
            let rv = rowersInRange.filter { inView($0.x, $0.z) }.count
            let vv = vesselsInRange.filter { inView($0.x, $0.z) }.count
            Self.log.info("In Reichweite \(rowersInRange.count) Ruderer (≤ 450 m) und \(vesselsInRange.count) Schiffe (≤ 4 km), davon im Blickfeld \(rv) bzw. \(vv); im Spiel \(self.rowerStates.count) Ruderer, \(self.vesselStates.count) Schiffe; t = \(Int(t)) s")
        }
    }
}
