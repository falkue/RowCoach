import Foundation
import os
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Boote der anderen im Rennen (getrennt vom Verkehr), gesteuert vom `RaceScenePlanner` (docs/MULTIPLAYER.md
/// „Grosse Felder“, „Umsetzung App“): je Planungsschritt (`RaceSceneFrame`, 10/s) sagt der Planer, wer wie gezeigt
/// wird – `full` (Figur mit Erscheinung, Animation, Namensschild, Schatten), `lite` (vereinfacht, ohne Schild und
/// Schatten), `impostor` (Silhouette im gemeinsamen Mesh `RaceImpostors`); der Rest nur im HUD.
///
/// - Rigs kommen aus einem `BoatRigPool` (wiederverwendet; full ↔ lite nur Umschalten). Geister (gespeicherte Fahrten)
///   bekommen ein eigenes halbtransparentes Rig.
/// - Position: Distanz aus dem Planer (bereits interpoliert), weich nachgezogen und zwischen den Schritten mit der
///   gemessenen Geschwindigkeit vorausgerechnet; Seitenlage `lateral` des Planers (visuelle Bahn, schon begrenzt
///   schnell), hier zusätzlich geglättet; Lage und Schild aus `RaceSceneLayout` (RowCoachKit, getestet).
/// - Ein-/Ausblenden (`fade`) nur für Rigs, die vor dem Laden der Landschaft angelegt wurden (`prewarm`): auf dem
///   A12X waren später angelegte Boote mit `OpacityComponent` unsichtbar (siehe `BoatRig.setFade`). Andere erscheinen
///   ohne Übergang.
/// - Schild (`RaceTagLayout`): nur bei `full`; Kind des Boots, 1,15 m über dem Wasser, nur die Schrift dreht sich zur
///   Kamera und wächst mit dem Abstand. Über 150 m aus.
///
/// Alles ist strikt nach `participantId` geführt, egal in welcher Reihenfolge die Einträge kommen.
@MainActor
final class RaceRowersSystem {
    let root = Entity()
    /// Vor dem Bau der Szene setzen, wenn ein Rennen kommt: dann legt `RowingSceneController.build` Rigs vorab an
    static var prewarmHint = false

    private final class Boat {
        let id: String
        let name: String
        let isGhost: Bool
        let appearance: RowerAppearance
        var tier: RaceRenderTier = .hidden
        var rig: BoatRig?
        var fadeAllowed = false
        var tag: Entity?
        var text: Entity?
        var textAnchor = SIMD2<Float>(0, 0)
        var tagVisible = false
        var target: Double
        var targetTime: CFTimeInterval
        var rate = 0.0
        var shown: Double
        var lateral: Double
        var lateralTarget: Double
        var fade: Float
        var fadeTarget: Float
        var appliedFade: Float = 1
        var strokeRate = 0
        var finished = false
        var phase = Double.random(in: 0..<1)

        init(id: String, participant: RaceParticipant, item: RaceSceneItem, now: CFTimeInterval) {
            self.id = id
            // virtuelle Teilnehmende immer gekennzeichnet: „Lea · SE ✦“ (docs/MULTIPLAYER.md „Virtuelle Teilnehmende“)
            name = participant.isVirtual ? "\(participant.nameWithCountry) \(RaceParticipant.virtualMark)"
                : participant.displayName
            isGhost = participant.source == .ghost
            appearance = participant.resolvedAppearance()
            target = item.distance
            targetTime = now
            shown = item.distance
            lateral = item.lateral
            lateralTarget = item.lateral
            fade = Float(item.fade)
            fadeTarget = Float(item.fade)
        }
    }

    private var boats: [String: Boat] = [:]
    private lazy var pool = BoatRigPool(root: root)
    /// Rigs, die vor dem Laden der Landschaft entstanden (dürfen ein-/ausblenden)
    private var warm = Set<ObjectIdentifier>()
    private let impostors = RaceImpostors()
    private var clusters: [RaceCrowdCluster] = []
    private var lanes = RaceVisualLanes()
    private var layout = RaceSceneLayout(colorCount: 6)
    private var pose: ((Double) -> TrackPose)?
    private var trackKey: String?
    private var lastLog: CFTimeInterval = 0
    private var impostorBuffer: [(x: Float, z: Float, heading: Float)] = []
    private static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Race")
    private static let ghostTint = UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
    private static let tagHideDistance: Float = 150
    /// höchstens so viele Silhouetten je Pulk-Gruppe
    private static let silhouettesPerCluster = 5

    init() {
        root.name = "race-rowers"
        root.addChild(impostors.root)
    }

    /// Rigs vorab anlegen (vor dem Laden der Landschaft), mit vereinfachter Stufe; sie dürfen später ein-/ausblenden
    func prewarm(_ count: Int) {
        guard count > 0, warm.isEmpty else { return }
        var rigs: [BoatRig] = []
        for i in 0..<count {
            let rig = pool.acquire(appearance: .random(seed: "warm-\(i)"), detail: .hidden)
            rig.prepareLite()
            rigs.append(rig)
            warm.insert(ObjectIdentifier(rig))
        }
        for rig in rigs { pool.release(rig) }
        Self.log.info("Szene: \(count, privacy: .public) Rennboote vorab angelegt")
    }

    /// Strecke und Runden (wie die Tempo-Linie); Bahnen für die Pulk-Silhouetten
    func setTrack(course: Course, laps: Bool) {
        let key = "\(course.id)|\(course.oneWayM)|\(laps)"
        guard key != trackKey else { return }
        trackKey = key
        lanes = RaceVisualLanes.forCourse(course)
        let track = CourseTrack(course: course)
        if laps {
            let lapTrack = LapTrack(track: track)
            pose = { lapTrack.pose(atDistance: $0) }
        } else {
            let length = track.totalLength
            pose = { track.pose(atDistance: min($0, length)) }
        }
    }

    /// Neuer Planungsschritt
    func update(_ frame: RaceSceneFrame) {
        let now = CACurrentMediaTime()
        var ids = Set<String>()
        for item in frame.items {
            ids.insert(item.participantId)
            let participant = frame.participants[item.participantId]
                ?? RaceParticipant(id: item.participantId, displayName: item.participantId, lane: 0)
            let boat: Boat
            if let b = boats[item.participantId] {
                boat = b
                let dt = now - b.targetTime
                if dt > 0.02 {
                    let measured = max((item.distance - b.target) / dt, 0)
                    b.rate = dt > 1.5 ? measured : b.rate + (measured - b.rate) * 0.5
                }
                if abs(item.distance - b.shown) > 60 { b.shown = item.distance; b.rate = 0 }
                b.target = item.distance
                b.targetTime = now
            } else {
                boat = Boat(id: item.participantId, participant: participant, item: item, now: now)
                boats[item.participantId] = boat
            }
            boat.lateralTarget = item.lateral
            boat.fadeTarget = Float(item.fade)
            boat.strokeRate = item.finished ? 0 : item.strokeRate
            boat.finished = item.finished
            if boat.tier != item.tier { setTier(item.tier, for: boat) }
        }
        for (id, b) in boats where !ids.contains(id) {
            setTier(.hidden, for: b)
            boats[id] = nil
            layout.forget(id)
        }
        clusters = frame.clusters
    }

    func clear() {
        for b in boats.values { setTier(.hidden, for: b) }
        boats = [:]
        clusters = []
        impostors.clear()
    }

    /// Stufe umsetzen: full/lite mit Rig (aus dem Vorrat), Schild nur bei full; impostor/hidden ohne Rig
    private func setTier(_ tier: RaceRenderTier, for b: Boat) {
        b.tier = tier
        switch tier {
        case .full, .lite:
            if b.rig == nil { attachRig(to: b) }
            b.rig?.setDetail(tier == .full ? .full : .lite)
            if tier == .full, b.tag == nil { makeTag(for: b) }
            b.tag?.isEnabled = tier == .full && b.tagVisible
        case .impostor, .hidden:
            detachRig(from: b)
        }
    }

    private func attachRig(to b: Boat) {
        let rig: BoatRig
        if b.isGhost {
            rig = BoatRig(appearance: b.appearance, ghostTint: Self.ghostTint, ghostOpacity: 0.55)
            root.addChild(rig.root)
        } else {
            rig = pool.acquire(appearance: b.appearance)
        }
        rig.root.name = "race-boat-\(b.id)"
        b.rig = rig
        b.fadeAllowed = warm.contains(ObjectIdentifier(rig))
        b.appliedFade = 1
        if b.fadeAllowed {
            b.fade = b.fadeTarget
            applyFade(b, force: true)
        }
        if let tag = b.tag { rig.root.addChild(tag) }
    }

    private func detachRig(from b: Boat) {
        guard let rig = b.rig else { return }
        b.tag?.removeFromParent()
        b.tagVisible = false
        rig.setFade(1)
        if b.isGhost { rig.root.removeFromParent() } else { pool.release(rig) }
        b.rig = nil
    }

    private func applyFade(_ b: Boat, force: Bool = false) {
        guard let rig = b.rig, b.fadeAllowed else { return }
        let f: Float = b.fade >= 0.98 ? 1 : max(b.fade, 0)
        guard force || abs(f - b.appliedFade) >= 0.02 || (f == 1 && b.appliedFade != 1) else { return }
        rig.setFade(f)
        b.appliedFade = f
    }

    /// Pro Bild: Position weich nachziehen, Schlag animieren, Schild skalieren, Impostoren und Pulk zeichnen
    func step(dt: Double, now: CFTimeInterval, eye: SIMD3<Float>) {
        guard let pose else { return }
        let eyeD = (x: Double(eye.x), y: Double(eye.y), z: Double(eye.z))
        let logNow = now - lastLog >= 10
        if logNow { lastLog = now }
        impostorBuffer.removeAll(keepingCapacity: true)
        let kLat = 1 - exp(-dt / 0.3)
        let kFade = Float(1 - exp(-dt / 0.1))
        for b in boats.values {
            let since = now - b.targetTime
            let horizon = b.finished || since > 2 ? 0 : min(since, 0.8)
            let predicted = b.target + b.rate * horizon
            b.shown += (predicted - b.shown) * (1 - exp(-dt / 0.15))
            b.lateral += (b.lateralTarget - b.lateral) * kLat
            let p = layout.place(id: b.id, pose: pose(b.shown), lateral: b.lateral, eye: eyeD)
            guard let rig = b.rig else {
                if b.tier == .impostor {
                    impostorBuffer.append((x: Float(p.boatX), z: Float(p.boatZ), heading: Float(p.heading)))
                }
                continue
            }
            rig.root.position = [Float(p.boatX), 0, Float(p.boatZ)]
            rig.root.orientation = simd_quatf(angle: Float(p.heading), axis: [0, 1, 0])
            b.phase += dt * Double(b.strokeRate) / 60
            b.phase -= b.phase.rounded(.down)
            rig.apply(b.strokeRate > 0 ? .at(phase: b.phase, strokeRate: b.strokeRate) : .rest)
            if b.fadeAllowed {
                b.fade += (b.fadeTarget - b.fade) * kFade
                applyFade(b)
            }
            placeTag(b, rig: rig, placement: p, eye: eye)
        }
        let single = impostorBuffer.count
        appendClusters(pose: pose)
        impostors.update(impostorBuffer, eye: eye)
        if logNow {
            let full = boats.values.filter { $0.tier == .full }.count
            let lite = boats.values.filter { $0.tier == .lite }.count
            let pack = impostorBuffer.count - single
            let created = pool.created
            // gleiche Begriffe wie im Rennen-Log (SessionController): Silhouetten = Einzelboote der Stufe impostor,
            // Pulk = zusätzliche Silhouetten für ausgeblendete Gruppen
            Self.log.info("Szene: Rennboote voll \(full, privacy: .public), vereinfacht \(lite, privacy: .public), Silhouetten \(single, privacy: .public) + Pulk \(pack, privacy: .public), Vorrat \(created, privacy: .public)")
        }
    }

    /// Pulk: je Gruppe einige Silhouetten über ihre Länge und die rechten Bahnen verteilt
    private func appendClusters(pose: (Double) -> TrackPose) {
        for c in clusters {
            let n = min(c.count, Self.silhouettesPerCluster)
            let step = n > 1 ? max(c.length / Double(n - 1), 9) : 0
            for k in 0..<n {
                let d = c.distance + (Double(k) - Double(n - 1) / 2) * step
                let slot = 1 + k % max(lanes.right, 1)
                let p = layout.place(id: "", pose: pose(d), lateral: lanes.lateral(slot: slot), eye: (x: 0, y: 0, z: 0))
                impostorBuffer.append((x: Float(p.boatX), z: Float(p.boatZ), heading: Float(p.heading)))
            }
        }
    }

    private func placeTag(_ b: Boat, rig: BoatRig, placement p: RaceBoatPlacement, eye: SIMD3<Float>) {
        guard let tag = b.tag, let text = b.text else { return }
        let dist = simd_distance(eye, SIMD3<Float>(Float(p.tagX), Float(p.tagY), Float(p.tagZ)))
        let visible = dist < Self.tagHideDistance && b.tier == .full
        if visible != b.tagVisible {
            b.tagVisible = visible
            tag.isEnabled = visible
        }
        guard visible else { return }
        // Bezugspunkt: Kind des Boots, also nur die Höhe (x/z = Boot); nicht skaliert
        tag.position = [0, Float(p.tagY), 0]
        tag.scale = .one
        // Schrift: skaliert, Mitte unten am Bezugspunkt
        let k = Float(p.tagScale)
        text.scale = SIMD3<Float>(repeating: k)
        text.position = [-b.textAnchor.x * k, -b.textAnchor.y * k, 0]
    }

    /// Namensschild: heller, fetter Text, dreht sich zur Kamera
    private func makeTag(for b: Boat) {
        // Kennzeichnung ✦ am Ende bleibt erhalten, auch wenn der Name gekürzt wird
        let mark = " " + RaceParticipant.virtualMark
        let label = b.name.hasSuffix(mark) && b.name.count > 18
            ? String(b.name.dropLast(mark.count).prefix(16)) + mark : String(b.name.prefix(18))
        let mesh = MeshResource.generateText(label, extrusionDepth: 0.01,
                                             font: .systemFont(ofSize: 0.30, weight: .bold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        var material = UnlitMaterial()
        material.color = .init(tint: .white)
        let text = ModelEntity(mesh: mesh, materials: [material])
        text.name = "race-tag-text-\(b.id)"
        text.components.set(DynamicLightShadowComponent(castsShadow: false))
        // Mitte unten der sichtbaren Schrift (Mesh-Koordinaten); `placeTag` legt sie skaliert auf den Bezugspunkt
        let bounds = mesh.bounds
        let anchor = SIMD2<Float>((bounds.min.x + bounds.max.x) / 2, bounds.min.y)
        text.position = [-anchor.x, -anchor.y, 0]
        let tag = Entity()
        tag.name = "race-tag-\(b.id)"
        tag.addChild(text)
        tag.position = [0, Float(layout.tags.baseHeight), 0]
        tag.components.set(BillboardComponent())
        tag.isEnabled = false
        b.tag = tag
        b.text = text
        b.textAnchor = anchor
        b.rig?.root.addChild(tag)
    }
}
