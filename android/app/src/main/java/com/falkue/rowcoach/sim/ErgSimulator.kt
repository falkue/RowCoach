package com.falkue.rowcoach.sim

import com.falkue.rowcoach.pm5.PM5
import com.falkue.rowcoach.pm5.PM5Encoder
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Synthetischer Ruderer am PM5 – Port von `ErgSimulator` aus RowCoachKit (ohne Puls).
 * Liefert dieselben Bytes wie ein echter PM5; die App schickt sie durch denselben Parser ([com.falkue.rowcoach.pm5.RowingState]).
 * Aufruf etwa alle 0,25 s mit [step].
 */
class ErgSimulator(
    /** Zieltempo, s pro 500 m */
    var pace: Double = 125.0,
    var strokeRate: Int = 22,
    var rowing: Boolean = true,
) {
    var elapsed = 0.0
        private set
    var distance = 0.0
        private set
    var speed = 0.0
        private set
    var strokeCount = 0
        private set
    private var calories = 0.0
    private var energy = 0.0
    private var sinceStroke = 0.0
    private var started = false

    val power: Int get() = if (speed > 0.05) (2.8 * speed.pow(3)).roundToInt() else 0
    val currentPace: Double get() = if (speed > 0.1) 500 / speed else 0.0

    fun step(dtIn: Double): List<Pair<PM5.Characteristic, ByteArray>> {
        val dt = dtIn.coerceIn(0.0, 2.0)
        val target = if (rowing && pace > 0) 500 / pace else 0.0
        // Schwungrad: Geschwindigkeit folgt dem Ziel mit etwa 1,5 s Verzögerung
        speed += (target - speed) * min(1.0, dt / 1.5)
        if (target == 0.0 && speed < 0.1) speed = 0.0
        if (speed > 0) started = true
        if (started && speed > 0) elapsed += dt
        distance += speed * dt
        val w = power.toDouble()
        energy += w * dt
        if (speed > 0) calories += (4 * w + 300) / 3600 * dt

        val out = mutableListOf<Pair<PM5.Characteristic, ByteArray>>()
        val interval = if (strokeRate > 0) 60.0 / strokeRate else Double.POSITIVE_INFINITY
        sinceStroke += dt
        if (rowing && sinceStroke >= interval) {
            sinceStroke = 0.0
            strokeCount++
            val drive = min(0.8, interval / 3)
            out += PM5.Characteristic.STROKE_DATA to PM5Encoder.strokeData(elapsed, distance, speed * interval,
                drive, interval - drive, strokeCount)
            out += PM5.Characteristic.ADDITIONAL_STROKE_DATA to PM5Encoder.additionalStrokeData(elapsed, power,
                strokeCount)
        }
        val rowingState = if (speed > 0) 1 else 0
        val avgPower = if (elapsed > 0) (energy / elapsed).roundToInt() else 0
        val avgPace = if (distance > 1 && elapsed > 0) elapsed / distance * 500 else 0.0
        out += PM5.Characteristic.GENERAL_STATUS to PM5Encoder.generalStatus(elapsed, distance,
            workoutState = if (started) 1 else 0, rowingState = rowingState, strokeState = if (rowing) 4 else 0)
        out += PM5.Characteristic.ADDITIONAL_STATUS1 to PM5Encoder.additionalStatus1(elapsed, speed,
            if (rowing) strokeRate else 0, null, currentPace, avgPace)
        out += PM5.Characteristic.ADDITIONAL_STATUS2 to PM5Encoder.additionalStatus2(elapsed, avgPower,
            calories.toInt())
        return out
    }
}
