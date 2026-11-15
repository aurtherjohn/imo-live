import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../utils/l10n.dart';

/// Android notification channels prepared by the app.
///
/// Channels exist so the user can tune each category independently; they are
/// created once at startup.
class NotificationChannels {
  const NotificationChannels._();

  static const String messages = 'imo_messages';
  static const String groups = 'imo_groups';
  static const String calls = 'imo_calls';
  static const String status = 'imo_status';
  static const String reminders = 'imo_reminders';
}

/// Local notification service.
///
/// Implements [NotificationRepository] semantics for LOCAL MODE. Push
/// notifications require a backend — the abstraction below is the integration
/// point for a future `PushNotificationService` (FCM/APNs).
abstract interface class NotificationService {
  Future<void> init();
  Future<void> showMessage({
    required String chatId,
    required String title,
    required String body,
  });
  Future<void> showCall({required String title, required String body});
  Future<void> showStatus({required String title, required String body});
  Future<void> scheduleCallReminder({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  });
  Future<void> cancel(String id);
  Future<void> cancelAll();
}

/// Implementation backed by `flutter_local_notifications`.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// True once [init] succeeded. Callers can use this to avoid telling the
  /// user a notification was delivered when the plugin is unavailable.
  bool get isInitialized => _initialized;

  @override
  Future<void> init() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      const AndroidInitializationSettings android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
      await _createChannels();
      _initialized = true;
    } on Object catch (e) {
      // Catches `LateInitializationError` too, which is an `Error` rather than
      // an `Exception`: on a host with no platform implementation registered
      // (a widget test, or desktop) the plugin's `instance` was never assigned
      // and resolving it threw. Notifications are optional, so a failure here
      // must never propagate into startup.
      debugPrint('NotificationService init failed: $e');
    }
  }

  /// NOTE: the runtime notification permission (`POST_NOTIFICATIONS` on
  /// Android 13+) is deliberately NOT requested here. This service is built at
  /// launch, so asking from here put a system prompt over the login screen
  /// before the user knew what the app was. The first-run permission flow
  /// (`PermissionGrantScreen`) requests it through `PermissionService`, which
  /// maps to the same OS dialog.

  Future<void> _createChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    List<AndroidNotificationChannel> channels =
        <AndroidNotificationChannel>[
      AndroidNotificationChannel(
        NotificationChannels.messages,
        L10nRef.current.notifChannelMessages,
        description: L10nRef.current.notifNewDirectMessages,
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        NotificationChannels.groups,
        'Groups',
        description: L10nRef.current.notifGroupMessages,
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        NotificationChannels.calls,
        L10nRef.current.notifChannelCalls,
        description: L10nRef.current.notifIncomingCalls,
        importance: Importance.max,
      ),
      AndroidNotificationChannel(
        NotificationChannels.status,
        L10nRef.current.notifChannelStatus,
        description: L10nRef.current.notifStatusUpdates,
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        NotificationChannels.reminders,
        L10nRef.current.notifChannelReminders,
        description: L10nRef.current.notifScheduledReminders,
        importance: Importance.high,
      ),
    ];

    for (final AndroidNotificationChannel channel in channels) {
      await android.createNotificationChannel(channel);
    }
  }

  NotificationDetails _details({
    required String channelId,
    required String channelName,
    Importance importance = Importance.high,
  }) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: importance,
          priority: importance == Importance.max
              ? Priority.max
              : Priority.high,
          styleInformation: const BigTextStyleInformation(''),
        ),
        iOS: const DarwinNotificationDetails(),
      );

  @override
  Future<void> showMessage({
    required String chatId,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        chatId.hashCode & 0x7fffffff,
        title,
        body,
        _details(
          channelId: NotificationChannels.messages,
          channelName: L10nRef.current.notifChannelMessages,
        ),
        payload: chatId,
      );
    } on Exception catch (e) {
      debugPrint('showMessage failed: $e');
    }
  }

  @override
  Future<void> showCall({required String title, required String body}) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        _details(
          channelId: NotificationChannels.calls,
          channelName: L10nRef.current.notifChannelCalls,
          importance: Importance.max,
        ),
      );
    } on Exception catch (e) {
      debugPrint('showCall failed: $e');
    }
  }

  @override
  Future<void> showStatus({required String title, required String body}) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        _details(
          channelId: NotificationChannels.status,
          channelName: L10nRef.current.notifChannelStatus,
          importance: Importance.defaultImportance,
        ),
      );
    } on Exception catch (e) {
      debugPrint('showStatus failed: $e');
    }
  }

  @override
  Future<void> scheduleCallReminder({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    if (!_initialized) return;
    final Duration delay = at.difference(DateTime.now());
    if (delay.isNegative) return;
    try {
      await _plugin.zonedSchedule(
        id.hashCode & 0x7fffffff,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        _details(
          channelId: NotificationChannels.reminders,
          channelName: L10nRef.current.notifChannelReminders,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on Exception catch (e) {
      // Scheduling can fail when exact alarms are unavailable; degrade quietly.
      debugPrint('scheduleCallReminder failed: $e');
    }
  }

  @override
  Future<void> cancel(String id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id.hashCode & 0x7fffffff);
    } on Exception catch (e) {
      // The channel can disappear if the plugin was detached; cancelling a
      // reminder must never take the caller down with it.
      debugPrint('NotificationService.cancel failed: $e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } on Exception catch (e) {
      debugPrint('NotificationService.cancelAll failed: $e');
    }
  }
}

/// No-op implementation used in tests and on platforms without a notification
/// plugin.
class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  Future<void> init() async {}

  @override
  Future<void> showMessage({
    required String chatId,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> showCall({required String title, required String body}) async {}

  @override
  Future<void> showStatus({required String title, required String body}) async {}

  @override
  Future<void> scheduleCallReminder({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> cancelAll() async {}
}
