import Foundation
import QuartzCore
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Leben auf dem Wasser in der 3D-Szene: andere Ruderer (`BoatRig` in anderen Trikotfarben, im eigenen Takt) und
/// Schiffe (`VesselModels`). Planung und Lage kommen aus `TrafficModel` (RowCoachKit); hier wird nur angezeigt.
///
/// - Ruderer: höchstens 4 sichtbar (die nächsten innerhalb von 450 m), zwischen 380 und 450 m weich ausgeblendet;
///   ohne Schatten. Je Farbe ein Boot, das erst bei Bedarf gebaut wird.
/// - Schiffe: je Fahrt ein Modell (Klon), an den Linienenden ein- und ausgeblendet, ab 4 km ausgeblendet.
/// - `RowingSceneController` hängt `root` einmal ein und ruft `step` pro Bild auf.
@MainActor
final class TrafficSystem {
    let root = Entity()
    var model: TrafficModel? {
        didSet {
            if model !== oldValue {
                clear()
                TrafficModel.log.info("Szene: Verkehr \(self.model == nil ? "aus" : "an", privacy: .public)")
            }
            root.isEnabled = model != nil
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
    ]

    static let maxVisibleRowers = 4
    private static let fadeStart = 380.0
    private static let vesselHideDistance = 4000.0

    private var rigs: [Int: BoatRig] = [:]              // je Farbe ein Boot
    private var vessels: [Int: Entity] = [:]           // je Fahrt ein Modell
    private var lastDiagnosis: CFTimeInterval = 0

    init() {
        root.name = "traffic"
        root.isEnabled = false
    }

    private func clear() {
        for rig in rigs.values { rig.root.isEnabled = false }
        for e in vessels.values { e.removeFromParent() }
        vessels.removeAll()
    }

    /// Pro Bild: Lage aller anderen Boote setzen. `boatX`, `boatZ`, `heading` = angezeigtes eigenes Boot.
    func step(now: CFTimeInterval, boatX: Double, boatZ: Double, heading: Double) {
        guard let model else { return }
        model.step(now: now, boatX: boatX, boatZ: boatZ, heading: heading)
        updateRowers(model.rowerStates)
        updateVessels(model.vesselStates, boatX: boatX, boatZ: boatZ)
        if now - lastDiagnosis >= 30 {
            lastDiagnosis = now
            diagnose(boatX: boatX, boatZ: boatZ, heading: heading)
        }
    }

    /// Protokoll alle 30 s: das nächste angezeigte Objekt mit Entfernung, Peilung (Grad, 0 = voraus, positiv =
    /// links), Weltposition, Höhe, isEnabled, Deckkraft, Grösse der Geometrie und ob es in der Szene hängt.
    private func diagnose(boatX: Double, boatZ: Double, heading: Double) {
        var entities: [(String, Entity)] = rigs.map { ("Ruderer-Farbe \($0.key)", $0.value.root) }
        entities += vessels.map { ("Schiff \($0.key) \($0.value.name)", $0.value) }
        let fx = -sin(heading), fz = -cos(heading)
        let candidates = entities.filter { $0.1.isEnabled }.map { item -> (String, Entity, Double) in
            let p = item.1.position(relativeTo: nil)
            return (item.0, item.1, hypot(Double(p.x) - boatX, Double(p.z) - boatZ))
        }
        let log = TrafficModel.log
        let rootInScene = root.scene != nil
        let rootEnabled = root.isEnabledInHierarchy
        guard let nearest = candidates.min(by: { $0.2 < $1.2 }) else {
            log.info("Szene: kein Boot angezeigt (Wurzel in Szene: \(rootInScene), aktiv: \(rootEnabled), Ruderer-Boote \(self.rigs.count), Schiffe \(self.vessels.count))")
            return
        }
        let (name, e, d) = nearest
        let p = e.position(relativeTo: nil)
        let vx = Double(p.x) - boatX, vz = Double(p.z) - boatZ
        let along = vx * fx + vz * fz
        let left = vx * fz - vz * fx
        let bearing = atan2(left, along) * 180 / .pi
        let opacity = e.components[OpacityComponent.self]?.opacity ?? 1
        let b = e.visualBounds(relativeTo: nil)
        let size = b.extents
        log.info("Szene: nächstes Boot \(name, privacy: .public): \(Int(d)) m, Peilung \(Int(bearing))°, Welt (\(Double(p.x)), \(Double(p.y)), \(Double(p.z))), isEnabled \(e.isEnabled), in Hierarchie aktiv \(e.isEnabledInHierarchy), Deckkraft \(Double(opacity)), Grösse \(Double(size.x)) × \(Double(size.y)) × \(Double(size.z)) m, Wurzel in Szene \(rootInScene), aktiv \(rootEnabled)")
    }

    // MARK: - Ruderer

    private func updateRowers(_ states: [RowerState]) {
        let visible = states
            .filter { $0.distance < VirtualRowers.visibleRange }
            .sorted { $0.distance < $1.distance }
            .prefix(Self.maxVisibleRowers)
        var shown = Set<Int>()
        for s in visible {
            let color = ((s.colorIndex % Self.palette.count) + Self.palette.count) % Self.palette.count
            let rig = rigs[color] ?? makeRig(color)
            shown.insert(color)
            if !rig.root.isEnabled { rig.root.isEnabled = true }
            rig.root.position = [Float(s.x), 0, Float(s.z)]
            rig.root.orientation = simd_quatf(angle: Float(s.heading), axis: [0, 1, 0])
            rig.apply(.at(phase: s.strokePhase, strokeRate: s.strokeRate))
            let fade = 1 - min(max((s.distance - Self.fadeStart) / (VirtualRowers.visibleRange - Self.fadeStart), 0), 1)
            Self.setOpacity(rig.root, Float(fade))
        }
        for (color, rig) in rigs where !shown.contains(color) && rig.root.isEnabled {
            rig.root.isEnabled = false
        }
    }

    private func makeRig(_ color: Int) -> BoatRig {
        let rig = BoatRig(colors: Self.palette[color])
        Self.disableShadows(rig.root)
        rig.root.name = "rower-\(color)"
        rig.root.isEnabled = false
        root.addChild(rig.root)
        rigs[color] = rig
        return rig
    }

    // MARK: - Schiffe

    private func updateVessels(_ states: [VesselState], boatX: Double, boatZ: Double) {
        var alive = Set<Int>()
        for s in states {
            alive.insert(s.id)
            let e: Entity
            if let existing = vessels[s.id] {
                e = existing
            } else {
                e = VesselModels.make(s.kind)
                root.addChild(e)
                vessels[s.id] = e
            }
            let far = hypot(s.x - boatX, s.z - boatZ) > Self.vesselHideDistance
            if e.isEnabled == far { e.isEnabled = !far }
            e.position = [Float(s.x), 0, Float(s.z)]
            e.orientation = simd_quatf(angle: Float(s.heading), axis: [0, 1, 0])
            Self.setOpacity(e, Float(s.fade))
        }
        for (id, e) in vessels where !alive.contains(id) {
            e.removeFromParent()
            vessels[id] = nil
        }
    }

    // MARK: - Hilfen

    /// Deckkraft über `OpacityComponent` (wirkt auf alle Kinder); bei 1 wird die Komponente entfernt.
    private static func setOpacity(_ e: Entity, _ opacity: Float) {
        if opacity >= 0.999 {
            if e.components.has(OpacityComponent.self) { e.components.remove(OpacityComponent.self) }
        } else {
            e.components.set(OpacityComponent(opacity: max(opacity, 0)))
        }
    }

    private static func disableShadows(_ e: Entity) {
        if e.components.has(ModelComponent.self) {
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
        }
        for child in e.children { disableShadows(child) }
    }
}
