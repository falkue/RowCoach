import CoreGraphics
import Foundation
import ImageIO
import simd

/// Kleine, zur Laufzeit erzeugte Bilder für Himmel, Sonne, Dunst und Wasser. Einzige Bilddatei: die Wolkenmaske.
enum ProceduralTextures {

    /// Lage der Himmelsrichtungen im equirektangularen Bild, wie RealityKit es als Skybox aufspannt:
    /// Spalte (Anteil der Breite), in der Norden (−z) liegt, und Laufrichtung des Azimuts nach rechts (+1 = Ost).
    /// Nicht durch eine Dokumentation belegt: Prüfen mit `-demoSun evening` – das Abendrot im Himmel muss bei der
    /// Sonnenscheibe (SkyRig, geometrisch immer richtig) stehen. Sonst hier nachstellen (0 / 0.25 / 0.75, −1).
    static let equirectNorthU: Float = 0.5
    static let equirectAzimuthSign: Float = 1

    /// Himmel als equirektangulares Bild (Breite = 2 × Höhe, Zeile 0 = Zenit): Verlauf Horizont → Zenit, Aufhellung
    /// bzw. Abendrot um die Sonne und Wolken aus der Maske (`CloudMask`, eingefärbt nach `env`).
    /// Dient als Skybox, Umgebungslicht und Spiegelung im Wasser (die Wolken spiegeln sich mit).
    /// Rechnet die Zeilen parallel (2048 × 1024 auf dem A12X im Release-Build deutlich unter 0,1 s); einmal je
    /// Szenenaufbau, danach kostet der Himmel pro Bild nichts.
    /// Dieselbe Rechnung steht in tools/coursebuilder/sky.py (Vorschauen).
    static func skyEquirect(_ env: SceneEnvironment, clouds: CloudMask? = nil, width: Int = 2048) -> CGImage? {
        let w = max(width, 64), h = w / 2
        // Spalten: Richtung in der Ebene (sin/cos des Azimuts)
        var colSin = [Float](repeating: 0, count: w), colCos = [Float](repeating: 0, count: w)
        for x in 0..<w {
            let u = (Float(x) + 0.5) / Float(w)
            let az = (u - equirectNorthU) * 2 * Float.pi * equirectAzimuthSign
            colSin[x] = sin(az)
            colCos[x] = cos(az)
        }
        let toSun = env.toSun
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        bytes.withUnsafeMutableBufferPointer { buf in
            guard let out = buf.baseAddress else { return }
            colSin.withUnsafeBufferPointer { cs in
                colCos.withUnsafeBufferPointer { cc in
                    DispatchQueue.concurrentPerform(iterations: h) { y in
                        skyRow(y: y, width: w, height: h, env: env, toSun: toSun, clouds: clouds,
                               colSin: cs, colCos: cc, out: out + y * w * 4)
                    }
                }
            }
        }
        return makeImage(bytes, width: w, height: h)
    }

