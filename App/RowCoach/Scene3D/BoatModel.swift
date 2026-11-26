import Foundation
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Skiff (8,2 m) mit Deck, Zierstreifen, Finne, Bugball, Rollsitz, Stemmbrett, Ausleger (wing, backwing,
/// traditional) und zwei Skulls (Blattform macon, bigblade, fat2) aus den Teilen von `tools/avatars`.
///
/// Rahmen: `root` = Bootskoordinaten (Ursprung Wasserlinie unter dem Ausleger, Bug = −z); `crew` ist um 180° gedreht
/// (Figur schaut zum Heck) und trägt Sitz, Schienen, Stemmbrett, Ausleger, Skulls und die Figur. Skulls: Drehpunkt
/// an der Dolle (`pivots`), darunter `spins` für das Abdrehen (das ganze Skull dreht, die hohle Blattseite zeigt im
/// Wasser zum Heck und beim Abdrehen nach oben).
@MainActor
final class BoatModel {
    /// Masse (Meter) – wie tools/avatars/boat.py
    enum D {
        static let pinX: Float = 0.80
        static let pinY: Float = 0.36
        static let pinZ: Float = -0.05
        static let inboard: Float = 0.88
        static let outboard: Float = 2.0
    }

    let root = Entity()
    let crew = Entity()
    private let seat = Entity()
    private let pivots = [Entity(), Entity()]
    private let spins = [Entity(), Entity()]

    private let hull, stripe, deck, cockpit, fin, bowball, flagSideR, flagSideL, flagDeck: PartSlot
    private let tracks, stretcher, gates, rigger, seatPart: PartSlot
    private let shafts, grips, sleeves, blades: [PartSlot]

    private(set) var look = RigLook()
    private let ghost: UnlitMaterial?
    private var flagToken = 0

    init(ghost: UnlitMaterial?) {
        self.ghost = ghost
        root.name = "boat"
        crew.name = "crew"
        crew.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        root.addChild(crew)
        hull = PartSlot(parent: root, name: "hull")
        stripe = PartSlot(parent: root, name: "stripe")
        deck = PartSlot(parent: root, name: "deck")
        cockpit = PartSlot(parent: root, name: "cockpit")
        fin = PartSlot(parent: root, name: "fin")
        bowball = PartSlot(parent: root, name: "bowball")
        flagSideR = PartSlot(parent: root, name: "flag-side-r")
        flagSideL = PartSlot(parent: root, name: "flag-side-l")
        flagDeck = PartSlot(parent: root, name: "flag-deck")
        tracks = PartSlot(parent: crew, name: "tracks")
        stretcher = PartSlot(parent: crew, name: "stretcher")
        gates = PartSlot(parent: crew, name: "gates")
        rigger = PartSlot(parent: crew, name: "rigger")
        crew.addChild(seat)
        seatPart = PartSlot(parent: seat, name: "seat")
        for i in 0..<2 {
            crew.addChild(pivots[i])
            pivots[i].addChild(spins[i])
        }
        shafts = spins.map { PartSlot(parent: $0, name: "shaft") }
        grips = spins.map { PartSlot(parent: $0, name: "grip") }
        sleeves = spins.map { PartSlot(parent: $0, name: "sleeve") }
        blades = spins.map { PartSlot(parent: $0, name: "blade") }
    }

    private func mat(_ c: RGBColor, _ roughness: Float, metallic: Float = 0) -> any Material {
        if let ghost { return ghost }
        return AvatarMaterials.pbr(c, roughness: roughness, metallic: metallic)
    }

    func configure(_ look: RigLook) {
        self.look = look
        let finish: Float = look.finish == "matte" ? 0.7 : (look.finish == "carbon" ? 0.35 : 0.22)
        let fittings = mat(RigLook.fittings, 0.5)
        hull.show("hull__hull", material: mat(look.hull, finish))
        stripe.show("hull_stripe__stripe", material: mat(look.stripe, finish))
        deck.show("deck__deck", material: mat(look.deck, finish + 0.05))
        cockpit.show("cockpit__fittings", material: fittings)
        fin.show("fin__fin", material: mat(look.rigger, 0.4))
        if look.bowBall {
            bowball.show("bowball__bowball", material: mat(RigLook.bowBallColor, 0.5))
        } else {
            bowball.hide()
        }
        tracks.show("tracks__fittings", material: fittings)
        stretcher.show("stretcher__fittings", material: fittings)
        gates.show("gates__fittings", material: fittings)
        let riggerType = ["wing", "backwing", "traditional"].contains(look.riggerType) ? look.riggerType : "wing"
        rigger.show("rigger_\(riggerType)__rigger", material: mat(look.rigger, 0.35))
        seatPart.show("seat__fittings", material: fittings)
        let shape = ["macon", "bigblade", "fat2"].contains(look.bladeShape) ? look.bladeShape : "bigblade"
        for (i, side) in ["R", "L"].enumerated() {
            shafts[i].show("oar_shaft__shaft", material: mat(look.shaft, 0.35))
            grips[i].show("oar_grip__fittings", material: fittings)
            sleeves[i].show("oar_sleeve__sleeve", material: mat(RigLook.sleeve, 0.5))
            blades[i].show("blade_\(shape)_\(side)__blade", material: mat(look.blade, 0.3))
        }
        // Flaggen am Boot: beidseitig nahe Bug und auf dem Heckdeck hinter dem Cockpit (Kamera hinter dem Boot)
        flagToken += 1
        for f in [flagSideR, flagSideL, flagDeck] { f.hide() }
        if let emoji = look.boatFlag, ghost == nil, AvatarAssets.shared.mesh("flag_deck__flag") != nil {
            let token = flagToken
            Task { @MainActor [weak self] in
                guard let m = await AvatarMaterials.flag(emoji), let self, self.flagToken == token else { return }
                self.flagSideR.show("flag_side_R__flag", material: m)
                self.flagSideL.show("flag_side_L__flag", material: m)
                self.flagDeck.show("flag_deck__flag", material: m)
            }
        }
    }

    /// Rollsitz und Skulls in die Stellung bringen; liefert die Griffpunkte (rechts, links) im crew-System.
    @discardableResult
    func apply(_ pose: BoatRig.StrokePose) -> [SIMD3<Float>] {
        seat.position = [0, RowerFigure.D.hipY - 0.10, pose.hipZ]
        return Self.oarPose(pose, pivots: pivots, spins: spins)
    }

    /// Lage der Skulls (auch für `lite`): Schwenk um die Dolle, Neigung je nach Blatthöhe, Abdrehen
    static func oarPose(_ pose: BoatRig.StrokePose, pivots: [Entity], spins: [Entity]?) -> [SIMD3<Float>] {
        let sweep = pose.sweepDegrees * .pi / 180
        let airY: Float = 0.18, waterY: Float = -0.06
        let bladeCenter = D.outboard - 0.23
        let bladeY = airY + (waterY - airY) * pose.bladeInWater
        let roll = asin(max(-1, min(1, (bladeY - D.pinY) / bladeCenter)))
        var handles: [SIMD3<Float>] = []
        for (i, s) in [Float(1), Float(-1)].enumerated() {
            // links: Grunddrehung 180°, damit +x des Skulls nach aussen zeigt
            let yaw = (s > 0 ? 0 : Float.pi) - s * sweep
            let q = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: roll, axis: [0, 0, 1])
            let pin = SIMD3<Float>(s * D.pinX, D.pinY, D.pinZ)
            pivots[i].position = pin
            pivots[i].orientation = q
            spins?[i].orientation = simd_quatf(angle: s * pose.feather * .pi / 2, axis: [1, 0, 0])
            // Griff etwas versetzt, damit sich die Hände nicht durchdringen (rechte Hand höher)
            handles.append(pin + q.act(SIMD3<Float>(-D.inboard + 0.07, 0, 0)) + SIMD3<Float>(0, s * 0.02, 0))
        }
        return handles
    }

    /// Ersatz-Rumpf ohne Modelldateien (wie das frühere prozedurale Skiff): elliptischer Querschnitt, flaches Deck.
    static func fallbackHullMesh() -> MeshResource {
        let bowZ: Float = -4.4, sternZ: Float = 3.6
        let sections = 48, around = 10
        let deckY: Float = 0.10, maxHalfWidth: Float = 0.20, maxDepth: Float = 0.16
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        func addTriangle(_ a: Int, _ b: Int, _ c: Int) {
            let pa = positions[a], pb = positions[b], pc = positions[c]
            let n = simd_cross(pb - pa, pc - pa)
            let avg = normals[a] + normals[b] + normals[c]
            if simd_dot(n, avg) >= 0 {
                indices += [UInt32(a), UInt32(b), UInt32(c)]
            } else {
                indices += [UInt32(a), UInt32(c), UInt32(b)]
            }
        }

        var ringStart: [Int] = []
        var deckStart: [Int] = []
        for i in 0...sections {
            let z = bowZ + (sternZ - bowZ) * Float(i) / Float(sections)
            let t = (z - (bowZ + sternZ) / 2) / ((sternZ - bowZ) / 2)
            let w = max(1 - t * t, 0)
            let hw = maxHalfWidth * pow(w, 0.6) + 0.004
            let dp = maxDepth * pow(w, 0.4) + 0.01
            ringStart.append(positions.count)
            for k in 0...around {
                let a = Float.pi * Float(k) / Float(around)
                positions.append([hw * cos(a), deckY - dp * sin(a), z])
                normals.append(simd_normalize(SIMD3<Float>(cos(a) / hw, -sin(a) / dp, 0)))
            }
            deckStart.append(positions.count)
            positions.append([hw, deckY, z])
            positions.append([-hw, deckY, z])
            normals.append([0, 1, 0])
            normals.append([0, 1, 0])
        }
        for i in 0..<sections {
            let r0 = ringStart[i], r1 = ringStart[i + 1]
            for k in 0..<around {
                addTriangle(r0 + k, r1 + k, r0 + k + 1)
                addTriangle(r0 + k + 1, r1 + k, r1 + k + 1)
            }
            let d0 = deckStart[i], d1 = deckStart[i + 1]
            addTriangle(d0, d0 + 1, d1)
            addTriangle(d1, d0 + 1, d1 + 1)
        }
        var descriptor = MeshDescriptor(name: "hull")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) { return mesh }
        return MeshResource.generateBox(size: [2 * maxHalfWidth, 0.2, sternZ - bowZ], cornerRadius: 0)
    }
}
