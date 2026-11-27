import Foundation
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Skiff mit Ruderfigur und zwei Skulls: setzt `BoatModel` (Rumpf, Ausleger, Skulls) und `RowerFigure` (Figur)
/// zusammen und animiert beide über `StrokePose`. Teile aus `tools/avatars` (USDZ), ohne Dateien prozedural.
///
/// Bootskoordinaten: Ursprung auf der Wasserlinie unter dem Ausleger, vorne = −z (wie `TrackPose.heading` 0),
/// x = rechts, y = oben. Wie im echten Skiff sitzt die Figur mit dem Gesicht zum Heck, also zur Kamera
/// (Falk, 23.11.2026); Figur, Rollsitz, Stemmbrett, Ausleger und Skulls hängen an `BoatModel.crew` (um 180° gedreht).
///
/// - Erscheinung: `init(appearance:catalog:)` bzw. `setAppearance(_:)` (Figurtyp, Farben, Boot, Flaggen); die alte
///   Schnittstelle `init(ghostTint:ghostOpacity:colors:)` gilt weiter (Grundfigur mit Trikot-/Blatt-/Rumpffarbe).
///   Ein Wechsel tauscht nur Meshes und Materialien derselben Entities (kein Neuaufbau).
/// - Geisterboot (`ghostTint`): alle Teile im einheitlichen, halbtransparenten, unbeleuchteten Material, ohne Schatten
///   und ohne Flaggen.
/// - Detailstufen (`setDetail`): `.full` (Figur mit Gelenken, Flaggen, Schatten), `.lite` (≤ 600 Dreiecke, ein
///   Material mit Palettentextur, Skulls schwenken, Figur starr, kein Schatten), `.hidden`. Beide Stufen bleiben
///   vorgehalten, der Wechsel schaltet nur `isEnabled` der beiden Zweige um.
@MainActor
final class BoatRig {
    let root = Entity()

    enum Detail: Sendable { case full, lite, hidden }

    private let fullRoot = Entity()
    private let boat: BoatModel
    private let figure: RowerFigure
    private var lite: LiteBoat?
    private let ghostMaterial: UnlitMaterial?
    private(set) var look: RigLook
    /// gewünschte Stufe (ohne lite-Teile zeigt `.lite` die volle Form)
    private(set) var detail: Detail = .full
    private var lastPose = StrokePose.rest
    /// Schattenwurf der vollen Stufe (Verkehr schaltet ihn ab); Geister und `lite` werfen nie Schatten
    var castsShadows = true {
        didSet { if castsShadows != oldValue { updateShadows() } }
    }

    /// Farben von Trikot, Blättern und Rumpf (alte Schnittstelle für andere Ruderer auf dem Wasser)
    struct Colors {
        var shirt: UIColor
        var blade: UIColor
        var hull: UIColor

        /// eigenes Boot: blaues Trikot, gelbe Blätter, weisser Rumpf
        static let standard = Colors(shirt: UIColor(red: 0.10, green: 0.22, blue: 0.48, alpha: 1),
                                     blade: UIColor(red: 0.95, green: 0.78, blue: 0.10, alpha: 1),
                                     hull: UIColor(white: 0.95, alpha: 1))
    }

    /// `ghostTint`: nil = normales Boot; sonst einheitliches unbeleuchtetes Material dieser Farbe mit `ghostOpacity`.
    /// `colors`: Trikot, Blätter und Rumpf (Standard = frühere Farben des eigenen Boots).
    convenience init(ghostTint: UIColor? = nil, ghostOpacity: Float = 0.6, colors: Colors = .standard) {
        self.init(look: RigLook(legacy: colors), ghostTint: ghostTint, ghostOpacity: ghostOpacity, detail: .full)
    }

