package com.falkue.rowcoach.ui

import java.util.Locale
import kotlin.math.roundToInt

fun formatTime(s: Double): String {
    val t = s.coerceAtLeast(0.0).toInt()
    return if (t >= 3600) String.format(Locale.ROOT, "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
    else String.format(Locale.ROOT, "%d:%02d", t / 60, t % 60)
}

/** Tempo je 500 m, z. B. 2:05,0 */
fun formatPace(s: Double): String {
    if (s <= 0 || !s.isFinite()) return "–:––"
    val tenths = (s * 10).roundToInt()
    return String.format(Locale.GERMANY, "%d:%02d,%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
}

fun formatDistance(m: Double): String =
    if (m < 10_000) "${m.roundToInt()} m" else String.format(Locale.GERMANY, "%.2f km", m / 1000)
