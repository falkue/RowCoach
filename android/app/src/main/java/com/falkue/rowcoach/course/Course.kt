package com.falkue.rowcoach.course

import android.content.Context
import org.json.JSONObject
import kotlin.math.atan2
import kotlin.math.hypot

/**
 * Eine Strecke aus assets/courses/<id>/course.json (dieselbe Datei wie in der iOS-App).
 * Szenenkoordinaten: Meter, y oben, x = E - E0, z = -(N - N0); "path_xz" liegt auf der Wasserfläche (y = 0).
 */
data class Course(
    val id: String,
    val title: String,
    val region: String,
    val totalM: Double,
    /** Pfad der GLB-Szene in den Assets, z. B. courses/henley-regatta/scene-standard.glb */
    val sceneAsset: String,
    val route: Route,
) {
    companion object {
        const val QUALITY = "standard"

        /** Alle Strecken, die fetch_assets.sh in die App kopiert hat (assets/courses/<id>/course.json). */
        fun loadAll(context: Context): List<Course> {
            val ids = context.assets.list("courses")?.sorted() ?: return emptyList()
            return ids.mapNotNull { id ->
                runCatching {
                    val text = context.assets.open("courses/$id/course.json").bufferedReader().use { it.readText() }
                    parse(text)
                }.getOrNull()
            }
        }

        fun parse(text: String): Course {
            val j = JSONObject(text)
            val p = j.getJSONArray("path_xz")
            val xs = DoubleArray(p.length())
            val zs = DoubleArray(p.length())
            for (i in 0 until p.length()) {
                val pt = p.getJSONArray(i)
                xs[i] = pt.getDouble(0)
                zs[i] = pt.getDouble(1)
            }
            // "henley-regatta/scene-{quality}.usdz" → "courses/henley-regatta/scene-standard.glb"
            val scene = j.getString("scene").replace("{quality}", QUALITY).removeSuffix(".usdz") + ".glb"
            val route = Route(xs, zs)
            return Course(
                id = j.getString("id"),
                title = j.optString("title", j.getString("id")),
                region = j.optString("region", ""),
                totalM = j.optDouble("total_m", route.length),
                sceneAsset = "courses/$scene",
                route = route,
            )
        }
    }
}

/** Polylinie mit Bogenlänge: Position und geglättete Fahrtrichtung für eine Distanz. */
class Route(private val xs: DoubleArray, private val zs: DoubleArray) {
    private val cum = DoubleArray(xs.size)

    init {
        require(xs.size >= 2) { "Pfad braucht mindestens zwei Punkte" }
        for (i in 1 until xs.size) cum[i] = cum[i - 1] + hypot(xs[i] - xs[i - 1], zs[i] - zs[i - 1])
    }

    val length: Double get() = cum.last()

    /** Punkt (x, z) bei Distanz d (auf [0, length] begrenzt) */
    fun pointAt(d: Double): Pair<Double, Double> {
        val s = d.coerceIn(0.0, length)
        var lo = 0
        var hi = cum.size - 1
        while (hi - lo > 1) {
            val mid = (lo + hi) ushr 1
            if (cum[mid] <= s) lo = mid else hi = mid
        }
        val seg = cum[hi] - cum[lo]
        val t = if (seg > 1e-9) (s - cum[lo]) / seg else 0.0
        return Pair(xs[lo] + (xs[hi] - xs[lo]) * t, zs[lo] + (zs[hi] - zs[lo]) * t)
    }

    /** Fahrtrichtung als Einheitsvektor (x, z), aus Punkten ±[window] m geglättet */
    fun headingAt(d: Double, window: Double = 8.0): Pair<Double, Double> {
        val (x0, z0) = pointAt(d - window)
        val (x1, z1) = pointAt(d + window)
        val l = hypot(x1 - x0, z1 - z0)
        return if (l > 1e-6) Pair((x1 - x0) / l, (z1 - z0) / l) else Pair(0.0, -1.0)
    }

    /** Gierwinkel um y, so dass die Boots-Achse -z (Bug) in Fahrtrichtung zeigt */
    fun yawAt(d: Double): Double {
        val (hx, hz) = headingAt(d)
        return atan2(-hx, -hz)
    }
}
