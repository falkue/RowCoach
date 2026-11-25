import Foundation
import QuartzCore
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Leben auf dem Wasser in der 3D-Szene: andere Ruderer (`BoatRig` in anderen Trikotfarben, im eigenen Takt) und
/// Schiffe (`VesselModels`). Planung und Lage kommen aus `TrafficModel` (RowCoachKit); hier wird nur angezeigt.
///
/// Robust für das Gerät (iPad A12X, 24.11.2026: Boote, die erst nach dem Laden der Landschaft angelegt und mit
/// `OpacityComponent` eingeblendet wurden, waren dort unsichtbar, im Simulator sichtbar):
/// - Alle Instanzen liegen in einem Vorrat, der beim Setzen des Modells angelegt wird, also vor dem Laden der
///   Landschaft: je Trikotfarbe ein Ruderer (12), je Schiffsart des Gewässers 2–3 Schiffe.
/// - Die Instanzen bleiben immer aktiv (`isEnabled` wird nicht umgeschaltet). Unbenutzte parken 400 m unter dem
///   eigenen Boot (ausserhalb des Blickfelds, unter Wasser).
/// - Keine Transparenz: Gezeichnete Ruderer liegen immer auf der Wasserlinie; nur zwischen 400 und 450 m Entfernung
///   sinken sie weich ab. Schiffe sinken auf den ersten und letzten 60 m ihrer Linie ab bzw. tauchen auf.
/// - Ruderer: höchstens 8 gezeichnet (die nächsten innerhalb von 450 m), ohne Schatten, Ruderbewegung im eigenen Takt;
///   alle übrigen rudern weiter und bleiben im Navigator sichtbar. Je Trikotfarbe (12) eine Instanz im Vorrat.
/// - Schiffe: ab 4 km Entfernung geparkt.
/// - `-demoTrafficPlain 1`: rote Quader mit `SimpleMaterial` statt Booten (zum Ausschliessen von Material und Mesh).
/// - `RowingSceneController` hängt `root` einmal ein und ruft `step` pro Bild auf.
@MainActor
final class TrafficSystem {
    let root = Entity()
    var model: TrafficModel? {
        didSet {
            if model !== oldValue {
                releaseAll()
                if let model { buildPool(kinds: model.vesselKinds) }
                TrafficModel.log.info("Szene: Verkehr \(self.model == nil ? "aus" : "an", privacy: .public), Vorrat \(self.rowerSlots.count) Ruderer, \(self.vesselSlots.count) Schiffe, einfache Quader \(self.plain)")
            }
        }
    }

