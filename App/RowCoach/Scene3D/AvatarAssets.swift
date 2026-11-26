import CoreGraphics
import Foundation
import Metal
import os
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Geteilte 3D-Teile für Figur und Boot aus dem Generator `tools/avatars` (USDZ im Bundle, `Resources/Avatars/`).
///
/// - Lädt `rower_parts.usdz`, `boat_parts.usdz` und `lite_parts.usdz` einmal (asynchron, `load()` beim Szenenaufbau)
///   und hält nur die `MeshResource`s je Prim-Name (`forearm__skin`, `blade_macon_R__blade`, …). Alle Boote teilen
///   sich diese Meshes; Farben kommen als Materialien je Erscheinung (`AvatarMaterials`).
/// - Bis die Teile geladen sind (oder wenn die Dateien fehlen) bauen `RowerFigure`/`BoatModel` eine prozedurale
///   Grundform wie früher; nach dem Laden tauschen alle angemeldeten Rigs ihre Meshes aus (`BoatRig.assetsDidLoad`).
@MainActor
final class AvatarAssets {
    static let shared = AvatarAssets()

    enum State { case idle, loading, ready, failed }
    private(set) var state: State = .idle
    private var meshes: [String: MeshResource] = [:]
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let rigs = NSHashTable<BoatRig>.weakObjects()
    static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Avatar")
    static let files = ["rower_parts", "boat_parts", "lite_parts"]

    var isReady: Bool { state == .ready }

    func mesh(_ name: String) -> MeshResource? { meshes[name] }

    /// Rig für den Austausch der Meshes nach dem Laden anmelden (schwach gehalten)
    func register(_ rig: BoatRig) {
        rigs.add(rig)
    }

    /// Lädt die Teile einmal; weitere Aufrufe warten auf denselben Ladevorgang.
    func load() async {
        switch state {
        case .ready, .failed: return
        case .loading:
            await withCheckedContinuation { waiting.append($0) }
            return
        case .idle: break
        }
        state = .loading
        for file in Self.files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "usdz", subdirectory: "Avatars")
                ?? Bundle.main.url(forResource: file, withExtension: "usdz") else {
                Self.log.error("Avatar: \(file, privacy: .public).usdz fehlt im Bundle – prozedurale Grundform")
                continue
            }
            do {
                let entity = try await Entity(contentsOf: url)
                collect(entity)
            } catch {
                Self.log.error("Avatar: \(file, privacy: .public).usdz nicht lesbar: \(error.localizedDescription, privacy: .public)")
            }
        }
        state = meshes.isEmpty ? .failed : .ready
        Self.log.info("Avatar: \(self.meshes.count) Teile geladen")
        for c in waiting { c.resume() }
        waiting = []
        if state == .ready {
            for rig in rigs.allObjects { rig.assetsDidLoad() }
        }
    }

    /// Meshes nach Entity-Namen einsammeln (RealityKit benennt die Entities nach den USD-Prims; falls eine
    /// Zwischenstufe ohne Namen entsteht, gilt der Name des Elternteils)
    private func collect(_ e: Entity) {
        if let model = e.components[ModelComponent.self] {
            let name = e.name.isEmpty ? (e.parent?.name ?? "") : e.name
            if name.contains("__") || name.hasPrefix("lite_") { meshes[name] = model.mesh }
        }
        for child in e.children { collect(child) }
    }
}

// MARK: - Erscheinung für das Rig

/// Alles, was Figur und Boot zum Zeichnen brauchen (aufgelöst aus `AppearanceCatalog.Resolved` oder aus den alten
/// `BoatRig.Colors`).
struct RigLook: Equatable {
    var hairStyle = "short"
    var shirtStyle = "tank"
    var accessories: Set<String> = []
    var build = "athletic"
    var heightScale: Float = 1
    var shoulderScale: Float = 1
    var skin = RGBColor(red: 0.86, green: 0.68, blue: 0.56)
    var hair = RGBColor(red: 0.23, green: 0.16, blue: 0.13)
    var shirt = RGBColor(red: 0.10, green: 0.22, blue: 0.48)
    var hull = RGBColor(red: 0.95, green: 0.95, blue: 0.95)
    var deck = RGBColor(red: 0.95, green: 0.95, blue: 0.95)
    var stripe = RGBColor(red: 0.12, green: 0.12, blue: 0.12)
    var rigger = RGBColor(red: 0.15, green: 0.15, blue: 0.17)
    var blade = RGBColor(red: 0.95, green: 0.78, blue: 0.10)
    var shaft = RGBColor(red: 0.12, green: 0.12, blue: 0.12)
    var riggerType = "wing"
    var bladeShape = "bigblade"
    var finish = "gloss"
    var bowBall = true
    var shirtFlag: String?
    var boatFlag: String?

