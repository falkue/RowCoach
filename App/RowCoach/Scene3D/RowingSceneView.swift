import RealityKit
import RowCoachKit
import SwiftUI

/// 3D-Ansicht der Ruderstrecke (Etappe 2). Team A legt das HUD darüber.
///
/// - `pose`: aktuelle Lage aus `CourseTrack.pose(atDistance:)`, darf mehrmals pro Sekunde wechseln;
///   die Ansicht interpoliert selbst flüssig dazwischen.
/// - `strokeRate`: Schläge pro Minute (0 = Figur ruht).
/// - `strokePhase`: 0…1 im Schlag (0 = Wasserfassen), falls bekannt; nil → die Ansicht taktet selbst aus `strokeRate`.
struct RowingSceneView: View {
    let course: Course
    let pose: TrackPose
    let strokeRate: Int
    let strokePhase: Double?
    /// Tore des Trainings (Position aus `LapTrack`); leer beim freien Rudern
    let gates: [GateMarker]
    /// Tempo-Linie beim freien Rudern: Distanz der Linie ab Start (m); nil = keine Linie
    let paceLineDistance: Double?
    /// Linie über `LapTrack` (Fahrt mit Runden) statt über `CourseTrack`
    let paceLineLaps: Bool
    /// Verkehr auf dem Wasser (andere Ruderer, Schiffe); setzen mit `.traffic(_:)`, nil = aus (Team L)
    private var trafficModel: TrafficModel?
    /// Boote der anderen im Rennen (Planer-Schritt); setzen mit `.raceScene(_:onFrameRate:)`, nil = keine
    private var raceFrame: RaceSceneFrame?
    /// gemessene Bildrate an den Rennplaner
    private var onFrameRate: ((Double) -> Void)?

    @Environment(CourseLibrary.self) private var library: CourseLibrary?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Der Controller wird erst beim ersten Zugriff gebaut: SwiftUI erzeugt die View-Struktur bei jedem
    /// Pose-Update neu, der Startwert von @State darf deshalb nichts Teures anlegen.
    @State private var box = ControllerBox()
    private var controller: RowingSceneController { box.controller }
    @State private var loadState: LoadState = .idle
    @State private var sceneReady = false

    /// Himmel und Licht; nil = aus der Einstellung „Sonnenstand“ bzw. `-demoSun` (SunSettings)
    private let sceneEnvironment: SceneEnvironment?

    init(course: Course, pose: TrackPose, strokeRate: Int, strokePhase: Double?,
         environment: SceneEnvironment? = nil, gates: [GateMarker] = [],
         paceLineDistance: Double? = nil, paceLineLaps: Bool = false) {
        self.course = course
        self.pose = pose
        self.strokeRate = strokeRate
        self.strokePhase = strokePhase
        self.sceneEnvironment = environment
        self.gates = gates
        self.paceLineDistance = paceLineDistance
        self.paceLineLaps = paceLineLaps
    }

    private enum LoadState: Equatable {
        case idle, loading, loaded, missing, failed(String)
    }

    /// Bibliothek aus der Umgebung, sonst eine eigene (lädt nur das kleine Verzeichnis der Strecken).
    private var effectiveLibrary: CourseLibrary { library ?? Self.fallbackLibrary }
    private static let fallbackLibrary = CourseLibrary()

    private var quality: SceneQuality { effectiveLibrary.quality }
    private var sceneURL: URL? { effectiveLibrary.sceneURL(for: course, quality: quality) }
    /// Licht-Variante ohne Sonnenschatten, wenn der Sonnenstand nicht der vorgerechneten Sonne entspricht
    private var lightVariant: LightVariantRequest? {
        let bakedSun = sceneEnvironment.map(\.matchesBakedSun) ?? SunSettings.current.matchesBakedSun
        guard !bakedSun else { return nil }
        return effectiveLibrary.lightVariant(SunSettings.ambientVariant, for: course, quality: quality)
    }

