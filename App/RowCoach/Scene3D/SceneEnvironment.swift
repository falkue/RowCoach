import Foundation
import simd
import UIKit

/// Himmel, Licht, Wasser und Dunst einer Szene. Später kommen Varianten dazu (Winter/Schnee, Sturm/Regen,
/// Abend …); die Szene liest nur diese Struktur, die Landschaft (USDZ) bleibt dieselbe.
/// Umgesetzt ist vorerst nur `summerSunny`.
struct SceneEnvironment: Equatable, Sendable {
    var name: String

    // MARK: Himmel (Skybox, zugleich Umgebungslicht und Spiegelung im Wasser)
    /// Farbe im Zenit (sRGB 0…1)
    var skyZenith: SIMD3<Float>
    /// Farbe am Horizont
    var skyHorizon: SIMD3<Float>
    /// Farbe unter dem Horizont (nur am Rand sichtbar, wichtig für das Umgebungslicht von unten)
    var skyBelowHorizon: SIMD3<Float>
    /// Exponent des Verlaufs: kleiner = blauer Himmel reicht tiefer
    var skyGradientExponent: Float

    // MARK: Sonne
    /// Kompassrichtung der Sonne in Grad (0 = Nord, 90 = Ost, 180 = Süd, 270 = West)
    var sunAzimuthDegrees: Float
    /// Höhe der Sonne über dem Horizont in Grad
    var sunElevationDegrees: Float
    var sunColor: SIMD3<Float>
    /// Beleuchtungsstärke in Lux (RealityKit-Standard 2145,7)
    var sunIntensity: Float

    // MARK: Wasser
    var waterColor: SIMD3<Float>
    var waterRoughness: Float
    /// Stärke der Wellen-Normalen (0 = spiegelglatt)
    var waterWaveStrength: Float
    /// Kachelgrösse der Wellentextur in Metern
    var waterTileSize: Float
    /// Drift der Wellen in m/s (x = Ost, y = Süd), 0 = stehend
    var waterDrift: SIMD2<Float>

    // MARK: Dunst
    var hazeColor: SIMD3<Float>
    /// Deckkraft des Dunstbands am Horizont (0 = aus)
    var hazeOpacity: Float
    /// Abstand des Dunstbands von der Kamera in Metern
    var hazeDistance: Float
    /// Höhe des Dunstbands in Metern
    var hazeHeight: Float

    static let summerSunny = SceneEnvironment(
        name: "Sommer, sonnig",
        skyZenith: [0.20, 0.42, 0.80],
        skyHorizon: [0.72, 0.82, 0.93],
        skyBelowHorizon: [0.55, 0.62, 0.66],
        skyGradientExponent: 0.55,
        sunAzimuthDegrees: 235,     // Nachmittag, Südwest
        sunElevationDegrees: 48,
        sunColor: [1.0, 0.96, 0.88],
        sunIntensity: 3000,
        waterColor: [0.035, 0.10, 0.14],
        waterRoughness: 0.22,
        waterWaveStrength: 0.18,
        waterTileSize: 14,
        waterDrift: [0.10, 0.06],
        hazeColor: [0.78, 0.84, 0.90],
        hazeOpacity: 0.45,
        hazeDistance: 4000,
        hazeHeight: 550
    )

    /// Richtung, in die das Sonnenlicht läuft (Szenenkoordinaten: x = Ost, y = oben, z = −Nord).
    var sunLightDirection: SIMD3<Float> {
        let a = sunAzimuthDegrees * .pi / 180
        let e = sunElevationDegrees * .pi / 180
        let toSun = SIMD3<Float>(sin(a) * cos(e), sin(e), -cos(a) * cos(e))
        return -simd_normalize(toSun)
    }
}

extension UIColor {
    convenience init(rgb c: SIMD3<Float>, alpha: CGFloat = 1) {
        self.init(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: alpha)
    }
}