    /// Eine Bildzeile des Himmels (siehe `skyEquirect`).
    private static func skyRow(y: Int, width w: Int, height h: Int, env: SceneEnvironment, toSun: SIMD3<Float>,
                               clouds: CloudMask?, colSin: UnsafeBufferPointer<Float>,
                               colCos: UnsafeBufferPointer<Float>, out: UnsafeMutablePointer<UInt8>) {
        let lat = 90 - (Float(y) + 0.5) / Float(h) * 180
        let latR = lat * .pi / 180
        let sl = sin(latR), cl = cos(latR)
        let base: SIMD3<Float>
        var t: Float = 0
        var glowRow: Float = 1
        if lat >= 0 {
            t = pow(lat / 90, env.skyGradientExponent)
            base = simd_mix(env.skyHorizon, env.skyZenith, SIMD3<Float>(repeating: t))
        } else {
            base = simd_mix(env.skyHorizon, env.skyBelowHorizon, SIMD3<Float>(repeating: min(-lat / 8, 1)))
            glowRow = max(0, 1 + lat / 8)
        }
        glowRow *= env.skyGlowStrength * (1 - 0.5 * t)
        // Wolkenmaske: obere Bildhälfte = Zeilen der Maske (Zenit … Horizont)
        var maskRow: UnsafePointer<UInt8>? = nil
        if lat > 0, let m = clouds, env.cloudOpacity > 0 {
            let r = min(Int((90 - lat) / 90 * Float(m.height)), m.height - 1)
            maskRow = m.row(r)
        }
        let cirrusScale = 0.92 + 0.08 * t
        for x in 0..<w {
            let d = SIMD3<Float>(cl * colSin[x], sl, -cl * colCos[x])
            let ang = acos(min(max(simd_dot(d, toSun), -1), 1))
            let a1 = ang / 0.50, a2 = ang / 0.12
            let g = min(glowRow * (0.65 * exp(-a1 * a1) + 0.35 * exp(-a2 * a2)), 1)
            var c = simd_mix(base, env.skyGlowColor, SIMD3<Float>(repeating: g))
            if let row = maskRow, let m = clouds {
                let px = row + min(x * m.width / w, m.width - 1) * 4
                let ci = Float(px[0]) / 255 * env.cloudOpacity
                if ci > 0.002 {
                    let cc = simd_mix(env.cirrusColor, env.skyGlowColor, SIMD3<Float>(repeating: min(g * 0.6, 1)))
                        * cirrusScale
                    c = simd_mix(c, cc, SIMD3<Float>(repeating: ci))
                }
                let cu = Float(px[1]) / 255 * env.cloudOpacity
                if cu > 0.002 {
                    let lit = Float(px[2]) / 255
                    var uc = simd_mix(env.cumulusShadowColor, env.cumulusLitColor, SIMD3<Float>(repeating: lit))
                    uc = simd_mix(uc, env.skyHorizon, SIMD3<Float>(repeating: 0.10))
                    c = simd_mix(c, uc, SIMD3<Float>(repeating: cu))
                }
            }
            c = simd_clamp(c, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
            let o = out + x * 4
            o[0] = UInt8(c.x * 255 + 0.5)
            o[1] = UInt8(c.y * 255 + 0.5)
            o[2] = UInt8(c.z * 255 + 0.5)
            o[3] = 255
        }
    }

    /// Sonnenscheibe mit Hof für das Sonnen-Billboard (SkyRig): RGBA, Farbe mit Alpha vormultipliziert, damit es
    /// gleich aussieht, ob RealityKit die Deckkraft aus Alpha oder aus dem Rotkanal liest. Das Bild deckt
    /// ±`halfAngleDegrees` um die Sonnenmitte ab.
    static func sunSprite(_ env: SceneEnvironment, size: Int = 256, halfAngleDegrees: Float) -> CGImage? {
        let low = 1 - min(max((env.sunElevationDegrees - 2) / 28, 0), 1)   // 1 = tiefe Sonne
        let disc = 0.32 / halfAngleDegrees * (1 + 0.5 * low)               // Radius der Scheibe (Anteil)
        let discColor = simd_mix(SIMD3<Float>(1.0, 0.99, 0.95), SIMD3<Float>(1.0, 0.78, 0.52), SIMD3<Float>(repeating: low))
        let haloColor = simd_mix(env.sunColor, env.skyGlowColor, SIMD3<Float>(repeating: 0.5))
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) + 0.5) / Float(size) * 2 - 1
                let dy = (Float(y) + 0.5) / Float(size) * 2 - 1
                let r = (dx * dx + dy * dy).squareRoot()
                let core = 1 - min(max((r - disc) / (disc * 0.25), 0), 1)
                let halo = (0.45 + 0.25 * low) * exp(-pow(r / 0.30, 2)) + 0.35 * exp(-pow(r / (disc * 2.2), 2))
                let edge = 1 - min(max((r - 0.9) / 0.1, 0), 1)                   // Rand sicher durchsichtig
                let alpha = min(max(core, Float(halo)), 1) * edge
                let col = simd_mix(haloColor, discColor, SIMD3<Float>(repeating: core)) * alpha
                let i = (y * size + x) * 4
                bytes[i] = UInt8(min(col.x, 1) * 255 + 0.5)
                bytes[i + 1] = UInt8(min(col.y, 1) * 255 + 0.5)
                bytes[i + 2] = UInt8(min(col.z, 1) * 255 + 0.5)
                bytes[i + 3] = UInt8(alpha * 255 + 0.5)
            }
        }
        return makeImage(bytes, width: size, height: size, alpha: true)
    }

    /// Farbe des Dunstrings je Azimut (Breite = Umfang, u = 0 bei Winkel 0 des Rings, siehe `SkyRig.ringMesh`):
    /// zur Sonne hin wärmer. Die Richtung kommt aus der Geometrie, hängt also nicht an der Skybox-Lage.
    static func hazeStrip(_ env: SceneEnvironment, width: Int = 256) -> CGImage? {
        rgbaImage(width: width, height: 2) { x, _ in
            let a = 2 * Float.pi * (Float(x) + 0.5) / Float(width)
            // Ringpunkt (cos a, sin a) in (x, z); Azimut ab Nord (−z) im Uhrzeigersinn
            let az = atan2(cos(a), -sin(a)) * 180 / .pi
            var da = (az - env.sunAzimuthDegrees + 540).truncatingRemainder(dividingBy: 360) - 180
            if da < -180 { da += 360 }
            let lobe = pow(max(cos(da * .pi / 180), 0), 3)
            let c = simd_mix(env.hazeColor, env.skyGlowColor, SIMD3<Float>(repeating: 0.6 * env.skyGlowStrength * lobe))
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
        return makeImage(bytes, width: width, height: height)
    }

    /// 8-Bit-RGBA-Bytes → CGImage (`alpha`: mit vormultipliziertem Alpha, sonst deckend).
    private static func makeImage(_ bytes: [UInt8], width: Int, height: Int, alpha: Bool = false) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: info.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Wolkenmaske aus dem Bundle (`sky-clouds.png`, erzeugt von tools/coursebuilder/sky_clouds.py): obere
/// Himmelshälfte, R = Cirrus, G = Cumuli, B = Licht auf den Cumuli. Einmal gelesen und behalten (≈ 4 MB).
final class CloudMask: @unchecked Sendable {
    let width: Int
    let height: Int
    /// eigener, fester Speicher (RGBA), damit `row` einen gültigen Zeiger liefern kann
    private let storage: UnsafeMutablePointer<UInt8>

    private init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        storage = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        storage.initialize(from: bytes, count: width * height * 4)
    }

    deinit { storage.deallocate() }

    /// Zeiger auf Zeile `r` (RGBA, 4 Byte je Pixel). Gültig, solange die Maske lebt.
    func row(_ r: Int) -> UnsafePointer<UInt8> {
        UnsafePointer(storage + r * width * 4)
    }

    /// nil, wenn die Datei fehlt (dann wolkenloser Himmel).
    static let bundled: CloudMask? = {
        guard let url = Bundle.main.url(forResource: "sky-clouds", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? CloudMask(width: w, height: h, bytes: bytes) : nil
    }()
}
