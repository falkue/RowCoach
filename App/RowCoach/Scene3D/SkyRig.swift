import Foundation
import Metal
import os
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Himmel, Sonnenscheibe und Dunst der Ruderszene (KONZEPT.md Abschnitt 16).
///
/// - Himmel: equirektangulares Bild mit Verlauf, Abendrot und Wolken (`ProceduralTextures.skyEquirect`) als Skybox.
///   Die Wolken stecken im Bild, also kein zusätzliches Objekt pro Bild; Umgebungslicht und Spiegelung im Wasser
///   nehmen sie automatisch mit. Die Wolken stehen still (bei Cirren fällt das kaum auf); bewegte Wolken hiessen
///   die Skybox pro Bild neu aufbauen oder eine durchsichtige Kuppel über alles zeichnen (Überzeichnung auf dem A12X).
/// - Sonnenscheibe: kleines, unbeleuchtetes Billboard in Sonnenrichtung (folgt der Kamera, eine Transformation pro
///   Bild), liegt geometrisch immer genau in der Richtung des DirectionalLight.
/// - Dunst: gestapelte, nach oben durchsichtiger werdende Ringe um die Kamera; zur Sonne hin wärmer (Textur je Azimut).
@MainActor
final class SkyRig {
    let root = Entity()
    private let haze = Entity()
    private let sun = ModelEntity()
    private var toSun = SIMD3<Float>(0, 1, 0)

    /// Abstand des Sonnen-Billboards (hinter dem Dunst bei 4 km, vor der Fernebene der Kamera bei 20 km)
    private let sunDistance: Float = 9000
    /// halbe Bildbreite des Billboards in Grad (Scheibe 0,32°, Rest ist Hof)
    private let sunHalfAngle: Float = 5

    /// Skyboxen je Umgebung (Name + Sonnenstand), damit ein zweites Öffnen der Strecke nichts neu rechnet
    private static var skyCache: [String: EnvironmentResource] = [:]

    nonisolated static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Scene")

    init() {
        root.addChild(haze)
        root.addChild(sun)
        sun.name = "sun-disc"
    }

    /// Dunst und Sonnenscheibe für `env` aufbauen (ersetzt vorherige).
    func build(_ env: SceneEnvironment) async {
        toSun = env.toSun
        await buildHaze(env)
        await buildSun(env)
    }

