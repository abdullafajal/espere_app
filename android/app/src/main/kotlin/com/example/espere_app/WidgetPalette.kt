package com.example.espere_app

import android.content.Context
import android.content.res.Configuration
import android.os.Build

/**
 * Wallpaper-based colours for the widget and the Quick Add popup (Android 12+).
 *
 * The colours live in res/color-v31 and res/color-night-v31 as references to the
 * system dynamic palette (system_accent1/2/3), which Android rebuilds from the
 * wallpaper. The widget hands the launcher these resource ids instead of fixed
 * values, so the launcher re-resolves them the moment the wallpaper (or light/dark
 * mode) changes - no app code has to run and nothing is polled.
 *
 *  - block  : accent 1 - big block and primary buttons
 *  - pill   : accent 2 - soft pills, tiles, fields (translucent)
 *  - accent : accent 3 - round buttons, dial, chips, badges
 *  - panel  : accent 1, very light and translucent (dark mode: midnight indigo)
 *  - sheet  : popup background, more opaque than the panel because text sits on it
 *  - onBlock: the logo colour on the block
 */
data class WidgetPalette(
    val block: Int,
    val accent: Int,
    val pill: Int,
    val panel: Int,
    val sheet: Int,
    val onBlock: Int
)

object WidgetPalettes {

    fun isDark(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    /** Current colours (for the popup, which is drawn by the app itself). Null on Android 11 and older. */
    fun get(context: Context): WidgetPalette? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return WidgetPalette(
            block = context.getColor(R.color.wp_block),
            accent = context.getColor(R.color.wp_accent),
            pill = context.getColor(R.color.wp_pill),
            panel = context.getColor(R.color.wp_panel),
            sheet = context.getColor(R.color.wp_sheet),
            onBlock = context.getColor(R.color.wp_on_block)
        )
    }
}
