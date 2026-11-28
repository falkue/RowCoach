package com.falkue.rowcoach.render

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import android.view.SurfaceView
import com.falkue.rowcoach.course.Route
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Filament
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.Skybox
import com.google.android.filament.SwapChain
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.android.DisplayHelper
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.Channels
import kotlin.math.cos
import kotlin.math.sin

/** Messwerte für die Anzeige (einmal pro Sekunde) */
data class RenderStats(
    val fps: Double = 0.0,
    /** mittlere CPU-Zeit je Bild in ms (Kamera + Filament-Aufruf, ohne GPU) */
    val cpuMs: Double = 0.0,
    val loadMs: Long = 0,
    val glbMb: Double = 0.0,
    val textureProgress: Float = 0f,
    val skippedFrames: Int = 0,
    val error: String? = null,
)

/**
 * Filament-Szene für die Fahrt: lädt die GLB der Strecke (gltfio), Sonne + gleichmässiges Umgebungslicht, Himmel als
 * Farbe mit Dunst, und fährt die Kamera hinter dem Boot entlang der Route.
 * Das Boot ist der Knoten "Boat" in der GLB (export_glb.py), Bug in -z, Ursprung auf der Wasserlinie.
 *
 * Lebenszyklus: [attach] im AndroidView-factory, [load] + [start] beim Öffnen, [destroy] beim Verlassen.
 */