    /// Skybox zu `env` (gecacht). Das Bild entsteht ausserhalb des Main Actors.
    static func skybox(for env: SceneEnvironment) async -> EnvironmentResource? {
        let key = "\(env.name)|\(env.sunAzimuthDegrees)|\(env.sunElevationDegrees)"
        if let cached = skyCache[key] { return cached }
        let image = await Task.detached(priority: .userInitiated) {
            ProceduralTextures.skyEquirect(env, clouds: CloudMask.bundled)
        }.value
        guard let image else { return nil }
        do {
            let resource = try await EnvironmentResource(equirectangular: image)
            skyCache[key] = resource
            return resource
        } catch {
            log.error("Skybox: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Startargument `-demoLookAtSun 1` (nur Testbetrieb): Blickrichtung der Kamera zur Sonne, damit Bildschirmfotos
    /// zeigen, ob Abendrot (Skybox) und Sonnenscheibe (Billboard) übereinanderliegen. Kurs um die Hochachse wie
    /// `cameraHeading` (0 = Blick nach −z), Neigung so, dass die Sonne im oberen Bilddrittel steht (höchstens 20°).
    var demoSunView: (heading: Float, pitch: Float)? {
        guard Self.demoLookAtSun else { return nil }
        let horiz = (toSun.x * toSun.x + toSun.z * toSun.z).squareRoot()
        guard horiz > 0.05 else { return nil }   // Sonne fast im Zenit: kein sinnvoller Kurs
        let elevation = atan2(toSun.y, horiz)
        return (atan2(-toSun.x, -toSun.z), min(max(elevation - 0.12, -0.05), 0.35))
    }

    static let demoLookAtSun = UserDefaults.standard.bool(forKey: "demoLookAtSun")

    /// Pro Bild: Dunst und Sonne wandern mit der Kamera.
    func follow(eye: SIMD3<Float>) {
        haze.position = [eye.x, 0, eye.z]
        sun.position = eye + toSun * sunDistance
    }

    // MARK: - Dunst

    private func buildHaze(_ env: SceneEnvironment) async {
        haze.children.removeAll()
        guard env.hazeOpacity > 0 else { return }
        var texture: TextureResource?
        if let strip = ProceduralTextures.hazeStrip(env) {
            texture = try? await TextureResource(image: strip, options: .init(semantic: .color))
        }
        let bands = 6
        for b in 0..<bands {
            let y0 = b == 0 ? -40 : env.hazeHeight * pow(Float(b) / Float(bands), 1.6)
            let y1 = env.hazeHeight * pow(Float(b + 1) / Float(bands), 1.6)
            let opacity = env.hazeOpacity * pow(1 - Float(b) / Float(bands), 1.5)
            var material = UnlitMaterial()
            if let texture {
                material.color = .init(tint: .white, texture: .init(texture))
            } else {
                material.color = .init(tint: UIColor(rgb: env.hazeColor))
            }
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            material.faceCulling = .none
            material.writesDepth = false
            let ring = ModelEntity(mesh: Self.ringMesh(radius: env.hazeDistance, y0: y0, y1: y1, segments: 72),
                                   materials: [material])
            haze.addChild(ring)
        }
    }

    // MARK: - Sonne

    private func buildSun(_ env: SceneEnvironment) async {
        guard let image = ProceduralTextures.sunSprite(env, halfAngleDegrees: sunHalfAngle),
              let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) else {
            sun.isEnabled = false
            return
        }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(scale: 1, texture: .init(texture)))
        material.faceCulling = .none
        material.writesDepth = false
        let size = 2 * sunDistance * tan(sunHalfAngle * .pi / 180)
        sun.model = ModelComponent(mesh: .generatePlane(width: size, height: size), materials: [material])
        // Ebene liegt in xy mit Normale +z: zur Kamera drehen (Kamera sieht immer entlang toSun)
        sun.orientation = simd_quatf(from: [0, 0, 1], to: -env.toSun)
        sun.components.set(DynamicLightShadowComponent(castsShadow: false))
        sun.isEnabled = true
    }

    // MARK: - Licht-Variante (Gebäude ohne Sonnenschatten)

    /// Tauscht unter den Gruppen `groups` (z. B. "Buildings", "Bridges") die Grundfarb-Textur jedes Meshes gegen
    /// `<name>.jpg` aus `folder` (export.py --light ambient; Geometrie und UV sind dieselben). Mit
    /// `castShadows` werfen diese Meshes danach live Schatten (nur Qualität hoch). Liefert die Zahl getauschter
    /// Meshes; 0 heisst: Szene bleibt wie geladen (z. B. andere Namen oder Materialart), nichts bricht.
    static func applyLightVariant(to root: Entity, folder: URL, groups: [String], castShadows: Bool) async -> Int {
        let fm = FileManager.default
        var swapped = 0, models = 0
        let sampler = MaterialParameters.Texture.Sampler(clampSampler())
        for name in groups {
            guard let group = root.findEntity(named: name) else { continue }
            for entity in descendants(of: group) {
                guard var model = entity.components[ModelComponent.self] else { continue }
                models += 1
                // Name des Meshes am Entity selbst oder (falls RealityKit eine Zwischenstufe einfügt) am Elternteil
                let candidates = [entity.name, entity.parent?.name ?? ""].filter { !$0.isEmpty }
                guard let url = candidates.map({ folder.appendingPathComponent("\($0).jpg") })
                    .first(where: { fm.fileExists(atPath: $0.path) }) else { continue }
                guard let texture = try? await TextureResource(contentsOf: url, options: .init(semantic: .color))
                else { continue }
                var changed = false
                model.materials = model.materials.map { material -> any Material in
                    guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                    pbr.baseColor = .init(tint: pbr.baseColor.tint, texture: .init(texture, sampler: sampler))
                    changed = true
                    return pbr
                }
                guard changed else { continue }
                entity.components.set(model)
                if castShadows { entity.components.set(DynamicLightShadowComponent(castsShadow: true)) }
                swapped += 1
            }
        }
        if swapped == 0 {
            log.error("Licht-Variante: keine Textur getauscht (\(models) Meshes unter \(groups.joined(separator: ","), privacy: .public))")
        } else {
            log.info("Licht-Variante: \(swapped) von \(models) Meshes ohne Sonnenschatten")
        }
        return swapped
    }

    private static func descendants(of e: Entity) -> [Entity] {
        var out: [Entity] = []
        for child in e.children {
            out.append(child)
            out.append(contentsOf: descendants(of: child))
        }
        return out
    }

    private static func clampSampler() -> MTLSamplerDescriptor {
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.maxAnisotropy = 4
        return d
    }

    // MARK: - Geometrie

    /// Offener Zylindermantel um den Ursprung (Normalen nach innen), u läuft einmal um den Ring (Winkel 0 → 2π,
    /// Punkt (r cos a, y, r sin a)), passend zu `ProceduralTextures.hazeStrip`.
    static func ringMesh(radius r: Float, y0: Float, y1: Float, segments: Int) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for i in 0...segments {
            let u = Float(i) / Float(segments)
            let a = 2 * Float.pi * u
            let c = cos(a), s = sin(a)
            positions.append([r * c, y0, r * s])
            positions.append([r * c, y1, r * s])
            normals.append([-c, 0, -s])
            normals.append([-c, 0, -s])
            uvs.append([u, 0.25])
            uvs.append([u, 0.75])
        }
        for i in 0..<segments {
            let b = UInt32(2 * i)
            indices += [b, b + 1, b + 2, b + 2, b + 1, b + 3]
        }
        var descriptor = MeshDescriptor(name: "haze")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) { return mesh }
        return MeshResource.generateBox(size: [0.01, 0.01, 0.01], cornerRadius: 0)
    }
}

