import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../constants/app_constants.dart';
import 'notification_service.dart';
import 'onesignal_service.dart';

/// Message categories the sender puts in the `type` field of the push payload.
/// Anything unrecognised is treated as [PushKind.unknown] and shown as a plain
/// message, so a new server-side category degrades instead of vanishing.
abstract final class PushKind {
  static const String message = 'message';
  static const String call = 'call';
  static const String status = 'status';
  static const String unknown = 'unknown';
}

/// The parts of a push payload the app acts on.
///
/// Kept as a plain `Map` parser, with no dependency on the OneSignal SDK types,
/// so the routing rules stay unit-testable without a platform channel.
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
  ///
  /// `callId` is accepted as a fallback spelling because the Cloudflare Worker's
  /// documented contract sends it; `callerId` is what the call route actually
  /// needs, so it is preferred when both are present.
  static const String keyCallerId = 'callerId';
  static const String keyCallerIdAlt = 'caller_id';
  static const String keyCallId = 'callId';
  static const String keyCallIdAlt = 'call_id';
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

  /// Parses a raw `additionalData` map.
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
        // `chat` is the spelling the Cloudflare Worker's send contract uses for
        // an ordinary message. It is a message, not a new category.
        'chat' => PushKind.message,
        _ => PushKind.unknown,
      },
      callerId: _read(data, <String>[
        keyCallerId,
        keyCallerIdAlt,
        keyCallId,
        keyCallIdAlt,
      ]),
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

/// OneSignal: identity binding, permission, and notification routing.
///
/// ### What this does and does not cover
///
/// This class owns the **client half** of push delivery:
///
/// * bind the signed-in uid to this device's OneSignal subscription (delegated
///   to [OneSignalService], which also mirrors the player id onto `users/{uid}`),
/// * show a message that arrives while the app is in the foreground — OneSignal
///   does not display those itself,
/// * route a tap on a notification to the conversation or call it belongs to.
///
/// **Sending** is out of scope and lives in [OneSignalService.sendNotificationToUser],
/// which posts to the project's Cloudflare Worker. The OneSignal REST key is
/// never in this app.
///
/// ### Payload contract
///
/// The sender must attach `additionalData` containing:
///
/// ```json
/// { "type": "chat" | "call" | "status",
///   "chatId": "<chat id>",        // chat
///   "callerId": "<caller uid>",   // call — `callId` also accepted
///   "isVideo": "true" | "false" }
/// ```
///
/// ### Failure policy
///
/// Everything is best-effort. Push is an enhancement, never a dependency: if the
/// permission is denied or the player id never arrives, the app keeps working
/// with local notifications only.
class PushNotificationService {
  /// Constructing the service must not touch a platform channel: `main()` builds
  /// it during startup, and a test host has no OneSignal plugin registered. The
  /// SDK is therefore only reached from [initialize] and the user methods.
  PushNotificationService({NotificationService? notifications})
      : _local = notifications;

  final NotificationService? _local;

  String _uid = '';
  String? _token;

  /// A tap that arrived before the router was wired.
  ///
  /// `initialize()` runs from `main()` so the listener is registered before the
  /// first frame — a tap that *launched* the app is delivered immediately, and
  /// registering any later drops it on the floor. But the navigation callbacks
  /// are only known once the router exists, a moment afterwards. So an early tap
  /// is parked here and replayed by the setters below rather than lost.
  PushPayload? _pendingTap;

  void Function(String chatId)? _onOpenChat;

  /// Called when a notification is tapped, with the conversation to open.
  ///
  /// Wired by `main()` to the router. Null until then, which also makes the
  /// service usable in a test host with no navigation.
  void Function(String chatId)? get onOpenChat => _onOpenChat;
  set onOpenChat(void Function(String chatId)? callback) {
    _onOpenChat = callback;
    _replayPendingTap();
  }

  void Function(String callerId, String callerName, bool isVideo)? _onOpenCall;

  /// Called when a **call** notification is tapped.
  ///
  /// Separate from [onOpenChat] because a call is not a conversation: it has no
  /// `chatId`, and routing it to the chat route would either open the wrong
  /// screen or, when the payload carries no `chatId` at all, do nothing. The
  /// arguments are the caller's uid, the display name to show, and whether it
  /// is a video call.
  void Function(String callerId, String callerName, bool isVideo)? get onOpenCall =>
      _onOpenCall;
  set onOpenCall(void Function(String callerId, String callerName, bool isVideo)? callback) {
    _onOpenCall = callback;
    _replayPendingTap();
  }

  /// The player id last read from OneSignal, or null if push never came up.
  String? get token => _token;

  /// The uid currently bound to this device.
  String get attachedUid => _uid;

  // -------------------------------------------------------------- lifecycle

  /// Registers the foreground and tap listeners.
  ///
  /// Safe to call before anyone is signed in — the uid is bound as soon as
  /// [attachUser] supplies one, so a fresh install that signs in afterwards
  /// still registers. Idempotent: `main()` calls it early so a launching tap is
  /// not lost, and the auth path calls it again once the router is up.
  Future<void> initialize() async {
    if (_listenersRegistered) return;
    _listenersRegistered = true;
    try {
      OneSignal.Notifications.addForegroundWillDisplayListener(_onForeground);
      OneSignal.Notifications.addClickListener(_onClick);
    } on Object catch (error) {
      _listenersRegistered = false;
      // No plugin on this host (a widget test, or desktop). Push is optional.
      debugPrint('OneSignal listeners not registered: $error');
    }
  }

