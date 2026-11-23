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
            if model !== oldValue { clear() }
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
