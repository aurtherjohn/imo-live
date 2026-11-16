package com.imo.live

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Brings the foreground service back after a reboot, a power-on from a
 * quick-boot state, or an app update.
 *
 * Only starts the service when the user left it running ([MonitorPrefs]);
 * a deliberate stop is respected across a restart. The service itself then
 * calls `START_STICKY`, so an unexpected death mid-session is also recovered
 * without waiting for a reboot.
 */
class MonitorBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val isRelevant = action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        if (!isRelevant) return
        if (!MonitorPrefs.isServiceEnabled(context)) return
        MonitorForegroundService.start(context)
    }
}
