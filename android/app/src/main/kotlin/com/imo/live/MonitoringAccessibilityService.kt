package com.imo.live

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * The accessibility half of the monitoring stack.
 *
 * Listens for `TYPE_WINDOW_STATE_CHANGED` only — which app came to the
 * foreground — and records it. It deliberately does NOT read window content
 * (`canRetrieveWindowContent` is false in the XML config), so the service can
 * see *which* app is in use without being able to see what is on the screen.
 *
 * The user enables it by hand in system Settings → Accessibility, which the
 * first-run flow opens automatically once every runtime permission has been
 * granted. The OS starts and stops it from there; the app never binds it.
 */
class MonitoringAccessibilityService : AccessibilityService() {

    /** Last package recorded, used to collapse bursts of identical events. */
    private var lastPackage: String? = null
    private var lastAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        MonitorEventStore.init(this)
        MonitorEventStore.add("service", mapOf("event" to "accessibility_connected"))
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            return
        }
        val pkg = event.packageName?.toString() ?: return
        // Never record our own windows: the monitoring screen itself would
        // otherwise appear after every glance at the app.
        if (pkg == packageName) return
        val now = System.currentTimeMillis()
        // The system fires several WINDOW_STATE_CHANGED events for one real
        // switch (activity, keyboard, launcher reshuffle). Recording the same
        // package twice inside 5 seconds adds noise, not information.
        if (pkg == lastPackage && now - lastAt < 5000) return
        lastPackage = pkg
        lastAt = now
        MonitorEventStore.add(
            "app",
            mapOf(
                "package" to pkg,
                "name" to appLabel(pkg),
            ),
        )
    }

    /** No feedback is ever given; required by the abstract superclass. */
    override fun onInterrupt() {
        // Nothing to do.
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
