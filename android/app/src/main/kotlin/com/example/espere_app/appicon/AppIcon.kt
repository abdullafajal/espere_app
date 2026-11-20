package com.example.espere_app.appicon

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
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

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
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
