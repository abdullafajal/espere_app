package com.example.espere_app

import android.app.WallpaperManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import androidx.core.graphics.ColorUtils

/**
 * Colours taken from several different areas of the user's wallpaper
 * (WallpaperColors gives primary, secondary and tertiary), instead of one
 * Material You accent.
 *
 *  - block  : wallpaper colour 1 - big block and primary buttons
 *  - pill   : wallpaper colour 2 - soft pills, tiles, fields (translucent)
 *  - accent : wallpaper colour 3 - round buttons, dial, chips, badges
 *  - panel  : wallpaper colour 1, very light and translucent (dark mode: midnight indigo)
 *  - onBlock: the logo colour on the block (follows colour 1 as well)
 */
data class WidgetPalette(
    val block: Int,
    val accent: Int,
    val pill: Int,
    val panel: Int,
    /** Popup sheet: a bit more opaque than the widget panel because text sits straight on it */
    val sheet: Int,
    /** Logo / text colour on the block: a very light tint of colour 1 (dark mode: a very dark one) */
    val onBlock: Int
)

object WidgetPalettes {

    private fun tone(color: Int, lightness: Float, minSat: Float): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[1] = hsl[1].coerceIn(minSat, 0.9f)
        hsl[2] = lightness
        return ColorUtils.HSLToColor(hsl)
    }

    private fun shiftHue(color: Int, degrees: Float): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[0] = (hsl[0] + degrees + 360f) % 360f
        return ColorUtils.HSLToColor(hsl)
    }

    fun isDark(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    /** Null on Android 11 and older, or when the wallpaper gives no colours. */
    fun get(context: Context, dark: Boolean = isDark(context)): WidgetPalette? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return try {
            val wc = WallpaperManager.getInstance(context)
                .getWallpaperColors(WallpaperManager.FLAG_SYSTEM) ?: return null
            val c1 = wc.primaryColor.toArgb()
            val c2 = wc.secondaryColor?.toArgb() ?: shiftHue(c1, 35f)
            val c3 = wc.tertiaryColor?.toArgb() ?: shiftHue(c1, -40f)
            if (dark) {
                WidgetPalette(
                    block = tone(c1, 0.78f, 0.50f),
                    accent = tone(c3, 0.78f, 0.50f),
                    pill = ColorUtils.setAlphaComponent(tone(c2, 0.32f, 0.30f), 0x8C),
                    panel = 0x8C141A33.toInt(), // dark keeps the midnight-indigo panel
                    sheet = 0x9E141A33.toInt(),
                    onBlock = tone(c1, 0.12f, 0.50f)
                )
            } else {
                WidgetPalette(
                    block = tone(c1, 0.30f, 0.45f),
                    accent = tone(c3, 0.32f, 0.45f),
                    pill = ColorUtils.setAlphaComponent(tone(c2, 0.80f, 0.55f), 0xA6),
                    panel = ColorUtils.setAlphaComponent(tone(c1, 0.94f, 0.60f), 0x7A),
                    sheet = ColorUtils.setAlphaComponent(tone(c1, 0.94f, 0.60f), 0x9E),
                    onBlock = tone(c1, 0.95f, 0.60f)
                )
            }
        } catch (e: Exception) {
            null
        }
    }
}
