import Foundation
import Metal
import os
import RealityKit
import simd
import UIKit

/// Ferne Rennboote als sehr billige Silhouetten (Planer-Stufe `impostor` und Gruppen „Pulk“).
///
/// Überarbeitet nach dem Mac-Test (27.11.2026: harte schwarze „Flossen“): je Boot ein liegendes, flaches Bild –
/// niedriger Rumpfstrich entlang der Fahrtrichtung, darüber eine kleine abgerundete Figur und zwei kurze, zum Wasser
/// geneigte Skull-Striche quer dazu. Farbe Grau mit Blauton, mit der Entfernung zum Dunst hin aufgehellt und
/// durchscheinender (drei Entfernungsstufen, je ein Mesh und ein Material → drei Draw-Calls für alle Silhouetten).
/// Beidseitig (man sieht sie von vorn, hinten und schräg). Pro Bild werden nur die Eckpunkte neu geschrieben.
///
/// Schlägt das Anlegen fehl (ältere Geräte, Treiber), bleibt die Stufe leer: ferne Boote fehlen dann einfach, HUD und
/// Minikarte zeigen das Feld weiter (Log „Silhouetten nicht verfügbar“).
/// Kontrollbild: docs/avatar/check-impostors.png (tools/avatars/impostors_check.py, gleiche Masse und Farben).
@MainActor
final class RaceImpostors {
    let root = Entity()
    let capacity: Int

    private final class Band {
        let mesh: LowLevelMesh
        let entity: ModelEntity
        var count = 0
        init(mesh: LowLevelMesh, entity: ModelEntity) {
            self.mesh = mesh
            self.entity = entity
        }
    }

    private var bands: [Band] = []
    private var lastCount = -1
    private var buffers: [[(x: Float, z: Float, heading: Float)]] = [[], [], []]
    private static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Race")

    /// Grenzen der Entfernungsstufen (m) und ihr Aussehen: Grundfarbe zum Dunst gemischt, Deckkraft
    static let bandLimits: [Float] = [250, 500]
    static let bandHazeMix: [Float] = [0.15, 0.42, 0.65]
    static let bandOpacity: [Float] = [0.78, 0.62, 0.48]
    static let baseColor = SIMD3<Float>(0.26, 0.31, 0.38)
    static let defaultHaze = SIMD3<Float>(0.74, 0.80, 0.87)

    // Form (Meter; x = quer zur Fahrtrichtung, y = hoch, f = entlang der Fahrtrichtung)
    /// Figur von hinten: Sockel, Schultern, Kopf (abgerundet, keine Spitze)
    static let body: [SIMD2<Float>] = [[-0.22, 0.10], [0.22, 0.10], [0.19, 0.45], [0.07, 0.68], [-0.07, 0.68],
                                       [-0.19, 0.45]]
    /// Skull-Strich je Seite: innen (x, y unten, y oben) → aussen
    static let oarInner: SIMD3<Float> = [0.34, 0.22, 0.27]
    static let oarOuter: SIMD3<Float> = [1.30, 0.10, 0.14]
    /// Rumpf entlang der Fahrtrichtung: halbe Länge, Höhe Mitte, Höhe Enden
    static let hullHalf: Float = 4.0
    static let hullTop: Float = 0.16
    static let hullEnd: Float = 0.05

    private static let vertsPerBoat = 6 + 8 + 4
    private static let trisPerBoat = 4 + 4 + 2
    private static let indicesPerBoat = trisPerBoat * 3 * 2

    init(capacity: Int = 400, haze: SIMD3<Float> = RaceImpostors.defaultHaze) {
        self.capacity = capacity
        root.name = "race-impostors"
        do {
            for b in 0..<3 {
                let m = try Self.makeMesh(capacity: capacity)
                let resource = try MeshResource(from: m)
                let e = ModelEntity(mesh: resource, materials: [Self.material(band: b, haze: haze)])
                e.name = "race-silhouettes-\(b)"
                e.components.set(DynamicLightShadowComponent(castsShadow: false))
                e.isEnabled = false
                root.addChild(e)
                bands.append(Band(mesh: m, entity: e))
            }
        } catch {
            bands = []
            Self.log.error("Szene: Silhouetten nicht verfügbar (\(error.localizedDescription, privacy: .public)) – ferne Boote nur im HUD")
        }
    }

    var isAvailable: Bool { !bands.isEmpty }

    /// Dunstfarbe der Szene (z. B. aus `SceneEnvironment`), damit ferne Silhouetten im Dunst verschwimmen
    func setHaze(_ haze: SIMD3<Float>) {
        for (b, band) in bands.enumerated() { band.entity.model?.materials = [Self.material(band: b, haze: haze)] }
    }

    static func color(band b: Int, haze: SIMD3<Float>) -> SIMD3<Float> {
        simd_mix(baseColor, haze, SIMD3<Float>(repeating: bandHazeMix[b]))
    }

