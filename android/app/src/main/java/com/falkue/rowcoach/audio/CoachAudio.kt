package com.falkue.rowcoach.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log

/**
 * Coach-Ansage aus den Assets abspielen (Machbarkeitstest: eine vorhandene m4a der iOS-App).
 * Die Clips liegen nach fetch_assets.sh unter assets/coach/<sprache>/<name>.m4a (unkomprimiert im APK).
 */
class CoachAudio(private val context: Context) {
    private var player: MediaPlayer? = null

    fun play(asset: String) {
        stop()
        try {
            val fd = context.assets.openFd(asset)
            player = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build())
                setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                fd.close()
                setOnCompletionListener { stop() }
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.w("RowCoachAudio", "Ansage $asset nicht abspielbar: ${e.message}")
        }
    }

    fun stop() {
        player?.release()
        player = null
    }

    companion object {
        /** Startansage („go“, Stil cox) – kopiert von App/RowCoach/Resources/Coach/en/ */
        const val START = "coach/en/go.1.cox.0.m4a"
    }
}
