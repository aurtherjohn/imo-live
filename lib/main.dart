import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'app/app.dart';
import 'app/auth_gate.dart';
import 'app/router.dart';
import 'app/theme/app_tokens.dart';
import 'core/config/app_secrets.dart';
import 'core/constants/app_constants.dart';
import 'core/services/push_notification_service.dart';
import 'core/utils/row_keys.dart';
import 'features/chats/presentation/providers.dart'
    show notificationServiceProvider;
import 'utils/crash_logger.dart';
import 'core/utils/l10n.dart';

/// The single provider container for the whole process.
///
/// Created here rather than inside [ProviderScope] because startup code outside
/// the widget tree — [PushNotificationService] in particular — has to reach the
/// same [notificationServiceProvider] instance the UI uses. Two
/// `FlutterLocalNotificationsPlugin` instances would fight over the method
/// channel, so there must be exactly one notification service.
final ProviderContainer appContainer = ProviderContainer();

/// Push registration, alive for the lifetime of the process.
PushNotificationService? pushService;

/// Application entry point.
///
/// Startup is deliberately defensive: this app must never present a black
/// screen. The single most important rule is enforced here — **nothing that can
/// hang is awaited before `runApp`**.
///
/// The whole body runs inside [CrashLogger.runGuarded], so any uncaught error is
/// written to a local file that can be read back on the device without `adb`.
void main() {
  CrashLogger.runGuarded(() {
    // --- Binding first, before *any* platform access --------------------
    WidgetsFlutterBinding.ensureInitialized();

    // --- Make build errors visible instead of silently black ------------
    _installErrorHandlers();

    // --- Firebase, bounded so it can never block the first frame --------
    unawaited(_initFirebase());

    // --- OneSignal SDK, before the first frame --------------------------
    _initOneSignal();

    // --- Nothing above may block; the first frame is unconditional ------
    runApp(
      UncontrolledProviderScope(
        container: appContainer,
        child: const ImoLiveApp(),
      ),
    );
  });
}

/// Brings up the OneSignal SDK, registers the notification listeners, and asks
/// for the permission.
///
/// Synchronous by design: `initialize` is a plain SDK call and must not be
/// awaited before `runApp`, because nothing about push is worth delaying the
/// first frame for. The permission prompt is fired and forgotten — a denial is
/// a normal outcome, and the app works without it.
///
/// The service is created **here** rather than in [_initPush] so its listeners
/// exist before the first frame: a tap on a notification that *launched* the
/// app is delivered as soon as the SDK is up, and registering the click listener
/// any later drops that tap. The navigation callbacks are attached afterwards by
/// [_initPush]; a tap arriving in between is parked by the service and replayed.
///
/// Identity is *not* bound here: `OneSignal.login(uid)` runs from
/// [PushNotificationService.attachUser], which the auth stream drives, so a
/// device that is signed out never advertises an account it does not have.
void _initOneSignal() {
  try {
    OneSignal.initialize(AppSecrets.oneSignalAppId);
    unawaited(OneSignal.Notifications.requestPermission(true));

    final PushNotificationService push = PushNotificationService(
      notifications: appContainer.read(notificationServiceProvider),
    );
    pushService = push;
    unawaited(push.initialize());
  } on Object catch (error) {
    // No plugin on this host (a widget test, or desktop). Push is optional.
    debugPrint('OneSignal.initialize failed: $error');
  }
}