    static let fixedShorts = RGBColor(hex: "#2B2C30")!
    static let socks = RGBColor(hex: "#F2F2EE")!
    static let shoes = RGBColor(hex: "#3A3C40")!
    static let fittings = RGBColor(hex: "#2B2C30")!
    static let sleeve = RGBColor(hex: "#E8E8E4")!
    static let bowBallColor = RGBColor(hex: "#F4F4F1")!
    static let eyes = RGBColor(hex: "#1C1A1A")!

    /// Shorts: beim Einteiler in Trikotfarbe, sonst Anthrazit
    var shorts: RGBColor { shirtStyle == "unisuit" ? shirt : Self.fixedShorts }

    init() {}

    init(_ r: AppearanceCatalog.Resolved) {
        let c = r.character
        hairStyle = c.hairStyle
        shirtStyle = c.shirtStyle
        accessories = Set(c.accessories)
        if c.hairStyle == "cap" { accessories.insert("cap") }
        if c.hairStyle == "headband" { accessories.insert("headband") }
        build = c.build
        heightScale = Float(c.heightScale)
        shoulderScale = Float(c.shoulderScale)
        skin = r.skin
        hair = r.hair
        shirt = r.shirt
        let b = r.boat
        hull = b.hull
        deck = b.deck
        stripe = b.stripe ?? b.hull
        rigger = b.rigger
        blade = b.blade
        shaft = b.shaft
        riggerType = b.riggerType
        bladeShape = b.bladeShape
        finish = b.finish
        bowBall = b.bowBall
        shirtFlag = r.shirtFlag
        boatFlag = r.boatFlag
    }

    /// Alte Schnittstelle (Trikot, Blätter, Rumpf): Grundfigur mit diesen Farben
    init(legacy colors: BoatRig.Colors) {
        self.init()
        shirt = RGBColor(colors.shirt)
        blade = RGBColor(colors.blade)
        hull = RGBColor(colors.hull)
        deck = hull
        accessories = ["sunglasses"]
    }

    /// Dicke der Glieder je Statur (Längen bleiben, damit Hände und Füsse an Griff und Stemmbrett bleiben)
    var limbThickness: Float {
        switch build {
        case "slim": return 0.90
        case "broad": return 1.12
        default: return 1.0
        }
    }

    var isDarkSkin: Bool { skin.red + skin.green + skin.blue < 0.9 }
}

extension RGBColor {
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var w: CGFloat = 0
            color.getWhite(&w, alpha: &a)
            r = w; g = w; b = w
        }
        self.init(red: Double(r), green: Double(g), blue: Double(b))
    }
}

// MARK: - Materialien

/// Materialien je Farbe/Rauheit (geteilt), Flaggen-Texturen aus dem Emoji und Palettentexturen für `lite`.
@MainActor
enum AvatarMaterials {
    private static var cache: [String: PhysicallyBasedMaterial] = [:]

