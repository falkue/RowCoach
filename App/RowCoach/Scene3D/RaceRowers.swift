import Foundation
import os
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Boote der anderen im Rennen (getrennt vom Verkehr): je Teilnehmendem ein `BoatRig` in eigener Farbe mit
/// Namensschild über der Figur. Geister (gespeicherte Fahrten) halbtransparent wie das Geisterboot der Tempo-Linie.
///
/// Alles ist strikt nach `participant.id` geführt: Boot, Schild, Distanz und Farbe gehören zusammen, egal in welcher
/// Reihenfolge die Stände kommen (sie sind nach Platz sortiert und wechseln beim Überholen).
///
/// - Position: Distanz aus `RemoteRowerState` (bereits interpoliert), weich nachgezogen und zwischen den Updates mit
///   der gemessenen Geschwindigkeit vorausgerechnet; Lage und Schild aus `RaceSceneLayout` (RowCoachKit, getestet).
/// - Schild (`RaceTagLayout`): Kind des Boots, Bezugspunkt 1,15 m über dem Wasser direkt über der Figur, ungeskaliert;
///   nur die Schrift dreht sich zur Kamera und wächst mit dem Abstand, mittig, nach oben wachsend. Über 150 m aus.
@MainActor
final class RaceRowersSystem {
    let root = Entity()

    private final class Rower {
        let id: String
        let name: String
        let rig: BoatRig
        /// Bezugspunkt des Schilds (Kind von `rig.root`, nicht skaliert, dreht sich zur Kamera)
        let tag: Entity
        /// Schrift im Schild (wird skaliert)
        let text: Entity
        /// Mitte unten der Schrift im eigenen Mesh (für die Ausrichtung am Bezugspunkt)
        let textAnchor: SIMD2<Float>
        var target: Double
        var targetTime: CFTimeInterval
        var rate = 0.0
        var shown: Double
        var strokeRate: Int
        var lateral: Double
        var finished: Bool
        var phase = Double.random(in: 0..<1)
        var tagVisible = true

        init(id: String, name: String, rig: BoatRig, tag: Entity, text: Entity, textAnchor: SIMD2<Float>,
             state: RemoteRowerState, now: CFTimeInterval) {
            self.id = id
            self.name = name
            self.rig = rig
            self.tag = tag
            self.text = text
            self.textAnchor = textAnchor
            target = state.distance
            targetTime = now
            shown = state.distance
            strokeRate = state.strokeRate
            lateral = state.lateral
            finished = state.finished
        }
    }

    private var rowers: [String: Rower] = [:]
    private var layout = RaceSceneLayout(colorCount: RaceRowersSystem.shirts.count)
    private var pose: ((Double) -> TrackPose)?
    private var trackKey: String?
    private var lastLog: CFTimeInterval = 0
    private static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Race")

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
    private static let tagHideDistance: Float = 150

    init() {
        root.name = "race-rowers"
    }

    /// Strecke und Runden (wie die Tempo-Linie)
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

