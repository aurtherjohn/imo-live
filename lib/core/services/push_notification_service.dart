import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import 'notification_service.dart';

/// Message categories the sender puts in the `type` field of the FCM data
/// payload. Anything unrecognised is treated as [PushKind.unknown] and shown as
/// a plain message, so a new server-side category degrades instead of vanishing.
abstract final class PushKind {
  static const String message = 'message';
  static const String call = 'call';
  static const String status = 'status';
  static const String unknown = 'unknown';
}

/// The parts of an FCM payload the app acts on.
///
/// Kept separate from [RemoteMessage] and built from a plain `Map` so the
/// parsing rules are unit-testable without a Firebase host.
class PushPayload {
  const PushPayload({
    this.chatId = '',
    this.title = '',
    this.body = '',
    this.kind = PushKind.unknown,
    this.callerId = '',
    this.isVideo = false,
  });

  /// Payload keys. `snake_case` variants are accepted because they are the
  /// common spelling on the server side.
  static const String keyChatId = 'chatId';
  static const String keyChatIdAlt = 'chat_id';
  static const String keyTitle = 'title';
  static const String keyBody = 'body';
  static const String keyKind = 'type';

  /// Who is calling, for a [PushKind.call] payload.
  ///
  /// A call has no `chatId` — it has a caller — so without this a tapped call
  /// notification has nothing to navigate to and could only be dropped.
  static const String keyCallerId = 'callerId';
  static const String keyCallerIdAlt = 'caller_id';
  static const String keyIsVideo = 'isVideo';
  static const String keyIsVideoAlt = 'is_video';

  /// The conversation to open when the notification is tapped. Empty when the
  /// payload carries no conversation — a status update, for instance.
  final String chatId;

  final String title;
  final String body;

  /// One of [PushKind].
  final String kind;

  /// The caller's uid, for a [PushKind.call] payload. Empty otherwise.
  final String callerId;

  /// Whether a [PushKind.call] payload is a video call.
  ///
  /// Absent means voice: the payload carries no `isVideo`, which is the same
  /// default a call document with no `type` field gets.
  final bool isVideo;

  /// Parses a raw FCM `data` map.
  ///
  /// Every value arrives as a string over the wire, but a payload assembled in
  /// Dart (a test, or a local re-send) may carry real types, so each field is
  /// coerced rather than cast. A null or non-string value becomes `''`.
  static PushPayload fromData(Map<String, dynamic> data) {
    final String kind = _read(data, <String>[keyKind]).toLowerCase().trim();
    return PushPayload(
      chatId: _read(data, <String>[keyChatId, keyChatIdAlt]),
      title: _read(data, <String>[keyTitle]),
      body: _read(data, <String>[keyBody]),
      kind: switch (kind) {
        PushKind.message || PushKind.call || PushKind.status => kind,
        _ => PushKind.unknown,
      },
      callerId: _read(data, <String>[keyCallerId, keyCallerIdAlt]),
      isVideo: _readBool(data, <String>[keyIsVideo, keyIsVideoAlt]),
    );
  }

  /// First key whose value reads as true.
  ///
  /// A bool arrives as a real `true` when the payload is built in Dart, but as
  /// the string `"true"` over the wire, so both are accepted. Anything else —
  /// absent, `"false"`, `"0"` — is false.
  static bool _readBool(Map<String, dynamic> data, List<String> keys) {
    for (final String key in keys) {
      final Object? value = data[key];
      if (value is bool) return value;
      if (value is String) {
        final String text = value.trim().toLowerCase();
        if (text == 'true' || text == '1') return true;
        if (text == 'false' || text == '0') return false;
      }
    }
    return false;
  }

  /// First non-empty value among [keys], trimmed.
  static String _read(Map<String, dynamic> data, List<String> keys) {
    for (final String key in keys) {
      final Object? value = data[key];
      if (value == null) continue;
      final String text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}

/// Handler for messages delivered while the app is **not** running.
///
/// Runs in its own isolate with no Flutter engine attached, so it must be
/// top-level (or static) and annotated with `@pragma('vm:entry-point')` —
/// otherwise the AOT compiler prunes it as unreachable and background delivery
/// silently stops.
///
/// Firebase is re-initialised here because the isolate does not inherit the
/// main one's `FirebaseApp`. It deliberately does *not* try to display
/// anything: a notification-type message is rendered by the system, and a
/// data-only message that needs local work should be handled after the user
/// taps through.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } on Object catch (error) {
    debugPrint('FCM background isolate: Firebase init failed: $error');
  }
  debugPrint(
    'FCM background message ${message.messageId ?? '-'} '
    'kind=${PushPayload.fromData(message.data).kind}',
  );
}