class SceneRenderer(
    private val context: Context,
    private val sceneAsset: String,
    private val route: Route,
    /** Distanz des Boots für das aktuelle Bild in m (wird je Bild abgefragt) */
    private val distanceProvider: () -> Double,
    private val onStats: (RenderStats) -> Unit,
) : Choreographer.FrameCallback {

    companion object {
        private const val TAG = "RowCoach3D"

        init {
            Filament.init()
            Gltfio.init()
        }

        // Kamera hinter dem Boot (Meter)
        private const val CAM_BACK = 9.0
        private const val CAM_HEIGHT = 2.6
        private const val LOOK_AHEAD = 14.0
        private const val LOOK_HEIGHT = 0.8
    }

    private val engine: Engine = Engine.create()
    private val renderer: Renderer = engine.createRenderer()
    private val scene: Scene = engine.createScene()
    private val view: View = engine.createView()
    private val cameraEntity = EntityManager.get().create()
    private val camera: Camera = engine.createCamera(cameraEntity)
    private val sunEntity = EntityManager.get().create()
    private val skybox: Skybox
    private val indirect: IndirectLight

    private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
    private val displayHelper = DisplayHelper(context)
    private var surfaceView: SurfaceView? = null
    private var swapChain: SwapChain? = null
    private val choreographer = Choreographer.getInstance()
    private var running = false

    private val materialProvider = UbershaderProvider(engine)
    private val assetLoader = AssetLoader(engine, materialProvider, EntityManager.get())
    private val resourceLoader = ResourceLoader(engine)
    private var asset: FilamentAsset? = null
    private var boatEntity = 0
    private var sourceReleased = false

    // Glättung der Kamera
    private var camYaw = Double.NaN

    // Messung
    private var frames = 0
    private var cpuNanos = 0L
    private var windowStart = 0L
    private var lastFrameNanos = 0L
    private var skipped = 0
    private var stats = RenderStats()

    init {
        view.scene = scene
        view.camera = camera
        // Für ältere Geräte: FXAA statt MSAA, keine Schatten, kein SSAO/Bloom (Standard aus)
        view.antiAliasing = View.AntiAliasing.FXAA
        view.isShadowingEnabled = false

        skybox = Skybox.Builder().color(0.56f, 0.73f, 0.92f, 1.0f).build(engine)
        scene.skybox = skybox
        // Gleichmässiges Himmelslicht (1 SH-Band = nur Farbe), Stärke passend zur Sonne
        indirect = IndirectLight.Builder()
            .irradiance(1, floatArrayOf(0.85f, 0.92f, 1.0f))
            .intensity(32_000f)
            .build(engine)
        scene.indirectLight = indirect

        // Dunst zum Horizont, damit der Rand der Umgebung (±9 km) weich im Himmel verschwindet
        view.fogOptions = View.FogOptions().apply {
            enabled = true
            distance = 300f
            density = 0.00025f
            heightFalloff = 0.004f
            maximumOpacity = 0.85f
            color = floatArrayOf(0.70f, 0.80f, 0.92f)
        }
        camera.setExposure(16f, 1f / 125f, 100f)
    }

    /** GLB lesen und Licht setzen (nach der Komposition aufrufen; meldet Ladezeit über onStats) */
    fun load() {
        if (asset != null || stats.loadMs > 0 || stats.error != null) return
        val t0 = SystemClock.elapsedRealtime()
        try {
            val buffer = context.assets.open(sceneAsset).use { input ->
                val size = input.available().coerceAtLeast(1 shl 20)
                var buf = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder())
                val ch = Channels.newChannel(input)
                while (true) {
                    if (!buf.hasRemaining()) {
                        val bigger = ByteBuffer.allocateDirect(buf.capacity() * 2).order(ByteOrder.nativeOrder())
                        buf.flip(); bigger.put(buf); buf = bigger
                    }
                    if (ch.read(buf) < 0) break
                }
                buf.flip()
                buf
            }
            val a = assetLoader.createAsset(buffer) ?: error("GLB nicht lesbar: $sceneAsset")
            // Texturen im Hintergrund dekodieren; bis dahin zeichnet Filament ohne Textur
            resourceLoader.asyncBeginLoad(a)
            scene.addEntities(a.entities)
            boatEntity = a.getFirstEntityByName("Boat")
            asset = a
            val sun = readSunDirection(buffer)
            LightManager.Builder(LightManager.Type.SUN)
                .color(1.0f, 0.96f, 0.90f)
                .intensity(100_000f)
                .direction(sun[0], sun[1], sun[2])
                .sunAngularRadius(1.9f)
                .castShadows(false)
                .build(engine, sunEntity)
            scene.addEntity(sunEntity)
            stats = stats.copy(loadMs = SystemClock.elapsedRealtime() - t0, glbMb = buffer.limit() / 1e6)
            Log.i(TAG, "Szene $sceneAsset geladen: ${"%.1f".format(buffer.limit() / 1e6)} MB, " +
                "${a.entities.size} Entities, Boot=${boatEntity != 0}, ${stats.loadMs} ms")
        } catch (e: Exception) {
            Log.e(TAG, "Szene nicht geladen", e)
            stats = stats.copy(error = "Szene fehlt: $sceneAsset (android/fetch_assets.sh ausführen)")
            // Ohne Szene trotzdem Sonne, damit Himmel und Anzeige laufen
            LightManager.Builder(LightManager.Type.SUN).direction(0.55f, -0.74f, -0.38f).intensity(100_000f)
                .build(engine, sunEntity)
            scene.addEntity(sunEntity)
        }
        onStats(stats)
    }

    /** Sonnenrichtung aus scene.extras der GLB (export_glb.py), sonst die Standard-Sonne 235°/48° */
    private fun readSunDirection(glb: ByteBuffer): FloatArray {
        val fallback = floatArrayOf(0.548f, -0.743f, -0.384f)
        return try {
            val b = glb.duplicate().order(ByteOrder.LITTLE_ENDIAN)
            val jsonLen = b.getInt(12)
            val bytes = ByteArray(jsonLen)
            b.position(20)
            b.get(bytes)
            val extras = JSONObject(String(bytes, Charsets.UTF_8)).getJSONArray("scenes")
                .getJSONObject(0).optJSONObject("extras") ?: return fallback
            val s = extras.optJSONArray("sunDirection") ?: return fallback
            floatArrayOf(s.getDouble(0).toFloat(), s.getDouble(1).toFloat(), s.getDouble(2).toFloat())
        } catch (e: Exception) {
            fallback
        }
    }

    fun attach(surface: SurfaceView) {
        surfaceView = surface
        uiHelper.renderCallback = object : UiHelper.RendererCallback {
            override fun onNativeWindowChanged(surface: Surface) {
                swapChain?.let { engine.destroySwapChain(it) }
                swapChain = engine.createSwapChain(surface)
                surfaceView?.display?.let { displayHelper.attach(renderer, it) }
            }

            override fun onDetachedFromSurface() {
                displayHelper.detach()
                swapChain?.let {
                    engine.destroySwapChain(it)
                    engine.flushAndWait()
                    swapChain = null
                }
            }

            override fun onResized(width: Int, height: Int) {
                view.viewport = Viewport(0, 0, width, height)
                val aspect = width.toDouble() / height.coerceAtLeast(1)
                camera.setProjection(55.0, aspect, 0.5, 15_000.0, Camera.Fov.VERTICAL)
            }
        }
        uiHelper.attachTo(surface)
    }

    fun start() {
        if (running) return
        running = true
        windowStart = System.nanoTime()
        choreographer.postFrameCallback(this)
    }

    fun stop() {
        running = false
        choreographer.removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        choreographer.postFrameCallback(this)
        val t0 = System.nanoTime()

        asset?.let { a ->
            if (!sourceReleased) {
                resourceLoader.asyncUpdateLoad()
                val p = resourceLoader.asyncGetLoadProgress()
                if (p >= 1f) {
                    a.releaseSourceData()
                    sourceReleased = true
                }
                if (p != stats.textureProgress) stats = stats.copy(textureProgress = p)
            }
        }
        updateBoatAndCamera()

        val sc = swapChain
        if (sc != null && uiHelper.isReadyToRender) {
            if (renderer.beginFrame(sc, frameTimeNanos)) {
                renderer.render(view)
                renderer.endFrame()
                frames++
            } else {
                skipped++
            }
        }
        cpuNanos += System.nanoTime() - t0

        // Frame-Abstände > 1,5 × 16,7 ms zählen als verpasst (Choreographer-Takt)
        if (lastFrameNanos != 0L && frameTimeNanos - lastFrameNanos > 25_000_000L) skipped++
        lastFrameNanos = frameTimeNanos

        val now = System.nanoTime()
        if (now - windowStart >= 1_000_000_000L) {
            val secs = (now - windowStart) / 1e9
            stats = stats.copy(fps = frames / secs, cpuMs = if (frames > 0) cpuNanos / 1e6 / frames else 0.0,
                skippedFrames = skipped)
            onStats(stats)
            frames = 0; cpuNanos = 0; skipped = 0; windowStart = now
        }
    }

    private fun updateBoatAndCamera() {
        val d = distanceProvider().coerceIn(0.0, route.length)
        val (bx, bz) = route.pointAt(d)
        val yaw = route.yawAt(d)

        if (boatEntity != 0) {
            val tm = engine.transformManager
            val inst = tm.getInstance(boatEntity)
            if (inst != 0) {
                val c = cos(yaw).toFloat()
                val s = sin(yaw).toFloat()
                // Rotation um y, spaltenweise (Filament: column-major)
                tm.setTransform(inst, floatArrayOf(
                    c, 0f, -s, 0f,
                    0f, 1f, 0f, 0f,
                    s, 0f, c, 0f,
                    bx.toFloat(), 0f, bz.toFloat(), 1f))
            }
        }

        // Kamera folgt mit leicht verzögerter Drehung (ruhigeres Bild in Kurven)
        camYaw = if (camYaw.isNaN()) yaw else camYaw + wrap(yaw - camYaw) * 0.08
        val fx = -sin(camYaw)   // Fahrtrichtung (x, z) aus dem Gierwinkel: Bug -z gedreht
        val fz = -cos(camYaw)
        camera.lookAt(
            bx - fx * CAM_BACK, CAM_HEIGHT, bz - fz * CAM_BACK,
            bx + fx * LOOK_AHEAD, LOOK_HEIGHT, bz + fz * LOOK_AHEAD,
            0.0, 1.0, 0.0)
    }

    /** Bäume ein-/ausblenden (Knoten tree_* aus export_glb.py) – A/B-Test der Bildrate, Bäume sind ~2/3 der Dreiecke */
    fun setTreesVisible(visible: Boolean) {
        val a = asset ?: return
        val trees = a.getEntitiesByPrefix("tree_")
        if (visible) scene.addEntities(trees) else scene.removeEntities(trees)
    }

    private fun wrap(a: Double): Double {
        var x = a
        while (x > Math.PI) x -= 2 * Math.PI
        while (x < -Math.PI) x += 2 * Math.PI
        return x
    }

    fun destroy() {
        stop()
        uiHelper.detach()
        asset?.let {
            scene.removeEntities(it.entities)
            if (!sourceReleased) resourceLoader.asyncCancelLoad()
            assetLoader.destroyAsset(it)
        }
        asset = null
        resourceLoader.destroy()
        assetLoader.destroy()
        materialProvider.destroyMaterials()
        materialProvider.destroy()
        engine.destroyEntity(sunEntity)
        engine.destroyIndirectLight(indirect)
        engine.destroySkybox(skybox)
        engine.destroyRenderer(renderer)
        engine.destroyView(view)
        engine.destroyScene(scene)
        engine.destroyCameraComponent(cameraEntity)
        EntityManager.get().destroy(cameraEntity)
        EntityManager.get().destroy(sunEntity)
        engine.destroy()
    }
}
