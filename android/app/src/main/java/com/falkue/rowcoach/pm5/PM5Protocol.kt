package com.falkue.rowcoach.pm5

import java.util.UUID

/**
 * Concept2 PM5 Bluetooth-Protokoll – Kotlin-Port der Byte-Layouts aus RowCoachKit (PM5Protocol.swift).
 * Quelle dort: Concept2 "PM CSAFE Communication Definition", Abschnitt "Smart Bluetooth".
 * Mehrbyte-Werte sind Little Endian. Längen, Mindestlängen und Skalierung wie im Kit; bei Änderungen beide anpassen,
 * bis der Swift-Kern per JNI eingebunden ist (android/README.md, „Weg zum Swift-Kern“).
 */
object PM5 {
    /** Basis-UUID CE06XXXX-43E5-11E4-916C-0800200C9A66 */
    fun uuid(short: Int): UUID = UUID.fromString(String.format("CE06%04X-43E5-11E4-916C-0800200C9A66", short))

    val discoveryService: UUID = uuid(0x0000)
    val rowingService: UUID = uuid(0x0030)

    /** Client Characteristic Configuration Descriptor (Notifications einschalten) */
    val cccd: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    enum class Characteristic(val short: Int) {
        GENERAL_STATUS(0x0031), ADDITIONAL_STATUS1(0x0032), ADDITIONAL_STATUS2(0x0033), SAMPLE_RATE(0x0034),
        STROKE_DATA(0x0035), ADDITIONAL_STROKE_DATA(0x0036), WORKOUT_SUMMARY(0x0039);

        val uuid: UUID get() = uuid(short)

        companion object {
            /** Characteristics, die RowCoach abonniert (wie `PM5.Characteristic.subscribed` im Kit) */
            val subscribed = listOf(GENERAL_STATUS, ADDITIONAL_STATUS1, ADDITIONAL_STATUS2, STROKE_DATA,
                ADDITIONAL_STROKE_DATA, WORKOUT_SUMMARY)

            fun from(uuid: UUID) = entries.firstOrNull { it.uuid == uuid }
        }
    }

    /** Wert für 0x0034: 3 = alle 100 ms (wie die iOS-App) */
    const val SAMPLE_RATE_100MS: Byte = 3
}

data class GeneralStatus(
    val elapsedTime: Double, val distance: Double, val workoutType: Int, val intervalType: Int,
    val workoutState: Int, val rowingState: Int, val strokeState: Int, val totalWorkDistance: Int,
    val workoutDuration: Long, val workoutDurationType: Int, val dragFactor: Int,
)

data class AdditionalStatus1(
    val elapsedTime: Double, val speed: Double, val strokeRate: Int, val heartRate: Int?,
    val currentPace: Double, val averagePace: Double, val restDistance: Int, val restTime: Double,
    val ergMachineType: Int?,
)

data class AdditionalStatus2(
    val elapsedTime: Double, val intervalCount: Int, val averagePower: Int, val totalCalories: Int,
    val splitAveragePace: Double, val splitAveragePower: Int, val splitAverageCalories: Int,
    val lastSplitTime: Double, val lastSplitDistance: Int,
)

data class StrokeData(
    val elapsedTime: Double, val distance: Double, val driveLength: Double, val driveTime: Double,
    val recoveryTime: Double, val strokeDistance: Double, val peakDriveForce: Double,
    val averageDriveForce: Double, val workPerStroke: Double, val strokeCount: Int,
)

data class AdditionalStrokeData(
    val elapsedTime: Double, val strokePower: Int, val strokeCalories: Int, val strokeCount: Int,
    val projectedWorkTime: Int, val projectedWorkDistance: Int,
)

data class WorkoutSummary(
    val logDate: Int, val logTime: Int, val elapsedTime: Double, val distance: Double, val averageStrokeRate: Int,
    val endingHeartRate: Int?, val averageHeartRate: Int?, val minHeartRate: Int?, val maxHeartRate: Int?,
    val dragFactorAverage: Int, val recoveryHeartRate: Int?, val workoutType: Int, val averagePace: Double,
)

sealed interface PM5Message {
    data class General(val v: GeneralStatus) : PM5Message
    data class Additional1(val v: AdditionalStatus1) : PM5Message
    data class Additional2(val v: AdditionalStatus2) : PM5Message
    data class Stroke(val v: StrokeData) : PM5Message
    data class AdditionalStroke(val v: AdditionalStrokeData) : PM5Message
    data class Summary(val v: WorkoutSummary) : PM5Message
}

