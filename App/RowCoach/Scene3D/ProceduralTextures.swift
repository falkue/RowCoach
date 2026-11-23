import CoreGraphics
import Foundation
import simd

/// Kleine, zur Laufzeit erzeugte Bilder für Himmel und Wasser (keine Bilddateien im Bundle nötig).
enum ProceduralTextures {

    /// Himmel als equirektangulares Bild (Breite = 2 × Höhe), nur von der Höhe über dem Horizont abhängig.
    /// Dient als Skybox und als Umgebungslicht (Spiegelung im Wasser).
    static func skyEquirect(_ env: SceneEnvironment, width: Int = 512) -> CGImage? {
        let height = width / 2
        return rgbaImage(width: width, height: height) { _, y in
            // Zeile 0 = Zenit, letzte Zeile = Nadir
            let lat = 90 - Float(y) / Float(height - 1) * 180
            let c: SIMD3<Float>
            if lat >= 0 {
                let t = pow(lat / 90, env.skyGradientExponent)
                c = simd_mix(env.skyHorizon, env.skyZenith, SIMD3<Float>(repeating: t))
            } else {
                let t = min(-lat / 8, 1)
                c = simd_mix(env.skyHorizon, env.skyBelowHorizon, SIMD3<Float>(repeating: t))
            }
            return SIMD4<Float>(c, 1)
        }
    }

    /// Kachelbare Normal-Map für kleine Wellen (Tangentenraum, z = Flächennormale).
    /// Summe von Sinuswellen mit ganzzahligen Wellenvektoren, deshalb nahtlos wiederholbar.
    static func waterNormalMap(size: Int = 256, strength: Float) -> CGImage? {
        // (kx, ky, Amplitude, Phase)
        let waves: [(Float, Float, Float, Float)] = [
            (1, 2, 0.050, 0.3), (3, -1, 0.035, 1.7), (-2, 3, 0.030, 4.1), (5, 2, 0.020, 2.2),
            (-4, -5, 0.015, 5.3), (7, -3, 0.012, 0.9), (2, 8, 0.010, 3.6), (-9, 4, 0.008, 1.1),
        ]
        let twoPi = Float.pi * 2
        return rgbaImage(width: size, height: size) { x, y in
            let u = Float(x) / Float(size), v = Float(y) / Float(size)
            var dhdu: Float = 0, dhdv: Float = 0
            for (kx, ky, a, p) in waves {
                let arg = twoPi * (kx * u + ky * v) + p
                let c = cos(arg) * a * twoPi
                dhdu += c * kx
                dhdv += c * ky
            }
            let n = simd_normalize(SIMD3<Float>(-dhdu * strength, -dhdv * strength, 1))
            return SIMD4<Float>(n * 0.5 + 0.5, 1)
        }
    }

    /// Erzeugt ein 8-Bit-RGBA-Bild (deckend) aus einer Farbfunktion (Werte 0…1).
    private static func rgbaImage(width: Int, height: Int,
                                  _ pixel: (Int, Int) -> SIMD4<Float>) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let c = simd_clamp(pixel(x, y), SIMD4<Float>(repeating: 0), SIMD4<Float>(repeating: 1))
                let i = (y * width + x) * 4
                bytes[i] = UInt8(c.x * 255 + 0.5)
                bytes[i + 1] = UInt8(c.y * 255 + 0.5)
                bytes[i + 2] = UInt8(c.z * 255 + 0.5)
                bytes[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
