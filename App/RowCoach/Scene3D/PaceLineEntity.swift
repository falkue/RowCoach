import Foundation
import RealityKit
import simd
import UIKit

/// Tempo-Linie in der 3D-Szene (freies Rudern): ein ruhiges, leuchtendes Band quer über die Bahn (14 m) mit
/// einer niedrigen Bojenkette und einem halbtransparenten „Geisterboot“ in der Mitte.
/// Eigene Farbe (Magenta), damit sie sich von den Trainings-Toren (orange, blau, gelbgrün, violett, weiss) abhebt.
/// Drei ModelEntities, zusammen 96 Dreiecke, ohne Schatten. Position und Richtung setzt `RowingSceneController`
/// pro Bild (die Distanz der Linie glättet er selbst).
@MainActor
final class PaceLineEntity {
    let root = Entity()
    /// Band auf dem Wasser (flach, halbtransparent) – gut sichtbar, wenn man nahe dran ist
    private let strip: ModelEntity
    /// niedrige Leiste mit Bojen – aus der Ferne sichtbar (ein flaches Band verschwindet bei flachem Blickwinkel)
    private let chain: ModelEntity
    private let ghost: ModelEntity

    static let color = UIColor(red: 0.98, green: 0.32, blue: 0.74, alpha: 1)
    private static let halfWidth: Float = 7
    /// Geisterboot ausblenden, wenn das eigene Boot näher ist (m), damit es nicht im Boot steckt
    private static let ghostHideDistance = 5.0

    init() {
        let w = Self.halfWidth
        let stripMesh = GateEntity.boxMesh(name: "paceline-strip", boxes: [
            (center: [0, 0.04, 0], size: [2 * w, 0.02, 0.9]),
        ])
        var bars: [(center: SIMD3<Float>, size: SIMD3<Float>)] = [
            (center: [0, 0.2, 0], size: [2 * w, 0.12, 0.05]),          // Leiste
        ]
        for x in [-w, -w / 2, w / 2, w] {                              // Bojen (Mitte frei für das Boot)
            bars.append((center: [x, 0.18, 0], size: [0.36, 0.36, 0.36]))
        }
        let chainMesh = GateEntity.boxMesh(name: "paceline-chain", boxes: bars)
        // Geisterboot: Rumpf und schmales Deck, Mitte auf der Linie, Bug nach −z
        let ghostMesh = GateEntity.boxMesh(name: "paceline-ghost", boxes: [
            (center: [0, 0.08, 0], size: [0.34, 0.16, 7.6]),
            (center: [0, 0.2, 0.3], size: [0.2, 0.08, 3.0]),
        ])

        var stripMaterial = UnlitMaterial()
        stripMaterial.color = .init(tint: Self.color)
        stripMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        stripMaterial.faceCulling = .none
        stripMaterial.writesDepth = false

        var chainMaterial = UnlitMaterial()
        chainMaterial.color = .init(tint: Self.color)
        chainMaterial.faceCulling = .none

        var ghostMaterial = UnlitMaterial()
        ghostMaterial.color = .init(tint: Self.color)
        ghostMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        ghostMaterial.writesDepth = false

        strip = ModelEntity(mesh: stripMesh, materials: [stripMaterial])
        chain = ModelEntity(mesh: chainMesh, materials: [chainMaterial])
        ghost = ModelEntity(mesh: ghostMesh, materials: [ghostMaterial])
        for e in [strip, chain, ghost] {
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(e)
        }
        root.name = "paceline"
        root.isEnabled = false
    }

    /// Lage der Linie (Szenenkoordinaten, heading wie `TrackPose`); `boatX`/`boatZ` = angezeigte Bootsposition.
    func place(x: Double, z: Double, heading: Double, boatX: Double, boatZ: Double) {
        root.position = [Float(x), 0, Float(z)]
        root.orientation = simd_quatf(angle: Float(heading), axis: [0, 1, 0])
        let near = hypot(x - boatX, z - boatZ) < Self.ghostHideDistance
        if ghost.isEnabled == near { ghost.isEnabled = !near }
    }
}
