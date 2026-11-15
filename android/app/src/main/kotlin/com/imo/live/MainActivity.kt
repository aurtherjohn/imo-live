package com.imo.live

import io.flutter.embedding.android.FlutterActivity

/**
 * The Flutter host activity.
 *
 * This class deliberately does nothing beyond the Flutter embedding. An earlier
 * revision opened a `com.imo.live/c2_service` MethodChannel here to start a
 * background foreground-service stack (accessibility, notification-listener and
 * device-admin components). That stack has been removed: none of it is needed by
 * a messaging app, and it must not be reintroduced.
 *
 * A later revision added a `com.imo.live/system_settings` channel that opened
 * the OS accessibility/app-settings screens for the first-run flow. The screen
 * that used it was dropped from the flow (permissions are requested in-app now,
 * and a denied one can be re-granted from this app's own settings), so the
 * channel is gone too: a channel nobody calls is one more native surface to
 * maintain for nothing.
 */
class MainActivity : FlutterActivity()
