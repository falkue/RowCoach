import Foundation
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Ein Tor in der 3D-Szene an der Stelle, an der die nächste Trainingsphase beginnt.
/// Position und Richtung kommen aus `LapTrack.pose(atDistance:)` (Szenenkoordinaten, heading wie `TrackPose`).
struct GateMarker: Equatable, Identifiable {
    var id: String
    var x: Double
    var z: Double
    var heading: Double
    /// Art der nächsten Phase (Farbe); nil = Ende des Trainings
    var kind: WorkoutPhase.Kind?

    init(id: String, x: Double, z: Double, heading: Double, kind: WorkoutPhase.Kind?) {
        self.id = id
        self.x = x
        self.z = z
        self.heading = heading
        self.kind = kind
    }
}

/// Zwei Pfosten mit Schwimmkörpern links und rechts der Bahn und ein Band darüber.
/// Zwei ModelEntities (weisse Pfosten; farbiges Band mit Schwimmkörpern), zusammen 60 Dreiecke, ohne Schatten.
@MainActor
final class GateEntity {
    let root = Entity()
    private let posts: ModelEntity
    private let band: ModelEntity
    private var kind: WorkoutPhase.Kind??
    private var target: GateMarker
    private var x: Double
    private var z: Double
    private var heading: Double

    /// halbe lichte Breite: Skulls ragen ca. 2,8 m seitlich hinaus
    private static let halfWidth: Float = 4.6
    private static let height: Float = 3.1
    /// Glättung der Position (s); grössere Sprünge werden direkt übernommen
    private static let tau = 0.35
    private static let snapDistance = 80.0

    private static var postMesh: MeshResource?
    private static var bandMesh: MeshResource?
    private static var postMaterial: PhysicallyBasedMaterial?
    private static var bandMaterials: [String: UnlitMaterial] = [:]

    init(marker: GateMarker) {
        target = marker
        x = marker.x
        z = marker.z
        heading = marker.heading
        posts = ModelEntity(mesh: Self.meshPosts(), materials: [Self.materialPosts()])
        band = ModelEntity(mesh: Self.meshBand(), materials: [Self.materialBand(marker.kind)])
        kind = .some(marker.kind)
        for e in [posts, band] {
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(e)
        }
        root.name = marker.id
        applyTransform()
    }

    func setTarget(_ marker: GateMarker) {
        target = marker
        if kind != .some(marker.kind) {
            kind = .some(marker.kind)
            band.model?.materials = [Self.materialBand(marker.kind)]
        }
        if hypot(marker.x - x, marker.z - z) > Self.snapDistance {
            x = marker.x
            z = marker.z
            heading = marker.heading
            applyTransform()
        }
    }

    /// Pro Bild: weich zur Zielposition
    func step(dt: Double) {
        let k = 1 - exp(-dt / Self.tau)
        x += (target.x - x) * k
        z += (target.z - z) * k
        var dh = (target.heading - heading).truncatingRemainder(dividingBy: 2 * .pi)
        if dh > .pi { dh -= 2 * .pi }
        if dh < -.pi { dh += 2 * .pi }
        heading += dh * k
        applyTransform()
    }

    private func applyTransform() {
        root.position = [Float(x), 0, Float(z)]
        root.orientation = simd_quatf(angle: Float(heading), axis: [0, 1, 0])
    }

    // MARK: Farben

    static func color(_ kind: WorkoutPhase.Kind?) -> UIColor {
        switch kind {
        case .work: return UIColor(red: 0.98, green: 0.45, blue: 0.18, alpha: 1)      // warm: Belastung
        case .rest: return UIColor(red: 0.30, green: 0.72, blue: 1.00, alpha: 1)      // kühl: Pause
        case .warmup: return UIColor(red: 0.80, green: 0.88, blue: 0.35, alpha: 1)
        case .cooldown: return UIColor(red: 0.55, green: 0.55, blue: 0.98, alpha: 1)
        case .other: return UIColor(white: 0.8, alpha: 1)
        case .none: return UIColor(white: 0.97, alpha: 1)                             // Ziel
        }
    }

    // MARK: Geometrie (gemeinsam für alle Tore)

    private static func meshPosts() -> MeshResource {
        if let m = postMesh { return m }
        let w = halfWidth, h = height
        let m = boxMesh(name: "gate-posts", boxes: [
            (center: [-w, h / 2 - 0.1, 0], size: [0.16, h + 0.2, 0.16]),
            (center: [w, h / 2 - 0.1, 0], size: [0.16, h + 0.2, 0.16]),
        ])
        postMesh = m
        return m
    }

    private static func meshBand() -> MeshResource {
        if let m = bandMesh { return m }
        let w = halfWidth, h = height
        let m = boxMesh(name: "gate-band", boxes: [
            (center: [0, h - 0.2, 0], size: [2 * w + 0.16, 0.34, 0.06]),     // Band
            (center: [-w, 0.08, 0], size: [0.7, 0.45, 0.7]),                 // Schwimmkörper links
            (center: [w, 0.08, 0], size: [0.7, 0.45, 0.7]),                  // Schwimmkörper rechts
        ])
        bandMesh = m
        return m
    }

    private static func materialPosts() -> PhysicallyBasedMaterial {
        if let m = postMaterial { return m }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.92, alpha: 1))
        m.roughness = .init(floatLiteral: 0.6)
        m.metallic = .init(floatLiteral: 0)
        postMaterial = m
        return m
    }

    private static func materialBand(_ kind: WorkoutPhase.Kind?) -> UnlitMaterial {
        let key = kind?.rawValue ?? "finish"
        if let m = bandMaterials[key] { return m }
        var m = UnlitMaterial()
        m.color = .init(tint: color(kind))
        m.faceCulling = .none
        bandMaterials[key] = m
        return m
    }

    /// Quader mit eigenen Eckpunkten je Seite (flache Normalen), Dreiecke gegen den Uhrzeigersinn von aussen.
    /// Auch für die Tempo-Linie (`PaceLineEntity`).
    static func boxMesh(name: String, boxes: [(center: SIMD3<Float>, size: SIMD3<Float>)]) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        // Normale n und Achsen u, v mit u × v = n
        let faces: [(n: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            ([1, 0, 0], [0, 1, 0], [0, 0, 1]),
            ([-1, 0, 0], [0, 0, 1], [0, 1, 0]),
            ([0, 1, 0], [0, 0, 1], [1, 0, 0]),
            ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
            ([0, 0, 1], [1, 0, 0], [0, 1, 0]),
            ([0, 0, -1], [0, 1, 0], [1, 0, 0]),
        ]
        for box in boxes {
            let h = box.size / 2
            for f in faces {
                let base = UInt32(positions.count)
                let c = box.center + f.n * simd_dot(simd_abs(f.n), h)
                let hu = f.u * simd_dot(f.u, h), hv = f.v * simd_dot(f.v, h)
                positions += [c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv]
                normals += [f.n, f.n, f.n, f.n]
                indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            }
        }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) { return mesh }
        return MeshResource.generateBox(size: [0.1, 0.1, 0.1], cornerRadius: 0)
    }
}
