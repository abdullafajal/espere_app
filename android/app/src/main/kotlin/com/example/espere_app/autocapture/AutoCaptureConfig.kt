package com.example.espere_app.autocapture

import android.content.Context

/**
 * Native switches set from Dart (AutoExpenseService). The listener reads them before it
 * looks at a notification, so when the feature is off nothing is read or stored.
 */
object AutoCaptureConfig {
    private const val PREFS = "auto_capture_config"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_DISABLED_GROUPS = "disabled_groups"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, false)

    fun isGroupDisabled(context: Context, group: String): Boolean =
        prefs(context).getStringSet(KEY_DISABLED_GROUPS, emptySet())?.contains(group) == true

    fun set(context: Context, enabled: Boolean, disabledGroups: Collection<String>) {
        prefs(context).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putStringSet(KEY_DISABLED_GROUPS, disabledGroups.toSet())
            .apply()
    }
}
