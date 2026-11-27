import Foundation
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Ruderfigur aus starren, weichen Segmenten (Teile aus `tools/avatars`, siehe docs/avatar/SPEC.md „Umsetzung 3D“).
///
/// Koordinaten: crew-System von `BoatRig` (Figur schaut nach −z, zum Heck = zur Kamera). Jedes Segment ist ein Entity
/// mit Ursprung im Gelenk; die Teile darin (Haut, Trikot, Haare, …) sind `PartSlot`s, deren Mesh und Material beim
/// Wechsel der Erscheinung getauscht werden. Dieselbe Rechnung steht in tools/avatars/rig.py (Vorschaubilder).
///
/// | Segment | Ursprung | Achse | Teile |
/// |---|---|---|---|
/// | pelvis | Hüftgelenk-Mitte (Rollsitz) | dreht mit der Oberkörperneigung | Becken, Torso (Trikotform), Brustflagge |
/// | head | Halsansatz (pelvis + 0,50 · Höhe) | 40 % der Neigung (Blick bleibt zum Heck) | Kopf, Augen (Iris + Sklera), Frisur, Bart, Brille, Kopfbedeckung (Cap, Stirnband, Kopftuch, Patka) |
/// | upperarm ×2 | Schulter | +y zum Ellbogen | Oberarm (+ Ärmel beim T-Shirt) |
/// | forearm ×2 | Ellbogen | +y zur Griffmitte (Hand am Ende) | Unterarm mit Faust (beim Langarm: Ärmel + Hand), Uhr (links) |
/// | thigh ×2 | Hüftgelenk ±0,10 | +y zum Knie | Shorts, Haut |
/// | shin ×2 | Knie | +y zum Knöchel | Haut, Socke |
/// | foot ×2 | Knöchel am Stemmbrett | fest | Schuh |
@MainActor
final class RowerFigure {
    /// Masse (Meter) – wie tools/avatars/figure.py
    enum D {
        static let hipY: Float = 0.26
        static let footY: Float = 0.14
        static let footZ: Float = -0.45
        static let hipHalf: Float = 0.10
        static let footHalf: Float = 0.12
        static let thigh: Float = 0.48
        static let shin: Float = 0.48
        static let torsoTop: Float = 0.50
        static let shoulderY: Float = 0.46
        static let shoulderHalf: Float = 0.17
        static let upperArm: Float = 0.31
        static let forearm: Float = 0.37
        /// Anteil der Oberkörperneigung, den der Kopf zurückdreht
        static let headCounter: Float = 0.6
        /// Arme dürfen sich höchstens so weit strecken, um den Griff zu erreichen
        static let maxStretch: Float = 1.08
    }

    let root = Entity()
    private let pelvis = Entity()
    private let head = Entity()
    private let upperArms = [Entity(), Entity()]      // rechts, links
    private let forearms = [Entity(), Entity()]
    private let thighs = [Entity(), Entity()]
    private let shins = [Entity(), Entity()]
    private let feet = [Entity(), Entity()]

    private let chestFlag: PartSlot
    /// Plätze je Segment (wachsen bei Bedarf); was die Regel nicht nennt, ist aus
    private var slots: [String: [PartSlot]] = [:]
    private var segments: [String: Entity] = [:]
    private var warned = Set<String>()

    private(set) var look = RigLook()
    private let ghost: UnlitMaterial?
    private var flagToken = 0

    init(ghost: UnlitMaterial?) {
        self.ghost = ghost
        root.name = "figure"
        for e in [pelvis, head] + upperArms + forearms + thighs + shins + feet { root.addChild(e) }
        pelvis.name = "pelvis"
        head.name = "head"
        chestFlag = PartSlot(parent: pelvis, name: "flag-chest")
        segments = ["pelvis": pelvis, "head": head,
                    "upperarm_R": upperArms[0], "upperarm_L": upperArms[1],
                    "forearm_R": forearms[0], "forearm_L": forearms[1],
                    "thigh_R": thighs[0], "thigh_L": thighs[1], "shin_R": shins[0], "shin_L": shins[1],
                    "foot_R": feet[0], "foot_L": feet[1]]
    }

    private func mat(_ c: RGBColor, _ roughness: Float, metallic: Float = 0) -> any Material {
        if let ghost { return ghost }
        return AvatarMaterials.pbr(c, roughness: roughness, metallic: metallic)
    }

    /// Form der Erscheinung für die gemeinsame Teile-Regel
    private static func shape(_ look: RigLook) -> AvatarPartRules.Shape {
        AvatarPartRules.Shape(hairStyle: look.hairStyle, shirtStyle: look.shirtStyle, legStyle: look.legStyle,
                              beard: look.beard, accessories: look.accessories.sorted())
    }