class PM5ParseException(message: String) : Exception(message)

private class LEReader(private val b: ByteArray) {
    var i = 0
    fun u8(): Int = (b[i++].toInt() and 0xFF)
    fun u16(): Int = u8() or (u8() shl 8)
    fun u24(): Int = u8() or (u8() shl 8) or (u8() shl 16)
}

private fun hr(v: Int): Int? = if (v == 0 || v == 255) null else v

object PM5Parser {
    private val expectedLength = mapOf(
        PM5.Characteristic.GENERAL_STATUS to 19, PM5.Characteristic.ADDITIONAL_STATUS1 to 17,
        PM5.Characteristic.ADDITIONAL_STATUS2 to 20, PM5.Characteristic.STROKE_DATA to 20,
        PM5.Characteristic.ADDITIONAL_STROKE_DATA to 18, PM5.Characteristic.WORKOUT_SUMMARY to 20,
    )

    /** Ältere Firmware sendet manche Nachrichten kürzer; fehlende hintere Felder werden mit 0 aufgefüllt (wie Kit). */
    private val minimumLength = mapOf(
        PM5.Characteristic.GENERAL_STATUS to 19, PM5.Characteristic.ADDITIONAL_STATUS1 to 16,
        PM5.Characteristic.ADDITIONAL_STATUS2 to 8, PM5.Characteristic.STROKE_DATA to 18,
        PM5.Characteristic.ADDITIONAL_STROKE_DATA to 9, PM5.Characteristic.WORKOUT_SUMMARY to 18,
    )

    fun parse(c: PM5.Characteristic, input: ByteArray): PM5Message {
        val need = expectedLength[c] ?: throw PM5ParseException("nicht unterstützt: 0x%04X".format(c.short))
        val minimum = minimumLength.getValue(c)
        if (input.size < minimum) {
            throw PM5ParseException("zu kurz: 0x%04X erwartet %d, erhalten %d".format(c.short, minimum, input.size))
        }
        val original = input.size
        val bytes = if (input.size >= need) input else input.copyOf(need)
        val r = LEReader(bytes)
        return when (c) {
            PM5.Characteristic.GENERAL_STATUS -> PM5Message.General(GeneralStatus(
                elapsedTime = r.u24() / 100.0, distance = r.u24() / 10.0,
                workoutType = r.u8(), intervalType = r.u8(),
                workoutState = r.u8(), rowingState = r.u8(), strokeState = r.u8(),
                totalWorkDistance = r.u24(), workoutDuration = r.u24().toLong(), workoutDurationType = r.u8(),
                dragFactor = r.u8()))
            PM5.Characteristic.ADDITIONAL_STATUS1 -> PM5Message.Additional1(AdditionalStatus1(
                elapsedTime = r.u24() / 100.0, speed = r.u16() / 1000.0, strokeRate = r.u8(),
                heartRate = hr(r.u8()), currentPace = r.u16() / 100.0, averagePace = r.u16() / 100.0,
                restDistance = r.u16(), restTime = r.u24() / 100.0,
                ergMachineType = if (original >= 17) r.u8() else null))
            PM5.Characteristic.ADDITIONAL_STATUS2 -> PM5Message.Additional2(AdditionalStatus2(
                elapsedTime = r.u24() / 100.0, intervalCount = r.u8(), averagePower = r.u16(),
                totalCalories = r.u16(), splitAveragePace = r.u16() / 100.0,
                splitAveragePower = r.u16(), splitAverageCalories = r.u16(),
                lastSplitTime = r.u24() / 10.0, lastSplitDistance = r.u24()))
            PM5.Characteristic.STROKE_DATA -> PM5Message.Stroke(StrokeData(
                elapsedTime = r.u24() / 100.0, distance = r.u24() / 10.0,
                driveLength = r.u8() / 100.0, driveTime = r.u8() / 100.0,
                recoveryTime = r.u16() / 100.0, strokeDistance = r.u16() / 100.0,
                peakDriveForce = r.u16() / 10.0, averageDriveForce = r.u16() / 10.0,
                workPerStroke = r.u16() / 10.0, strokeCount = r.u16()))
            PM5.Characteristic.ADDITIONAL_STROKE_DATA -> PM5Message.AdditionalStroke(AdditionalStrokeData(
                elapsedTime = r.u24() / 100.0, strokePower = r.u16(), strokeCalories = r.u16(),
                strokeCount = r.u16(), projectedWorkTime = r.u24(), projectedWorkDistance = r.u24()))
            PM5.Characteristic.WORKOUT_SUMMARY -> PM5Message.Summary(WorkoutSummary(
                logDate = r.u16(), logTime = r.u16(), elapsedTime = r.u24() / 100.0,
                distance = r.u24() / 10.0, averageStrokeRate = r.u8(),
                endingHeartRate = hr(r.u8()), averageHeartRate = hr(r.u8()), minHeartRate = hr(r.u8()),
                maxHeartRate = hr(r.u8()), dragFactorAverage = r.u8(), recoveryHeartRate = hr(r.u8()),
                workoutType = r.u8(), averagePace = r.u16() / 10.0))
            PM5.Characteristic.SAMPLE_RATE -> throw PM5ParseException("nicht unterstützt: 0x0034")
        }
    }
}