/// Firebase Cloud Messaging: permission, registration token, and message
/// routing.
///
/// ### What this does and does not cover
///
/// This class owns the **client half** of push delivery:
///
/// * ask for the notification permission,
/// * fetch the FCM registration token and keep it fresh on
///   `users/{uid}.fcmTokens`,
/// * show a message that arrives while the app is in the foreground (FCM does
///   not display those itself),
/// * route a tap on a notification to the conversation it belongs to.
///
/// **Sending** is out of scope. A client must never hold an FCM server key —
/// anyone who decompiles the APK would then be able to push to every user — so
/// messages are sent by a trusted caller (a Cloud Function or the app's own
/// backend) using the Admin SDK.
///
/// ### Payload contract
///
/// The sender must send a **data** message (or a notification message with a
/// `data` block) containing:
///
/// ```json
/// {
///   "token": "<registration token>",
///   "data": { "chatId": "<chat id>", "title": "…", "body": "…",
///             "type": "message" },
///   "android": { "notification": { "channel_id": "imo_messages" } }
/// }
/// ```
///
/// `channel_id` must be `imo_messages`; without it Android falls back to the
/// plugin's own default channel, which the user cannot tune per category from
/// the app's notification settings.
///
/// ### Failure policy
///
/// Everything is best-effort. Push is an enhancement, never a dependency: if
/// Firebase is unreachable, the permission is denied, or the token write fails,
/// the app keeps working with local notifications only.
class PushNotificationService {
  /// Constructing the service must not touch a platform channel: `main()` builds
  /// it during startup, and a test host has no Firebase plugin registered. The
  /// singletons are therefore resolved on first use unless one was injected.
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    NotificationService? notifications,
  })  : _messagingInstance = messaging,
        _dbInstance = firestore,
        _local = notifications;

  FirebaseMessaging? _messagingInstance;
  FirebaseFirestore? _dbInstance;
  final NotificationService? _local;

  FirebaseMessaging get _messaging =>
      _messagingInstance ??= FirebaseMessaging.instance;

  FirebaseFirestore get _db => _dbInstance ??= FirebaseFirestore.instance;

  /// Where registration tokens are stored.
  static const String usersCollection = 'users';

  /// Field on `users/{uid}` holding every device token for that account.
  ///
  /// An array, not a scalar: the same account on two phones would otherwise
  /// keep overwriting a single slot, and the older device would silently stop
  /// receiving pushes.
  static const String tokenField = 'fcmTokens';

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  String _uid = '';
  String? _token;

  /// Called when a notification is tapped, with the conversation to open.
  ///
  /// Wired by `main()` to the router. Null until then, which also makes the
  /// service usable in a test host with no navigation.
  void Function(String chatId)? onOpenChat;

  /// Called when a **call** notification is tapped.
  ///
  /// Separate from [onOpenChat] because a call is not a conversation: it has no
  /// `chatId`, and routing it to the chat route would either open the wrong
  /// screen or, when the payload carries no `chatId` at all, do nothing. The
  /// arguments are the caller's uid, the display name to show, and whether it
  /// is a video call.
  void Function(String callerId, String callerName, bool isVideo)? onOpenCall;

  /// The last token this device registered, or null if push never came up.
  String? get token => _token;

  /// The uid whose document currently holds this device's token.
  String get attachedUid => _uid;

  /// Authorisation state from the last [initialize] call. Null before it runs.
  AuthorizationStatus? permissionStatus;

  // -------------------------------------------------------------- lifecycle

  /// Registers handlers and asks for permission.
  ///
  /// Safe to call before anyone is signed in — the token is stored as soon as
  /// [attachUser] supplies a uid, so a fresh install that pushes only after
  /// login still works.
  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _requestPermission();

    try {
      // iOS only: lets a foreground message show an alert. A no-op on Android.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } on Object catch (error) {
      debugPrint('FCM presentation options not applied: $error');
    }

    _tokenSub = _messaging.onTokenRefresh.listen(
      _persistToken,
      onError: (Object error) => debugPrint('FCM token refresh failed: $error'),
    );
    _foregroundSub = FirebaseMessaging.onMessage.listen(
      _onForegroundMessage,
      onError: (Object error) => debugPrint('FCM foreground stream: $error'),
    );
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
      _onOpenedApp,
      onError: (Object error) => debugPrint('FCM open-app stream: $error'),
    );

    await _fetchToken();

    // A tap on the notification that launched the app from a cold start is not
    // delivered through `onMessageOpenedApp` — it has to be pulled once.
    await _consumeInitialMessage();
  }

  /// Releases the stream subscriptions.
  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _tokenSub = null;
    _foregroundSub = null;
    _openedSub = null;
  }

  // ------------------------------------------------------------------ users

  /// Binds the device to [uid] and stores its token.
  ///
  /// Called on sign-in and on every auth change. Re-attaching the same uid is
  /// cheap and idempotent.
  Future<void> attachUser(String uid) async {
    if (uid.isEmpty || uid == _uid) return;
    _uid = uid;
    if (_token != null) {
      await _persistToken(_token!);
    } else {
      await _fetchToken();
    }
  }

  /// Removes this device's token, so a signed-out account stops receiving
  /// pushes for someone else's conversations.
  Future<void> detachUser() async {
    final String uid = _uid;
    final String? token = _token;
    _uid = '';
    if (uid.isEmpty || token == null) return;
    await _removeToken(uid, token);
  }

  // ------------------------------------------------------------- permission

  Future<void> _requestPermission() async {
    try {
      final NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      permissionStatus = settings.authorizationStatus;
      debugPrint('FCM permission: ${settings.authorizationStatus.name}');
    } on Object catch (error) {
      // A denied or unavailable permission is a normal outcome, not a bug.
      debugPrint('FCM permission request failed: $error');
    }
  }

  // ------------------------------------------------------------------ token

  Future<void> _fetchToken() async {
    try {
      final String? token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('FCM returned no registration token');
        return;
      }
      await _persistToken(token);
    } on Object catch (error) {
      debugPrint('FCM getToken failed: $error');
    }
  }

  /// Writes [token] to Firestore when a user is attached, and caches it either
  /// way so a later [attachUser] can publish it without another round trip.
  Future<void> _persistToken(String token) async {
    _token = token;
    final String uid = _uid;
    if (uid.isEmpty) return;

    try {
      await _db.collection(usersCollection).doc(uid).set(
        <String, dynamic>{
          tokenField: FieldValue.arrayUnion(<String>[token]),
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('FCM token not written to users/$uid: $error');
    }
  }

  Future<void> _removeToken(String uid, String token) async {
    try {
      await _db.collection(usersCollection).doc(uid).set(
        <String, dynamic>{
          tokenField: FieldValue.arrayRemove(<String>[token]),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('FCM token not removed from users/$uid: $error');
    }
  }

  // ---------------------------------------------------------------- routing

  Future<void> _consumeInitialMessage() async {
    try {
      final RemoteMessage? message = await _messaging.getInitialMessage();
      if (message == null) return;
      _onOpenedApp(message);
    } on Object catch (error) {
      debugPrint('FCM initial message not read: $error');
    }
  }

  /// A message arrived while the app was visible.
  ///
  /// FCM does not render these itself, so the local notification plugin shows
  /// it using the app's own channels — otherwise a message to the conversation
  /// currently on screen would appear to do nothing.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final PushPayload payload = PushPayload.fromData(message.data);
    final String title = _firstNonEmpty(
      <String?>[payload.title, message.notification?.title, AppConstants.appName],
    );
    final String body = _firstNonEmpty(
      <String?>[payload.body, message.notification?.body],
    );

    debugPrint(
      'FCM foreground ${message.messageId ?? '-'} kind=${payload.kind} '
      'chat=${payload.chatId}',
    );

    final NotificationService? local = _local;
    if (local == null) return;

    try {
      switch (payload.kind) {
        case PushKind.call:
          await local.showCall(title: title, body: body);
        case PushKind.status:
          await local.showStatus(title: title, body: body);
        case _:
          await local.showMessage(
            chatId: payload.chatId,
            title: title,
            body: body,
          );
      }
    } on Object catch (error) {
      debugPrint('FCM foreground display failed: $error');
    }
  }

  /// The user tapped a notification.
  ///
  /// Branches on the payload kind first. A call is not a conversation: it
  /// carries a caller instead of a chat, so sending it down the chat path is
  /// exactly how a call tap opens the wrong screen — or, when the payload has
  /// no `chatId` at all, does nothing.
  void _onOpenedApp(RemoteMessage message) {
    final PushPayload payload = PushPayload.fromData(message.data);

    if (payload.kind == PushKind.call) {
      if (payload.callerId.isEmpty) {
        debugPrint('FCM call tap carried no callerId — no navigation');
        return;
      }
      // For a call, the notification title is the caller's display name.
      onOpenCall?.call(payload.callerId, payload.title, payload.isVideo);
      return;
    }

    if (payload.chatId.isEmpty) {
      debugPrint('FCM tap carried no chatId — no navigation');
      return;
    }
    onOpenChat?.call(payload.chatId);
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final String? value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }
}