    /// Material je Farbschlüssel der Regel (nil = unbekannter Schlüssel → Teil bleibt aus)
    private func material(_ key: String, _ look: RigLook) -> (any Material)? {
        if let ghost { return ghost }
        let unisuit = look.shirtStyle == "unisuit"
        switch key {
        case "skin": return AvatarMaterials.skin(look)
        case "hair": return AvatarMaterials.hair(look.hair, curly: ["curly", "afro"].contains(look.hairStyle))
        case "beard": return AvatarMaterials.hair(look.hair, curly: false, beard: true)
        case "shirt": return AvatarMaterials.pbr(look.shirt, roughness: unisuit ? 0.45 : 0.75)
        case "shorts": return AvatarMaterials.pbr(look.shorts, roughness: unisuit ? 0.45 : 0.8)
        case "socks": return AvatarMaterials.pbr(RigLook.socks, roughness: 0.8)
        case "shoes": return AvatarMaterials.pbr(RigLook.shoes, roughness: 0.7)
        case "eyes": return AvatarMaterials.pbr(RigLook.eyes, roughness: 0.2)
        case "eyes_hl": return AvatarMaterials.pbr(RGBColor(hex: "#F3EFE8")!, roughness: 0.25)
        case "headwear": return AvatarMaterials.pbr(look.shirt, roughness: 0.8)
        case "cap": return AvatarMaterials.pbr(look.shirt, roughness: 0.75)
        case "headband": return AvatarMaterials.pbr(RGBColor(hex: "#F2F2EE")!, roughness: 0.8)
        case "sunglasses":
            let frame = look.isDarkSkin ? RGBColor(hex: "#C9CCD1")! : RGBColor(hex: "#1E1F22")!
            return AvatarMaterials.pbr(frame, roughness: 0.15, metallic: 0.6)
        case "watch": return AvatarMaterials.pbr(RGBColor(hex: "#1E1F22")!, roughness: 0.3)
        default: return nil
        }
    }

    private func warnOnce(_ text: String) {
        guard warned.insert(text).inserted else { return }
        AvatarAssets.log.error("Avatar: \(text, privacy: .public)")
    }

    /// Teile und Farben für eine Erscheinung setzen. Welche Teile sichtbar sind, entscheidet allein
    /// `AvatarPartRules.figureParts` (Kit, dieselbe Regel wie die Vorschau); jedes andere Teil ist aus, jedes sichtbare
    /// bekommt das Material seines Farbschlüssels. Fehlt ein Mesh oder ist ein Schlüssel unbekannt: aus + Warnung.
    func configure(_ look: RigLook) {
        self.look = look
        var used: [String: Int] = [:]
        for part in AvatarPartRules.figureParts(Self.shape(look)) {
            guard let segment = segments[part.segment] else {
                warnOnce("unbekanntes Segment \(part.segment) für \(part.prim)")
                continue
            }
            guard let material = material(part.color, look) else {
                warnOnce("unbekannter Farbschlüssel \(part.color) für \(part.prim)")
                continue
            }
            guard AvatarParts.mesh(part.prim) != nil else {
                // vor dem Laden fehlen viele Teile (prozedurale Grundform) – warnen erst danach
                if AvatarAssets.shared.isReady { warnOnce("Teil \(part.prim) fehlt – bleibt aus") }
                continue
            }
            let i = used[part.segment, default: 0]
            used[part.segment] = i + 1
            var list = slots[part.segment] ?? []
            if i >= list.count {
                list.append(PartSlot(parent: segment, name: "\(part.segment)-\(i)"))
                slots[part.segment] = list
            }
            list[i].show(part.prim, material: material)
            list[i].entity.name = part.prim
        }
        // alles, was die Regel diesmal nicht nennt, aus
        for (segment, list) in slots {
            for slot in list.dropFirst(used[segment, default: 0]) { slot.hide() }
        }
        if ghost != nil {
            for list in slots.values { for slot in list {
                slot.entity.components.set(DynamicLightShadowComponent(castsShadow: false))
            } }
        }
        // Flagge auf der Brust (die Kamera sieht die Figur von vorne): Textur aus dem Emoji, sobald sie da ist
        flagToken += 1
        chestFlag.hide()
        if let emoji = look.shirtFlag, ghost == nil, AvatarAssets.shared.mesh("flag_chest__flag") != nil {
            let token = flagToken
            Task { @MainActor [weak self] in
                guard let m = await AvatarMaterials.flag(emoji), let self, self.flagToken == token else { return }
                self.chestFlag.show("flag_chest__flag", material: m)
            }
        }
    }

