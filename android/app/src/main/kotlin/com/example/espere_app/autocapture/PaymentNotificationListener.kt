package com.example.espere_app.autocapture

import android.app.Notification
import android.content.ComponentName
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.util.UUID

/**
 * Picks up payment notifications for on-device auto-tracking.
 *
 * Privacy rules enforced here (before anything reaches Dart):
 *  - The feature must be switched on by the user (AutoCaptureConfig), otherwise every
 *    notification is ignored.
 *  - Only allow-listed packages are looked at; for every other app we return before reading
 *    its extras.
 *  - SMS apps: only messages from bank / UPI sender IDs. Personal SMS are dropped.
 *  - WhatsApp: chat messages are dropped; only payment notifications go through.
 *  - Ongoing, group-summary and progress notifications are ignored.
 *  - Only title / text / bigText / postTime / package / key are kept, and only if the text
 *    contains an amount. Nothing is logged.
 */
class PaymentNotificationListener : NotificationListenerService() {

    companion object {
        /** Cheap native check: is there an amount at all? (Dart does the real parsing.) */
        private val AMOUNT = Regex(
            "(?:₹|\\bRs\\.?|\\bINR)\\s*\\.?\\s*\\d|(?:debited|credited)\\s+by\\s+\\d",
            RegexOption.IGNORE_CASE
        )

        /** WhatsApp Pay notifications (not chat messages). */
        private val WHATSAPP_PAYMENT = Regex(
            "\\b(payment|you sent|you paid|sent you|you received|received)\\b",
            RegexOption.IGNORE_CASE
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        // Allow-list first: other apps are ignored without touching their content.
        val source = AutoCaptureSources.PACKAGES[sbn.packageName] ?: return
        try {
            handle(sbn, source)
        } catch (_: Throwable) {
            // Never crash the listener on an unexpected notification.
        }
    }

    private fun handle(sbn: StatusBarNotification, source: AutoCaptureSources.Source) {
        if (!AutoCaptureConfig.isEnabled(this)) return
        if (AutoCaptureConfig.isGroupDisabled(this, source.group)) return

        val n = sbn.notification ?: return
        if (sbn.isOngoing || n.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val extras = n.extras ?: return
        if (extras.getInt(Notification.EXTRA_PROGRESS_MAX, 0) > 0 ||
            extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE, false)
        ) return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()

        if (source.group == AutoCaptureSources.GROUP_SMS &&
            !AutoCaptureSources.isBankSender(title)
        ) return // personal SMS: not read any further

        if (source.group == AutoCaptureSources.GROUP_WHATSAPP &&
            n.category == Notification.CATEGORY_MESSAGE
        ) return // WhatsApp chats are never read

        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val all = "$title\n$text\n$bigText"

        if (source.group == AutoCaptureSources.GROUP_WHATSAPP && !WHATSAPP_PAYMENT.containsMatchIn(all)) return
        if (!AMOUNT.containsMatchIn(all)) return

        val event = JSONObject()
            .put("id", UUID.randomUUID().toString())
            .put("key", sbn.key)
            .put("packageName", sbn.packageName)
            .put("group", source.group)
            .put("label", source.label)
            .put("title", title)
            .put("text", text)
            .put("bigText", bigText)
            .put("postTime", sbn.postTime)

        AutoCaptureQueue.add(this, event)
        AutoCaptureBridge.notifyNewEvents()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        requestRebind(ComponentName(this, PaymentNotificationListener::class.java))
    }
}
