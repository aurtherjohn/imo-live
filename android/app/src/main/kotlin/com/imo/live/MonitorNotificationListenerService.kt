package com.imo.live

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * The real-time notification listener.
 *
 * Records every notification the device posts (title, text and the app that
 * posted it) as it arrives, so the Monitoring screen shows a live feed of what
 * happened while the app was closed. The user grants access by hand in system
 * Settings → Notification access, which the first-run flow opens automatically
 * after the accessibility step.
 */
class MonitorNotificationListenerService : NotificationListenerService() {

    /** Collapses duplicate posts (same app + title within a second). */
    private var lastKey: String? = null
    private var lastAt = 0L

    override fun onListenerConnected() {
        super.onListenerConnected()
        MonitorEventStore.init(this)
        MonitorEventStore.add("service", mapOf("event" to "notification_listener_connected"))
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        MonitorEventStore.add("service", mapOf("event" to "notification_listener_disconnected"))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        // Our own foreground-service notification would loop forever: it is
        // posted by this app, recorded here, and re-shown on every update.
        if (sbn.packageName == packageName) return
        val notification: Notification = sbn.notification ?: return
        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        if (title.isNullOrBlank() && text.isNullOrBlank()) return
        val key = "${sbn.packageName}|$title"
        val now = System.currentTimeMillis()
        if (key == lastKey && now - lastAt < 1000) return
        lastKey = key
        lastAt = now
        MonitorEventStore.add(
            "notification",
            mapOf(
                "package" to sbn.packageName,
                "app" to appLabel(sbn.packageName),
                "title" to title?.take(200),
                "text" to text?.take(500),
            ),
        )
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        @Suppress("DEPRECATION")
        val info = pm.getApplicationInfo(pkg, 0)
        pm.getApplicationLabel(info).toString()
    } catch (_: Exception) {
        pkg
    }
}
