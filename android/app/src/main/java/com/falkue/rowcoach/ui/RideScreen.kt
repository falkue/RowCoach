package com.falkue.rowcoach.ui

import android.os.Build
import android.os.SystemClock
import android.view.SurfaceView
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.falkue.rowcoach.audio.CoachAudio
import com.falkue.rowcoach.ble.PM5BleClient
import com.falkue.rowcoach.course.Course
import com.falkue.rowcoach.pm5.RowingState
import com.falkue.rowcoach.render.RenderStats
import com.falkue.rowcoach.render.SceneRenderer
import com.falkue.rowcoach.sim.ErgSimulator
import kotlinx.coroutines.delay
import java.util.Locale

enum class RideSource { SIMULATOR, PM5 }

/**
 * Fahrt-Ansicht: 3D-Szene (Filament) mit Kamera hinter dem Boot und eine einfache Anzeige.
 * Quelle Simulator: ErgSimulator erzeugt PM5-Bytes alle 0,25 s → RowingState (Parser) → Anzeige und Bootsposition.
 * Quelle PM5: dieselben Bytes kommen per Bluetooth vom Gerät.
 */
@Composable
fun RideScreen(course: Course, source: RideSource, ble: PM5BleClient, onBack: () -> Unit) {
    val context = LocalContext.current
    val rowing = remember { RowingState() }
    val snapshot by rowing.snapshot.collectAsState()
    var stats by remember { mutableStateOf(RenderStats()) }
    var trees by remember { mutableStateOf(true) }
    val sim = remember { ErgSimulator(pace = 118.0, strokeRate = 24) }
    val audio = remember { CoachAudio(context) }

    // Distanz für das 3D-Bild: monoton, aus letzter Meldung + Geschwindigkeit interpoliert
    val renderDistance = remember {
        var shown = 0.0
        val f: () -> Double = {
            val d = rowing.renderDistance(SystemClock.elapsedRealtime())
            if (d < shown - 5) shown = d          // Neustart am PM5: zurückspringen
            else if (d > shown) shown = d
            shown
        }
        f
    }

    val renderer = remember {
        SceneRenderer(context, course.sceneAsset, course.route, renderDistance) { s -> stats = s }
    }

    DisposableEffect(Unit) {
        rowing.reset()
        audio.play(CoachAudio.START)
        if (source == RideSource.PM5) ble.onNotification = { c, b -> rowing.ingest(c, b) }
        renderer.load()
        renderer.start()
        onDispose {
            renderer.destroy()
            audio.stop()
            ble.onNotification = null
        }
    }

    if (source == RideSource.SIMULATOR) {
        LaunchedEffect(Unit) {
            var last = SystemClock.elapsedRealtime()
            while (true) {
                delay(250)
                val now = SystemClock.elapsedRealtime()
                for ((c, b) in sim.step((now - last) / 1000.0)) rowing.ingest(c, b)
                last = now
            }
        }
    }

    BackHandler(onBack = onBack)

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx -> SurfaceView(ctx).also { renderer.attach(it) } },
            modifier = Modifier.fillMaxSize(),
        )
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(12.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                Metric("Zeit", formatTime(snapshot.elapsed))
                Metric("Distanz", formatDistance(snapshot.distance))
                Metric("Tempo /500 m", formatPace(snapshot.pace))
                Metric("Schlagzahl", if (snapshot.strokeRate > 0) "${snapshot.strokeRate}" else "–")
                Metric("Watt", if (snapshot.power > 0) "${snapshot.power}" else "–")
                Box(Modifier.weight(1f))
                OutlinedButton(onClick = { trees = !trees; renderer.setTreesVisible(trees) }) {
                    Text(if (trees) "Bäume aus" else "Bäume an", color = Color.White)
                }
                Button(onClick = onBack, colors = ButtonDefaults.buttonColors(containerColor = Bahnen.Gelb,
                    contentColor = Bahnen.Tinte)) { Text("Ende", fontWeight = FontWeight.Bold) }
            }
            Box(Modifier.weight(1f))
            val left = course.totalM - snapshot.distance
            Row(verticalAlignment = Alignment.Bottom) {
                Text(if (left > 0) "noch ${formatDistance(left)} · ${course.title}" else "Ziel erreicht",
                    color = Color.White, fontSize = 14.sp,
                    modifier = Modifier.background(Color(0x99000000), RoundedCornerShape(8.dp))
                        .padding(horizontal = 10.dp, vertical = 6.dp))
                Box(Modifier.weight(1f))
                DebugStats(stats, source)
            }
        }
    }
}

@Composable
private fun Metric(label: String, value: String) {
    Column(Modifier.background(Color(0xCC0B0F1E), RoundedCornerShape(10.dp))
        .padding(horizontal = 12.dp, vertical = 6.dp)) {
        Text(label, color = Bahnen.Gelb, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        Text(value, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace)
    }
}

/** Messwerte des Machbarkeitstests: FPS, CPU-Zeit je Bild, Ladezeit, Texturfortschritt */
@Composable
private fun DebugStats(s: RenderStats, source: RideSource) {
    val lines = buildList {
        add(String.format(Locale.ROOT, "%.0f fps · CPU %.1f ms/Bild · %d verpasst/s", s.fps, s.cpuMs, s.skippedFrames))
        add(String.format(Locale.ROOT, "GLB %.1f MB in %d ms · Texturen %.0f %%", s.glbMb, s.loadMs,
            s.textureProgress * 100))
        add("${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} · " +
            if (source == RideSource.SIMULATOR) "Simulator" else "PM5")
        s.error?.let { add(it) }
    }
    Column(Modifier.background(Color(0x99000000), RoundedCornerShape(8.dp)).padding(8.dp)) {
        lines.forEach { Text(it, color = Color.White, fontSize = 11.sp, fontFamily = FontFamily.Monospace) }
    }
}
