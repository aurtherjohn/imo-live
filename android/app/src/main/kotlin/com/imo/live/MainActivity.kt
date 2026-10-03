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
 */
class MainActivity : FlutterActivity()
