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

    @Environment(CourseLibrary.self) private var library: CourseLibrary?
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

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let controller = self.controller
            let environment = sceneEnvironment ?? SunSettings.environment(for: course)
            SkyRig.log.info("Sonne \(environment.name, privacy: .public): \(Double(environment.sunAzimuthDegrees))°/\(Double(environment.sunElevationDegrees))°")
            if let sky = await controller.build(environment: environment, quality: quality) {
                content.environment = .skybox(sky)
            }
            content.add(controller.root)
            controller.setPose(pose)
            controller.setStroke(rate: strokeRate, phase: strokePhase)
            controller.setGates(gates)
            controller.setPaceLine(distance: paceLineDistance, course: course, laps: paceLineLaps)
            // Verkehr: hier nur setzen, wenn vorhanden. Der Wert stammt vom ersten Aufbau der Ansicht und ist nach dem
            // Warten auf `build` oft veraltet (nil), während `.task(id:)` unten schon das Modell der Fahrt gesetzt hat.
            if let trafficModel { controller.setTraffic(trafficModel) }
            controller.updateSubscription = content.subscribe(to: SceneEvents.Update.self, on: nil,
                                                              componentType: nil) { [weak controller] event in
                MainActor.assumeIsolated {
                    controller?.tick(deltaTime: event.deltaTime)
                }
            }
            sceneReady = true
        } placeholder: {
            ProgressView("3D-Szene wird vorbereitet …")
        }
        .ignoresSafeArea()
        .onChange(of: pose) { _, newPose in controller.setPose(newPose) }
        .onChange(of: strokeRate) { _, _ in controller.setStroke(rate: strokeRate, phase: strokePhase) }
        .onChange(of: strokePhase) { _, _ in controller.setStroke(rate: strokeRate, phase: strokePhase) }
        .onChange(of: gates) { _, newGates in controller.setGates(newGates) }
        .onChange(of: paceLineDistance) { _, d in
            controller.setPaceLine(distance: d, course: course, laps: paceLineLaps)
        }
        .task(id: trafficModel.map { ObjectIdentifier($0) }) { controller.setTraffic(trafficModel) }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.height > proxy.size.width
        } action: { portrait in
            controller.setPortrait(portrait)
        }
        .task(id: LoadKey(url: sceneURL, variant: lightVariant, ready: sceneReady)) {
            await loadLandscape()
        }
        .overlay(alignment: .center) { loadingOverlay }
    }

    /// Verkehr der Fahrt (Team L)
    func traffic(_ model: TrafficModel?) -> RowingSceneView {
        var view = self
        view.trafficModel = model
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
