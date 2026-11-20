package com.example.espere_app.haptics

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The app's haptics, played on the vibrator directly. Flutter's HapticFeedback goes
 * through the view's "touch feedback" constants, which many phones (e.g. MIUI) ignore for
 * some kinds, so taps vibrated in some places and not in others.
 *
 * Kinds (see lib/theme/motion.dart AppHaptics): tap, land, press, confirm, warn, from
 * light to heavy, all strong enough to feel clearly.
 */
object Haptics {
    private const val CHANNEL = "com.example.espere_app/haptics"

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        val vibrator: Vibrator? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                app.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
        } catch (_: Exception) {
            null
        }
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "play") {
                play(vibrator, call.arguments as? String ?: "tap")
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun play(vibrator: Vibrator?, kind: String) {
        val v = vibrator ?: return
        try {
            if (!v.hasVibrator()) return
            // Stronger than the system "tick/click" presets (which are faint on many
            // phones): short one-shots at high strength.
            val (ms, amp) = when (kind) {
                "tap" -> 14L to 210
                "land" -> 16L to 210
                "press" -> 20L to 235
                "confirm" -> 28L to 255
                "warn" -> 45L to 255
                else -> 14L to 210
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val a = if (v.hasAmplitudeControl()) amp else VibrationEffect.DEFAULT_AMPLITUDE
                v.vibrate(VibrationEffect.createOneShot(ms, a))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(ms)
            }
        } catch (_: Exception) {
        }
    }
}