    static func pbr(_ c: RGBColor, roughness: Float, metallic: Float = 0) -> PhysicallyBasedMaterial {
        let key = "\(c.hex)|\(roughness)|\(metallic)"
        if let m = cache[key] { return m }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c.uiColor)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        cache[key] = m
        return m
    }

    /// Einheitliches, halbtransparentes und unbeleuchtetes Material (Geisterboot)
    static func ghost(_ tint: UIColor, opacity: Float) -> UnlitMaterial {
        var m = UnlitMaterial()
        m.color = .init(tint: tint)
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        m.faceCulling = .none
        m.writesDepth = false
        return m
    }

    // Flaggen

    private static var flagCache: [String: TextureResource] = [:]
    private static var flagPending: [String: Task<TextureResource?, Never>] = [:]

    /// Flaggen-Material (Textur aus dem Emoji, je Land einmal erzeugt)
    static func flag(_ emoji: String) async -> PhysicallyBasedMaterial? {
        guard let texture = await flagTexture(emoji) else { return nil }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(texture))
        m.roughness = .init(floatLiteral: 0.6)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    static func flagTexture(_ emoji: String) async -> TextureResource? {
        if let t = flagCache[emoji] { return t }
        if let p = flagPending[emoji] { return await p.value }
        let task = Task<TextureResource?, Never> { @MainActor in
            guard let image = AvatarMaterials.renderFlag(emoji) else { return nil }
            return try? await TextureResource(image: image, options: .init(semantic: .color))
        }
        flagPending[emoji] = task
        let t = await task.value
        flagPending[emoji] = nil
        if let t { flagCache[emoji] = t }
        return t
    }

    /// Zeichnet das Flaggen-Emoji (iOS liefert es als farbiges Bild) und schneidet den transparenten Rand ab.
    static func renderFlag(_ emoji: String) -> CGImage? {
        let size = CGSize(width: 192, height: 192)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: 150)])
            let b = text.size()
            text.draw(at: CGPoint(x: (size.width - b.width) / 2, y: (size.height - b.height) / 2))
        }
        guard let cg = image.cgImage else { return nil }
        return cropTransparent(cg) ?? cg
    }

    private static func cropTransparent(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        // etwas einrücken: der Emoji-Rand ist abgerundet und leicht schattiert
        let inset = 2
        let rect = CGRect(x: minX + inset, y: minY + inset, width: maxX - minX - 2 * inset, height: maxY - minY - 2 * inset)
        return image.cropping(to: rect)
    }

    // Palette (lite)

    /// Reihenfolge der Slots wie `lite.PALETTE` im Generator (u = (Slot + 0,5) / 16)
    static let paletteSlots = ["hull", "deck", "stripe", "rigger", "blade", "shaft", "skin", "shirt", "hair",
                               "shorts", "fittings", "shoes"]
    private static var paletteCache: [String: TextureResource] = [:]

    static func paletteColors(_ look: RigLook) -> [RGBColor] {
        let map: [String: RGBColor] = ["hull": look.hull, "deck": look.deck, "stripe": look.stripe,
                                       "rigger": look.rigger, "blade": look.blade, "shaft": look.shaft,
                                       "skin": look.skin, "shirt": look.shirt, "hair": look.hair,
                                       "shorts": look.shorts, "fittings": RigLook.fittings, "shoes": RigLook.shoes]
        return paletteSlots.map { map[$0] ?? .neutralGray }
    }

    static func paletteTexture(_ look: RigLook) async -> TextureResource? {
        let colors = paletteColors(look)
        let key = colors.map(\.hex).joined()
        if let t = paletteCache[key] { return t }
        var bytes = [UInt8](repeating: 255, count: 16 * 4)
        for (i, c) in colors.enumerated() {
            bytes[i * 4] = UInt8(max(0, min(255, c.red * 255)))
            bytes[i * 4 + 1] = UInt8(max(0, min(255, c.green * 255)))
            bytes[i * 4 + 2] = UInt8(max(0, min(255, c.blue * 255)))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: 16, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 64,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let t = try? await TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
        paletteCache[key] = t
        return t
    }

    static func palette(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        let d = MTLSamplerDescriptor()
        d.minFilter = .nearest
        d.magFilter = .nearest
        d.mipFilter = .notMipmapped
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        m.baseColor = .init(tint: .white, texture: .init(texture, sampler: .init(d)))
        m.roughness = .init(floatLiteral: 0.55)
        m.metallic = .init(floatLiteral: 0)
        return m
    }
}

// MARK: - Teil-Platz

/// Ein Platz für ein Teil an einem Segment: dasselbe Entity bleibt, Mesh und Material werden getauscht
/// (schneller Wechsel der Erscheinung ohne neue Entities).
@MainActor
final class PartSlot {
    let entity = ModelEntity()

    init(parent: Entity, name: String) {
        entity.name = name
        entity.isEnabled = false
        parent.addChild(entity)
    }