    /// Grösse, mit der die aktuelle RealityView aufgebaut wurde (nil = noch nicht gemessen)
    @State private var builtSize: CGSize?
    /// zuletzt gemessene Grösse; der Neuaufbau wartet, bis sie sich kurz nicht mehr ändert (Stage Manager zieht stufenlos)
    @State private var pendingSize: CGSize?
    /// erhöht sich bei jedem Neuaufbau nach einer Grössenänderung (`.id` der RealityView)
    @State private var generation = 0

    /// Neuaufbau der RealityView nach einer Grössenänderung (Drehen, Split View, Stage Manager). Die RealityView legt
    /// auf dem iPhone beim Drehen ihre Zeichenfläche nicht neu an: Hoch → quer füllte die Szene nur die linke Hälfte
    /// (Hochformat-Breite), der Rest blieb schwarz. Der Neuaufbau ist billig, weil der Controller (Entities, Landschaft,
    /// Himmel) erhalten bleibt: `build` und `loadLandscape` laden nichts doppelt, nur `root` wechselt in die neue
    /// Ansicht. Testbetrieb `-sceneRebuildOnResize 0` schaltet ihn ab (prüfen, ob die feste Grösse allein reicht).
    private static let rebuildOnResize = UserDefaults.standard.object(forKey: "sceneRebuildOnResize") as? Bool ?? true

    var body: some View {
        // Feste Grösse aus dem GeometryReader (statt nur `.ignoresSafeArea()`), damit die RealityView bei jeder
        // Änderung eine eindeutige neue Grösse bekommt.
        GeometryReader { geo in
            realityView
                .id(generation)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onChange(of: pose) { _, newPose in controller.setPose(newPose) }
        .onChange(of: reduceMotion) { _, on in controller.setReduceMotion(on) }
        .onChange(of: strokeRate) { _, _ in controller.setStroke(rate: strokeRate, phase: strokePhase) }
        .onChange(of: strokePhase) { _, _ in controller.setStroke(rate: strokeRate, phase: strokePhase) }
        .onChange(of: gates) { _, newGates in controller.setGates(newGates) }
        .onChange(of: paceLineDistance) { _, d in
            controller.setPaceLine(distance: d, course: course, laps: paceLineLaps)
        }
        .task(id: trafficModel.map { ObjectIdentifier($0) }) { controller.setTraffic(trafficModel) }
        .onChange(of: raceFrame) { _, frame in
            controller.setRaceScene(frame, course: course, laps: paceLineLaps)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            sizeChanged(size)
        }
        .task(id: pendingSize) {
            await rebuildIfResized()
        }
        .task(id: LoadKey(url: sceneURL, variant: lightVariant, ready: sceneReady)) {
            await loadLandscape()
        }
        .overlay(alignment: .center) { loadingOverlay }
    }

    private var realityView: some View {
        RealityView { content in
            content.camera = .virtual
            let controller = self.controller
            let environment = sceneEnvironment ?? SunSettings.environment(for: course)
            SkyRig.log.info("Sonne \(environment.name, privacy: .public): \(Double(environment.sunAzimuthDegrees))°/\(Double(environment.sunElevationDegrees))°")
            if let sky = await controller.build(environment: environment, quality: quality) {
                content.environment = .skybox(sky)
            }
            // Rennboote vor der Landschaft anlegen (die lädt erst nach `sceneReady`)
            controller.prewarmRaceIfExpected()
            controller.onFrameRate = onFrameRate
            // eigener Halter je RealityView: beim Neuaufbau zieht `root` in den neuen Halter um; räumt die alte Ansicht
            // danach ihren Inhalt ab, betrifft das nur ihren (leeren) Halter
            let holder = Entity()
            holder.addChild(controller.root)
            content.add(holder)
            controller.setReduceMotion(reduceMotion)
            controller.setPose(pose)
            controller.setStroke(rate: strokeRate, phase: strokePhase)
            controller.setGates(gates)
            controller.setPaceLine(distance: paceLineDistance, course: course, laps: paceLineLaps)
            // Verkehr: hier nur setzen, wenn vorhanden. Der Wert stammt vom ersten Aufbau der Ansicht und ist nach dem
            // Warten auf `build` oft veraltet (nil), während `.task(id:)` unten schon das Modell der Fahrt gesetzt hat.
            if let trafficModel { controller.setTraffic(trafficModel) }
            // Rennboote wie der Verkehr nur setzen, wenn vorhanden: der Wert stammt vom ersten Aufbau und ist nach dem
            // Warten auf `build` oft veraltet (leer) – sonst verschwinden die Boote kurz („0 Rennboote“)
            if let raceFrame { controller.setRaceScene(raceFrame, course: course, laps: paceLineLaps) }
            // Neuaufbau nach Grössenänderung: das Abo der alten Ansicht beenden
            controller.updateSubscription?.cancel()
            controller.updateSubscription = content.subscribe(to: SceneEvents.Update.self, on: nil,
                                                              componentType: nil) { [weak controller] event in
                MainActor.assumeIsolated {
                    controller?.tick(deltaTime: event.deltaTime)
                }
            }
            sceneReady = true
        } placeholder: {
            // beim Neuaufbau nach dem Drehen kein Hinweistext, nur ein kurzer dunkler Moment
            if sceneReady {
                Color.black
            } else {
                ProgressView("3D-Szene wird vorbereitet …")
            }
        }
    }

    /// Neue Grösse: Sichtfeld sofort anpassen, Neuaufbau (falls nötig) nach kurzer Ruhe in `rebuildIfResized`
    private func sizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        controller.setViewport(aspect: Double(size.width / size.height))
        if builtSize == nil {
            builtSize = size
        } else {
            pendingSize = size
        }
    }