    /// Boot mit Erscheinung aus dem Katalog (eigenes Boot: `RowerProfileStore.shared.appearance`, Rennen:
    /// `RaceParticipant.resolvedAppearance()`, Verkehr/Bots: `RowerAppearance.random(seed:)`).
    convenience init(appearance: RowerAppearance, catalog: AppearanceCatalog = .current, ghostTint: UIColor? = nil,
                     ghostOpacity: Float = 0.6, detail: Detail = .full) {
        self.init(look: RigLook(catalog.resolve(appearance)), ghostTint: ghostTint, ghostOpacity: ghostOpacity,
                  detail: detail)
    }

    init(look: RigLook, ghostTint: UIColor?, ghostOpacity: Float, detail: Detail) {
        ghostMaterial = ghostTint.map { AvatarMaterials.ghost($0, opacity: ghostOpacity) }
        boat = BoatModel(ghost: ghostMaterial)
        figure = RowerFigure(ghost: ghostMaterial)
        self.look = look
        root.addChild(fullRoot)
        fullRoot.addChild(boat.root)
        boat.crew.addChild(figure.root)
        boat.configure(look)
        figure.configure(look)
        updateShadows()
        AvatarAssets.shared.register(self)
        setDetail(detail)
    }

    // MARK: - Erscheinung und Detailstufe

    func setAppearance(_ appearance: RowerAppearance, catalog: AppearanceCatalog = .current) {
        setLook(RigLook(catalog.resolve(appearance)))
    }

    func setColors(_ colors: Colors) {
        setLook(RigLook(legacy: colors))
    }

    func setLook(_ newLook: RigLook) {
        guard newLook != look else { return }
        look = newLook
        boat.configure(look)
        figure.configure(look)
        updateShadows()          // neu angelegte Teil-Plätze übernehmen die Schatten-Einstellung
        lite?.configure(look)
        apply(lastPose)
    }

    /// Detailstufe umschalten (sofort, ohne Neuaufbau; die lite-Teile entstehen beim ersten Gebrauch und bleiben)
    func setDetail(_ d: Detail) {
        detail = d
        var showLite = d == .lite
        if showLite {
            if lite == nil, AvatarAssets.shared.mesh("lite_hull") != nil {
                let l = LiteBoat(ghost: ghostMaterial)
                l.configure(look)
                root.addChild(l.root)
                lite = l
            }
            if lite == nil { showLite = false }   // ohne lite-Teile: volle Form
        }
        let showFull = d == .full || (d == .lite && !showLite)
        if fullRoot.isEnabled != showFull { fullRoot.isEnabled = showFull }
        if let lite, lite.root.isEnabled != showLite { lite.root.isEnabled = showLite }
        apply(lastPose)
    }

    /// Lite-Teile vorab anlegen (z. B. beim Aufbau eines Rennens), damit der erste Wechsel nichts erzeugt
    func prepareLite() {
        guard lite == nil, AvatarAssets.shared.mesh("lite_hull") != nil else { return }
        let l = LiteBoat(ghost: ghostMaterial)
        l.configure(look)
        l.root.isEnabled = false
        root.addChild(l.root)
        lite = l
    }

    /// Sichtbarkeit 0…1 über `OpacityComponent` (1 = Komponente entfernt). Achtung A12X (TrafficSystem, 24.11.2026):
    /// Boote, die erst nach dem Laden der Landschaft angelegt und mit `OpacityComponent` eingeblendet wurden, waren
    /// auf dem Gerät unsichtbar – deshalb Rigs vor dem Laden anlegen (`BoatRigPool.prewarm`) und im Zweifel ohne Fade.
    func setFade(_ f: Float) {
        if f >= 0.999 {
            if root.components.has(OpacityComponent.self) { root.components.remove(OpacityComponent.self) }
        } else {
            root.components.set(OpacityComponent(opacity: max(0, f)))
        }
    }

    /// Die USDZ-Teile sind nachgeladen: Meshes der vorhandenen Plätze austauschen
    func assetsDidLoad() {
        boat.configure(look)
        figure.configure(look)
        updateShadows()
        if detail == .lite { setDetail(.lite) } else { apply(lastPose) }
    }

