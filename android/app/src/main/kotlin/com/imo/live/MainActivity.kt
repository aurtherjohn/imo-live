package com.imo.live

import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Flutter host activity.
 *
 * Hosts the `com.imo.live/monitor` method channel used by the Dart
 * [MonitoringService] to query and drive the monitoring stack: whether the
 * accessibility service and the notification listener are enabled, opening
 * their settings screens, starting/stopping the foreground service, device
 * information and the event store.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.imo.live/monitor"
        private const val REQUEST_RUNTIME = 90701
    }

    private var pendingPermissionsResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MonitorEventStore.init(applicationContext)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    handle(call, result)
                } catch (error: Exception) {
                    result.error("monitor_error", error.message, null)
                }
            }
    }

    private fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAccessibilityEnabled" ->
                result.success(isAccessibilityServiceEnabled())

            "openAccessibilitySettings" -> {
                openScreen(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                result.success(true)
            }

            "isNotificationListenerEnabled" ->
                result.success(isNotificationListenerEnabled())

            "openNotificationListenerSettings" -> {
                openScreen(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                result.success(true)
            }

            "startService" -> {
                MonitorPrefs.setServiceEnabled(this, true)
                MonitorForegroundService.start(this)
                result.success(true)
            }

            "stopService" -> {
                MonitorPrefs.setServiceEnabled(this, false)
                MonitorForegroundService.stop(this)
                result.success(true)
            }

            "isServiceRunning" ->
                result.success(MonitorForegroundService.isRunning)

            "getDeviceInfo" ->
                result.success(deviceInfo())

            "getEvents" -> {
                val type = call.argument<String>("type")
                val limit = call.argument<Int>("limit") ?: 200
                result.success(MonitorEventStore.query(type, limit))
            }

            "clearEvents" -> {
                MonitorEventStore.clear()
                result.success(true)
            }

            "hasPermissions" -> {
                val permissions = call.argument<List<String>>("permissions") ?: emptyList()
                result.success(permissions.associateWith { perm ->
                    checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
                })
            }

            "requestPermissions" -> {
                val permissions = call.argument<List<String>>("permissions") ?: emptyList()
                if (permissions.isEmpty()) {
                    result.success(emptyMap<String, Boolean>())
                    return
                }
                if (pendingPermissionsResult != null) {
                    result.error("busy", "Another permission request is in flight.", null)
                    return
                }
                pendingPermissionsResult = result
                requestPermissions(permissions.toTypedArray(), REQUEST_RUNTIME)
            }

            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_RUNTIME) return
        val result = pendingPermissionsResult
        pendingPermissionsResult = null
        if (result == null) return
        if (permissions.size != grantResults.size) {
            result.success(permissions.associateWith { false })
            return
        }
        result.success(permissions.zip(grantResults).associate { (perm, grant) ->
            perm to (grant == PackageManager.PERMISSION_GRANTED)
        })
    }

    // -------------------------------------------------------- helpers

    private fun isAccessibilityServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val me = ComponentName(this, MonitoringAccessibilityService::class.java)
            .flattenToString()
        return enabled.split(':').any { it.equals(me, ignoreCase = true) }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val me = ComponentName(this, MonitorNotificationListenerService::class.java)
            .flattenToString()
        return enabled.split(':').any { it.equals(me, ignoreCase = true) }
    }

    private fun openScreen(action: String) {
        try {
            startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            // Some OEMs ship a stripped settings app; fall back to the
            // generic app-settings screen rather than crash.
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(android.net.Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (_: Exception) {
                // Ignored.
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun deviceInfo(): Map<String, Any?> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val mem = ActivityManager.MemoryInfo()
        am?.getMemoryInfo(mem)
        val dm = resources.displayMetrics
        val versionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (_: Exception) {
            null
        }
        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "board" to Build.BOARD,
            "hardware" to Build.HARDWARE,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "securityPatch" to Build.VERSION.SECURITY_PATCH,
            "buildId" to Build.VERSION.INCREMENTAL,
            "isEmulator" to (Build.FINGERPRINT.contains("generic") ||
                Build.MODEL.contains("Emulator")),
            "androidId" to Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ANDROID_ID,
            ),
            "screenWidth" to dm.widthPixels,
            "screenHeight" to dm.heightPixels,
            "densityDpi" to dm.densityDpi,
            "totalMemoryBytes" to mem.totalMem,
            "appId" to packageName,
            "appVersion" to versionName,
        )
    }
}