/// Einstellung „Sonnenstand“ (Einstellungen → Darstellung) und Startargument `-demoSun morning|noon|evening`.
enum SunSettings {
    /// UserDefaults-Schlüssel; Werte = `SunPreset.rawValue`, Standard `summerAfternoon`
    static let storageKey = "scene.sun"
    /// Startargument `-demoSun <wert>` (Argument-Domäne von UserDefaults), übersteuert die Einstellung
    static let demoKey = "demoSun"
    /// Licht-Variante der Kartenpakete ohne Sonnenschatten (course.json "light_variants")
    static let ambientVariant = "ambient"
    /// Ort ohne Koordinaten (Teststrecke): Zürich
    static let fallbackLocation = (latitude: 47.3667, longitude: 8.5500)

    static var current: SunPreset {
        if let arg = UserDefaults.standard.string(forKey: demoKey), let p = SunPreset(argument: arg) { return p }
        return SunPreset(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .summerAfternoon
    }

    static func label(_ p: SunPreset) -> String {
        switch p {
        case .summerAfternoon: return "Sommernachmittag (fest)"
        case .now: return "Jetzt (Uhrzeit am Ort)"
        case .morning: return "Sommermorgen"
        case .noon: return "Sommermittag"
        case .evening: return "Sommerabend"
        }
    }

    /// Himmel und Licht für eine Strecke. Sommernachmittag = genau die vorgerechnete Sonne.
    static func environment(for course: Course, preset: SunPreset = current, now: Date = Date()) -> SceneEnvironment {
        if preset.matchesBakedSun { return .summerSunny }
        let loc = SolarPosition.location(of: course) ?? fallbackLocation
        let pos = preset.position(latitude: loc.latitude, longitude: loc.longitude, now: now)
        return .forSun(pos, name: label(preset))
    }
}

/// Welche Licht-Variante auf die geladene Szene kommt: Texturordner und die Gruppen, deren Meshes ihn nutzen.
struct LightVariantRequest: Equatable, Sendable {
    var folder: URL
    var replaces: [String]
}