    /// Neue Stände übernehmen (nach id; Reihenfolge egal)
    func update(_ states: [RemoteRowerState]) {
        let now = CACurrentMediaTime()
        let ids = Set(states.map(\.id))
        for id in Array(rowers.keys) where !ids.contains(id) {
            rowers[id]?.rig.root.removeFromParent()
            rowers[id] = nil
            layout.forget(id)
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
                rowers[s.id] = makeRower(s, now: now)
            }
        }
    }

    func clear() {
        for r in rowers.values { r.rig.root.removeFromParent() }
        rowers = [:]
    }

    private func makeRower(_ s: RemoteRowerState, now: CFTimeInterval) -> Rower {
        let colorIndex = layout.colorIndex(for: s.id)
        let color = Self.shirts[colorIndex]
        let rig = s.participant.source == .ghost
            ? BoatRig(ghostTint: Self.ghostTint, ghostOpacity: 0.55)
            : BoatRig(colors: BoatRig.Colors(shirt: color, blade: color, hull: UIColor(white: 0.95, alpha: 1)))
        rig.root.name = "race-boat-\(s.id)"
        let (tag, text, anchor) = Self.makeTag(s.participant.displayName, id: s.id, height: Float(layout.tags.baseHeight))
        rig.root.addChild(tag)
        root.addChild(rig.root)
        Self.log.info("Szene: Rennboot \(s.participant.displayName, privacy: .public) (\(s.id, privacy: .public)) angelegt, Farbe \(colorIndex, privacy: .public), seitlich \(Int(s.lateral), privacy: .public) m")
        return Rower(id: s.id, name: s.participant.displayName, rig: rig, tag: tag, text: text, textAnchor: anchor,
                     state: s, now: now)
    }

    /// Pro Bild: Position weich nachziehen, Schlag animieren, Schild zur Kamera `eye` skalieren
    func step(dt: Double, now: CFTimeInterval, eye: SIMD3<Float>) {
        guard let pose else { return }
        let eyeD = (x: Double(eye.x), y: Double(eye.y), z: Double(eye.z))
        let logNow = now - lastLog >= 10
        if logNow { lastLog = now }
        for r in rowers.values {
            let since = now - r.targetTime
            let horizon = r.finished || since > 2 ? 0 : min(since, 0.8)
            let predicted = r.target + r.rate * horizon
            r.shown += (predicted - r.shown) * (1 - exp(-dt / 0.15))
            let p = layout.place(id: r.id, pose: pose(r.shown), lateral: r.lateral, eye: eyeD)
            r.rig.root.position = [Float(p.boatX), 0, Float(p.boatZ)]
            r.rig.root.orientation = simd_quatf(angle: Float(p.heading), axis: [0, 1, 0])
            r.phase += dt * Double(r.strokeRate) / 60
            r.phase -= r.phase.rounded(.down)
            r.rig.apply(r.strokeRate > 0 ? .at(phase: r.phase, strokeRate: r.strokeRate) : .rest)
            placeTag(r, placement: p, eye: eye)
            if logNow {
                let w = r.tag.position(relativeTo: nil)
                Self.log.info("Szene: \(r.name, privacy: .public) Boot \(p.boatX, format: .fixed(precision: 1), privacy: .public)/\(p.boatZ, format: .fixed(precision: 1), privacy: .public), Schild \(w.x, format: .fixed(precision: 1), privacy: .public)/\(w.y, format: .fixed(precision: 2), privacy: .public)/\(w.z, format: .fixed(precision: 1), privacy: .public), Massstab \(p.tagScale, format: .fixed(precision: 2), privacy: .public)")
            }
        }
    }

    private func placeTag(_ r: Rower, placement p: RaceBoatPlacement, eye: SIMD3<Float>) {
        let dist = simd_distance(eye, SIMD3<Float>(Float(p.tagX), Float(p.tagY), Float(p.tagZ)))
        let visible = dist < Self.tagHideDistance
        if visible != r.tagVisible {
            r.tagVisible = visible
            r.tag.isEnabled = visible
        }
        guard visible else { return }
        // Bezugspunkt: Kind des Boots, also nur die Höhe (x/z = Boot); nicht skaliert
        r.tag.position = [0, Float(p.tagY), 0]
        r.tag.scale = .one
        // Schrift: skaliert, Mitte unten am Bezugspunkt
        let k = Float(p.tagScale)
        r.text.scale = SIMD3<Float>(repeating: k)
        r.text.position = [-r.textAnchor.x * k, -r.textAnchor.y * k, 0]
    }

    /// Namensschild: heller, fetter Text, dreht sich zur Kamera
    private static func makeTag(_ name: String, id: String, height: Float) -> (Entity, Entity, SIMD2<Float>) {
        let mesh = MeshResource.generateText(String(name.prefix(18)), extrusionDepth: 0.01,
                                             font: .systemFont(ofSize: 0.30, weight: .bold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        var material = UnlitMaterial()
        material.color = .init(tint: .white)
        let text = ModelEntity(mesh: mesh, materials: [material])
        text.name = "race-tag-text-\(id)"
        text.components.set(DynamicLightShadowComponent(castsShadow: false))
        // Mitte unten der sichtbaren Schrift (Mesh-Koordinaten); `placeTag` legt sie skaliert auf den Bezugspunkt
        let b = mesh.bounds
        let anchor = SIMD2<Float>((b.min.x + b.max.x) / 2, b.min.y)
        text.position = [-anchor.x, -anchor.y, 0]
        let tag = Entity()
        tag.name = "race-tag-\(id)"
        tag.addChild(text)
        tag.position = [0, height, 0]
        tag.components.set(BillboardComponent())
        return (tag, text, anchor)
    }
}
