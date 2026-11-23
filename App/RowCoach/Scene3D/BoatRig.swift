import Foundation
import RealityKit
import simd
import UIKit

/// Prozedurales Skiff (ca. 8 m) mit Ruderfigur und zwei Skulls, ganz ohne Modelldateien.
///
/// Bootskoordinaten: Ursprung auf der Wasserlinie unter dem Ausleger, vorne = −z (wie `TrackPose.heading` 0),
/// x = rechts, y = oben. Wie im echten Skiff sitzt die Figur mit dem Gesicht zum Heck, also zur Kamera
/// (Falk, 23.11.2026). Figur, Rollsitz, Stemmbrett, Ausleger und Skulls hängen dafür an `crew`, das um 180°
/// gedreht ist; im crew-System schaut die Figur nach −z (Auslage = Hände vorne, Blätter Richtung Bug).
@MainActor
final class BoatRig {
    let root = Entity()
    /// Ruderfigur samt Sitz, Stemmbrett, Ausleger und Skulls; um 180° gedreht (Gesicht zum Heck)
    private let crew = Entity()

    // Bewegliche Teile
    private let seat: ModelEntity
    private let pelvis = Entity()          // Hüftgelenk; Oberkörper und Kopf hängen daran
    private let torso: ModelEntity
    private let head: ModelEntity
    private let thighs: [ModelEntity]
    private let shins: [ModelEntity]
    private let arms: [ModelEntity]
    private let oarPivots: [Entity]        // Dollen (rechts, links)
    private let blades: [ModelEntity]

    // Masse (Meter)
    private enum D {
        static let pinX: Float = 0.80
        static let pinY: Float = 0.36
        static let pinZ: Float = -0.05
        static let inboard: Float = 0.88
        static let outboard: Float = 2.0
        static let hipY: Float = 0.26
        static let footZ: Float = -0.45
        static let footY: Float = 0.14
        static let thighLength: Float = 0.48
        static let shinLength: Float = 0.48
        static let torsoLength: Float = 0.50
        static let shoulderHalfWidth: Float = 0.17
    }

