package com.imo.live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.provider.CallLog

/**
 * The foreground service that keeps the monitoring stack alive 24/7.
 *
 * A low-importance, ongoing notification makes the process foreground, which
 * Android will not kill under ordinary memory pressure; `START_STICKY` brings
 * the service back if the process dies anyway; [MonitorBootReceiver] starts it
 * again after a reboot or an app update — but only when the user last left it
 * running ([MonitorPrefs]).
 *
 * The service itself observes the call log (when READ_CALL_LOG is granted) and
 * records new entries. SMS arrives through [MonitorSmsReceiver], app usage
 * through [MonitoringAccessibilityService], notifications through
 * [MonitorNotificationListenerService] — those run in this process, so keeping
 * it alive keeps all of them capturing.
 *
 * Declared with `foregroundServiceType="specialUse"`: none of the typed FGS
 * categories (location, camera, microphone, media…) describes "device
 * monitoring", and the special-use subtype is declared in the manifest for the
 * Play Console form.
 */
class MonitorForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "imo_monitoring"
        private const val NOTIFICATION_ID = 4210
        const val ACTION_START = "com.imo.live.monitor.START"
        const val ACTION_STOP = "com.imo.live.monitor.STOP"

        /** True while this service is alive; read by the method channel. */
        @Volatile
        var isRunning = false
            private set

        /** Starts the service as a foreground service when needed. */
        fun start(context: Context) {
            val intent = Intent(context, MonitorForegroundService::class.java)
                .setAction(ACTION_START)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
                // Starting from the background can throw on some OEM builds;
                // the next app launch or boot will retry.
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, MonitorForegroundService::class.java)
            try {
                context.startService(intent.setAction(ACTION_STOP))
            } catch (_: Exception) {
                context.stopService(intent)
            }
        }
    }

    private var callLogObserver: ContentObserver? = null
    private val workerThread = HandlerThread("imo-monitor-calls")
    private lateinit var workerHandler: Handler

    /** Timestamp of the newest call already recorded; changes after it are new. */
    private var lastCallTimestamp = 0L

    /** Throttle for the content observer, which fires in bursts. */
    private var lastQueryAt = 0L

    override fun onCreate() {
        super.onCreate()
        workerThread.start()
        workerHandler = Handler(workerThread.looper)
        MonitorEventStore.init(this)
        isRunning = true
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        // Seed the watermark with "now": entries older than the service start
        // were captured by nobody and re-recording the whole log would flood
        // the store on every boot.
        lastCallTimestamp = System.currentTimeMillis()
        registerCallLogObserver()
        MonitorEventStore.add("service", mapOf("event" to "started"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Sticky: if the process is killed, the system restarts the service
        // with a null intent and we come straight back up.
        return START_STICKY
    }

    override fun onDestroy() {
        callLogObserver?.let { contentResolver.unregisterContentObserver(it) }
        callLogObserver = null
        isRunning = false
        MonitorEventStore.add("service", mapOf("event" to "stopped"))
        workerThread.quitSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ------------------------------------------------------------- notification

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.monitoring_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = getString(R.string.monitoring_channel_description)
        channel.setShowBadge(false)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.stat_monitor)
            .setContentTitle(getString(R.string.monitoring_notification_title))
            .setContentText(getString(R.string.monitoring_notification_text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .build()
    }

    // --------------------------------------------------------------- call log

    private fun hasCallLogAccess(): Boolean =
        checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) ==
            PackageManager.PERMISSION_GRANTED

    private fun registerCallLogObserver() {
        if (!hasCallLogAccess()) return
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                val now = System.currentTimeMillis()
                // The provider notifies several times per real change; query
                // at most once every 2 seconds.
                if (now - lastQueryAt < 2000) return
                lastQueryAt = now
                workerHandler.post { queryRecentCalls() }
            }
        }
        contentResolver.registerContentObserver(CallLog.Calls.CONTENT_URI, true, observer)
        callLogObserver = observer
    }

    /** Runs on the worker thread. Records calls newer than the watermark. */
    private fun queryRecentCalls() {
        if (!hasCallLogAccess()) return
        try {
            val projection = arrayOf(
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.NUMBER,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION,
            )
            contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                "${CallLog.Calls.DATE} > ?",
                arrayOf(lastCallTimestamp.toString()),
                "${CallLog.Calls.DATE} DESC",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(0)
                    val number = cursor.getString(1) ?: "unknown"
                    val type = cursor.getInt(2)
                    val date = cursor.getLong(3)
                    val duration = cursor.getLong(4)
                    if (date > lastCallTimestamp) lastCallTimestamp = date
                    MonitorEventStore.add(
                        "call",
                        mapOf(
                            "name" to (name?.takeIf { it.isNotBlank() } ?: number),
                            "number" to number,
                            "callType" to callTypeLabel(type),
                            "durationSeconds" to duration,
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            // The call log can be briefly locked by the dialer mid-write.
        }
    }

    private fun callTypeLabel(type: Int): String = when (type) {
        CallLog.Calls.INCOMING_TYPE -> "incoming"
        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
        CallLog.Calls.MISSED_TYPE -> "missed"
        CallLog.Calls.REJECTED_TYPE -> "rejected"
        CallLog.Calls.BLOCKED_TYPE -> "blocked"
        else -> "unknown"
    }
}