    private func updateShadows() {
        let cast = castsShadows && ghostMaterial == nil
        Self.setShadows(fullRoot, cast: cast)
    }

    private static func setShadows(_ e: Entity, cast: Bool) {
        if e is ModelEntity {
            e.components.set(DynamicLightShadowComponent(castsShadow: cast))
        }
        for child in e.children { setShadows(child, cast: cast) }
    }

    // MARK: - Bewegung

    /// Körper- und Ruderstellung zu einem Zeitpunkt im Schlag.
    struct StrokePose {
        /// Ruderwinkel in Grad, positiv = Blatt Richtung Heck (Auslage), negativ = Richtung Bug (Endzug)
        var sweepDegrees: Float
        /// 0 = Blatt in der Luft, 1 = Blatt im Wasser
        var bladeInWater: Float
        /// 0 = Blatt senkrecht, 1 = flach (abgedreht)
        var feather: Float
        /// Rollsitz: 0 = vorne (Auslage), 1 = hinten (Beine gestreckt)
        var slide: Float
        /// Oberkörperneigung in Grad, positiv = nach vorne
        var leanDegrees: Float

        /// Ruhestellung: Beine lang, Hände am Körper, Blätter flach auf dem Wasser
        static let rest = StrokePose(sweepDegrees: -20, bladeInWater: 0.75, feather: 1, slide: 0.9, leanDegrees: -5)

        /// Hüfte (Rollsitz) im crew-System, z
        var hipZ: Float { 0.05 + (0.50 - 0.05) * slide }

        func mixed(with o: StrokePose, _ t: Float) -> StrokePose {
            func m(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
            return StrokePose(sweepDegrees: m(sweepDegrees, o.sweepDegrees),
                              bladeInWater: m(bladeInWater, o.bladeInWater),
                              feather: m(feather, o.feather), slide: m(slide, o.slide),
                              leanDegrees: m(leanDegrees, o.leanDegrees))
        }

        /// Stellung aus der Schlagphase (0 = Auslage/Wasserfassen, Durchzug, dann Freilauf bis 1).
        static func at(phase p: Double, strokeRate: Int) -> StrokePose {
            let driveShare = StrokePhaseTracker.visualDriveShare(strokeRate: strokeRate)
            let phase = p - floor(p)
            let f: Float                 // 0 = Auslage, 1 = Endzug
            var inWater: Float = 0
            var feather: Float = 0
            if phase < driveShare {
                let u = Float(phase / driveShare)
                f = easeInOut(u)
                inWater = smoothStep(0, 0.08, u) * (1 - smoothStep(0.92, 1, u))
            } else {
                let u = Float((phase - driveShare) / (1 - driveShare))
                f = 1 - easeInOut(u)
                feather = min(smoothStep(0, 0.12, u), 1 - smoothStep(0.75, 0.95, u))
            }
            // Reihenfolge ergibt sich aus f: im Durchzug erst Beine, dann Oberkörper; im Freilauf umgekehrt
            return StrokePose(sweepDegrees: 58 + (-38 - 58) * f,
                              bladeInWater: inWater,
                              feather: feather,
                              slide: smoothStep(0, 0.6, f),
                              leanDegrees: 25 + (-15 - 25) * smoothStep(0.3, 0.9, f))
        }
    }

    func apply(_ pose: StrokePose) {
        lastPose = pose
        if fullRoot.isEnabled {
            let handles = boat.apply(pose)
            figure.apply(hipZ: pose.hipZ, lean: pose.leanDegrees * .pi / 180, handles: handles)
        } else if let lite, lite.root.isEnabled {
            lite.apply(pose)
        }
    }
}

/// Detailstufe `lite`: Rumpf mit Auslegern, starre Figur und zwei Skulls als je ein Mesh (zusammen ≤ 600 Dreiecke),
/// ein Material mit 16 × 1-Palettentextur je Erscheinung, ohne Schatten. Die Skulls schwenken, die Figur rutscht
/// leicht mit dem Rollsitz; keine Gelenke.
@MainActor
final class LiteBoat {
    let root = Entity()
    private let crew = Entity()
    private let rowerHolder = Entity()
    private let pivots = [Entity(), Entity()]
    private let hull, rower: PartSlot
    private let oars: [PartSlot]
    private let ghost: UnlitMaterial?
    private var token = 0

