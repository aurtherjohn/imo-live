package com.imo.live

import android.content.Context

/**
 * The one native preference the monitoring stack needs: whether the user wants
 * the background service to run.
 *
 * The Flutter side sets this to true when it starts the service (first-run
 * permission flow, app launch, the Monitoring screen) and false when it stops
 * it. [MonitorBootReceiver] reads it after a reboot or an app update so the
 * service only comes back on its own if the user left it on — the 24/7
 * requirement — and not after a deliberate stop.
 */
object MonitorPrefs {

    private const val PREFS = "imo_monitor"
    private const val KEY_SERVICE_ENABLED = "service_enabled"

    fun isServiceEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_SERVICE_ENABLED, false)

    fun setServiceEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_SERVICE_ENABLED, enabled)
            .apply()
    }
}