/** Erzeugt PM5-Notifications als Bytes (Port von `PM5Encoder` im Kit) – für den Simulator. */
object PM5Encoder {
    private fun clamp(v: Double, max: Double): Int =
        if (!v.isFinite()) 0 else Math.round(v).coerceIn(0L, max.toLong()).toInt()

    private fun u8(v: Double) = byteArrayOf(clamp(v, 255.0).toByte())
    private fun u16(v: Double): ByteArray {
        val x = clamp(v, 65_535.0); return byteArrayOf((x and 0xFF).toByte(), ((x shr 8) and 0xFF).toByte())
    }
    private fun u24(v: Double): ByteArray {
        val x = clamp(v, 16_777_215.0)
        return byteArrayOf((x and 0xFF).toByte(), ((x shr 8) and 0xFF).toByte(), ((x shr 16) and 0xFF).toByte())
    }

    /** 0x0031, 19 Bytes */
    fun generalStatus(elapsed: Double, distance: Double, workoutState: Int, rowingState: Int, strokeState: Int,
                      dragFactor: Int = 120): ByteArray =
        u24(elapsed * 100) + u24(distance * 10) + byteArrayOf(1, 0) +
            byteArrayOf(workoutState.toByte(), rowingState.toByte(), strokeState.toByte()) +
            u24(0.0) + u24(0.0) + byteArrayOf(0) + u8(dragFactor.toDouble())

    /** 0x0032, 17 Bytes; Puls null = 255 (ungültig) */
    fun additionalStatus1(elapsed: Double, speed: Double, strokeRate: Int, heartRate: Int?, pace: Double,
                          averagePace: Double): ByteArray =
        u24(elapsed * 100) + u16(speed * 1000) + u8(strokeRate.toDouble()) + u8((heartRate ?: 255).toDouble()) +
            u16(pace * 100) + u16(averagePace * 100) + u16(0.0) + u24(0.0) + byteArrayOf(0)

    /** 0x0033, 20 Bytes */
    fun additionalStatus2(elapsed: Double, averagePower: Int, calories: Int): ByteArray =
        u24(elapsed * 100) + byteArrayOf(0) + u16(averagePower.toDouble()) + u16(calories.toDouble()) +
            u16(0.0) + u16(0.0) + u16(0.0) + u24(0.0) + u24(0.0)

    /** 0x0035, 20 Bytes */
    fun strokeData(elapsed: Double, distance: Double, strokeDistance: Double, driveTime: Double,
                   recoveryTime: Double, strokeCount: Int): ByteArray =
        u24(elapsed * 100) + u24(distance * 10) + u8(140.0) + u8(driveTime * 100) + u16(recoveryTime * 100) +
            u16(strokeDistance * 100) + u16(0.0) + u16(0.0) + u16(0.0) + u16(strokeCount.toDouble())

    /** 0x0036, 18 Bytes */
    fun additionalStrokeData(elapsed: Double, power: Int, strokeCount: Int): ByteArray =
        u24(elapsed * 100) + u16(power.toDouble()) + u16((4 * power + 300).toDouble()) +
            u16(strokeCount.toDouble()) + u24(0.0) + u24(0.0) + u24(0.0)
}
