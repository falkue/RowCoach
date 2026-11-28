import Metal
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

/// Zeichenfläche ohne RealityView/ARView: `RealityRenderer` (iOS 18+) rendert in einen eigenen `CAMetalLayer`, dessen
/// `drawableSize` wir selbst in `layoutSubviews` setzen. Grund: RealityView und ARView legen auf iOS 26/27 beim Drehen
/// ihre Zeichenfläche nicht neu an (alte Grösse bzw. schwarz); hier gibt es keine fremde Zeichenfläche mehr, die
/// RealityKit festhalten könnte. Es gibt genau EINEN Renderer pro Fahrt, auch beim Drehen (kein Neuaufbau).
///
/// Unterschiede zur RealityView: kein `.skybox`-Hintergrund (RealityRenderer kennt nur Farbe) → Himmelskuppel
/// (`SkyDome`), Bildbasiertes Licht über `renderer.lighting`; Kamera = `controller.cameraEntity`; `tick` direkt aus
/// dem CADisplayLink statt `SceneEvents.Update`.
struct SceneRendererContainer: UIViewRepresentable {
    let controller: RowingSceneController
    let skybox: EnvironmentResource?
    let skyImage: CGImage?
    let onReady: () -> Void

    func makeUIView(context: Context) -> SceneRendererView {
        let view = SceneRendererView(controller: controller, skybox: skybox, skyImage: skyImage)
        DispatchQueue.main.async { onReady() }
        return view
    }

    func updateUIView(_ view: SceneRendererView, context: Context) {}

    static func dismantleUIView(_ view: SceneRendererView, coordinator: ()) {
        view.stop()
    }
}

final class SceneRendererView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private let controller: RowingSceneController
    private let renderer: RealityRenderer?
    private let dome: Entity?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    /// höchstens drei Bilder gleichzeitig unterwegs (sonst staut sich bei langsamer GPU die Warteschlange)
    private let inFlight = DispatchSemaphore(value: 3)

    init(controller: RowingSceneController, skybox: EnvironmentResource?, skyImage: CGImage?) {
        self.controller = controller
        let device = MTLCreateSystemDefaultDevice()
        var renderer: RealityRenderer?
        do { renderer = try RealityRenderer() } catch {
            SkyRig.log.error("Szene: RealityRenderer nicht verfügbar: \(error.localizedDescription, privacy: .public)")
        }
        self.renderer = renderer
        self.dome = skyImage.flatMap { SkyDome.make(image: $0) }
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = .black
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = false   // RealityRenderer schreibt u. U. per Compute in das Ziel
        metalLayer.isOpaque = true
        guard let renderer else { return }
        renderer.cameraSettings.colorBackground = .color(UIColor.black.cgColor)
        renderer.cameraSettings.isToneMappingEnabled = true
        if let skybox { renderer.lighting.resource = skybox }
        controller.root.removeFromParent()
        renderer.entities.append(contentsOf: [controller.root])
        if let dome { renderer.entities.append(contentsOf: [dome]) }
        renderer.activeCamera = controller.cameraEntity
        controller.updateSubscription?.cancel()
        controller.updateSubscription = nil
        SkyRig.log.info("Szene: RealityRenderer angelegt")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, link == nil {
            let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if window == nil {
            link?.invalidate()
            link = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = scale
        metalLayer.contentsScale = scale
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard size.width > 0, size.height > 0, size != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = size
        SkyRig.log.info("Szene: Renderer-Grösse \(Int(self.bounds.width))×\(Int(self.bounds.height)) pt, drawable \(Int(size.width))×\(Int(size.height))")
    }

    func stop() {
        link?.invalidate()
        link = nil
        renderer?.entities.removeAll()
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard let renderer, metalLayer.drawableSize.width > 0 else { return }
        let dt = lastTimestamp.map { link.targetTimestamp - $0 } ?? link.duration
        lastTimestamp = link.targetTimestamp
        controller.tick(deltaTime: dt)
        if let dome { dome.position = controller.cameraEntity.position(relativeTo: nil) }
        guard inFlight.wait(timeout: .now()) == .success else { return }   // Bild auslassen statt blockieren
        guard let drawable = metalLayer.nextDrawable() else { inFlight.signal(); return }
        do {
            let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: drawable.texture))
            let semaphore = inFlight
            try renderer.updateAndRender(deltaTime: dt, cameraOutput: output,
                                         whenScheduled: { _ in drawable.present() },
                                         onComplete: { _ in semaphore.signal() })
        } catch {
            inFlight.signal()
            SkyRig.log.error("Szene: Rendern fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Himmelskuppel aus dem Skybox-Bild (equirektangular): innen sichtbare, unbeleuchtete Kugel um die Kamera.
/// Radius zwischen Sonnen-Billboard (9 km) und Fernebene (20 km). Falls Himmel/Sonne verdreht erscheinen:
/// `yawOffset` anpassen (UV-Naht von generateSphere vs. Azimut 0 der Textur).
enum SkyDome {
    static let radius: Float = 15_000
    static let yawOffset: Float = 0

    @MainActor static func make(image: CGImage) -> Entity? {
        guard let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.faceCulling = .none   // Kamera sitzt innen; Spiegelung unten macht das Bild seitenrichtig
        let entity = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        entity.name = "sky-dome"
        // Innenseite zeigen: X spiegeln (dreht die Dreiecke um und spiegelt das Bild zurück in Blickrichtung)
        entity.scale = [-1, 1, 1]
        entity.orientation = simd_quatf(angle: yawOffset, axis: [0, 1, 0])
        return entity
    }
}
