import Foundation
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Kleine Bibliothek prozeduraler, ruhiger Low-Poly-Schiffe (je wenige hundert Dreiecke, einfache PBR-Farben,
/// keine Schatten). Koordinaten wie `BoatRig`: Ursprung auf der Wasserlinie in Schiffsmitte, vorne = −z, y = oben.
///
/// Je Art wird das Modell einmal gebaut und danach geklont (gleiche Meshes und Materialien). Dazu gehört ein
/// halbtransparentes, unbeleuchtetes Dreieck als Bugwelle und Kielwasser.
@MainActor
enum VesselModels {
    private static var prototypes: [VesselKind: Entity] = [:]

    /// Neues Modell der Art (Klon des einmal gebauten Prototyps)
    static func make(_ kind: VesselKind) -> Entity {
        if let p = prototypes[kind] { return p.clone(recursive: true) }
        let p = build(kind)
        prototypes[kind] = p
        return p.clone(recursive: true)
    }

    // MARK: - Farben

    private static let white = UIColor(white: 0.93, alpha: 1)
    private static let offWhite = UIColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1)
    private static let navy = UIColor(red: 0.10, green: 0.17, blue: 0.32, alpha: 1)
    private static let glass = UIColor(red: 0.12, green: 0.16, blue: 0.20, alpha: 1)
    private static let wood = UIColor(red: 0.47, green: 0.31, blue: 0.18, alpha: 1)
    private static let darkWood = UIColor(red: 0.33, green: 0.22, blue: 0.13, alpha: 1)
    private static let hullBlack = UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    private static let red = UIColor(red: 0.66, green: 0.14, blue: 0.12, alpha: 1)
    private static let cargo = UIColor(red: 0.26, green: 0.33, blue: 0.30, alpha: 1)
    private static let funnel = UIColor(red: 0.93, green: 0.82, blue: 0.52, alpha: 1)
    private static let sail = UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1)
    private static let shirt = UIColor(red: 0.80, green: 0.30, blue: 0.18, alpha: 1)
    private static let skin = UIColor(red: 0.86, green: 0.68, blue: 0.56, alpha: 1)

    // MARK: - Modelle

    private static func build(_ kind: VesselKind) -> Entity {
        var parts = Parts()
        let wakeLength: Float, wakeSpread: Float
        switch kind {
        case .motorboot:
            // 7 m Sportboot: weisser Rumpf, dunkle Scheibe, Sitzbank
            parts.hull(white, length: 7, beam: 2.5, top: 0.75, bottom: -0.3, bow: 0.35)
            parts.hull(navy, length: 7.04, beam: 2.54, top: 0.12, bottom: -0.32, bow: 0.35)
            parts.box(glass, center: [0, 1.05, -0.6], size: [2.0, 0.55, 0.12])
            parts.box(white, center: [0, 0.95, 0.9], size: [1.8, 0.4, 0.8])
            wakeLength = 26; wakeSpread = 9
        case .segelboot:
            // 8 m Kielboot: Rumpf, Kajüte, Mast, Gross- und Vorsegel
            parts.hull(white, length: 8, beam: 2.6, top: 0.7, bottom: -0.4, bow: 0.4)
            parts.box(offWhite, center: [0, 0.95, 0.4], size: [1.6, 0.45, 2.6])
            parts.box(glass, center: [0, 0.98, -0.85], size: [0.12, 0.12, 0.12])
            parts.box(UIColor(white: 0.75, alpha: 1), center: [0, 6.2, -0.9], size: [0.12, 11, 0.12])
            parts.box(UIColor(white: 0.75, alpha: 1), center: [0, 1.9, 0.6], size: [0.1, 0.1, 3.0])
            parts.triangle(sail, [0, 1.95, -0.8], [0, 11.4, -0.8], [0, 1.95, 2.1])
            parts.triangle(sail, [0, 1.2, -1.0], [0, 9.6, -0.98], [0, 0.9, -3.75])
            wakeLength = 12; wakeSpread = 4
        case .kursschiff:
            // Kursschiff bzw. Ausflugsschiff (48 m): weiss mit blauem Wasserpass, zwei Decks, Steuerhaus
            parts.hull(white, length: 48, beam: 8.6, top: 1.6, bottom: -1.2, bow: 0.18)
            parts.hull(navy, length: 48.1, beam: 8.7, top: 0.35, bottom: -1.25, bow: 0.18)
            parts.box(white, center: [0, 2.8, 2.5], size: [7.4, 2.4, 33])
            parts.box(glass, center: [0, 3.0, 2.5], size: [7.5, 0.9, 31])
            parts.box(white, center: [0, 4.0 + 1.1, 4.5], size: [6.4, 2.2, 18])
            parts.box(glass, center: [0, 5.3, 4.5], size: [6.5, 0.8, 16.5])
            parts.box(navy, center: [0, 6.25, 4.5], size: [6.8, 0.12, 19])
            parts.box(white, center: [0, 7.1, -2.5], size: [4.0, 1.7, 3.4])
            parts.box(glass, center: [0, 7.3, -2.5], size: [4.1, 0.7, 3.5])
            parts.box(UIColor(white: 0.85, alpha: 1), center: [0, 4.5, 22.5], size: [0.1, 4.0, 0.1])
            parts.box(red, center: [0, 6.0, 22.9], size: [0.05, 0.7, 0.9])
            wakeLength = 110; wakeSpread = 38
        case .raddampfer:
            // Raddampfer (62 m): weiss, Radkästen an den Seiten, Kamin hell mit schwarzem Rand
            parts.hull(white, length: 62, beam: 8.2, top: 1.8, bottom: -1.3, bow: 0.16)
            parts.hull(navy, length: 62.1, beam: 8.3, top: 0.3, bottom: -1.35, bow: 0.16)
            for s: Float in [1, -1] {
                parts.box(white, center: [s * 5.4, 2.0, -1], size: [2.6, 3.2, 7.5])
                parts.box(navy, center: [s * 5.4, 3.65, -1], size: [2.7, 0.15, 7.6])
            }
            parts.box(white, center: [0, 3.1, 5], size: [7.6, 2.6, 40])
            parts.box(glass, center: [0, 3.3, 5], size: [7.7, 0.9, 38])
            parts.box(white, center: [0, 5.4, 9], size: [6.2, 2.0, 22])
            parts.box(glass, center: [0, 5.6, 9], size: [6.3, 0.7, 20])
            parts.box(white, center: [0, 7.2, -0.6], size: [3.8, 1.6, 3.0])
            parts.box(glass, center: [0, 7.4, -0.6], size: [3.9, 0.6, 3.1])
            parts.prism(funnel, center: [0, 6.4, 3.5], radius: 0.95, height: 4.4, sides: 8)
            parts.prism(hullBlack, center: [0, 10.6, 3.5], radius: 0.98, height: 0.5, sides: 8)
            wakeLength = 120; wakeSpread = 40
        case .rheinschiff:
            // Gütermotorschiff (105 m): dunkler Rumpf mit rotem Streifen, lange Lukendeckel, Aufbau am Heck
            parts.hull(hullBlack, length: 105, beam: 11.4, top: 1.6, bottom: -2.6, bow: 0.07)
            for s: Float in [1, -1] {
                parts.box(red, center: [s * 5.71, 1.2, 0], size: [0.06, 0.35, 92])
            }
            parts.box(cargo, center: [0, 2.05, -4], size: [9.6, 0.9, 74])
            for z in stride(from: Float(-38), through: 30, by: 8.5) {
                parts.box(UIColor(red: 0.21, green: 0.27, blue: 0.25, alpha: 1), center: [0, 2.55, z],
                          size: [9.7, 0.12, 0.35])
            }
            parts.box(white, center: [0, 3.0, 45], size: [9.6, 2.8, 10])
            parts.box(glass, center: [0, 3.4, 45], size: [9.7, 0.7, 9])
            parts.box(white, center: [0, 5.6, 42], size: [5.2, 2.2, 4.2])
            parts.box(glass, center: [0, 5.9, 42], size: [5.3, 0.9, 4.3])
            parts.box(white, center: [0, 1.9, -49], size: [6, 0.6, 3])
            wakeLength = 140; wakeSpread = 34
        case .weidling:
            // Weidling (10 m): schmales Holzboot mit hochgezogenem Bug, eine stehende Person mit Stachel
            parts.hull(wood, length: 10, beam: 1.6, top: 0.45, bottom: -0.15, bow: 0.3)
            parts.box(darkWood, center: [0, 0.47, 0], size: [1.5, 0.05, 9])
            parts.triangle(wood, [0.25, 0.45, -4.0], [-0.25, 0.45, -4.0], [0, 0.95, -5.1])
            parts.box(navy, center: [0, 1.0, 3.6], size: [0.38, 0.75, 0.25])
            parts.box(shirt, center: [0, 1.75, 3.6], size: [0.42, 0.75, 0.26])
            parts.box(skin, center: [0, 2.3, 3.6], size: [0.22, 0.25, 0.22])
            parts.stick(darkWood, from: [0.3, 2.1, 3.4], to: [0.6, -0.8, 5.4], thickness: 0.06)
            wakeLength = 9; wakeSpread = 3
        case .faehre:
            // Basler Fähre (11 m): Holzrumpf, kleine Kabine mit rotem Dach
            parts.hull(wood, length: 11, beam: 3.2, top: 0.55, bottom: -0.3, bow: 0.25)
            parts.box(offWhite, center: [0, 1.35, 0.3], size: [2.2, 1.6, 4.2])
            parts.box(glass, center: [0, 1.6, 0.3], size: [2.25, 0.55, 3.6])
            parts.box(red, center: [0, 2.2, 0.3], size: [2.7, 0.14, 4.8])
            wakeLength = 6; wakeSpread = 2.5
        }
        let root = parts.entity(name: kind.rawValue)
        root.addChild(wake(length: Float(kind.length), behind: wakeLength, spread: wakeSpread))
        return root
    }

    /// Bugwelle und Kielwasser: flaches, halbtransparentes Dreieck vom Bug nach hinten aufgeweitet
    private static func wake(length: Float, behind: Float, spread: Float) -> ModelEntity {
        let bow = SIMD3<Float>(0, 0.05, -length / 2 + 0.3)
        let tail = length / 2 + behind
        var p = Parts()
        let halfBeam = max(length / 14, 0.8)
        p.add(UIColor.white, a: bow, b: [-halfBeam - spread, 0.05, tail], c: [halfBeam + spread, 0.05, tail])
        var m = UnlitMaterial()
        m.color = .init(tint: UIColor(white: 1, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        m.faceCulling = .none
        m.writesDepth = false
        let mesh = p.groups.first.flatMap { $0.value.mesh(name: "wake") } ?? MeshResource.generatePlane(width: 1, depth: 1)
        let e = ModelEntity(mesh: mesh, materials: [m])
        e.name = "wake"
        e.components.set(DynamicLightShadowComponent(castsShadow: false))
        return e
    }
}

// MARK: - Bausteine

/// Sammelt Dreiecke je Farbe (flach schattiert) und baut daraus je Farbe ein ModelEntity.
@MainActor
private struct Parts {
    @MainActor
    struct Group {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        func mesh(name: String) -> MeshResource? {
            var d = MeshDescriptor(name: name)
            d.positions = MeshBuffers.Positions(positions)
            d.normals = MeshBuffers.Normals(normals)
            d.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [d])
        }
    }

    /// Schlüssel = Farbe als RGBA-Text (UIColor ist nicht Hashable genug für Gleichheit nach Wert)
    var groups: [String: Group] = [:]
    var colors: [String: UIColor] = [:]

    private static func key(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f-%.3f-%.3f-%.3f", r, g, b, a)
    }

    /// Dreieck mit Flächennormale; `outward` (optional) legt die Seite fest, in die die Normale zeigen soll
    mutating func add(_ color: UIColor, a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, outward: SIMD3<Float>? = nil) {
        var n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        guard len > 1e-8 else { return }
        n /= len
        var bb = b, cc = c
        if let o = outward, simd_dot(n, o) < 0 {
            n = -n
            swap(&bb, &cc)
        }
        let k = Self.key(color)
        colors[k] = color
        var g = groups[k] ?? Group()
        let base = UInt32(g.positions.count)
        g.positions += [a, bb, cc]
        g.normals += [n, n, n]
        g.indices += [base, base + 1, base + 2]
        groups[k] = g
    }

    mutating func quad(_ color: UIColor, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       outward: SIMD3<Float>) {
        add(color, a: a, b: b, c: c, outward: outward)
        add(color, a: a, b: c, c: d, outward: outward)
    }

    /// doppelseitiges Dreieck (Segel)
    mutating func triangle(_ color: UIColor, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        add(color, a: a, b: b, c: c)
    }

    mutating func box(_ color: UIColor, center: SIMD3<Float>, size: SIMD3<Float>) {
        let h = size / 2
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { center + SIMD3<Float>(x * h.x, y * h.y, z * h.z) }
        quad(color, p(1, -1, -1), p(1, 1, -1), p(1, 1, 1), p(1, -1, 1), outward: [1, 0, 0])
        quad(color, p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1), outward: [-1, 0, 0])
        quad(color, p(-1, 1, -1), p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1), outward: [0, 1, 0])
        quad(color, p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1), outward: [0, -1, 0])
        quad(color, p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), outward: [0, 0, 1])
        quad(color, p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1), p(1, -1, -1), outward: [0, 0, -1])
    }

    /// Dünner Stab zwischen zwei Punkten (quadratischer Querschnitt)
    mutating func stick(_ color: UIColor, from a: SIMD3<Float>, to b: SIMD3<Float>, thickness: Float) {
        let d = simd_normalize(b - a)
        let up: SIMD3<Float> = abs(d.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(d, up)) * thickness / 2
        let v = simd_normalize(simd_cross(d, u)) * thickness / 2
        let ring = [u + v, -u + v, -u - v, u - v]
        for i in 0..<4 {
            let p0 = ring[i], p1 = ring[(i + 1) % 4]
            quad(color, a + p0, b + p0, b + p1, a + p1, outward: (p0 + p1) / 2)
        }
    }

    /// Senkrechtes Prisma (Kamin): Mitte des Bodens in `center`
    mutating func prism(_ color: UIColor, center: SIMD3<Float>, radius: Float, height: Float, sides: Int) {
        let top = center + SIMD3<Float>(0, height, 0)
        for i in 0..<sides {
            let a0 = 2 * Float.pi * Float(i) / Float(sides), a1 = 2 * Float.pi * Float(i + 1) / Float(sides)
            let o0 = SIMD3<Float>(radius * cos(a0), 0, radius * sin(a0))
            let o1 = SIMD3<Float>(radius * cos(a1), 0, radius * sin(a1))
            quad(color, center + o0, top + o0, top + o1, center + o1, outward: (o0 + o1) / 2)
            add(color, a: top, b: top + o0, c: top + o1, outward: [0, 1, 0])
        }
    }

    /// Rumpf: Deckumriss (Heck eckig, Bug spitz) oben bei `top`, schmaler und kürzer unten bei `bottom`,
    /// mit Seitenwänden, Deck und Boden. `bow` = Anteil der Länge, auf dem der Bug zuläuft.
    mutating func hull(_ color: UIColor, length: Float, beam: Float, top: Float, bottom: Float, bow: Float) {
        func outline(_ l: Float, _ b: Float) -> [SIMD2<Float>] {
            let hb = b / 2, z0 = -l / 2, z1 = l / 2
            let shoulder = z0 + l * bow
            // gegen den Uhrzeigersinn von oben: Bug, rechte Schulter, rechtes Heck, linkes Heck, linke Schulter
            return [[0, z0], [hb * 0.55, z0 + l * bow * 0.35], [hb, shoulder], [hb, z1 - l * 0.04],
                    [hb * 0.85, z1], [-hb * 0.85, z1], [-hb, z1 - l * 0.04], [-hb, shoulder],
                    [-hb * 0.55, z0 + l * bow * 0.35]]
        }
        let up = outline(length, beam)
        let down = outline(length * 0.94, beam * 0.72)
        let n = up.count
        let mid = SIMD3<Float>(0, (top + bottom) / 2, 0)
        for i in 0..<n {
            let j = (i + 1) % n
            let a = SIMD3<Float>(up[i].x, top, up[i].y), b = SIMD3<Float>(up[j].x, top, up[j].y)
            let c = SIMD3<Float>(down[j].x, bottom, down[j].y), d = SIMD3<Float>(down[i].x, bottom, down[i].y)
            let faceCenter = (a + b + c + d) / 4
            quad(color, a, b, c, d, outward: faceCenter - mid)
            // Deck und Boden als Fächer um die Mitte
            add(color, a: [0, top, 0], b: a, c: b, outward: [0, 1, 0])
            add(color, a: [0, bottom, 0], b: d, c: c, outward: [0, -1, 0])
        }
    }

    /// Ein Entity mit je einem ModelEntity pro Farbe (flache PBR-Farbe, ohne Schatten)
    func entity(name: String) -> Entity {
        let root = Entity()
        root.name = name
        for (k, g) in groups {
            guard let mesh = g.mesh(name: "\(name)-\(k)"), let color = colors[k] else { continue }
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: color)
            m.roughness = .init(floatLiteral: 0.75)
            m.metallic = .init(floatLiteral: 0)
            m.faceCulling = .none
            let e = ModelEntity(mesh: mesh, materials: [m])
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(e)
        }
        return root
    }
}