    init(ghost: UnlitMaterial?) {
        self.ghost = ghost
        root.name = "boat-lite"
        crew.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        root.addChild(crew)
        crew.addChild(rowerHolder)
        hull = PartSlot(parent: root, name: "lite-hull")
        rower = PartSlot(parent: rowerHolder, name: "lite-rower")
        for p in pivots { crew.addChild(p) }
        oars = pivots.map { PartSlot(parent: $0, name: "lite-oar") }
    }

    func configure(_ look: RigLook) {
        token += 1
        let interim: any Material = ghost ?? AvatarMaterials.pbr(look.hull, roughness: 0.5)
        show(interim)
        guard ghost == nil else { return }
        let t = token
        Task { @MainActor [weak self] in
            guard let texture = await AvatarMaterials.paletteTexture(look), let self, self.token == t else { return }
            self.show(AvatarMaterials.palette(texture))
        }
    }

    private func show(_ m: any Material) {
        hull.show("lite_hull", material: m)
        rower.show("lite_rower", material: m)
        oars[0].show("lite_oar_R", material: m)
        oars[1].show("lite_oar_L", material: m)
        for slot in [hull, rower] + oars {
            slot.entity.components.set(DynamicLightShadowComponent(castsShadow: false))
        }
    }

    func apply(_ pose: BoatRig.StrokePose) {
        // Figur in mittlerer Stellung modelliert (slide 0,5); leicht mitschieben
        rowerHolder.position = [0, 0, (pose.slide - 0.5) * 0.30]
        _ = BoatModel.oarPose(pose, pivots: pivots, spins: nil)
    }
}

/// Vorrat an Rigs für grosse Felder (RaceRowers / RaceScenePlanner): Rigs werden einmal angelegt, beim Abgeben
/// versteckt und beim Holen mit neuer Erscheinung und Stufe wiederverwendet – kein Neuaufbau beim Stufenwechsel.
@MainActor
final class BoatRigPool {
    let root: Entity
    private var free: [BoatRig] = []
    private(set) var created = 0
    private static let parkDepth: Float = 400

    init(root: Entity) {
        self.root = root
    }

    /// Rigs vorab anlegen (vor dem Laden der Landschaft, siehe Hinweis in `BoatRig.setFade`)
    func prewarm(_ count: Int, withLite: Bool = true) {
        while free.count < count {
            let rig = BoatRig(appearance: RowerAppearance(), detail: .hidden)
            if withLite { rig.prepareLite() }
            park(rig)
            free.append(rig)
            created += 1
        }
    }

    func acquire(appearance: RowerAppearance, catalog: AppearanceCatalog = .current,
                 detail: BoatRig.Detail = .full) -> BoatRig {
        let rig: BoatRig
        if let r = free.popLast() {
            rig = r
            rig.setAppearance(appearance, catalog: catalog)
        } else {
            rig = BoatRig(appearance: appearance, catalog: catalog, detail: .hidden)
            created += 1
        }
        if rig.root.parent !== root { root.addChild(rig.root) }
        rig.setFade(1)
        rig.setDetail(detail)
        return rig
    }

    func release(_ rig: BoatRig) {
        rig.setDetail(.hidden)
        park(rig)
        free.append(rig)
    }

    private func park(_ rig: BoatRig) {
        if rig.root.parent !== root { root.addChild(rig.root) }
        rig.root.position = [0, -Self.parkDepth, 0]
    }
}

private func smoothStep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

private func easeInOut(_ x: Float) -> Float {
    0.5 - 0.5 * cos(Float.pi * max(0, min(1, x)))
}