    /// Trikot, Blätter und Rumpf der anderen Ruderer (Index = `RowerState.colorIndex`)
    static let palette: [BoatRig.Colors] = [
        .init(shirt: UIColor(red: 0.80, green: 0.12, blue: 0.14, alpha: 1),   // rot, weisse Blätter
              blade: UIColor(white: 0.95, alpha: 1), hull: UIColor(white: 0.93, alpha: 1)),
        .init(shirt: UIColor(red: 0.10, green: 0.52, blue: 0.30, alpha: 1),   // grün, grüne Blätter
              blade: UIColor(red: 0.12, green: 0.60, blue: 0.32, alpha: 1), hull: UIColor(white: 0.93, alpha: 1)),
        .init(shirt: UIColor(white: 0.96, alpha: 1),                           // weiss, rote Blätter, gelber Rumpf
              blade: UIColor(red: 0.82, green: 0.12, blue: 0.12, alpha: 1),
              hull: UIColor(red: 0.95, green: 0.82, blue: 0.30, alpha: 1)),
        .init(shirt: UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1),   // orange, schwarze Blätter
              blade: UIColor(white: 0.10, alpha: 1), hull: UIColor(white: 0.93, alpha: 1)),
        .init(shirt: UIColor(red: 0.45, green: 0.20, blue: 0.55, alpha: 1),   // violett, weisse Blätter
              blade: UIColor(white: 0.95, alpha: 1), hull: UIColor(white: 0.93, alpha: 1)),
        .init(shirt: UIColor(red: 0.20, green: 0.65, blue: 0.85, alpha: 1),   // hellblau, blaue Blätter
              blade: UIColor(red: 0.10, green: 0.30, blue: 0.70, alpha: 1),
              hull: UIColor(red: 0.85, green: 0.86, blue: 0.88, alpha: 1)),
        .init(shirt: UIColor(red: 0.95, green: 0.85, blue: 0.15, alpha: 1),   // gelb, blaue Blätter
              blade: UIColor(red: 0.12, green: 0.25, blue: 0.60, alpha: 1), hull: UIColor(white: 0.93, alpha: 1)),
        .init(shirt: UIColor(white: 0.12, alpha: 1),                           // schwarz, gelbe Blätter
              blade: UIColor(red: 0.95, green: 0.80, blue: 0.10, alpha: 1), hull: UIColor(white: 0.93, alpha: 1)),
        .init(shirt: UIColor(red: 0.90, green: 0.40, blue: 0.60, alpha: 1),   // pink, weisse Blätter
              blade: UIColor(white: 0.95, alpha: 1), hull: UIColor(white: 0.93, alpha: 1)),
        .init(shirt: UIColor(red: 0.15, green: 0.35, blue: 0.20, alpha: 1),   // dunkelgrün, rote Blätter, roter Rumpf
              blade: UIColor(red: 0.80, green: 0.15, blue: 0.12, alpha: 1),
              hull: UIColor(red: 0.75, green: 0.18, blue: 0.14, alpha: 1)),
        .init(shirt: UIColor(red: 0.55, green: 0.10, blue: 0.15, alpha: 1),   // weinrot, weisse Blätter
              blade: UIColor(white: 0.95, alpha: 1), hull: UIColor(white: 0.93, alpha: 1)),
        .init(shirt: UIColor(red: 0.30, green: 0.30, blue: 0.75, alpha: 1),   // blau, orange Blätter
              blade: UIColor(red: 0.95, green: 0.50, blue: 0.10, alpha: 1),
              hull: UIColor(red: 0.80, green: 0.88, blue: 0.95, alpha: 1)),
    ]

    /// höchstens so viele Ruderer gleichzeitig gezeichnet (A12X); die übrigen rudern weiter und stehen im Navigator
    static let maxVisibleRowers = 8
    private static let vesselHideDistance = 4000.0
    private static let parkDepth: Float = 400

    /// Eine Instanz im Vorrat: Ruderer (mit BoatRig) oder Schiff
    private final class Slot {
        let root: Entity
        let rig: BoatRig?
        let kind: VesselKind?
        var owner: Int?
        init(root: Entity, rig: BoatRig?, kind: VesselKind?) {
            self.root = root
            self.rig = rig
            self.kind = kind
        }
    }

    private var rowerSlots: [Int: Slot] = [:]           // je Trikotfarbe
    private var vesselSlots: [Slot] = []
    private var lastDiagnosis: CFTimeInterval = 0
    /// ab dieser Entfernung sinken Ruderer langsam unter die Wasserfläche (bis 450 m ganz)
    private static let sinkStart = 400.0
    /// `-demoTrafficPlain 1`: rote Quader statt Booten
    let plain = UserDefaults.standard.bool(forKey: "demoTrafficPlain")

    init() {
        root.name = "traffic"
    }

    // MARK: - Vorrat

    private func buildPool(kinds: [VesselKind]) {
        for color in Self.palette.indices where rowerSlots[color] == nil {
            rowerSlots[color] = makeRowerSlot(color)
        }
        for kind in kinds {
            let have = vesselSlots.filter { $0.kind == kind }.count
            // Segelboote: bis zu 8 zugleich (Segelrevier, z. B. Außenalster)
            let want = kind == .segelboot ? 8 : (kind.isLarge ? 2 : 3)
            for _ in have..<max(want, have) { vesselSlots.append(makeVesselSlot(kind)) }
        }
    }

    private func makeRowerSlot(_ color: Int) -> Slot {
        let slot: Slot
        if plain {
            slot = Slot(root: Self.plainBox(size: [1.2, 1.2, 8]), rig: nil, kind: nil)
        } else {
            let rig = BoatRig(colors: Self.palette[color])
            Self.disableShadows(rig.root)
            slot = Slot(root: rig.root, rig: rig, kind: nil)
        }
        slot.root.name = "rower-\(color)"
        slot.root.position = [0, -Self.parkDepth, 0]
        root.addChild(slot.root)
        return slot
    }

    private func makeVesselSlot(_ kind: VesselKind) -> Slot {
        let e = plain ? Self.plainBox(size: [Float(kind.length) / 6, 3, Float(kind.length)]) : VesselModels.make(kind)
        e.name = "vessel-\(kind.rawValue)"
        e.position = [0, -Self.parkDepth, 0]
        root.addChild(e)
        return Slot(root: e, rig: nil, kind: kind)
    }

    private static func plainBox(size: SIMD3<Float>) -> Entity {
        let e = ModelEntity(mesh: .generateBox(size: size), materials: [SimpleMaterial(color: .red, isMetallic: false)])
        e.components.set(DynamicLightShadowComponent(castsShadow: false))
        return e
    }

    private func releaseAll() {
        for slot in rowerSlots.values {
            slot.owner = nil
            slot.root.position = [0, -Self.parkDepth, 0]
        }
        for slot in vesselSlots {
            slot.owner = nil
            slot.root.position = [0, -Self.parkDepth, 0]
        }
    }

    // MARK: - Pro Bild

    /// Pro Bild: Lage aller anderen Boote setzen. `boatX`, `boatZ`, `heading` = angezeigtes eigenes Boot.
    func step(now: CFTimeInterval, boatX: Double, boatZ: Double, heading: Double) {
        guard let model else { return }
        model.step(now: now, boatX: boatX, boatZ: boatZ, heading: heading)
        let park = SIMD3<Float>(Float(boatX), -Self.parkDepth, Float(boatZ))
        updateRowers(model.rowerStates, now: now, park: park)
        updateVessels(model.vesselStates, boatX: boatX, boatZ: boatZ, park: park)
        if now - lastDiagnosis >= 30 {
            lastDiagnosis = now
            diagnose(boatX: boatX, boatZ: boatZ, heading: heading)
            logNearestRowers(boatX: boatX, boatZ: boatZ, heading: heading)
        }
    }

    // MARK: - Ruderer

    private func updateRowers(_ states: [RowerState], now: CFTimeInterval, park: SIMD3<Float>) {
        let visible = states
            .filter { $0.distance < VirtualRowers.visibleRange }
            .sorted { $0.distance < $1.distance }
            .prefix(Self.maxVisibleRowers)
        var used = Set<Int>()
        for s in visible {
            let color = ((s.colorIndex % Self.palette.count) + Self.palette.count) % Self.palette.count
            guard !used.contains(color) else { continue }
            let slot = rowerSlots[color] ?? {
                let made = makeRowerSlot(color)
                rowerSlots[color] = made
                TrafficModel.log.info("Szene: Ruderer-Instanz \(color) nachträglich angelegt")
                return made
            }()
            used.insert(color)
            slot.owner = s.id
            // Gezeichnete Ruderer liegen auf der Wasserlinie (y = 0). Nur ganz weit weg (400–450 m) sinken sie weich
            // unter die Wasserfläche, statt zu verschwinden – abhängig von der Entfernung, nicht von der Zeit.
            let sink = Float(min(max((s.distance - Self.sinkStart) / (VirtualRowers.visibleRange - Self.sinkStart), 0), 1))
            slot.root.position = [Float(s.x), -2.5 * sink, Float(s.z)]
            slot.root.orientation = simd_quatf(angle: Float(s.heading), axis: [0, 1, 0])
            slot.rig?.apply(.at(phase: s.strokePhase, strokeRate: s.strokeRate))
        }
        for (color, slot) in rowerSlots where !used.contains(color) {
            slot.owner = nil
            slot.root.position = park
        }
    }

    // MARK: - Schiffe

    private func updateVessels(_ states: [VesselState], boatX: Double, boatZ: Double, park: SIMD3<Float>) {
        let alive = Set(states.map(\.id))
        for slot in vesselSlots where slot.owner.map({ !alive.contains($0) }) ?? false { slot.owner = nil }
        for s in states {
            let slot: Slot
            if let owned = vesselSlots.first(where: { $0.owner == s.id }) {
                slot = owned
            } else if let free = vesselSlots.first(where: { $0.owner == nil && $0.kind == s.kind }) {
                slot = free
            } else {
                slot = makeVesselSlot(s.kind)
                vesselSlots.append(slot)
                TrafficModel.log.info("Szene: Schiffs-Instanz \(s.kind.rawValue, privacy: .public) nachträglich angelegt")
            }
            slot.owner = s.id
            if hypot(s.x - boatX, s.z - boatZ) > Self.vesselHideDistance {
                slot.root.position = park
                continue
            }
            // an den Linienenden auftauchen bzw. absinken (statt Transparenz)
            let sink = Float(1 - s.fade) * (Self.height(s.kind) + 1)
            slot.root.position = [Float(s.x), -sink, Float(s.z)]
            slot.root.orientation = simd_quatf(angle: Float(s.heading), axis: [0, 1, 0])
        }
        for slot in vesselSlots where slot.owner == nil { slot.root.position = park }
    }

    /// Höhe über der Wasserlinie (m), zum Absinken an den Linienenden
    private static func height(_ kind: VesselKind) -> Float {
        switch kind {
        case .segelboot: return 12
        case .raddampfer: return 11
        case .kursschiff: return 8
        case .alsterdampfer: return 5
        case .rheinschiff: return 7
        default: return 3
        }
    }

    // MARK: - Diagnose

    /// Protokoll alle 30 s: die 3 nächsten gezeichneten Ruderer (Entfernung, Peilung, y, isEnabled).
    /// Peilung in Grad relativ zur Fahrtrichtung: 0 = voraus, positiv = links, negativ = rechts, ±180 = hinten.
    private func logNearestRowers(boatX: Double, boatZ: Double, heading: Double) {
        let fx = -sin(heading), fz = -cos(heading)
        let drawn = rowerSlots.values.filter { $0.owner != nil }.map { slot -> (Double, String) in
            let p = slot.root.position(relativeTo: nil)
            let vx = Double(p.x) - boatX, vz = Double(p.z) - boatZ
            let bearing = atan2(vx * fz - vz * fx, vx * fx + vz * fz) * 180 / .pi
            let d = hypot(vx, vz)
            return (d, "\(slot.root.name) \(Int(d)) m, Peilung \(Int(bearing))°, y \(String(format: "%.2f", p.y)), isEnabled \(slot.root.isEnabledInHierarchy)")
        }.sorted { $0.0 < $1.0 }.prefix(3).map(\.1)
        let text = drawn.isEmpty ? "keine" : drawn.joined(separator: "; ")
        TrafficModel.log.info("Szene: nächste gezeichnete Ruderer (Peilung 0 = voraus, + = links, − = rechts): \(text, privacy: .public)")
    }

    /// Protokoll alle 30 s: das nächste angezeigte Boot mit Entfernung, Peilung (Grad, 0 = voraus, positiv = links),
    /// Weltposition, isEnabled, Deckkraft (eigene und der Eltern), Materialien, Meshes und Grösse.
    private func diagnose(boatX: Double, boatZ: Double, heading: Double) {
        var entities: [(String, Entity)] = rowerSlots.compactMap { $0.value.owner == nil ? nil : ("Ruderer-Farbe \($0.key)", $0.value.root) }
        entities += vesselSlots.compactMap { $0.owner == nil ? nil : ("Schiff \($0.owner ?? 0) \($0.root.name)", $0.root) }
        let fx = -sin(heading), fz = -cos(heading)
        let log = TrafficModel.log
        let rootInScene = root.scene != nil
        let rootEnabled = root.isEnabledInHierarchy
        let rootOpacity = Double(root.components[OpacityComponent.self]?.opacity ?? 1)
        let candidates = entities.map { item -> (String, Entity, Double) in
            let p = item.1.position(relativeTo: nil)
            return (item.0, item.1, hypot(Double(p.x) - boatX, Double(p.z) - boatZ))
        }
        guard let nearest = candidates.min(by: { $0.2 < $1.2 }) else {
            log.info("Szene: kein Boot angezeigt (Wurzel in Szene \(rootInScene), aktiv \(rootEnabled), Deckkraft Wurzel \(rootOpacity), Vorrat \(self.rowerSlots.count) Ruderer, \(self.vesselSlots.count) Schiffe)")
            return
        }
        let (name, e, d) = nearest
        let p = e.position(relativeTo: nil)
        let vx = Double(p.x) - boatX, vz = Double(p.z) - boatZ
        let bearing = atan2(vx * fz - vz * fx, vx * fx + vz * fz) * 180 / .pi
        // Deckkraft auf dem Boot oder einem Elternteil
        var opacities: [String] = []
        var cursor: Entity? = e
        while let c = cursor {
            if let o = c.components[OpacityComponent.self] { opacities.append("\(c.name.isEmpty ? "?" : c.name)=\(o.opacity)") }
            cursor = c.parent
        }
        // Materialien und Meshes im Boot
        var models = 0, emptyMeshes = 0, materialTypes = Set<String>(), materialCount = 0, transparentChildren = 0
        func walk(_ x: Entity) {
            if let m = x.components[ModelComponent.self] {
                models += 1
                if m.mesh.bounds.extents == .zero { emptyMeshes += 1 }
                materialCount += m.materials.count
                for mat in m.materials { materialTypes.insert(String(describing: type(of: mat))) }
            }
            if x.components.has(OpacityComponent.self) { transparentChildren += 1 }
            for c in x.children { walk(c) }
        }
        walk(e)
        let modelCount = models, emptyCount = emptyMeshes, materialTotal = materialCount, opacityChildren = transparentChildren
        let size = e.visualBounds(relativeTo: nil).extents
        let types = materialTypes.sorted().joined(separator: ", ")
        let opacityText = opacities.isEmpty ? "keine" : opacities.joined(separator: ", ")
        log.info("Szene: nächstes Boot \(name, privacy: .public): \(Int(d)) m, Peilung \(Int(bearing))° (+ = links, − = rechts), Welt (\(Double(p.x)), \(Double(p.y)), \(Double(p.z))), isEnabled \(e.isEnabled), in Hierarchie aktiv \(e.isEnabledInHierarchy), OpacityComponent \(opacityText, privacy: .public), Kinder mit Opacity \(opacityChildren), Modelle \(modelCount) (leere Meshes \(emptyCount)), Materialien \(materialTotal): \(types, privacy: .public), Grösse \(Double(size.x)) × \(Double(size.y)) × \(Double(size.z)) m, Wurzel in Szene \(rootInScene), aktiv \(rootEnabled), Deckkraft Wurzel \(rootOpacity)")
    }

    // MARK: - Hilfen

    private static func disableShadows(_ e: Entity) {
        if e.components.has(ModelComponent.self) {
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
        }
        for child in e.children { disableShadows(child) }
    }
}
