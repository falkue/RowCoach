import Foundation
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Boote der anderen im Rennen (getrennt vom Verkehr): je Teilnehmendem ein `BoatRig` in eigener Farbe mit
/// Namensschild über dem Boot. Geister (gespeicherte Fahrten) halbtransparent wie das Geisterboot der Tempo-Linie.
///
/// Position: Distanz aus `RemoteRowerState` (bereits interpoliert), weich nachgezogen und zwischen den Updates mit
/// der gemessenen Geschwindigkeit vorausgerechnet; Lage aus `CourseTrack` bzw. `LapTrack` derselben Strecke,
/// seitlich um `lateral` versetzt (positiv = links der Fahrtrichtung, siehe `RaceLanes`).
@MainActor
final class RaceRowersSystem {
    let root = Entity()

    private final class Rower {
        let rig: BoatRig
        let label: Entity
        var target: Double
        var targetTime: CFTimeInterval
        var rate = 0.0
        var shown: Double
        var strokeRate: Int
        var lateral: Double
        var finished: Bool
        var phase = Double.random(in: 0..<1)

        init(rig: BoatRig, label: Entity, distance: Double, now: CFTimeInterval, state: RemoteRowerState) {
            self.rig = rig
            self.label = label
            target = distance
            targetTime = now
            shown = distance
            strokeRate = state.strokeRate
            lateral = state.lateral
            finished = state.finished
        }
    }

    private var rowers: [String: Rower] = [:]
    private var pose: ((Double) -> TrackPose)?
    private var trackKey: String?

    /// Trikotfarben der Gegner (gut unterscheidbar, nicht das Blau des eigenen Boots)
    private static let shirts: [UIColor] = [
        UIColor(red: 0.85, green: 0.20, blue: 0.18, alpha: 1),
        UIColor(red: 0.10, green: 0.62, blue: 0.40, alpha: 1),
        UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1),
        UIColor(red: 0.55, green: 0.25, blue: 0.70, alpha: 1),
        UIColor(red: 0.10, green: 0.60, blue: 0.75, alpha: 1),
        UIColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1),
    ]
    private static let ghostTint = UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)

    init() {
        root.name = "race-rowers"
    }

    /// Strecke und Runden (wie die Tempo-Linie); bei Wechsel werden die Boote neu gesetzt
    func setTrack(course: Course, laps: Bool) {
        let key = "\(course.id)|\(course.oneWayM)|\(laps)"
        guard key != trackKey else { return }
        trackKey = key
        let track = CourseTrack(course: course)
        if laps {
            let lapTrack = LapTrack(track: track)
            pose = { lapTrack.pose(atDistance: $0) }
        } else {
            let length = track.totalLength
            pose = { track.pose(atDistance: min($0, length)) }
        }
    }

    func update(_ states: [RemoteRowerState]) {
        let now = CACurrentMediaTime()
        let ids = Set(states.map(\.id))
        for (id, r) in rowers where !ids.contains(id) {
            r.rig.root.removeFromParent()
            rowers[id] = nil
        }
        for s in states {
            if let r = rowers[s.id] {
                let dt = now - r.targetTime
                if dt > 0.02 {
                    let measured = max((s.distance - r.target) / dt, 0)
                    r.rate = dt > 1.5 ? measured : r.rate + (measured - r.rate) * 0.5
                }
                if abs(s.distance - r.shown) > 60 { r.shown = s.distance; r.rate = 0 }
                r.target = s.distance
                r.targetTime = now
                r.strokeRate = s.finished ? 0 : s.strokeRate
                r.lateral = s.lateral
                r.finished = s.finished
            } else {
                let index = rowers.count % Self.shirts.count
                let ghost = s.participant.source == .ghost
                let rig = ghost ? BoatRig(ghostTint: Self.ghostTint, ghostOpacity: 0.55)
                    : BoatRig(colors: BoatRig.Colors(shirt: Self.shirts[index], blade: Self.shirts[index],
                                                      hull: UIColor(white: 0.95, alpha: 1)))
                let label = Self.makeLabel(s.participant.displayName)
                rig.root.addChild(label)
                rig.root.name = "race-\(s.id)"
                root.addChild(rig.root)
                rowers[s.id] = Rower(rig: rig, label: label, distance: s.distance, now: now, state: s)
            }
        }
    }

    func clear() {
        for r in rowers.values { r.rig.root.removeFromParent() }
        rowers = [:]
    }

    /// Pro Bild: Position weich nachziehen und Schlag animieren
    func step(dt: Double, now: CFTimeInterval) {
        guard let pose else { return }
        for r in rowers.values {
            let since = now - r.targetTime
            let horizon = r.finished || since > 2 ? 0 : min(since, 0.8)
            let predicted = r.target + r.rate * horizon
            r.shown += (predicted - r.shown) * (1 - exp(-dt / 0.15))
            let p = pose(r.shown)
            // seitlich versetzen: links der Fahrtrichtung = (−cos h, +sin h) in (x, z)
            let lx = -cos(p.heading), lz = sin(p.heading)
            r.rig.root.position = [Float(p.x + lx * r.lateral), 0, Float(p.z + lz * r.lateral)]
            r.rig.root.orientation = simd_quatf(angle: Float(p.heading), axis: [0, 1, 0])
            r.phase += dt * Double(r.strokeRate) / 60
            r.phase -= r.phase.rounded(.down)
            r.rig.apply(r.strokeRate > 0 ? .at(phase: r.phase, strokeRate: r.strokeRate) : .rest)
        }
    }

    /// Namensschild: heller Text, dreht sich zur Kamera, etwa 2,4 m über dem Wasser
    private static func makeLabel(_ text: String) -> Entity {
        let mesh = MeshResource.generateText(String(text.prefix(18)), extrusionDepth: 0.01,
                                             font: .systemFont(ofSize: 0.32, weight: .semibold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        var material = UnlitMaterial()
        material.color = .init(tint: .white)
        let model = ModelEntity(mesh: mesh, materials: [material])
        // Text um die Mitte legen
        let b = mesh.bounds
        model.position = [-(b.min.x + b.max.x) / 2, 0, 0]
        model.components.set(DynamicLightShadowComponent(castsShadow: false))
        let holder = Entity()
        holder.addChild(model)
        holder.position = [0, 2.4, 0]
        holder.components.set(BillboardComponent())
        return holder
    }
}
