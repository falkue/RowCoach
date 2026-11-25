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
///
/// Namensschild (`RaceTagLayout`): Bezugspunkt 1,45 m über dem Wasser direkt über der Figur, ungeskaliert; nur die
/// Schrift dreht sich zur Kamera und wächst mit dem Abstand (≈ 3 % des Abstands, 1×–4×), mittig über dem Boot, nach
/// oben wachsend. Jede zweite Bahn rechts hebt das Schild leicht an. Weiter als 150 m weg ausgeblendet.
@MainActor
final class RaceRowersSystem {
    let root = Entity()

    private final class Rower {
        let rig: BoatRig
        let label: Entity
        /// Schrift im Schild (wird skaliert; der Bezugspunkt `label` nicht)
        let text: Entity
        let textCenter: SIMD2<Float>
        var target: Double
        var targetTime: CFTimeInterval
        var rate = 0.0
        var shown: Double
        var strokeRate: Int
        var lateral: Double
        var finished: Bool
        var phase = Double.random(in: 0..<1)
        var labelVisible = true

        init(rig: BoatRig, label: (holder: Entity, text: Entity, center: SIMD2<Float>), distance: Double,
             now: CFTimeInterval, state: RemoteRowerState) {
            self.rig = rig
            self.label = label.holder
            self.text = label.text
            self.textCenter = label.center
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
                rig.root.addChild(label.holder)
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

    private static let tagLayout = RaceTagLayout()
    private static let labelHideDistance: Float = 150

    /// Pro Bild: Position weich nachziehen, Schlag animieren, Namensschilder zur Kamera `eye` skalieren
    func step(dt: Double, now: CFTimeInterval, eye: SIMD3<Float>) {
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
            placeLabel(r, eye: eye)
        }
    }

    private func placeLabel(_ r: Rower, eye: SIMD3<Float>) {
        let layout = Self.tagLayout
        let boat = r.rig.root.position
        let dist = simd_distance(eye, boat + SIMD3<Float>(0, Float(layout.baseHeight), 0))
        let visible = dist < Self.labelHideDistance
        if visible != r.labelVisible {
            r.labelVisible = visible
            r.label.isEnabled = visible
        }
        guard visible else { return }
        let scale = layout.scale(cameraDistance: Double(dist))
        // Bezugspunkt ungeskaliert direkt über der Figur; nur die Schrift wird skaliert und um ihre Mitte gelegt
        r.label.position = [0, Float(layout.anchorHeight(lateral: r.lateral, scale: scale)), 0]
        let k = Float(scale)
        r.text.scale = SIMD3<Float>(repeating: k)
        r.text.position = [-r.textCenter.x * k, -r.textCenter.y * k, 0]
    }

    /// Namensschild: heller Text, dreht sich zur Kamera; Bezugspunkt 1,45 m über dem Wasser (`RaceTagLayout`)
    private static func makeLabel(_ text: String) -> (holder: Entity, text: Entity, center: SIMD2<Float>) {
        let mesh = MeshResource.generateText(String(text.prefix(18)), extrusionDepth: 0.01,
                                             font: .systemFont(ofSize: 0.30, weight: .bold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        var material = UnlitMaterial()
        material.color = .init(tint: .white)
        let model = ModelEntity(mesh: mesh, materials: [material])
        // waagrecht mittig, Unterkante am Bezugspunkt (das Schild wächst nach oben, nicht in die Figur)
        let b = mesh.bounds
        let center = SIMD2<Float>((b.min.x + b.max.x) / 2, b.min.y)
        model.position = [-center.x, -center.y, 0]
        model.components.set(DynamicLightShadowComponent(castsShadow: false))
        let holder = Entity()
        holder.addChild(model)
        holder.position = [0, Float(tagLayout.baseHeight), 0]
        holder.components.set(BillboardComponent())
        return (holder, model, center)
    }
}
