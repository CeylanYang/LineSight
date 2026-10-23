package com.example.linesight_flutter

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import kotlin.math.roundToInt

/** V4.2 touch envelopes, aligned to the Flutter reveal's elapsed time. */
class LineSightHaptics(private val context: Context) {
    private val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
        context.getSystemService(VibratorManager::class.java).defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }
    private val handler = Handler(Looper.getMainLooper())
    private val pending = mutableListOf<Runnable>()
    private data class Cue(val time: Int, val duration: Int, val amplitude: Int)
    private val lead = listOf(
        Cue(70, 12, 42), Cue(470, 16, 55), Cue(840, 18, 70),
        Cue(1180, 20, 92), Cue(1460, 22, 119), Cue(1740, 25, 150), Cue(2010, 28, 178)
    )

    fun play(elapsedMs: Int) {
        cancel()
        if (!vibrator.hasVibrator() || Settings.System.getInt(
                context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0) return
        val elapsed = elapsedMs.coerceIn(0, 2800)
        if (Build.VERSION.SDK_INT >= 26 && vibrator.hasAmplitudeControl()) {
            val durations = ArrayList<Long>()
            val amplitudes = ArrayList<Int>()
            var cursor = elapsed
            fun step(duration: Int, amplitude: Int) {
                if (duration > 0) {
                    durations += duration.toLong()
                    amplitudes += amplitude.coerceIn(0, 255)
                    cursor += duration
                }
            }
            for (cue in lead.filter { it.time >= elapsed }) {
                step(cue.time - cursor, 0)
                step(3, (cue.amplitude * .42).roundToInt())
                step(cue.duration - 8, cue.amplitude)
                step(5, (cue.amplitude * .28).roundToInt())
            }
            if (durations.isNotEmpty()) {
                step(8, 0)
                effect(VibrationEffect.createWaveform(durations.toLongArray(), amplitudes.toIntArray(), -1))
            }
        } else if (Build.VERSION.SDK_INT >= 29) {
            // Sparse system ticks avoid full-power buzzing on fixed-amplitude motors.
            for (time in listOf(470, 1180, 2010).filter { it >= elapsed }) {
                schedule(time - elapsed) { effect(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)) }
            }
        }
        // ~370 ms of silence separates the lead from the final confirmation.
        if (elapsed <= 2410) schedule(2410 - elapsed) {
            when {
                Build.VERSION.SDK_INT >= 29 -> effect(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
                Build.VERSION.SDK_INT >= 26 -> effect(VibrationEffect.createOneShot(14, VibrationEffect.DEFAULT_AMPLITUDE))
                else -> { @Suppress("DEPRECATION") vibrator.vibrate(14) }
            }
        }
    }

    private fun effect(effect: VibrationEffect) {
        if (Build.VERSION.SDK_INT >= 33) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
        } else {
            vibrator.vibrate(effect, AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        }
    }

    private fun schedule(delay: Int, action: () -> Unit) {
        val task = Runnable { action() }
        pending += task
        handler.postDelayed(task, delay.toLong())
    }

    fun cancel() {
        pending.forEach { handler.removeCallbacks(it) }
        pending.clear()
        vibrator.cancel()
    }
}
