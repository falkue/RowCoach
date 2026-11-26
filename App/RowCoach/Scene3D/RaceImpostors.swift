import Foundation
import Metal
import os
import RealityKit
import simd
import UIKit

/// Ferne Rennboote als ein einziges, sehr billiges Mesh (Planer-Stufe `impostor` und Gruppen „Pulk“): je Boot eine
/// dunkle Silhouette quer zur Fahrtrichtung (Körper als Dreieck, Skulls als Balken), 7 Ecken, 6 Dreiecke (beidseitig,
/// damit man sie von vorn und hinten sieht). Ein `LowLevelMesh` mit festem Indexpuffer; pro Bild werden nur die
/// Eckpunkte neu geschrieben. Ein Material (unbeleuchtet), keine Schatten, ein Draw-Call für alle.
///
/// Schlägt das Anlegen fehl (ältere Geräte, Treiber), bleibt die Stufe leer: ferne Boote fehlen dann einfach, HUD und
/// Minikarte zeigen das Feld weiter (Log „Impostoren nicht verfügbar“).
@MainActor
final class RaceImpostors {
    let root = Entity()
    let capacity: Int
    private var mesh: LowLevelMesh?
    private var entity: ModelEntity?
    private var lastCount = -1
    private static let vertsPerBoat = 7
    private static let indicesPerBoat = 18
    private static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Race")

    /// Silhouette von hinten (Meter): Körper 0,5 breit bis 1,0 hoch, Skulls 3,2 breit
    private static let bodyHalfWidth: Float = 0.25
    private static let bodyBase: Float = 0.15
    private static let bodyTop: Float = 1.0
    private static let oarHalfSpan: Float = 1.6
    private static let oarLow: Float = 0.30
    private static let oarHigh: Float = 0.38

    init(capacity: Int = 400) {
        self.capacity = capacity
        root.name = "race-impostors"
        do {
            var d = LowLevelMesh.Descriptor()
            d.vertexAttributes = [LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: 0)]
            d.vertexLayouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)]
            d.vertexCapacity = capacity * Self.vertsPerBoat
            d.indexCapacity = capacity * Self.indicesPerBoat
            d.indexType = .uint32
            let m = try LowLevelMesh(descriptor: d)
            // Indizes einmal: Körper (0,1,2) und Balken (3,4,5)(3,5,6), jeweils auch rückwärts
            let pattern: [UInt32] = [0, 1, 2, 0, 2, 1, 3, 4, 5, 3, 5, 6, 3, 5, 4, 3, 6, 5]
            m.withUnsafeMutableIndices { raw in
                let idx = raw.bindMemory(to: UInt32.self)
                for b in 0..<capacity {
                    let base = UInt32(b * Self.vertsPerBoat)
                    for (k, v) in pattern.enumerated() { idx[b * Self.indicesPerBoat + k] = base + v }
                }
            }
            m.parts.replaceAll([LowLevelMesh.Part(indexCount: Self.indicesPerBoat, topology: .triangle,
                                                  bounds: BoundingBox(min: [-1, -1, -1], max: [1, 1, 1]))])
            let resource = try MeshResource(from: m)
            let material = UnlitMaterial(color: UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1))
            let e = ModelEntity(mesh: resource, materials: [material])
            e.name = "race-impostor-mesh"
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            e.isEnabled = false
            root.addChild(e)
            mesh = m
            entity = e
        } catch {
            Self.log.error("Szene: Impostoren nicht verfügbar (\(error.localizedDescription, privacy: .public)) – ferne Boote nur im HUD")
        }
    }

    var isAvailable: Bool { mesh != nil }

    /// Silhouetten setzen: Lage (Welt, Wasserlinie y = 0) und Fahrtrichtung (`TrackPose.heading`)
    func update(_ boats: [(x: Float, z: Float, heading: Float)]) {
        guard let mesh, let entity else { return }
        let n = min(boats.count, capacity)
        if n != lastCount {
            lastCount = n
            Self.log.debug("Szene: \(n, privacy: .public) Impostoren")
        }
        guard n > 0 else {
            if entity.isEnabled { entity.isEnabled = false }
            return
        }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let up = SIMD3<Float>(0, 1, 0)
        let extentLow = SIMD3<Float>(Self.oarHalfSpan, 0, Self.oarHalfSpan)
        let extentHigh = SIMD3<Float>(Self.oarHalfSpan, Self.bodyTop, Self.oarHalfSpan)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let v = raw.bindMemory(to: SIMD3<Float>.self)
            for i in 0..<n {
                let b = boats[i]
                // rechts der Fahrtrichtung: Fahrtrichtung (−sin h, −cos h) → rechts (cos h, −sin h)
                let r = SIMD3<Float>(cos(b.heading), 0, -sin(b.heading))
                let p = SIMD3<Float>(b.x, 0, b.z)
                let body = r * Self.bodyHalfWidth
                let oar = r * Self.oarHalfSpan
                let base: SIMD3<Float> = up * Self.bodyBase
                let low: SIMD3<Float> = up * Self.oarLow
                let high: SIMD3<Float> = up * Self.oarHigh
                let o = i * Self.vertsPerBoat
                v[o] = p - body + base
                v[o + 1] = p + body + base
                v[o + 2] = p + up * Self.bodyTop
                v[o + 3] = p - oar + low
                v[o + 4] = p + oar + low
                v[o + 5] = p + oar + high
                v[o + 6] = p - oar + high
                lo = simd_min(lo, p - extentLow)
                hi = simd_max(hi, p + extentHigh)
            }
        }
        mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: n * Self.indicesPerBoat, topology: .triangle,
                                                 bounds: BoundingBox(min: lo, max: hi))])
        if !entity.isEnabled { entity.isEnabled = true }
    }

    func clear() {
        update([])
    }
}