    /// Mesh aus den Avatar-Teilen bzw. prozeduraler Ersatz; nil = Platz leer
    func show(_ part: String?, material: any Material) {
        guard let part, let source = AvatarParts.mesh(part) else {
            if entity.isEnabled { entity.isEnabled = false }
            return
        }
        if var model = entity.model, model.mesh === source.mesh {
            model.materials = [material]
            entity.model = model
        } else {
            entity.model = ModelComponent(mesh: source.mesh, materials: [material])
        }
        entity.transform = source.transform
        if !entity.isEnabled { entity.isEnabled = true }
    }

    func setMaterial(_ material: any Material) {
        guard var model = entity.model else { return }
        model.materials = [material]
        entity.model = model
    }

    func hide() {
        if entity.isEnabled { entity.isEnabled = false }
    }
}

/// Mesh je Teil: aus den USDZ-Teilen, sonst prozeduraler Ersatz (Kästen und Kugeln wie früher, in denselben
/// Segment-Rahmen).
@MainActor
enum AvatarParts {
    struct Source {
        let mesh: MeshResource
        let transform: Transform
    }

    private static var fallback: [String: Source] = [:]

    static func mesh(_ name: String) -> Source? {
        if let m = AvatarAssets.shared.mesh(name) { return Source(mesh: m, transform: .identity) }
        if let f = fallback[name] { return f }
        guard let f = makeFallback(name) else { return nil }
        fallback[name] = f
        return f
    }

    private static func box(_ size: SIMD3<Float>, at p: SIMD3<Float>, radius: Float = 0,
                            rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) -> Source {
        Source(mesh: .generateBox(size: size, cornerRadius: radius), transform: Transform(scale: .one, rotation: rotation, translation: p))
    }

    private static func sphere(_ r: Float, at p: SIMD3<Float>) -> Source {
        Source(mesh: .generateSphere(radius: r), transform: Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: p))
    }

    private static func makeFallback(_ name: String) -> Source? {
        let D = RowerFigure.D.self
        let B = BoatModel.D.self
        switch name {
        case "hips__shorts": return box([0.30, 0.16, 0.24], at: [0, 0, 0.015], radius: 0.05)
        case "torso_tee__shirt", "torso_tank__shirt", "torso_unisuit__shirt":
            return box([0.34, 0.50, 0.20], at: [0, 0.25, 0], radius: 0.07)
        case "head__skin": return sphere(0.11, at: [0, 0.165, 0])
        case let n where n.hasPrefix("hair_"): return sphere(0.105, at: [0, 0.195, 0.025])
        case "acc_sunglasses__accessory": return box([0.17, 0.035, 0.03], at: [0, 0.18, -0.095], radius: 0.01)
        case "upperarm_bare__skin", "upperarm_tee__shirt":
            return box([0.075, D.upperArm, 0.075], at: [0, D.upperArm / 2, 0])
        case "forearm__skin": return box([0.07, D.forearm, 0.07], at: [0, D.forearm / 2, 0])
        case "thigh__shorts": return box([0.13, D.thigh, 0.13], at: [0, D.thigh / 2, 0])
        case "shin__skin": return box([0.10, D.shin, 0.10], at: [0, D.shin / 2, 0])
        case "foot__shoes": return box([0.09, 0.06, 0.25], at: [0, -0.02, -0.08])
        case "hull__hull": return Source(mesh: BoatModel.fallbackHullMesh(), transform: .identity)
        case "seat__fittings": return box([0.26, 0.04, 0.28], at: .zero)
        case "stretcher__fittings":
            return box([0.34, 0.16, 0.03], at: [0, D.footY, D.footZ - 0.06], rotation: simd_quatf(angle: 0.6, axis: [1, 0, 0]))
        case "oar_shaft__shaft":
            return box([B.inboard + B.outboard, 0.035, 0.035], at: [(B.outboard - B.inboard) / 2, 0, 0])
        case "oar_grip__fittings": return box([0.14, 0.045, 0.045], at: [-B.inboard + 0.07, 0, 0])
        case let n where n.hasPrefix("blade_"): return box([0.46, 0.19, 0.012], at: [B.outboard - 0.23, 0, 0])
        case let n where n.hasPrefix("rigger_"):
            return box([2 * B.pinX, 0.025, 0.06], at: [0, 0.14, B.pinZ])
        default: return nil
        }
    }
}
