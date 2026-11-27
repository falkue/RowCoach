import Foundation
import Metal
import os
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
    /// Himmel, Sonnenscheibe und Dunst (SkyRig.swift)
    private let sky = SkyRig()
    /// Tore des Trainings (meist eines)
    private let gatesRoot = Entity()
    private var gates: [String: GateEntity] = [:]
    /// Tempo-Linie beim freien Rudern (aus, solange keine Distanz gesetzt ist)
    private let paceLine = PaceLineEntity()
    /// Verkehr auf dem Wasser: andere Ruderer und Schiffe (Team L, TrafficSystem.swift)
    private let traffic = TrafficSystem()
    /// Boote der anderen im Rennen (RaceRowers.swift); leer ohne Rennen
    private let raceRowers = RaceRowersSystem()
    private var raceRowersLogged = -1
    /// Bildrate (etwa jede Sekunde) an den Rennplaner; nil = niemand hört zu
    var onFrameRate: ((Double) -> Void)?
    private var fpsFrames = 0
    private var fpsTime = 0.0

    private(set) var environment: SceneEnvironment = .summerSunny
    private(set) var quality: SceneQuality = .standard
    private(set) var loadedSceneURL: URL?
    /// Licht-Variante ohne Sonnenschatten, die auf die geladene Szene angewendet ist (nil = Bake-Sonne)
    private(set) var loadedLightVariant: LightVariantRequest?
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
    /// Bedienungshilfe „Bewegung reduzieren“: Wasser driftet nicht, die Kamera schwenkt ohne Nachlauf mit dem Boot
    private var reduceMotion = false

    // Tempo-Linie: Distanz-Eingang (springt mit jedem Update der Session) und weich angezeigte Distanz
    private var paceTarget: Double?
    private var paceTargetTime: CFTimeInterval = 0
    private var paceRate = 0.0
    private var paceInterval = 0.25
    private var paceShown = 0.0
    private var paceTrackKey: String?
    private var pacePose: ((Double) -> TrackPose)?
    private var paceMax = Double.infinity
    /// Sprünge über diese Distanz werden direkt übernommen (neue Fahrt)
    private let paceSnapDistance = 60.0

    init() {
        root.addChild(landscape)
        root.addChild(boat.root)
        root.addChild(sun)
        root.addChild(sky.root)
        root.addChild(gatesRoot)
        root.addChild(paceLine.root)
        root.addChild(traffic.root)     // Verkehr (Team L)
        root.addChild(raceRowers.root)
        root.addChild(camera)
        camera.camera = PerspectiveCameraComponent(near: 0.2, far: 20_000, fieldOfViewInDegrees: 55)
        // Eigenes Boot nach dem Profil (Figur, Farben, Boot, Flaggen); bei Änderung neu einkleiden
        let store = RowerProfileStore.shared
        boat.setAppearance(store.appearance, catalog: store.catalog)
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: RowerProfileStore.didChangeAppearance, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let store = RowerProfileStore.shared
                self.boat.setAppearance(store.appearance, catalog: store.catalog)
            }
        }
    }

    private var appearanceObserver: NSObjectProtocol?

    // MARK: - Aufbau

    /// Einmalig beim Erzeugen der RealityView: Licht, Wasser, Himmel und Dunst. Liefert die Skybox-Umgebung zurück
    /// (nil, wenn sie nicht erzeugt werden konnte; dann bleibt die Standardumgebung von RealityKit).
    /// Mehrfacher Aufruf (neue RealityView mit demselben Controller) baut nichts doppelt.
    func build(environment env: SceneEnvironment, quality: SceneQuality) async -> EnvironmentResource? {
        if isBuilt { return skyResource }
        isBuilt = true
        // Figur- und Bootsteile (USDZ) einmal laden; bis dahin zeigen die Rigs die prozedurale Grundform
        await AvatarAssets.shared.load()
        self.environment = env
        self.quality = quality
        configureSun(env, quality: quality)
        await buildWater(env)
        await sky.build(env)
        skyResource = await SkyRig.skybox(for: env)
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

    // MARK: - Landschaft

    /// Lädt die USDZ der Strecke asynchron. Die Materialien der Datei bleiben unverändert (Team C rechnet
    /// Licht in die Texturen ein). Eine vorher geladene Szene wird zuerst entfernt, damit nie zwei Szenen
    /// gleichzeitig im Speicher liegen.
    /// `lightVariant`: Sonnenstand ≠ Bake-Sonne → Gebäude- und Brückentexturen ohne Sonnenschatten einsetzen
    /// (course.json "light_variants"); bei Qualität hoch werfen diese Meshes dann live Schatten.
    func loadLandscape(from url: URL, lightVariant: LightVariantRequest? = nil) async throws {
        if loadedSceneURL == url && loadedLightVariant == lightVariant { return }
        landscape.children.removeAll()
        loadedSceneURL = nil
        loadedLightVariant = nil
        let entity = try await Entity(contentsOf: url)
        // Gebäude- und Geländeschatten sind auf der Spark vorgerechnet; live wirft nur das Boot Schatten.
        Self.disableShadowCasting(entity)
        if let v = lightVariant {
            _ = await SkyRig.applyLightVariant(to: entity, folder: v.folder, groups: v.replaces,
                                               castShadows: quality == .hoch)
        }
        landscape.children.removeAll()
        landscape.addChild(entity)
        loadedSceneURL = url
        loadedLightVariant = lightVariant
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

    /// Tempo-Linie setzen: Distanz der Linie ab Start (nil = keine Linie). Position und Richtung kommen aus
    /// `CourseTrack` (hin, Wende, zurück; am Ende bleibt sie stehen) bzw. mit `laps` aus `LapTrack`.
    /// Zwischen den Updates wird mit der gemessenen Geschwindigkeit vorausgerechnet und geglättet.
    func setPaceLine(distance: Double?, course: Course, laps: Bool) {
        guard let distance, distance.isFinite else {
            paceTarget = nil
            paceLine.root.isEnabled = false
            return
        }
        let key = "\(course.id)|\(course.oneWayM)|\(laps)"
        if key != paceTrackKey {
            let track = CourseTrack(course: course)
            if laps {
                let lapTrack = LapTrack(track: track)
                pacePose = { lapTrack.pose(atDistance: $0) }
                paceMax = .infinity
            } else {
                pacePose = { track.pose(atDistance: $0) }
                paceMax = track.totalLength
            }
            paceTrackKey = key
            paceTarget = nil
        }
        let now = CACurrentMediaTime()
        if let last = paceTarget, abs(distance - last) <= paceSnapDistance {
            let dt = now - paceTargetTime
            if dt > 0.02 {
                paceInterval += (min(dt, 1.0) - paceInterval) * 0.3
                let measured = max((distance - last) / dt, 0)
                paceRate = measured == 0 || dt > 1.5 ? measured : paceRate + (measured - paceRate) * 0.5
            }
        } else {
            paceShown = min(distance, paceMax)
            paceRate = 0
        }
        paceTarget = distance
        paceTargetTime = now
        paceLine.root.isEnabled = true
    }

    /// Boote der anderen im Rennen nach dem Planer (nil = keine); Lage über dieselbe Strecke wie die Tempo-Linie
    func setRaceScene(_ frame: RaceSceneFrame?, course: Course, laps: Bool) {
        let count = frame?.items.count ?? 0
        if count != raceRowersLogged {
            raceRowersLogged = count
            Logger(subsystem: "com.falkue.RowCoach", category: "Race").info(
                "Szene: \(count, privacy: .public) Rennboote im Plan, \(frame?.clusters.count ?? 0, privacy: .public) Pulk-Gruppen")
        }
        guard let frame else {
            raceRowers.clear()
            return
        }
        raceRowers.setTrack(course: course, laps: laps)
        raceRowers.update(frame)
    }

    /// Rennboote vorab anlegen, wenn ein Rennen kommt (`RaceRowersSystem.prewarmHint`); muss vor dem Laden der
    /// Landschaft geschehen (Ein-/Ausblenden auf dem A12X, siehe `BoatRig.setFade`)
    func prewarmRaceIfExpected() {
        guard RaceRowersSystem.prewarmHint || UserDefaults.standard.integer(forKey: "demoRace") > 0
            || UserDefaults.standard.integer(forKey: "demoTournament") > 0 else { return }
        let b = RaceDeviceProfile.budget
        raceRowers.prewarm(b.full + b.lite)
    }

    /// Verkehr der Fahrt (andere Ruderer, Schiffe); nil = aus (Team L)
    func setTraffic(_ model: TrafficModel?) {
        traffic.model = model
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

    /// „Bewegung reduzieren“ (Bedienungshilfen) ein- oder ausschalten
    func setReduceMotion(_ on: Bool) {
        reduceMotion = on
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
        if let onFrameRate, deltaTime > 0 {
            fpsFrames += 1
            fpsTime += deltaTime
            if fpsTime >= 1 {
                onFrameRate(Double(fpsFrames) / fpsTime)
                fpsFrames = 0
                fpsTime = 0
            }
        }
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
            if reduceMotion {
                cameraHeading = boatHeading
            } else {
                cameraHeading += Self.angleDelta(from: cameraHeading, to: boatHeading) * (1 - exp(-dt / cameraHeadingTau))
            }
        }

        // Boot
        let boatPosition = SIMD3<Float>(Float(boatX), 0, Float(boatZ))
        boat.root.position = boatPosition
        boat.root.orientation = simd_quatf(angle: Float(boatHeading), axis: [0, 1, 0])

        // Kamera: hinter dem Boot, Blick nach vorn
        // Testbetrieb `-demoLookAtSun 1`: Kamera blickt zur Sonne (Lage von Abendrot und Sonnenscheibe prüfen)
        let sunView = sky.demoSunView
        let heading = sunView?.heading ?? Float(cameraHeading)
        let forward = SIMD3<Float>(-sin(heading), 0, -cos(heading))
        let eye = boatPosition - forward * cameraBack + SIMD3<Float>(0, cameraHeight, 0)
        let pitch = sunView?.pitch ?? -atan2(cameraHeight - lookTargetHeight, cameraBack + lookAhead)
        camera.position = eye
        camera.orientation = simd_quatf(angle: heading, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])

        // Wasser und Dunst wandern mit der Kamera
        if !reduceMotion { waterTime += dt }
        if let water {
            let tile = environment.waterTileSize
            let drift = environment.waterDrift * Float(waterTime)
            let dx = drift.x.truncatingRemainder(dividingBy: tile)
            let dz = drift.y.truncatingRemainder(dividingBy: tile)
            water.position = [(eye.x / tile).rounded(.down) * tile + dx, 0, (eye.z / tile).rounded(.down) * tile + dz]
        }
        sky.follow(eye: eye)
        for gate in gates.values { gate.step(dt: dt) }
        updatePaceLine(dt: dt, now: now)
        traffic.step(now: now, boatX: boatX, boatZ: boatZ, heading: boatHeading)   // Verkehr (Team L)
        raceRowers.step(dt: dt, now: now, eye: eye)

        updateStroke(dt: dt, now: now)
    }

    private func updatePaceLine(dt: Double, now: CFTimeInterval) {
        guard let target = paceTarget, let pose = pacePose else { return }
        let since = now - paceTargetTime
        // Kommt länger nichts Neues (Pause, Ziel), nicht weiter vorausrechnen
        let stale = since > max(paceInterval * 2, 0.6) + 0.5
        let horizon = stale ? 0 : min(since, min(max(paceInterval * 1.5, 0.1), 0.8))
        let predicted = min(target + paceRate * horizon, paceMax)
        paceShown += (predicted - paceShown) * (1 - exp(-dt / 0.15))
        let p = pose(paceShown)
        paceLine.place(x: p.x, z: p.z, heading: p.heading, boatX: boatX, boatZ: boatZ)
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
        // Geisterboot der Tempo-Linie im selben Schlagtakt; steht die Linie im Ziel, ruht die Figur
        if paceTarget != nil {
            paceLine.applyStroke(paceShown >= paceMax - 0.05 ? .rest : pose)
        }
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
}
