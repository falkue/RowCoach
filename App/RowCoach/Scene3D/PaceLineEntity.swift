import Foundation
import RealityKit
import simd
import UIKit

/// Tempo-Linie in der 3D-Szene (freies Rudern): ein „Geisterboot“ – dieselbe Figur und dasselbe Skiff wie das eigene
/// Boot (`BoatRig` mit einheitlichem, halbtransparentem und unbeleuchtetem Material), im selben Schlagtakt – und eine
/// dünne, flache Bojenlinie quer über die Bahn (14 m) kurz hinter seinem Heck.
///
/// - Bezugspunkt: Der Ursprung von `root` ist die Distanz der Linie; das Geisterboot steht dort mit demselben
///   Bezugspunkt wie das eigene Boot (Wasserlinie unter dem Ausleger). Abstand 0 = beide Boote genau nebeneinander.
/// - Die Bojenlinie liegt 0,6 m hinter dem Heck (Heck bei +3,6 m), also ausserhalb der Reichweite der Skulls
///   (höchstens ca. 2 m vor und hinter der Dolle), und knapp über dem Wasser; sie verschmilzt nicht mit den Skulls.
/// - Eigene Farbe (Magenta), damit sie sich von den Trainings-Toren (orange, blau, gelbgrün, violett, weiss) abhebt.
/// - Ohne Schatten. Position und Richtung setzt `RowingSceneController` pro Bild (die Distanz glättet er selbst).
@MainActor
final class PaceLineEntity {
    let root = Entity()
    /// Band auf dem Wasser (flach, stark transparent)
    private let strip: ModelEntity
    /// dünne Leine mit kleinen Bojen knapp über dem Wasser
    private let chain: ModelEntity
    private let ghost: BoatRig

    static let color = UIColor(red: 0.98, green: 0.32, blue: 0.74, alpha: 1)
    /// Geisterboot: hell weiss-magenta, hebt sich deutlich vom Wasser ab
    static let ghostColor = UIColor(red: 1.0, green: 0.70, blue: 0.92, alpha: 1)
    private static let halfWidth: Float = 7
    /// Lage der Bojenlinie relativ zum Bezugspunkt (m, +z = Richtung Heck)
    private static let lineOffsetZ: Float = 4.2
    /// Geisterboot ausblenden, wenn das eigene Boot näher ist (m), damit es nicht im Boot steckt
    private static let ghostHideDistance = 5.0

    init() {
        let w = Self.halfWidth
        let z = Self.lineOffsetZ
        let stripMesh = GateEntity.boxMesh(name: "paceline-strip", boxes: [
            (center: [0, 0.03, z], size: [2 * w, 0.01, 0.5]),
        ])
        var bars: [(center: SIMD3<Float>, size: SIMD3<Float>)] = [
            (center: [0, 0.07, z], size: [2 * w, 0.04, 0.04]),           // Leine
        ]
        for x in [-w, -w * 2 / 3, -w / 3, w / 3, w * 2 / 3, w] {         // kleine Bojen, Mitte frei
            bars.append((center: [x, 0.08, z], size: [0.22, 0.16, 0.22]))
        }
        let chainMesh = GateEntity.boxMesh(name: "paceline-chain", boxes: bars)

        var stripMaterial = UnlitMaterial()
        stripMaterial.color = .init(tint: Self.color)
        stripMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        stripMaterial.faceCulling = .none
        stripMaterial.writesDepth = false

        var chainMaterial = UnlitMaterial()
        chainMaterial.color = .init(tint: Self.color)
        chainMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        chainMaterial.faceCulling = .none

        strip = ModelEntity(mesh: stripMesh, materials: [stripMaterial])
        chain = ModelEntity(mesh: chainMesh, materials: [chainMaterial])
        ghost = BoatRig(ghostTint: Self.ghostColor, ghostOpacity: 0.6)
        for e in [strip, chain] {
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(e)
        }
        root.addChild(ghost.root)
        root.name = "paceline"
        root.isEnabled = false
    }

    /// Lage der Linie (Szenenkoordinaten, heading wie `TrackPose`); `boatX`/`boatZ` = angezeigte Bootsposition.
    func place(x: Double, z: Double, heading: Double, boatX: Double, boatZ: Double) {
        root.position = [Float(x), 0, Float(z)]
        root.orientation = simd_quatf(angle: Float(heading), axis: [0, 1, 0])
        let near = hypot(x - boatX, z - boatZ) < Self.ghostHideDistance
        if ghost.root.isEnabled == near { ghost.root.isEnabled = !near }
    }

    /// Schlagstellung der Geisterfigur (nur, solange sie sichtbar ist)
    func applyStroke(_ pose: BoatRig.StrokePose) {
        guard root.isEnabled, ghost.root.isEnabled else { return }
        ghost.apply(pose)
    }
}
