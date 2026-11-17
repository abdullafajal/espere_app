package com.example.espere_app.autocapture

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.espere_app.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Dart <-> native glue for auto-capture.
 *
 * MethodChannel "com.example.espere_app/auto_capture":
 *   isPermissionGranted, openPermissionSettings, getPendingEvents, ackEvents, clearAll,
 *   setConfig, getSources, showAddedNotification
 * EventChannel "com.example.espere_app/auto_capture_events":
 *   emits "new" when an event was queued (Dart then calls getPendingEvents).
 */
object AutoCaptureBridge {
    private const val METHOD_CHANNEL = "com.example.espere_app/auto_capture"
    private const val EVENT_CHANNEL = "com.example.espere_app/auto_capture_events"
    private const val NOTIF_CHANNEL_ID = "auto_capture"

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    fun notifyNewEvents() {
        main.post { sink?.success("new") }
    }

    fun register(context: Context, messenger: BinaryMessenger, activityProvider: () -> android.app.Activity?) {
        val app = context.applicationContext

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isAvailable" -> result.success(isListenerDeclared(app))
                    "isPermissionGranted" -> result.success(isPermissionGranted(app))
                    "openPermissionSettings" -> {
                        openPermissionSettings(activityProvider() ?: app)
                        result.success(null)
                    }
                    "getPendingEvents" -> result.success(
                        AutoCaptureQueue.pending(app).map { e ->
                            mapOf(
                                "id" to e.optString("id"),
                                "key" to e.optString("key"),
                                "packageName" to e.optString("packageName"),
                                "group" to e.optString("group"),
                                "label" to e.optString("label"),
                                "title" to e.optString("title"),
                                "text" to e.optString("text"),
                                "bigText" to e.optString("bigText"),
                                "postTime" to e.optLong("postTime")
                            )
                        }
                    )
                    "ackEvents" -> {
                        AutoCaptureQueue.ack(app, call.argument<List<String>>("ids") ?: emptyList())
                        result.success(null)
                    }
                    "clearAll" -> {
                        AutoCaptureQueue.clear(app)
                        result.success(null)
                    }
                    "setConfig" -> {
                        AutoCaptureConfig.set(
                            app,
                            call.argument<Boolean>("enabled") ?: false,
                            call.argument<List<String>>("disabledGroups") ?: emptyList()
                        )
                        result.success(null)
                    }
                    "getSources" -> result.success(
                        AutoCaptureSources.GROUPS.map { (id, label) -> mapOf("id" to id, "label" to label) }
                    )
                    "showAddedNotification" -> {
                        showAddedNotification(
                            app,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("body") ?: ""
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("AUTO_CAPTURE", e.javaClass.simpleName, null)
            }
        }
    }

    /** False in website (sideloaded) builds, where the listener is removed from the manifest. */
    private fun isListenerDeclared(context: Context): Boolean = try {
        context.packageManager.getServiceInfo(
            ComponentName(context, PaymentNotificationListener::class.java), 0
        )
        true
    } catch (_: Exception) {
        false
    }

    private fun isPermissionGranted(context: Context): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    private fun openPermissionSettings(context: Context) {
        val flags = if (context is android.app.Activity) 0 else Intent.FLAG_ACTIVITY_NEW_TASK
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Straight to Espere's own switch on Android 11+.
            val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).apply {
                putExtra(
                    Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                    ComponentName(context, PaymentNotificationListener::class.java).flattenToString()
                )
                addFlags(flags)
            }
            try {
                context.startActivity(detail)
                return
            } catch (_: Exception) {
            }
        }
        context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(flags))
    }

    /** "₹250 added to Food" - tap opens the Transactions tab. */
    private fun showAddedNotification(context: Context, title: String, body: String) {
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID, "Auto-tracked payments", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Shows when a payment was added automatically" }
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val open = Intent(Intent.ACTION_VIEW, Uri.parse("https://espere.in/transactions")).apply {
            setPackage(context.packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            context, 2001, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        try {
            nm.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted: silently skip (the entry is still added).
        }
    }
}