    init() {
        let white = Self.material(.init(white: 0.95, alpha: 1), roughness: 0.35)
        let carbon = Self.material(.init(white: 0.12, alpha: 1), roughness: 0.5)
        let shirt = Self.material(.init(red: 0.10, green: 0.22, blue: 0.48, alpha: 1), roughness: 0.8)
        let shorts = Self.material(.init(white: 0.15, alpha: 1), roughness: 0.8)
        let skin = Self.material(.init(red: 0.86, green: 0.68, blue: 0.56, alpha: 1), roughness: 0.7)
        let bladeColor = Self.material(.init(red: 0.95, green: 0.78, blue: 0.10, alpha: 1), roughness: 0.4)
        let unitBox = MeshResource.generateBox(size: [1, 1, 1], cornerRadius: 0)

        // Erst alle gespeicherten Teile anlegen (Swift verlangt das vor jedem Zugriff auf self) …
        seat = ModelEntity(mesh: MeshResource.generateBox(size: [0.26, 0.04, 0.28], cornerRadius: 0), materials: [carbon])
        torso = ModelEntity(mesh: MeshResource.generateBox(size: [0.36, 0.50, 0.20], cornerRadius: 0.07),
                            materials: [shirt])
        head = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.11), materials: [skin])
        thighs = (0..<2).map { _ in ModelEntity(mesh: unitBox, materials: [shorts]) }
        shins = (0..<2).map { _ in ModelEntity(mesh: unitBox, materials: [skin]) }
        arms = (0..<2).map { _ in ModelEntity(mesh: unitBox, materials: [skin]) }

        // Skulls: Schaft entlang +x (Griff innen bei −inboard), Blatt aussen
        var pivots: [Entity] = []
        var bladeEntities: [ModelEntity] = []
        let shaftLength = D.inboard + D.outboard
        for _ in 0..<2 {
            let pivot = Entity()
            let shaft = ModelEntity(mesh: MeshResource.generateBox(size: [shaftLength, 0.035, 0.035], cornerRadius: 0),
                                    materials: [white])
            shaft.position = [(D.outboard - D.inboard) / 2, 0, 0]
            let grip = ModelEntity(mesh: MeshResource.generateBox(size: [0.14, 0.045, 0.045], cornerRadius: 0), materials: [carbon])
            grip.position = [-D.inboard + 0.07, 0, 0]
            let blade = ModelEntity(mesh: MeshResource.generateBox(size: [0.46, 0.19, 0.012], cornerRadius: 0), materials: [bladeColor])
            blade.position = [D.outboard - 0.23, 0, 0]
            pivot.addChild(shaft)
            pivot.addChild(grip)
            pivot.addChild(blade)
            pivots.append(pivot)
            bladeEntities.append(blade)
        }
        oarPivots = pivots
        blades = bladeEntities

        // … dann den Szenengraph zusammensetzen
        let hull = ModelEntity(mesh: Self.hullMesh(), materials: [white])
        root.addChild(hull)
        crew.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        root.addChild(crew)

        // Ausleger: je zwei Streben vom Bordrand zur Dolle
        for s: Float in [1, -1] {
            let pin = SIMD3<Float>(s * D.pinX, D.pinY - 0.03, D.pinZ)
            for from in [SIMD3<Float>(s * 0.18, 0.10, D.pinZ + 0.35), SIMD3<Float>(s * 0.18, 0.10, D.pinZ - 0.40)] {
                let strut = ModelEntity(mesh: unitBox, materials: [carbon])
                Self.place(strut, from: from, to: pin, thickness: 0.025)
                crew.addChild(strut)
            }
        }

        // Stemmbrett
        let stretcher = ModelEntity(mesh: MeshResource.generateBox(size: [0.34, 0.16, 0.03], cornerRadius: 0), materials: [carbon])
        stretcher.position = [0, D.footY, D.footZ - 0.06]
        stretcher.orientation = simd_quatf(angle: 0.6, axis: [1, 0, 0])
        crew.addChild(stretcher)

        crew.addChild(seat)

        // Figur: Becken, Oberkörper und Kopf hängen am Hüftgelenk
        let hips = ModelEntity(mesh: MeshResource.generateBox(size: [0.34, 0.16, 0.24], cornerRadius: 0.05),
                               materials: [shorts])
        hips.position = [0, 0.02, 0]
        torso.position = [0, 0.27, 0]
        head.position = [0, D.torsoLength + 0.17, 0]
        pelvis.addChild(hips)
        pelvis.addChild(torso)
        pelvis.addChild(head)
        crew.addChild(pelvis)
        for e in thighs + shins + arms { crew.addChild(e) }
        for p in oarPivots { crew.addChild(p) }

        apply(StrokePose.rest)
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

        func mixed(with o: StrokePose, _ t: Float) -> StrokePose {
            func m(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
            return StrokePose(sweepDegrees: m(sweepDegrees, o.sweepDegrees),
                              bladeInWater: m(bladeInWater, o.bladeInWater),
                              feather: m(feather, o.feather), slide: m(slide, o.slide),
                              leanDegrees: m(leanDegrees, o.leanDegrees))
        }

        /// Stellung aus der Schlagphase (0 = Auslage/Wasserfassen, Durchzug, dann Freilauf bis 1).
        static func at(phase p: Double, strokeRate: Int) -> StrokePose {
            let driveShare = min(0.5, 0.25 + Double(max(strokeRate, 0)) * 0.006)
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
        // Rollsitz und Hüfte
        let hipZ: Float = 0.05 + (0.50 - 0.05) * pose.slide
        let hip = SIMD3<Float>(0, D.hipY, hipZ)
        seat.position = [0, D.hipY - 0.10, hipZ]
        pelvis.position = hip
        let lean = pose.leanDegrees * .pi / 180
        // Drehung um +x mit negativem Winkel neigt den Oberkörper nach vorne (−z)
        let leanRotation = simd_quatf(angle: -lean, axis: [1, 0, 0])
        pelvis.orientation = leanRotation

        // Ruder
        let sweep = pose.sweepDegrees * .pi / 180
        let airY: Float = 0.18, waterY: Float = -0.06
        let bladeCenter = D.outboard - 0.23
        let bladeY = airY + (waterY - airY) * pose.bladeInWater
        let roll = asin(max(-1, min(1, (bladeY - D.pinY) / bladeCenter)))
        var handles: [SIMD3<Float>] = []
        for (i, s) in [Float(1), Float(-1)].enumerated() {
            // links: Grunddrehung 180°, damit +x des Ruders nach aussen zeigt
            let yaw = (s > 0 ? 0 : Float.pi) - s * sweep
            let q = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: roll, axis: [0, 0, 1])
            let pin = SIMD3<Float>(s * D.pinX, D.pinY, D.pinZ)
            oarPivots[i].position = pin
            oarPivots[i].orientation = q
            blades[i].orientation = simd_quatf(angle: pose.feather * .pi / 2, axis: [1, 0, 0])
            // Griff etwas versetzt, damit sich die Hände nicht durchdringen (rechte Hand höher)
            handles.append(pin + q.act(SIMD3<Float>(-D.inboard + 0.07, 0, 0)) + SIMD3<Float>(0, s * 0.02, 0))
        }

        // Arme: Schulter → Griff
        for (i, s) in [Float(1), Float(-1)].enumerated() {
            let shoulder = hip + leanRotation.act([s * D.shoulderHalfWidth, D.torsoLength - 0.04, 0])
            Self.place(arms[i], from: shoulder, to: handles[i], thickness: 0.075)
        }

        // Beine: Hüfte → Knie → Fuss, Knie nach oben ausgewichen
        for (i, s) in [Float(1), Float(-1)].enumerated() {
            let h = SIMD3<Float>(s * 0.10, D.hipY, hipZ)
            let f = SIMD3<Float>(s * 0.12, D.footY, D.footZ)
            let d = simd_distance(h, f)
            let reach = min(d, D.thighLength + D.shinLength - 0.001)
            let mid = (h + f) / 2
            let rise = sqrt(max(0, D.thighLength * D.thighLength - (reach / 2) * (reach / 2)))
            let knee = mid + SIMD3<Float>(0, rise, 0)
            Self.place(thighs[i], from: h, to: knee, thickness: 0.13)
            Self.place(shins[i], from: knee, to: f, thickness: 0.10)
        }
    }

    // MARK: - Hilfen

    /// Setzt eine Einheitsbox (1 × 1 × 1) als Stab zwischen zwei Punkte (im Koordinatensystem des Elternteils).
    private static func place(_ e: Entity, from a: SIMD3<Float>, to b: SIMD3<Float>, thickness: Float) {
        let d = b - a
        let len = max(simd_length(d), 0.001)
        e.position = (a + b) / 2
        e.orientation = simd_quatf(from: [0, 1, 0], to: d / len)
        e.scale = [thickness, len, thickness]
    }

    private static func material(_ color: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        m.faceCulling = .none   // prozedurale Teile: unabhängig von der Dreiecksreihenfolge sichtbar
        return m
    }

    /// Rumpf als Spantenmodell: elliptischer Querschnitt unten, flaches Deck oben, spitze Enden.
    /// Normalen werden aus der Geometrie berechnet, die Dreiecke danach ausgerichtet (gegen den Uhrzeigersinn
    /// von aussen gesehen).
    private static func hullMesh() -> MeshResource {
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

        // Unterwasserschiff: Ringe (around + 1 Punkte) je Spant
        var ringStart: [Int] = []
        var deckStart: [Int] = []
        for i in 0...sections {
            let z = bowZ + (sternZ - bowZ) * Float(i) / Float(sections)
            let t = (z - (bowZ + sternZ) / 2) / ((sternZ - bowZ) / 2)       // −1 … 1
            let w = max(1 - t * t, 0)
            let hw = maxHalfWidth * pow(w, 0.6) + 0.004
            let dp = maxDepth * pow(w, 0.4) + 0.01
            ringStart.append(positions.count)
            for k in 0...around {
                let a = Float.pi * Float(k) / Float(around)                  // 0 = rechts, π = links
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
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            return mesh
        }
        // Rückfall, falls die Erzeugung scheitert: schlanke Box
        return MeshResource.generateBox(size: [2 * maxHalfWidth, 0.2, sternZ - bowZ], cornerRadius: 0)
    }
}

private func smoothStep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

private func easeInOut(_ x: Float) -> Float {
    0.5 - 0.5 * cos(Float.pi * max(0, min(1, x)))
}