    private static func material(band b: Int, haze: SIMD3<Float>) -> UnlitMaterial {
        let c = color(band: b, haze: haze)
        var m = UnlitMaterial(color: UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: bandOpacity[b]))
        m.faceCulling = .none
        return m
    }

    private static func makeMesh(capacity: Int) throws -> LowLevelMesh {
        var d = LowLevelMesh.Descriptor()
        d.vertexAttributes = [LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: 0)]
        d.vertexLayouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)]
        d.vertexCapacity = capacity * vertsPerBoat
        d.indexCapacity = capacity * indicesPerBoat
        d.indexType = .uint32
        let m = try LowLevelMesh(descriptor: d)
        // Figur 0…5 (Fächer), Skulls 6…9 und 10…13, Rumpf 14…17; jedes Dreieck auch rückwärts
        let tris: [(UInt32, UInt32, UInt32)] = [(0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 5),
                                                (6, 7, 8), (6, 8, 9), (10, 11, 12), (10, 12, 13),
                                                (14, 15, 16), (14, 16, 17)]
        var pattern: [UInt32] = []
        for (a, b, c) in tris { pattern += [a, b, c, a, c, b] }
        m.withUnsafeMutableIndices { raw in
            let idx = raw.bindMemory(to: UInt32.self)
            for boat in 0..<capacity {
                let base = UInt32(boat * vertsPerBoat)
                for (k, v) in pattern.enumerated() { idx[boat * indicesPerBoat + k] = base + v }
            }
        }
        m.parts.replaceAll([LowLevelMesh.Part(indexCount: indicesPerBoat, topology: .triangle,
                                              bounds: BoundingBox(min: [-1, -1, -1], max: [1, 1, 1]))])
        return m
    }

    /// Silhouetten setzen: Lage (Welt, Wasserlinie y = 0), Fahrtrichtung (`TrackPose.heading`), Kamera für die
    /// Entfernungsstufe
    func update(_ boats: [(x: Float, z: Float, heading: Float)], eye: SIMD3<Float>) {
        guard !bands.isEmpty else { return }
        for i in 0..<3 { buffers[i].removeAll(keepingCapacity: true) }
        for b in boats.prefix(capacity) {
            let d = simd_distance(SIMD2<Float>(b.x, b.z), SIMD2<Float>(eye.x, eye.z))
            let band = d < Self.bandLimits[0] ? 0 : (d < Self.bandLimits[1] ? 1 : 2)
            buffers[band].append(b)
        }
        let total = buffers.reduce(0) { $0 + $1.count }
        if total != lastCount {
            lastCount = total
            Self.log.debug("Szene: \(total, privacy: .public) Silhouetten")
        }
        for (i, band) in bands.enumerated() { write(buffers[i], into: band) }
    }

    private func write(_ boats: [(x: Float, z: Float, heading: Float)], into band: Band) {
        let n = boats.count
        band.count = n
        guard n > 0 else {
            if band.entity.isEnabled { band.entity.isEnabled = false }
            return
        }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let reach = max(Self.hullHalf, Self.oarOuter.x)
        band.mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let v = raw.bindMemory(to: SIMD3<Float>.self)
            for i in 0..<n {
                let b = boats[i]
                // Fahrtrichtung (−sin h, −cos h), rechts davon (cos h, −sin h)
                let r = SIMD3<Float>(cos(b.heading), 0, -sin(b.heading))
                let f = SIMD3<Float>(-sin(b.heading), 0, -cos(b.heading))
                let p = SIMD3<Float>(b.x, 0, b.z)
                func at(_ x: Float, _ y: Float) -> SIMD3<Float> { p + r * x + SIMD3<Float>(0, y, 0) }
                let o = i * Self.vertsPerBoat
                for (k, q) in Self.body.enumerated() { v[o + k] = at(q.x, q.y) }
                let a = Self.oarInner, c = Self.oarOuter
                for (k, s) in [Float(1), Float(-1)].enumerated() {
                    let ob = o + 6 + k * 4
                    v[ob] = at(s * a.x, a.y)
                    v[ob + 1] = at(s * c.x, c.y)
                    v[ob + 2] = at(s * c.x, c.z)
                    v[ob + 3] = at(s * a.x, a.z)
                }
                let h = o + 14
                v[h] = p - f * Self.hullHalf + SIMD3<Float>(0, Self.hullEnd, 0)
                v[h + 1] = p + SIMD3<Float>(0, Self.hullTop, 0)
                v[h + 2] = p + f * Self.hullHalf + SIMD3<Float>(0, Self.hullEnd, 0)
                v[h + 3] = p + SIMD3<Float>(0, 0.0, 0)
                lo = simd_min(lo, p - SIMD3<Float>(reach, 0, reach))
                hi = simd_max(hi, p + SIMD3<Float>(reach, 0.7, reach))
            }
        }
        band.mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: n * Self.indicesPerBoat, topology: .triangle,
                                                      bounds: BoundingBox(min: lo, max: hi))])
        if !band.entity.isEnabled { band.entity.isEnabled = true }
    }

    func clear() {
        update([], eye: .zero)
    }
}