    /// Stellung: Hüfte auf dem Rollsitz bei `hipZ`, Oberkörperneigung `lean` (rad, positiv = nach vorne),
    /// Griffpunkte der Skulls (rechts, links) im crew-System.
    func apply(hipZ: Float, lean: Float, handles: [SIMD3<Float>]) {
        let hs = look.heightScale, ss = look.shoulderScale, th = look.limbThickness
        let hip = SIMD3<Float>(0, D.hipY, hipZ)
        // Drehung um +x mit negativem Winkel neigt nach vorne (−z)
        let qLean = simd_quatf(angle: -lean, axis: [1, 0, 0])
        pelvis.position = hip
        pelvis.orientation = qLean
        pelvis.scale = [th * ss, hs, th * (look.build == "broad" ? 1.1 : 1)]
        head.position = hip + qLean.act([0, D.torsoTop * hs, 0])
        head.orientation = simd_quatf(angle: -lean * (1 - D.headCounter), axis: [1, 0, 0])
        head.scale = SIMD3<Float>(repeating: hs.squareRoot())

        for (i, s) in [Float(1), Float(-1)].enumerated() where i < handles.count {
            let shoulder = hip + qLean.act([s * D.shoulderHalf * ss, D.shoulderY * hs, 0])
            let l1 = D.upperArm * hs, l2 = D.forearm * hs
            let (elbow, k) = Self.twoBone(shoulder, handles[i], l1, l2, pole: [s * 0.75, -0.35, 0.55],
                                          maxStretch: D.maxStretch)
            let toHand = handles[i] - elbow
            let hand = elbow + toHand / max(simd_length(toHand), 1e-5) * l2 * k
            Self.segment(upperArms[i], from: shoulder, to: elbow, hint: [s, 0, 0], scale: [th, hs * k, th])
            Self.segment(forearms[i], from: elbow, to: hand, hint: [s, 0, 0], scale: [th, hs * k, th])
        }
        for (i, s) in [Float(1), Float(-1)].enumerated() {
            let h = SIMD3<Float>(s * D.hipHalf, D.hipY, hipZ)
            let f = SIMD3<Float>(s * D.footHalf, D.footY, D.footZ)
            let (knee, k) = Self.twoBone(h, f, D.thigh, D.shin, pole: [s * 0.12, 1, 0], maxStretch: 1.08)
            Self.segment(thighs[i], from: h, to: knee, hint: [s, 0, 0], scale: [th, k, th])
            Self.segment(shins[i], from: knee, to: f, hint: [s, 0, 0], scale: [th, k, th])
            feet[i].position = f
            feet[i].scale = [th, 1, 1]
        }
    }

    // MARK: - Geometrie

    /// Zwei Glieder (Längen l1, l2) von a nach b, Gelenk zur Seite `pole`. Ist b zu weit, strecken sich beide
    /// bis `maxStretch`; Ergebnis: Gelenkpunkt und Streckfaktor.
    static func twoBone(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ l1: Float, _ l2: Float, pole: SIMD3<Float>,
                        maxStretch: Float) -> (SIMD3<Float>, Float) {
        let d = b - a
        let dist = simd_length(d)
        var k: Float = 1
        if dist > (l1 + l2) * 0.999 { k = min(dist / ((l1 + l2) * 0.999), maxStretch) }
        let l1s = l1 * k, l2s = l2 * k
        let distC = max(min(dist, (l1s + l2s) * 0.999), 1e-4)
        let u = d / max(dist, 1e-5)
        let x = (l1s * l1s - l2s * l2s + distC * distC) / (2 * distC)
        let h = (max(l1s * l1s - x * x, 0)).squareRoot()
        var pp = pole - u * simd_dot(pole, u)
        let ppl = simd_length(pp)
        pp = ppl > 1e-5 ? pp / ppl : SIMD3<Float>(0, 1, 0)
        return (a + u * x + pp * h, k)
    }

    /// Segment-Entity: Ursprung `from`, y-Achse Richtung `to`, x-Achse möglichst nahe `hint`
    static func segment(_ e: Entity, from: SIMD3<Float>, to: SIMD3<Float>, hint: SIMD3<Float>, scale: SIMD3<Float>) {
        e.position = from
        e.orientation = basis(y: to - from, hint: hint)
        e.scale = scale
    }

    static func basis(y dir: SIMD3<Float>, hint: SIMD3<Float>) -> simd_quatf {
        let len = simd_length(dir)
        let y = len > 1e-6 ? dir / len : SIMD3<Float>(0, 1, 0)
        var x = hint - y * simd_dot(hint, y)
        if simd_length(x) < 1e-5 { x = simd_cross(y, [0, 0, 1]) }
        x = simd_normalize(x)
        let z = simd_cross(x, y)
        return simd_quatf(simd_float3x3(columns: (x, y, z)))
    }
}
