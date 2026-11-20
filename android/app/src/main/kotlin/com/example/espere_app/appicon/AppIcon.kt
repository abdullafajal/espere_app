package com.example.espere_app.appicon

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.app.Activity
import android.os.Build
import com.example.espere_app.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Switches the launcher icon between the app colours. Each colour is an
 * activity-alias (".IconLime", ".IconMint", ...) in AndroidManifest.xml pointing at
 * MainActivity; exactly one of them is enabled at a time.
 */
object AppIcon {
    private const val CHANNEL = "com.example.espere_app/app_icon"
    val NAMES = listOf("Lime", "Mint", "Sky", "Lavender", "Pink", "Peach", "Sun")

    fun register(activity: Activity, messenger: BinaryMessenger) {
        val app = activity.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "current" -> result.success(current(app))
                "set" -> {
                    val name = call.arguments as? String
                    if (name == null || name !in NAMES) {
                        result.error("bad_name", "Unknown icon $name", null)
                    } else {
                        try {
                            set(app, name)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("failed", e.message, null)
                        }
                    }
                }
                "setSplash" -> {
                    val name = call.arguments as? String ?: "Lime"
                    result.success(setSplash(activity, name))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun component(context: Context, name: String) =
        ComponentName(context.packageName, "${context.packageName}.Icon$name")

    fun current(context: Context): String {
        val pm = context.packageManager
        for (name in NAMES) {
            val state = pm.getComponentEnabledSetting(component(context, name))
            val on = state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && name == "Lime")
            if (on) return name
        }
        return "Lime"
    }

    /**
     * The launch splash in the app colour from the next cold start on. Android 13+
     * remembers a splash theme per app; older versions keep the default (Lime).
     */
    fun setSplash(activity: Activity, name: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        // Direct R references (not getIdentifier) so the build keeps these styles.
        val id = when (name) {
            "Mint" -> R.style.LaunchTheme_Mint
            "Sky" -> R.style.LaunchTheme_Sky
            "Lavender" -> R.style.LaunchTheme_Lavender
            "Pink" -> R.style.LaunchTheme_Pink
            "Peach" -> R.style.LaunchTheme_Peach
            "Sun" -> R.style.LaunchTheme_Sun
            else -> R.style.LaunchTheme
        }
        return try {
            activity.splashScreen.setSplashScreenTheme(id)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun set(context: Context, name: String) {
        val pm = context.packageManager
        // Enable the new one first so there is never a moment with no launcher icon.
        pm.setComponentEnabledSetting(
            component(context, name),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for (other in NAMES) {
            if (other == name) continue
            pm.setComponentEnabledSetting(
                component(context, other),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