    private func rebuildIfResized() async {
        guard Self.rebuildOnResize, let size = pendingSize, let built = builtSize else { return }
        guard abs(size.width - built.width) > 1 || abs(size.height - built.height) > 1 else { return }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        builtSize = size
        generation += 1
    }

    /// Verkehr der Fahrt (Team L)
    func traffic(_ model: TrafficModel?) -> RowingSceneView {
        var view = self
        view.trafficModel = model
        return view
    }

    /// Boote der anderen im Rennen nach dem Planer (siehe `RaceRowersSystem`); `onFrameRate` bekommt etwa jede
    /// Sekunde die gemessene Bildrate (Rückkopplung des Planers)
    func raceScene(_ frame: RaceSceneFrame?, onFrameRate: ((Double) -> Void)? = nil) -> RowingSceneView {
        var view = self
        view.raceFrame = frame
        view.onFrameRate = onFrameRate
        return view
    }

    @MainActor
    private final class ControllerBox {
        lazy var controller = RowingSceneController()
    }

    private struct LoadKey: Equatable {
        var url: URL?
        var variant: LightVariantRequest?
        var ready: Bool
    }

    private func loadLandscape() async {
        guard sceneReady else { return }
        guard let url = sceneURL else {
            // Strecke ohne Landschaft (z. B. Course.straight): nur Wasser und Himmel, ohne Hinweis
            controller.clearLandscape()
            loadState = course.scene.isEmpty ? .idle : .missing
            return
        }
        controller.setQuality(quality)
        loadState = .loading
        do {
            try await controller.loadLandscape(from: url, lightVariant: lightVariant)
            // zweite Wasserfarbe (nur Strecken mit course.json "water_tint", Amazonas)
            await controller.setWaterTint(course.waterTint, sceneURL: url)
            if !Task.isCancelled { loadState = .loaded }
        } catch {
            if !Task.isCancelled { loadState = .failed(error.localizedDescription) }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        switch loadState {
        case .loading:
            ProgressView("Landschaft wird geladen …")
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .missing:
            Label("Keine 3D-Landschaft installiert (install_courses.py)", systemImage: "map")
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .failed(let message):
            Label("Landschaft konnte nicht geladen werden: \(message)", systemImage: "exclamationmark.triangle")
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .idle, .loaded:
            EmptyView()
        }
    }
}