/// Brings Firebase up and connects it to the router's auth gate.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 8));
  } on Object catch (error) {
    debugPrint('Firebase.initializeApp failed: $error');
    resolveAuthWithoutFirebase();
    return;
  }

  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } on Object catch (error) {
    debugPrint('Firestore settings not applied: $error');
  }

  // --- Session durability -------------------------------------------------
  //
  // ⚠️ `setPersistence` is a **web-only** API. On Android and iOS the plugin
  // throws `UnimplementedError`: the native SDKs already persist the session to
  // disk (SharedPreferences on Android, the Keychain on iOS) and expose no
  // alternative mode. Calling it unconditionally — which is the obvious reading
  // of "set persistence to LOCAL" — would throw on every mobile launch.
  //
  // On mobile the fix for a session that does not survive a restart is therefore
  // not here; it is in the auth gate, which used to treat a slow first auth
  // event as "signed out" and bounce the user to the login screen. See
  // `_authResolveDeadline` in app/auth_gate.dart.
  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } on Object catch (error) {
      debugPrint('setPersistence(LOCAL) failed: $error');
    }
  }

  try {
    final Stream<User?> authState = FirebaseAuth.instance.authStateChanges();
    connectAuthStream(authState);
    authState.listen(
      (User? user) {
        publishAuthState(user);
        // Sign-out must stop pushes to this device. Fire and forget: the
        // token write is best-effort and must never delay the router.
        unawaited(_syncPushUser(user));
      },
      onError: (Object error) {
        debugPrint('Auth state stream failed: $error');
        publishAuthState(null);
      },
    );
    await FirebaseAuth.instance.authStateChanges().first.timeout(
      const Duration(seconds: 5),
    );
  } on Object catch (error) {
    // ⚠️ Deliberately does **not** force the app to signed-out. Firebase is up
    // and `connectAuthStream` has already run, so a real session is still on its
    // way; declaring the user signed out here is what produced the reported
    // "auto-logout" on a slow cold start. The gate keeps waiting, and
    // `_authEventSafetyNet` bounds that wait.
    debugPrint('No auth event within 5s; the gate will keep waiting: $error');
  }

  // Push comes up last and only once the auth state is known: the registration
  // token is stored under a uid, and a tap on a notification has to be able to
  // navigate without being bounced by the auth gate.
  await _initPush();
}

/// Brings up push and keeps its identity bound to the signed-in account.
///
/// Every failure is swallowed on purpose — push is an enhancement, and a
/// missing registration must never keep anyone out of the app.
Future<void> _initPush() async {
  try {
    // The instance was created by [_initOneSignal] so its listeners exist before
    // the first frame. Fall back to creating one only if that failed.
    final PushNotificationService push =
        pushService ??
        PushNotificationService(
          notifications: appContainer.read(notificationServiceProvider),
        );
    // The payload's `chatId` is a *row key*, not always a conversation id: a
    // channel post push carries `channel:<id>` (see `functions/channel_push.js`)
    // so the tap can open the channel. Routing every key straight to the chat
    // route would send a channel tap to a conversation that does not exist.
    push.onOpenChat = (String rowKey) => RowKeys.open(appRouter, rowKey);
    // A call notification is not a chat: it has to open the call screen, in
    // incoming mode, or the callee taps a ringing call and lands nowhere.
    push.onOpenCall = (String callerId, String callerName, bool isVideo) =>
        appRouter.go(
          '${AppRoutes.call}?id=${Uri.encodeComponent(callerId)}'
          '&name=${Uri.encodeComponent(callerName.isEmpty ? 'Unknown' : callerName)}'
          '&video=$isVideo'
          '&outgoing=0',
        );
    await push.initialize();
    pushService = push;
    await _syncPushUser(FirebaseAuth.instance.currentUser);
  } on Object catch (error) {
    debugPrint('Push notifications unavailable: $error');
  }
}

/// Publishes or withdraws the device token as the session changes, so a
/// signed-out device stops receiving pushes meant for the previous account.
Future<void> _syncPushUser(User? user) async {
  final PushNotificationService? push = pushService;
  if (push == null) return;
  try {
    if (user == null) {
      await push.detachUser();
    } else {
      await push.attachUser(user.uid);
    }
  } on Object catch (error) {
    debugPrint('Push token sync failed: $error');
  }
}

/// Routes framework-level errors to visible UI **and** to the crash log.
void _installErrorHandlers() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _StartupErrorWidget(details: details);
  };

  final FlutterExceptionHandler? previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }
    unawaited(
      CrashLogger.record(
        details.exception,
        details.stack,
        source: 'flutter',
        context: details.library,
      ),
    );
    if (kDebugMode) {
      previous?.call(details);
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    unawaited(CrashLogger.record(error, stack, source: 'platform'));
    return true;
  };
}

/// Fallback shown when a widget fails to build.
class _StartupErrorWidget extends StatelessWidget {
  const _StartupErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final String? library = details.library;
    final String message = details.exceptionAsString();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: AppColors.darkBg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color.fromARGB(255, 242, 34, 72),
                  size: 44,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.somethingWentWrongOnThis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      library == null ? message : '[$library] $message',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB9B9C2),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.theRestOfTheApp,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
