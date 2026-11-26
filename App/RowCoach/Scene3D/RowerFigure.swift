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

    private let hips, torsoA, torsoB, chestFlag: PartSlot
    private let headSkin, eyes, eyesWhite, hair, beard, sunglasses, headwear: PartSlot
    private let upperA, upperB, forearm, forearmB, thighA, thighB, shinA, shinB, foot: [PartSlot]
    private let watch: PartSlot

    private(set) var look = RigLook()
    private let ghost: UnlitMaterial?
    private var flagToken = 0

    init(ghost: UnlitMaterial?) {
        self.ghost = ghost
        root.name = "figure"
        for e in [pelvis, head] + upperArms + forearms + thighs + shins + feet { root.addChild(e) }
        pelvis.name = "pelvis"
        head.name = "head"
        hips = PartSlot(parent: pelvis, name: "hips")
        torsoA = PartSlot(parent: pelvis, name: "torso-a")
        torsoB = PartSlot(parent: pelvis, name: "torso-b")
        chestFlag = PartSlot(parent: pelvis, name: "flag-chest")
        headSkin = PartSlot(parent: head, name: "head-skin")
        eyes = PartSlot(parent: head, name: "eyes")
        eyesWhite = PartSlot(parent: head, name: "eyes-white")
        beard = PartSlot(parent: head, name: "beard")
        hair = PartSlot(parent: head, name: "hair")
        sunglasses = PartSlot(parent: head, name: "sunglasses")
        headwear = PartSlot(parent: head, name: "headwear")
        upperA = upperArms.map { PartSlot(parent: $0, name: "upperarm-a") }
        upperB = upperArms.map { PartSlot(parent: $0, name: "upperarm-b") }
        forearm = forearms.map { PartSlot(parent: $0, name: "forearm") }
        forearmB = forearms.map { PartSlot(parent: $0, name: "forearm-b") }
        watch = PartSlot(parent: forearms[1], name: "watch")
        thighA = thighs.map { PartSlot(parent: $0, name: "thigh-a") }
        thighB = thighs.map { PartSlot(parent: $0, name: "thigh-b") }
        shinA = shins.map { PartSlot(parent: $0, name: "shin-a") }
        shinB = shins.map { PartSlot(parent: $0, name: "shin-b") }
        foot = feet.map { PartSlot(parent: $0, name: "foot") }
    }

    private func mat(_ c: RGBColor, _ roughness: Float, metallic: Float = 0) -> any Material {
        if let ghost { return ghost }
        return AvatarMaterials.pbr(c, roughness: roughness, metallic: metallic)
    }

    /// Frisuren, die unter der Cap als kurze Haarkappe erscheinen (lange Formen bleiben sichtbar)
    private static let capHair: Set<String> = ["short", "buzz", "curly", "afro", "headband", "cap"]

    /// Teile und Farben für eine Erscheinung setzen (dieselben Entities, nur Mesh/Material getauscht).
    /// Dieselben Regeln wie `figure_prims` in tools/avatars/rig.py.
    func configure(_ look: RigLook) {
        self.look = look
        let unisuit = look.shirtStyle == "unisuit"
        let longSleeve = look.shirtStyle == "longsleeve"
        let shirt = mat(look.shirt, unisuit ? 0.45 : 0.75)
        let skin: any Material = ghost.map { $0 as any Material } ?? AvatarMaterials.skin(look)
        let shorts = mat(look.shorts, unisuit ? 0.45 : 0.8)
        let legs = look.legStyle == "long" ? shorts : skin
        hips.show("hips__shorts", material: shorts)
        switch look.shirtStyle {
        case "tee", "longsleeve":
            torsoA.show("torso_tee__shirt", material: shirt)
            torsoB.hide()
        case "unisuit":
            torsoA.show("torso_unisuit__shirt", material: shirt)
            torsoB.show("torso_unisuit__skin", material: skin)
        default:
            torsoA.show("torso_tank__shirt", material: shirt)
            torsoB.show("torso_tank__skin", material: skin)
        }
        headSkin.show("head__skin", material: skin)
        let acc = look.accessories
        if acc.contains("sunglasses") {
            eyes.hide()
            eyesWhite.hide()
            let frame = look.isDarkSkin ? RGBColor(hex: "#C9CCD1")! : RGBColor(hex: "#1E1F22")!
            sunglasses.show("acc_sunglasses__accessory", material: mat(frame, 0.15, metallic: 0.6))
        } else {
            eyes.show("eyes__eyes", material: mat(RigLook.eyes, 0.2))
            eyesWhite.show("eyes_white__eyes_hl", material: mat(RGBColor(hex: "#F3EFE8")!, 0.25))
            sunglasses.hide()
        }
        let curly = ["curly", "afro"].contains(look.hairStyle)
        let hairMat: any Material = ghost.map { $0 as any Material } ?? AvatarMaterials.hair(look.hair, curly: curly)
        let wear = look.headwear
        if look.hairStyle == "bald" || wear == "hijab" || wear == "patka" {
            hair.hide()
        } else {
            let style = wear == "cap" && Self.capHair.contains(look.hairStyle) ? "cap" : look.hairStyle
            hair.show("hair_\(style)__hair", material: hairMat)
        }
        if look.beard == "short" || look.beard == "full" {
            let beardMat: any Material = ghost.map { $0 as any Material }
                ?? AvatarMaterials.hair(look.hair, curly: false, beard: true)
            beard.show("beard_\(look.beard)__hair", material: beardMat)
        } else {
            beard.hide()
        }
        switch wear ?? "" {
        case "hijab": headwear.show("acc_hijab__headwear", material: mat(look.shirt, 0.8))
        case "patka": headwear.show("acc_patka__headwear", material: mat(look.shirt, 0.8))
        case "cap": headwear.show("acc_cap__accessory", material: mat(look.shirt, 0.75))
        case "headband": headwear.show("acc_headband__accessory", material: mat(RGBColor(hex: "#F2F2EE")!, 0.8))
        default: headwear.hide()
        }
        for i in 0..<2 {
            switch look.shirtStyle {
            case "tee":
                upperA[i].show("upperarm_tee__shirt", material: shirt)
                upperB[i].show("upperarm_tee__skin", material: skin)
            case "longsleeve":
                upperA[i].show("upperarm_bare__skin", material: shirt)
                upperB[i].hide()
            default:
                upperA[i].show("upperarm_bare__skin", material: skin)
                upperB[i].hide()
            }
            if longSleeve, AvatarAssets.shared.mesh("forearm_long__shirt") != nil {
                forearm[i].show("forearm_long__shirt", material: shirt)
                forearmB[i].show("forearm_long__skin", material: skin)
            } else {
                forearm[i].show("forearm__skin", material: skin)
                forearmB[i].hide()
            }
            thighA[i].show("thigh__shorts", material: shorts)
            thighB[i].show("thigh__skin", material: legs)
            shinA[i].show("shin__skin", material: legs)
            shinB[i].show("shin__socks", material: mat(RigLook.socks, 0.8))
            foot[i].show("foot__shoes", material: mat(RigLook.shoes, 0.7))
        }
        if acc.contains("watch") {
            watch.show("acc_watch__accessory", material: mat(RGBColor(hex: "#1E1F22")!, 0.3))
        } else {
            watch.hide()
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
