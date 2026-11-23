import Foundation
import Metal
import QuartzCore
import RealityKit
import RowCoachKit
import simd
import UIKit

/// Hält die Entities der Ruderszene und bewegt sie pro Bild: Boot und Kamera folgen der Strecke weich,
/// zwischen den Pose-Updates (PM5 etwa alle 250 ms) wird vorausgerechnet und geglättet.
@MainActor
final class RowingSceneController {
    // Szenengraph
    let root = Entity()
    private let landscape = Entity()        // Platz für die geladene USDZ
    private let camera = PerspectiveCamera()
    private let sun = DirectionalLight()
    private let boat = BoatRig()
    private var water: ModelEntity?
    private let haze = Entity()
    /// Tore des Trainings (meist eines)
    private let gatesRoot = Entity()
    private var gates: [String: GateEntity] = [:]

    private(set) var environment: SceneEnvironment = .summerSunny
    private(set) var quality: SceneQuality = .standard
    private(set) var loadedSceneURL: URL?
    var updateSubscription: EventSubscription?
    private var isBuilt = false
    private var skyResource: EnvironmentResource?

    // Kamera relativ zum Boot (Vorgabe Falk): 4,5 m dahinter, 2,2 m hoch, Blickziel 60 m voraus
    private let cameraBack: Float = 4.5
    private let cameraHeight: Float = 2.2
    private let lookAhead: Float = 60
    private let lookTargetHeight: Float = 0.3

    // Glättung (Zeitkonstanten in s)
    private let positionTau = 0.12
    private let boatHeadingTau = 0.25
    private let cameraHeadingTau = 0.9
    /// Sprünge über diese Distanz werden nicht interpoliert (neuer Start, Streckenwechsel)
    private let snapDistance = 40.0

    // Pose-Eingang
    private var lastPose: TrackPose?
    private var lastPoseTime: CFTimeInterval = 0
    private var velocity = SIMD2<Double>(0, 0)
    private var updateInterval = 0.25

    // Angezeigter Zustand
    private var boatX = 0.0, boatZ = 0.0
    private var boatHeading = 0.0
    private var cameraHeading = 0.0

    // Schlag
    private var strokeRate = 0
    private var strokePhaseInput: Double?
    private var strokePhaseInputTime: CFTimeInterval = 0
    private var phase = 0.0
    private var rowingWeight: Float = 0     // 0 = Ruhe, 1 = rudern (weich überblendet)

    // Wasser
    private var waterTime = 0.0

    init() {
        root.addChild(landscape)
        root.addChild(boat.root)
        root.addChild(sun)
        root.addChild(haze)
        root.addChild(gatesRoot)
        root.addChild(camera)
        camera.camera = PerspectiveCameraComponent(near: 0.2, far: 20_000, fieldOfViewInDegrees: 55)
    }

    // MARK: - Aufbau

    /// Einmalig beim Erzeugen der RealityView: Licht, Wasser, Dunst. Liefert die Skybox-Umgebung zurück
    /// (nil, wenn sie nicht erzeugt werden konnte; dann bleibt die Standardumgebung von RealityKit).
    /// Mehrfacher Aufruf (neue RealityView mit demselben Controller) baut nichts doppelt.
    func build(environment env: SceneEnvironment, quality: SceneQuality) async -> EnvironmentResource? {
        if isBuilt { return skyResource }
        isBuilt = true
        self.environment = env
        self.quality = quality
        configureSun(env, quality: quality)
        await buildWater(env)
        buildHaze(env)
        if let sky = ProceduralTextures.skyEquirect(env) {
            skyResource = try? await EnvironmentResource(equirectangular: sky)
        }
        return skyResource
    }

    /// Qualitätsstufe nachträglich ändern (Schatten an/aus); die passende USDZ lädt `loadLandscape`.
    func setQuality(_ quality: SceneQuality) {
        guard quality != self.quality else { return }
        self.quality = quality
        configureSun(environment, quality: quality)
    }

