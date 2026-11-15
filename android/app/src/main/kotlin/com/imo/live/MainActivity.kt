package com.imo.live

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Flutter host activity.
 *
 * This class does nothing beyond the Flutter embedding apart from one tiny
 * method channel, `com.imo.live/system_settings`. The first-run flow ends by
 * pointing the user at two system screens that have no cross-platform API:
 * the accessibility list and this app's own settings page. The channel only
 * *opens* those screens — it reads and changes nothing.
 *
 * NOTE: the earlier C2 stack (an accessibility service that read other apps'
 * text, a notification listener, a keep-alive foreground service, a boot
 * receiver and a device admin) was deliberately removed and must not be
 * reintroduced. A messaging app needs none of it.
 */
class MainActivity : FlutterActivity() {
    private val systemSettingsChannel = "com.imo.live/system_settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAccessibilitySettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    }
                    "openAppSettings" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", packageName, null)
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
