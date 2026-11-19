package com.example.espere_app.reminders

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.espere_app.MainActivity
import com.example.espere_app.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * Morning and night reminders that run on the phone (no server, works offline).
 *
 * The times live in Flutter's shared preferences (`reminder_morning` / `reminder_night`,
 * minutes after midnight, -1 = off). When one fires, the message is built from the
 * transactions saved on the phone, shown as a notification and added to the in-app
 * Notifications list (`cache_notifications`), then the next day is scheduled.
 */
object DailyReminder {
    private const val CHANNEL = "com.example.espere_app/reminders"
    private const val NOTIF_CHANNEL_ID = "daily_reminders"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    const val ACTION_FIRE = "com.example.espere_app.DAILY_REMINDER"
    const val EXTRA_SLOT = "slot"

    const val MORNING = "morning"
    const val NIGHT = "night"
    private const val DEFAULT_MORNING = 9 * 60
    private const val DEFAULT_NIGHT = 21 * 60

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "reschedule" -> {
                    scheduleAll(app)
                    result.success(true)
                }
                "test" -> {
                    fire(app, call.argument<String>("slot") ?: NIGHT, reschedule = false)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        scheduleAll(app)
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    /** Minutes after midnight for [slot], or -1 when it is off. */
    private fun minutesFor(context: Context, slot: String): Int {
        val raw = prefs(context).all["flutter.reminder_$slot"]
        return when (raw) {
            is Number -> raw.toInt()
            else -> if (slot == MORNING) DEFAULT_MORNING else DEFAULT_NIGHT
        }
    }

    private fun pendingFor(context: Context, slot: String): PendingIntent {
        val intent = Intent(context, DailyReminderReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_SLOT, slot)
        }
        return PendingIntent.getBroadcast(
            context,
            if (slot == MORNING) 3101 else 3102,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun scheduleAll(context: Context) {
        schedule(context, MORNING)
        schedule(context, NIGHT)
    }

    private fun schedule(context: Context, slot: String) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingFor(context, slot)
        am.cancel(pi)
        val minutes = minutesFor(context, slot)
        if (minutes < 0) return

        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minutes / 60)
            set(Calendar.MINUTE, minutes % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis() + 5_000) add(Calendar.DAY_OF_YEAR, 1)
        }
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        try {
            if (exact) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pi)
            }
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pi)
        }
    }

    /** Shows the reminder for [slot] now. */
    fun fire(context: Context, slot: String, reschedule: Boolean = true) {
        try {
            val p = prefs(context)
            val loggedIn = !p.getString("flutter.auth_token", null).isNullOrEmpty()
            if (loggedIn && minutesFor(context, slot) >= 0 || !reschedule) {
                val (title, body) = message(context, slot)
                addToInbox(context, title, body, slot)
                show(context, slot, title, body)
            }
        } finally {
            if (reschedule) schedule(context, slot)
        }
    }

    // ─── Message ─────────────────────────────────────────────────────────────

    private fun message(context: Context, slot: String): Pair<String, String> {
        val p = prefs(context)
        var symbol = "₹"
        var today = 0.0
        var todayCount = 0
        var yesterday = 0.0
        try {
            val raw = p.getString("flutter.cache_transactions", null)
            if (raw != null) {
                val json = JSONObject(raw)
                symbol = json.optString("currency_symbol", "₹").ifEmpty { "₹" }
                val list = json.optJSONArray("transactions") ?: JSONArray()
                val startToday = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                }.timeInMillis
                val startYesterday = startToday - 24L * 60 * 60 * 1000
                val endToday = startToday + 24L * 60 * 60 * 1000
                for (i in 0 until list.length()) {
                    val t = list.optJSONObject(i) ?: continue
                    if (t.optString("type") != "expense") continue
                    val amount = t.optString("amount").toDoubleOrNull() ?: continue
                    val at = parseIso(t.optString("date")) ?: continue
                    when {
                        at in startToday until endToday -> { today += amount; todayCount++ }
                        at in startYesterday until startToday -> yesterday += amount
                    }
                }
            }
        } catch (_: Exception) {
        }

        return if (slot == MORNING) {
            if (yesterday > 0) {
                "Good morning" to "Yesterday you spent ${money(symbol, yesterday)}. Tap to plan today and log as you go."
            } else {
                "Good morning" to "Log your spends as you go today. It takes 5 seconds."
            }
        } else {
            if (todayCount > 0) {
                val entries = if (todayCount == 1) "entry" else "entries"
                "Today: ${money(symbol, today)} spent" to
                    "$todayCount $entries logged. Anything else to add? Tap to log it."
            } else {
                "Log today's expenses" to
                    "You haven't added anything today. It takes 5 seconds to keep your budget on track."
            }
        }
    }

    private fun money(symbol: String, v: Double): String {
        val f = NumberFormat.getNumberInstance(Locale("en", "IN")).apply {
            maximumFractionDigits = if (v == Math.floor(v)) 0 else 2
            minimumFractionDigits = 0
        }
        return symbol + f.format(v)
    }

    private val isoRegex = Regex(
        """^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|[+-]\d{2}:?\d{2})?$"""
    )

    /** Epoch millis of an ISO-8601 date ("…Z", "…+05:30" or no zone = UTC). */
    internal fun parseIso(s: String): Long? {
        val m = isoRegex.matchEntire(s.trim()) ?: return null
        val g = m.groupValues
        val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(g[1].toInt(), g[2].toInt() - 1, g[3].toInt(), g[4].toInt(), g[5].toInt(), g[6].ifEmpty { "0" }.toInt())
        }
        var ms = cal.timeInMillis + (g[7].padEnd(3, '0').take(3).ifEmpty { "0" }.toInt())
        val zone = g[8]
        if (zone.isNotEmpty() && zone != "Z") {
            val sign = if (zone[0] == '-') -1 else 1
            val digits = zone.substring(1).replace(":", "")
            val offset = digits.substring(0, 2).toInt() * 60 + digits.substring(2, 4).toInt()
            ms -= sign * offset * 60_000L
        }
        return ms
    }

    // ─── In-app list ─────────────────────────────────────────────────────────

    private fun addToInbox(context: Context, title: String, body: String, slot: String) {
        val p = prefs(context)
        val list = try {
            JSONArray(p.getString("flutter.cache_notifications", null) ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val now = System.currentTimeMillis()
        val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(now)
        val item = JSONObject().apply {
            put("id", -(now / 1000))
            put("title", title)
            put("message", body)
            put("data", JSONObject().apply {
                put("action", if (slot == NIGHT) "open_quick_add" else "open_dashboard")
                put("kind", "daily_reminder")
                put("local", "true")
            })
            put("is_read", false)
            put("created_at", iso)
        }
        val out = JSONArray().put(item)
        for (i in 0 until minOf(list.length(), 99)) out.put(list.get(i))
        p.edit().putString("flutter.cache_notifications", out.toString()).apply()
    }

    // ─── Notification ────────────────────────────────────────────────────────

    private fun show(context: Context, slot: String, title: String, body: String) {
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID, "Daily reminders", NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "Morning and night reminders to log your spending" }
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val open = if (slot == NIGHT) {
            Intent(Intent.ACTION_VIEW, Uri.parse("https://espere.in/transaction/add")).apply {
                setPackage(context.packageName)
            }
        } else {
            Intent(context, MainActivity::class.java)
        }.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
        val pi = PendingIntent.getActivity(
            context,
            if (slot == MORNING) 3201 else 3202,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        try {
            nm.notify(if (slot == MORNING) 3301 else 3302, notification)
        } catch (_: SecurityException) {
            // Notifications not allowed: the entry is still in the in-app list.
        }
    }
}

/** Fires the reminders, and schedules them again after a reboot, an app update or a
 *  clock / time-zone change (alarms do not survive those). */
class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            DailyReminder.ACTION_FIRE -> {
                val pending = goAsync()
                Thread {
                    try {
                        DailyReminder.fire(
                            context.applicationContext,
                            intent.getStringExtra(DailyReminder.EXTRA_SLOT) ?: DailyReminder.NIGHT
                        )
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
            else -> DailyReminder.scheduleAll(context.applicationContext)
        }
    }
}