    private func configureSun(_ env: SceneEnvironment, quality: SceneQuality) {
        sun.light = DirectionalLightComponent(color: UIColor(rgb: env.sunColor), intensity: env.sunIntensity)
        // DirectionalLight leuchtet entlang seiner −z-Achse
        sun.orientation = simd_quatf(from: [0, 0, -1], to: env.sunLightDirection)
        if quality == .hoch {
            sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 250, depthBias: 1.5)
        } else {
            sun.shadow = nil
        }
    }

    /// Wasser: ein grosses Viereck auf y = 0, das mit der Kamera mitwandert (auf die Kachelgrösse gerastert,
    /// damit das Wellenmuster still steht). Die Wellen bewegen sich, indem das Viereck langsam driftet –
    /// das kostet nur eine Transformationsänderung pro Bild.
    private func buildWater(_ env: SceneEnvironment) async {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(rgb: env.waterColor))
        material.roughness = .init(floatLiteral: env.waterRoughness)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.6)
        material.faceCulling = .none
        if env.waterWaveStrength > 0,
           let image = ProceduralTextures.waterNormalMap(strength: env.waterWaveStrength),
           let texture = try? await TextureResource(image: image, options: .init(semantic: .normal)) {
            let sampler = MTLSamplerDescriptor()
            sampler.sAddressMode = .repeat
            sampler.tAddressMode = .repeat
            sampler.minFilter = .linear
            sampler.magFilter = .linear
            sampler.mipFilter = .linear
            sampler.maxAnisotropy = 4
            material.normal = .init(texture: .init(texture, sampler: .init(sampler)))
        }
        let entity = ModelEntity(mesh: Self.waterMesh(halfSize: 15_000, tile: env.waterTileSize),
                                 materials: [material])
        entity.name = "water"
        root.addChild(entity)
        water = entity
    }

    /// Dunst am Horizont: gestapelte, nach oben durchsichtiger werdende Ringe um die Kamera.
    /// Einfache Ersatzlösung für Nebel (RealityKit hat auf iOS keinen Distanznebel).
    private func buildHaze(_ env: SceneEnvironment) {
        haze.children.removeAll()
        guard env.hazeOpacity > 0 else { return }
        let bands = 6
        for b in 0..<bands {
            let y0 = b == 0 ? -40 : env.hazeHeight * pow(Float(b) / Float(bands), 1.6)
            let y1 = env.hazeHeight * pow(Float(b + 1) / Float(bands), 1.6)
            let opacity = env.hazeOpacity * pow(1 - Float(b) / Float(bands), 1.5)
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(rgb: env.hazeColor))
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            material.faceCulling = .none
            material.writesDepth = false
            let ring = ModelEntity(mesh: Self.ringMesh(radius: env.hazeDistance, y0: y0, y1: y1, segments: 72),
                                   materials: [material])
            haze.addChild(ring)
        }
    }

    // MARK: - Landschaft

    /// Lädt die USDZ der Strecke asynchron. Die Materialien der Datei bleiben unverändert (Team C rechnet
    /// Licht in die Texturen ein). Eine vorher geladene Szene wird zuerst entfernt, damit nie zwei Szenen
    /// gleichzeitig im Speicher liegen.
    func loadLandscape(from url: URL) async throws {
        if loadedSceneURL == url { return }
        landscape.children.removeAll()
        loadedSceneURL = nil
        let entity = try await Entity(contentsOf: url)
        // Gebäude- und Geländeschatten sind auf der Spark vorgerechnet; live wirft nur das Boot Schatten.
        Self.disableShadowCasting(entity)
        landscape.children.removeAll()
        landscape.addChild(entity)
        loadedSceneURL = url
    }

    private static func disableShadowCasting(_ e: Entity) {
        if e.components.has(ModelComponent.self) {
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
        }
        for child in e.children { disableShadowCasting(child) }
    }

    func clearLandscape() {
        landscape.children.removeAll()
        loadedSceneURL = nil
    }

    // MARK: - Eingänge

    func setPose(_ pose: TrackPose) {
        let now = CACurrentMediaTime()
        defer { lastPose = pose; lastPoseTime = now }
        guard let last = lastPose else {
            snap(to: pose)
            return
        }
        let dt = now - lastPoseTime
        let jump = hypot(pose.x - last.x, pose.z - last.z)
        if jump > snapDistance {
            snap(to: pose)
            return
        }
        if dt > 0.02 {
            updateInterval += (min(dt, 1.0) - updateInterval) * 0.3
            let measured = SIMD2<Double>((pose.x - last.x) / dt, (pose.z - last.z) / dt)
            velocity = dt > 1.5 ? measured : velocity + (measured - velocity) * 0.6
        }
        if pose.finished { velocity = .zero }
    }

    /// Tore setzen (Training). Neue Tore erscheinen sofort an ihrer Stelle, bestehende gleiten zur neuen Position.
    func setGates(_ markers: [GateMarker]) {
        let ids = Set(markers.map(\.id))
        for (id, gate) in gates where !ids.contains(id) {
            gate.root.removeFromParent()
            gates[id] = nil
        }
        for m in markers {
            if let gate = gates[m.id] {
                gate.setTarget(m)
            } else {
                let gate = GateEntity(marker: m)
                gatesRoot.addChild(gate.root)
                gates[m.id] = gate
            }
        }
    }

    func setStroke(rate: Int, phase: Double?) {
        strokeRate = max(rate, 0)
        if let phase {
            strokePhaseInput = phase
            strokePhaseInputTime = CACurrentMediaTime()
        } else {
            strokePhaseInput = nil
        }
    }

    /// Hochformat (iPhone): horizontales Sichtfeld festhalten, damit der Bildausschnitt nicht zu eng wird.
    func setPortrait(_ portrait: Bool) {
        camera.camera.fieldOfViewOrientation = portrait ? .horizontal : .vertical
        camera.camera.fieldOfViewInDegrees = portrait ? 70 : 55
    }

    private func snap(to pose: TrackPose) {
        boatX = pose.x
        boatZ = pose.z
        boatHeading = pose.heading
        cameraHeading = pose.heading
        velocity = .zero
    }

    // MARK: - Pro Bild

    func tick(deltaTime: Double) {
        let dt = min(max(deltaTime, 0), 0.1)
        guard dt > 0 else { return }
        let now = CACurrentMediaTime()

        if let pose = lastPose {
            // Vorausrechnen ab der letzten Pose, höchstens etwas länger als ein Update-Intervall
            let horizon = min(now - lastPoseTime, min(max(updateInterval * 1.5, 0.1), 0.6))
            let targetX = pose.x + velocity.x * horizon
            let targetZ = pose.z + velocity.y * horizon
            let kPos = 1 - exp(-dt / positionTau)
            boatX += (targetX - boatX) * kPos
            boatZ += (targetZ - boatZ) * kPos
            boatHeading += Self.angleDelta(from: boatHeading, to: pose.heading) * (1 - exp(-dt / boatHeadingTau))
            cameraHeading += Self.angleDelta(from: cameraHeading, to: boatHeading) * (1 - exp(-dt / cameraHeadingTau))
        }

        // Boot
        let boatPosition = SIMD3<Float>(Float(boatX), 0, Float(boatZ))
        boat.root.position = boatPosition
        boat.root.orientation = simd_quatf(angle: Float(boatHeading), axis: [0, 1, 0])

        // Kamera: hinter dem Boot, Blick nach vorn
        let heading = Float(cameraHeading)
        let forward = SIMD3<Float>(-sin(heading), 0, -cos(heading))
        let eye = boatPosition - forward * cameraBack + SIMD3<Float>(0, cameraHeight, 0)
        let pitch = -atan2(cameraHeight - lookTargetHeight, cameraBack + lookAhead)
        camera.position = eye
        camera.orientation = simd_quatf(angle: heading, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])

        // Wasser und Dunst wandern mit der Kamera
        waterTime += dt
        if let water {
            let tile = environment.waterTileSize
            let drift = environment.waterDrift * Float(waterTime)
            let dx = drift.x.truncatingRemainder(dividingBy: tile)
            let dz = drift.y.truncatingRemainder(dividingBy: tile)
            water.position = [(eye.x / tile).rounded(.down) * tile + dx, 0, (eye.z / tile).rounded(.down) * tile + dz]
        }
        haze.position = [eye.x, 0, eye.z]
        for gate in gates.values { gate.step(dt: dt) }

        updateStroke(dt: dt, now: now)
    }

    private func updateStroke(dt: Double, now: CFTimeInterval) {
        let cyclesPerSecond = Double(strokeRate) / 60
        phase += dt * cyclesPerSecond
        if let input = strokePhaseInput {
            // Phase vom Gerät: vorausrechnen und sanft nachziehen
            let predicted = input + (now - strokePhaseInputTime) * cyclesPerSecond
            var error = (predicted - phase).truncatingRemainder(dividingBy: 1)
            if error > 0.5 { error -= 1 }
            if error < -0.5 { error += 1 }
            phase += error * (1 - exp(-dt / 0.15))
        }
        phase -= phase.rounded(.down)

        let rowing = strokeRate > 0 || strokePhaseInput != nil
        let target: Float = rowing ? 1 : 0
        rowingWeight += (target - rowingWeight) * Float(1 - exp(-dt / 0.5))
        let pose = BoatRig.StrokePose.rest.mixed(with: .at(phase: phase, strokeRate: strokeRate), rowingWeight)
        boat.apply(pose)
    }

    // MARK: - Geometrie

    private static func angleDelta(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }

    /// Ebenes Viereck auf y = 0 mit gekachelten UV (1 UV-Einheit = `tile` Meter) und Tangenten für die Normal-Map.
    private static func waterMesh(halfSize h: Float, tile: Float) -> MeshResource {
        let corners: [SIMD3<Float>] = [[-h, 0, -h], [-h, 0, h], [h, 0, h], [h, 0, -h]]
        var descriptor = MeshDescriptor(name: "water")
        descriptor.positions = MeshBuffers.Positions(corners)
        descriptor.normals = MeshBuffers.Normals([SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: 4))
        descriptor.tangents = MeshBuffers.Tangents([SIMD3<Float>](repeating: SIMD3<Float>(1, 0, 0), count: 4))
        descriptor.bitangents = MeshBuffers.Tangents([SIMD3<Float>](repeating: SIMD3<Float>(0, 0, -1), count: 4))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(corners.map { SIMD2<Float>($0.x / tile, -$0.z / tile) })
        // gegen den Uhrzeigersinn von oben gesehen (Normale +y)
        descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        if let mesh = try? MeshResource.generate(from: [descriptor]) { return mesh }
        return MeshResource.generatePlane(width: 2 * h, depth: 2 * h)
    }

    /// Offener Zylindermantel um den Ursprung (Normalen nach innen).
    private static func ringMesh(radius r: Float, y0: Float, y1: Float, segments: Int) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0...segments {
            let a = 2 * Float.pi * Float(i) / Float(segments)
            let c = cos(a), s = sin(a)
            positions.append([r * c, y0, r * s])
            positions.append([r * c, y1, r * s])
            normals.append([-c, 0, -s])
            normals.append([-c, 0, -s])
        }
        for i in 0..<segments {
            let b = UInt32(2 * i)
            indices += [b, b + 1, b + 2, b + 2, b + 1, b + 3]
        }
        var descriptor = MeshDescriptor(name: "haze")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) { return mesh }
        return MeshResource.generateBox(size: [0.01, 0.01, 0.01], cornerRadius: 0)
    }
}
