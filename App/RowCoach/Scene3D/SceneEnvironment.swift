import Foundation
import RowCoachKit
import simd
import UIKit

/// Himmel, Licht, Wasser und Dunst einer Szene. Später kommen Varianten dazu (Winter/Schnee, Sturm/Regen …);
/// die Szene liest nur diese Struktur, die Landschaft (USDZ) bleibt dieselbe.
/// Umgesetzt: Sommertag mit Cirruswolken, Sonnenstand frei (`forSun`); `summerSunny` = Bake-Sonne 235°/48°.
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
    /// Aufhellung rund um die Sonne (am Abend Abendrot), Farbe und Stärke (0 = aus)
    var skyGlowColor: SIMD3<Float>
    var skyGlowStrength: Float

    // MARK: Wolken (Maske sky-clouds.png aus tools/coursebuilder/sky_clouds.py, eingefärbt je Sonnenstand)
    var cirrusColor: SIMD3<Float>
    var cumulusLitColor: SIMD3<Float>
    var cumulusShadowColor: SIMD3<Float>
    /// Deckkraft der Wolken (0 = wolkenlos)
    var cloudOpacity: Float

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

    /// Sommernachmittag: genau die Sonne, die bake.py in die Gebäude rechnet (235°/48°, Südwest).
    /// Die Farben ergeben sich aus `forSun` und entsprechen den bisherigen Werten (Himmel 0.20/0.42/0.80 usw.).
    static let summerSunny = forSun(azimuth: 235, elevation: 48, name: "Sommer, sonnig")

    /// Sommertag mit Cirruswolken bei beliebigem Sonnenstand. Tiefe Sonne: wärmeres, schwächeres Licht, Abendrot am
    /// Horizont zur Sonne hin, rosa Wolken, wärmerer und dichterer Dunst. Die Höhe wird auf mindestens 2° geklemmt
    /// (`SolarPosition.minimumSceneElevation`): keine Nachtszene.
    /// Dieselben Kurven stehen in tools/coursebuilder/sky.py (Vorschauen); ändert sich eine Fassung, die andere nachziehen.
    static func forSun(azimuth: Double, elevation: Double, name: String? = nil) -> SceneEnvironment {
        let el = Float(max(elevation, SolarPosition.minimumSceneElevation))
        let h = smoothstep(2, 30, el)          // 0 = tiefe Sonne, 1 = hoch (ab 30°)
        func mix(_ low: SIMD3<Float>, _ high: SIMD3<Float>) -> SIMD3<Float> {
            simd_mix(low, high, SIMD3<Float>(repeating: h))
        }
        return SceneEnvironment(
            name: name ?? String(format: "Sonne %.0f°/%.0f°", azimuth, Double(el)),
            skyZenith: mix([0.14, 0.26, 0.54], [0.20, 0.42, 0.80]),
            skyHorizon: mix([0.88, 0.62, 0.46], [0.72, 0.82, 0.93]),
            skyBelowHorizon: mix([0.42, 0.38, 0.38], [0.55, 0.62, 0.66]),
            skyGradientExponent: 0.55,
            skyGlowColor: mix([1.0, 0.50, 0.22], [1.0, 0.97, 0.90]),
            skyGlowStrength: 0.85 + (0.22 - 0.85) * h,
            cirrusColor: mix([1.0, 0.72, 0.58], [1.0, 1.0, 1.0]),
            cumulusLitColor: mix([1.0, 0.80, 0.64], [1.0, 1.0, 1.0]),
            cumulusShadowColor: mix([0.50, 0.42, 0.48], [0.60, 0.65, 0.74]),
            cloudOpacity: 0.95,
            sunAzimuthDegrees: Float(azimuth),
            sunElevationDegrees: el,
            sunColor: mix([1.00, 0.58, 0.32], [1.0, 0.96, 0.88]),
            sunIntensity: 3000 * (0.30 + 0.70 * smoothstep(2, 40, el)),
            waterColor: [0.035, 0.10, 0.14],
            waterRoughness: 0.22,
            waterWaveStrength: 0.18,
            waterTileSize: 14,
            waterDrift: [0.10, 0.06],
            hazeColor: mix([0.84, 0.70, 0.62], [0.78, 0.84, 0.90]),
            hazeOpacity: 0.55 + (0.45 - 0.55) * h,
            hazeDistance: 4000,
            hazeHeight: 550
        )
    }

    static func forSun(_ sun: SolarPosition, name: String? = nil) -> SceneEnvironment {
        forSun(azimuth: sun.azimuthDegrees, elevation: sun.elevationDegrees, name: name)
    }

    private static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Steht die Sonne dort, wo bake.py sie in die Gebäude rechnet (235°/48°)? Sonst passt die Licht-Variante
    /// ohne Sonnenschatten besser.
    var matchesBakedSun: Bool {
        abs(sunAzimuthDegrees - Float(SunPreset.bakedSun.azimuthDegrees)) < 0.5
            && abs(sunElevationDegrees - Float(SunPreset.bakedSun.elevationDegrees)) < 0.5
    }

    /// Einheitsvektor zur Sonne (Szenenkoordinaten: x = Ost, y = oben, z = −Nord).
    var toSun: SIMD3<Float> { -sunLightDirection }

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