  bool _listenersRegistered = false;

  /// Releases the listeners.
  Future<void> dispose() async {
    try {
      OneSignal.Notifications.removeForegroundWillDisplayListener(_onForeground);
      OneSignal.Notifications.removeClickListener(_onClick);
    } on Object catch (error) {
      debugPrint('OneSignal listeners not removed: $error');
    }
  }

  // ------------------------------------------------------------------ users

  /// Binds the device to [uid] and stores its player id.
  ///
  /// Called on sign-in and on every auth change. Re-attaching the same uid is
  /// cheap and idempotent.
  Future<void> attachUser(String uid) async {
    if (uid.isEmpty || uid == _uid) return;
    _uid = uid;
    await OneSignalService.linkUser(uid);
    _token = OneSignalService.playerId;
  }

  /// Detaches this device, so a signed-out account stops receiving pushes for
  /// someone else's conversations.
  Future<void> detachUser() async {
    if (_uid.isEmpty) return;
    _uid = '';
    _token = null;
    await OneSignalService.unlinkUser();
  }

  // ---------------------------------------------------------------- routing

  /// A message arrived while the app was visible.
  ///
  /// OneSignal does not render these itself, so the local notification plugin
  /// shows it using the app's own channels — otherwise a message to the
  /// conversation currently on screen would appear to do nothing.
  void _onForeground(OSNotificationWillDisplayEvent event) {
    // The app draws it, so suppress OneSignal's own rendering first. Doing this
    // before any await matters: once the listener returns, the notification is
    // already on screen.
    event.preventDefault();

    final PushPayload payload = PushPayload.fromData(_dataOf(event.notification));
    final String title = _firstNonEmpty(<String?>[
      payload.title,
      event.notification.title,
      AppConstants.appName,
    ]);
    final String body = _firstNonEmpty(<String?>[
      payload.body,
      event.notification.body,
    ]);

    debugPrint('OneSignal foreground kind=${payload.kind} chat=${payload.chatId}');
    _logChannel(event.notification);

    final NotificationService? local = _local;
    if (local == null) return;

    // The local call is deliberately not awaited: this runs on the listener the
    // SDK invoked, and holding it open would stall the next notification.
    switch (payload.kind) {
      case PushKind.call:
        unawaited(local.showCall(title: title, body: body));
      case PushKind.status:
        unawaited(local.showStatus(title: title, body: body));
      case _:
        unawaited(
          local.showMessage(
            chatId: payload.chatId,
            title: title,
            body: body,
          ),
        );
    }
  }

  /// The user tapped a notification.
  ///
  /// Branches on the payload kind first. A call is not a conversation: it
  /// carries a caller instead of a chat, so sending it down the chat path is
  /// exactly how a call tap opens the wrong screen — or, when the payload has
  /// no `chatId` at all, does nothing.
  void _onClick(OSNotificationClickEvent event) {
    _logChannel(event.notification);
    _dispatch(PushPayload.fromData(_dataOf(event.notification)));
  }

  /// Prints the Android notification channel this push was rendered on.
  ///
  /// OneSignal renders a *background* push itself, on the channel named by the
  /// payload's `android_channel_id`. With no such field it falls back to its own
  /// default channel, and the user can then no longer mute messages while keeping
  /// calls audible — the app's own `imo_messages`/`imo_calls` channels would only
  /// ever be used for the foreground case.
  ///
  /// That field is a top-level OneSignal parameter, so it never reaches
  /// `additionalData`. `rawPayload` is the only place it is visible, and only on
  /// a device. This is the one check that separates "the relay sets the channel"
  /// from "it silently does not".
  ///
  /// Debug-only, and deliberately prints the channel and the key list rather than
  /// the payload: the values include message text.
  static void _logChannel(OSNotification notification) {
    if (!kDebugMode) return;
    final Map<String, dynamic>? raw = notification.rawPayload;
    final Object? channel = raw?['android_channel_id'] ?? raw?['androidChannelId'];
    debugPrint(
      'OneSignal channel=${channel ?? 'ABSENT (OneSignal default channel)'} '
      'rawKeys=${raw?.keys.join(',') ?? '(no rawPayload)'}',
    );
  }

  /// Routes a parsed tap, parking it when the router is not wired yet.
  void _dispatch(PushPayload payload) {
    if (payload.kind == PushKind.call) {
      if (payload.callerId.isEmpty) {
        debugPrint('OneSignal call tap carried no callerId — no navigation');
        return;
      }
      if (_onOpenCall == null) {
        _pendingTap = payload;
        return;
      }
      // For a call, the notification title is the caller's display name.
      _onOpenCall!.call(payload.callerId, payload.title, payload.isVideo);
      return;
    }

    if (payload.chatId.isEmpty) {
      debugPrint('OneSignal tap carried no chatId — no navigation');
      return;
    }
    if (_onOpenChat == null) {
      _pendingTap = payload;
      return;
    }
    _onOpenChat!.call(payload.chatId);
  }

  /// Replays a tap that arrived before its navigation callback existed.
  void _replayPendingTap() {
    final PushPayload? pending = _pendingTap;
    if (pending == null) return;
    _pendingTap = null;
    _dispatch(pending);
  }

  /// The `additionalData` map, or an empty one when the push carried none.
  static Map<String, dynamic> _dataOf(OSNotification notification) {
    final Map<String, dynamic>? data = notification.additionalData;
    return data ?? <String, dynamic>{};
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final String? value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }
}
