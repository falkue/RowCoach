package com.falkue.rowcoach.pm5

import android.os.SystemClock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Was die Fahrt-Ansicht anzeigt (stark vereinfachtes Gegenstück zu `RowingSnapshot` im Kit). */
data class RowingSnapshot(
    val elapsed: Double = 0.0,      // s
    val distance: Double = 0.0,     // m
    val speed: Double = 0.0,        // m/s
    val pace: Double = 0.0,         // s pro 500 m, 0 = steht
    val strokeRate: Int = 0,        // Schläge/min
    val power: Int = 0,             // W
    val strokeCount: Int = 0,
    val heartRate: Int? = null,
    /** SystemClock.elapsedRealtime() der letzten Distanz, für die Interpolation im 3D-Bild */
    val distanceAtMs: Long = 0,
)

/**
 * Nimmt rohe PM5-Notifications (vom Simulator oder vom echten Gerät) entgegen, dekodiert sie mit [PM5Parser] und
 * führt den Zustand – derselbe Weg für beide Quellen, wie in der iOS-App (SimulatorDevice → DeviceManager).
 */
class RowingState {
    private val _snapshot = MutableStateFlow(RowingSnapshot())
    val snapshot: StateFlow<RowingSnapshot> = _snapshot.asStateFlow()

    var parseErrors = 0
        private set

    fun reset() {
        _snapshot.value = RowingSnapshot(distanceAtMs = SystemClock.elapsedRealtime())
    }

    fun ingest(characteristic: PM5.Characteristic, bytes: ByteArray) {
        val msg = try {
            PM5Parser.parse(characteristic, bytes)
        } catch (e: PM5ParseException) {
            parseErrors++
            return
        }
        val s = _snapshot.value
        _snapshot.value = when (msg) {
            is PM5Message.General -> s.copy(elapsed = msg.v.elapsedTime, distance = msg.v.distance,
                distanceAtMs = SystemClock.elapsedRealtime())
            is PM5Message.Additional1 -> s.copy(speed = msg.v.speed, strokeRate = msg.v.strokeRate,
                pace = msg.v.currentPace, heartRate = msg.v.heartRate ?: s.heartRate)
            is PM5Message.AdditionalStroke -> s.copy(power = msg.v.strokePower, strokeCount = msg.v.strokeCount)
            is PM5Message.Stroke -> s.copy(strokeCount = msg.v.strokeCount)
            is PM5Message.Additional2, is PM5Message.Summary -> s
        }
    }

    /** Distanz für das aktuelle Bild: letzte gemeldete Distanz + Geschwindigkeit × Alter (höchstens 1 s). */
    fun renderDistance(nowMs: Long = SystemClock.elapsedRealtime()): Double {
        val s = _snapshot.value
        val age = ((nowMs - s.distanceAtMs).coerceIn(0, 1000)) / 1000.0
        return s.distance + s.speed * age
    }
}
