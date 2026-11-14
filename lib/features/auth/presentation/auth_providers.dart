import 'dart:async';

// `OAuthProvider` also exists in firebase_auth; ours describes the *in-app*
// flow, so the plugin's version is hidden to keep the name unambiguous.
import 'package:firebase_auth/firebase_auth.dart' hide OAuthProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/country_data.dart';
import '../../../core/services/e2ee_service.dart';
import '../../../core/services/firebase_auth_service.dart';
import '../../../core/services/firestore_chat_service.dart';
import '../../../core/services/in_app_oauth_service.dart';
import '../../../core/services/remote_contact_service.dart';
import '../../../core/services/session_reset.dart';
import '../../chats/domain/chat_service.dart' show chatMirrorProvider;
import '../../chats/domain/remote_chats_sync.dart'
    show firestoreChatsStreamProvider, liveChatsStreamProvider;
import '../../chats/presentation/providers.dart';

/// The Firebase Authentication facade.
final Provider<FirebaseAuthService> firebaseAuthServiceProvider =
    Provider<FirebaseAuthService>((Ref ref) => FirebaseAuthService());

/// The in-app Google flow.
final Provider<InAppOAuthService> inAppOAuthProvider =
    Provider<InAppOAuthService>((Ref ref) => InAppOAuthService());

/// The shared user directory (phone / email / @username / uid lookups).
final Provider<RemoteContactService> remoteContactServiceProvider =
    Provider<RemoteContactService>((Ref ref) => const RemoteContactService());

/// End-to-end encryption for one-to-one chats.
///
/// One instance for the whole app: it caches this device's key pair and the
/// peer keys it has already fetched, so a second instance would redo the
/// key exchange on every message.
final Provider<E2eeService> e2eeServiceProvider =
    Provider<E2eeService>((Ref ref) => E2eeService());

/// The Firestore side of messaging.
final Provider<FirestoreChatService> firestoreChatServiceProvider =
    Provider<FirestoreChatService>(
  (Ref ref) => FirestoreChatService(e2ee: ref.read(e2eeServiceProvider)),
);

/// Emits the signed-in user, or null. This is the app's auth gate.
final StreamProvider<User?> authStateProvider =
    StreamProvider<User?>((Ref ref) {
  return ref.watch(firebaseAuthServiceProvider).authStateChanges();
});

/// The signed-in user's uid, or an empty string. Convenient in providers that
/// only need the id and must not rebuild when unrelated profile fields change.
final Provider<String> currentUidProvider = Provider<String>((Ref ref) {
  return ref.watch(authStateProvider).valueOrNull?.uid ?? '';
});

/// The signed-in user's own country dial code, digits only (e.g. `880`).
///
/// Search needs this to resolve a number typed without a country code:
/// `01712345678` is only the same person as `+8801712345678` because the
/// *caller* is in Bangladesh.
///
/// The source is the user's own auth address: the phone sign-up flow derives it
/// from the full E.164 digits (`p8801712345678@phone.imolive.app`), so the code
/// is recoverable without a network read or an extra profile field. An email
/// account never carries one, so this falls back to Bangladesh — the same
/// pre-selection the phone screen and the new-contact form both use
/// (`countryForIso('BD')`), which keeps all three in step.
final Provider<String> currentDialCodeProvider = Provider<String>((Ref ref) {
  final String? email = ref.watch(authStateProvider).valueOrNull?.email;
  if (email != null && AppConstants.isPhoneAuthEmail(email)) {
    // `p<digits>@…` — strip the `p` and the domain, then match the code.
    final String digits = email
        .substring(0, email.lastIndexOf('@'))
        .replaceFirst(RegExp(r'^p'), '')
        .replaceAll(RegExp(r'[^0-9]'), '');
    final String? code = CountryData.byDialPrefix(digits)?.dialCode;
    if (code != null && code.isNotEmpty) return code.replaceAll('+', '');
  }
  final String? fallback = CountryData.byIso('BD')?.dialCode;
  return (fallback ?? '+880').replaceAll('+', '');
});

/// True while the very first auth event has not arrived.
///
/// The router waits on this before choosing between login and home, so a cold
/// start with a persisted session never flashes the login screen.
final Provider<bool> authResolvingProvider = Provider<bool>((Ref ref) {
  return ref.watch(authStateProvider).isLoading;
});

/// Live profile document for a uid, used by chat headers and profile pages.
final StreamProviderFamily<RemoteProfile?, String> remoteProfileProvider =
    StreamProvider.family<RemoteProfile?, String>((Ref ref, String uid) {
  return ref.watch(remoteContactServiceProvider).watchProfile(uid);
});

// NOTE: the email-verification state providers that used to live here
// (`pendingVerificationEmailProvider`, `verificationEmailProvider`,
// `needsEmailVerificationProvider`) were removed on 2026-10-06 along with email
// sign-in and the OTP screen. Google and phone are the only providers left, and
// neither has an email that can be "unverified":
//
//   * a Google account is verified by Google before Firebase sees it;
//   * a phone account's address is derived from the number
//     (`AppConstants.phoneAuthEmailFor`) and no mailbox exists to confirm it,
//     so `emailVerified` would be false forever.
//
// The matching half of this rule is in `app/auth_gate.dart::authRedirect`.

// ============================================================================
// Controller
// ============================================================================

/// The result of an auth attempt, so screens can branch without try/catch
/// noise in the widget tree.
@immutable
class AuthOutcome {
  const AuthOutcome.success([this.uid = ''])
      : error = null;

  const AuthOutcome.failure(String message)
      : uid = '',
        error = message;

  final String uid;
  final String? error;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// Drives login, signup, OAuth and sign-out, and keeps Firestore presence in
/// step with the auth session.
final NotifierProvider<AuthController, AsyncValue<void>> authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<void>>(AuthController.new);

class AuthController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() {
    // Presence follows the auth session for the whole app lifetime: signing in
    // marks the user online, signing out marks them offline with a fresh
    // `lastSeen`. This is the only place that owns the transition.
    final AsyncValue<User?> auth = ref.watch(authStateProvider);
    auth.whenData((User? user) {
      final FirebaseAuthService service = ref.read(firebaseAuthServiceProvider);
      final E2eeService e2ee = ref.read(e2eeServiceProvider);
      if (user == null) {
        // Drop the in-memory key pair. The stored private key survives, so
        // signing back in on this device restores the same identity.
        e2ee.reset();
        return;
      }
      unawaited(service.touchPresence(user.uid, isOnline: true));
      // Generates and publishes the X25519 key pair on first run, then
      // re-publishes it on later sign-ins so a peer who signed up in the
      // meantime picks it up.
      unawaited(e2ee.ensureIdentity(user.uid));
    });
    return const AsyncData<void>(null);
  }

  FirebaseAuthService get _auth => ref.read(firebaseAuthServiceProvider);
  InAppOAuthService get _oauth => ref.read(inAppOAuthProvider);

  // NOTE: `signInWithEmail` and `signUpWithEmail` were removed on 2026-10-06.
  // They were the only flows that produced an account needing an emailed
  // confirmation link, and that link never arrived on a real device — so the
  // account existed and was permanently unusable. Google and phone are the two
  // providers that complete inside the app.

  /// Completes a Google sign-in started from the login or signup screen.
  Future<AuthOutcome> signInWithGoogle() => _runOAuth(_oauth.signInWithGoogle);

  /// Creates an account from a phone number and a PIN.
  ///
  /// There is no verification step to hand back: the number is not confirmed by
  /// SMS, and the derived sign-in address has no mailbox to confirm. The account
  /// is usable the moment this returns, so the result is a plain success and
  /// the gate sends the user straight into the app.
  Future<AuthOutcome> signUpWithPhone({
    required String phoneDigits,
    required String pin,
    required String firstName,
    required String lastName,
    String username = '',
  }) async {
    state = const AsyncLoading<void>();
    try {
      final String uid = await _auth.signUpWithPhone(
        phoneDigits: phoneDigits,
        pin: pin,
        firstName: firstName,
        lastName: lastName,
        username: username,
      );
      state = const AsyncData<void>(null);
      await _adoptSession();
      return AuthOutcome.success(uid);
    } on AuthException catch (error) {
      state = AsyncError<void>(error, StackTrace.current);
      return AuthOutcome.failure(error.message);
    } on Object catch (error) {
      state = AsyncError<void>(error, StackTrace.current);
      return const AuthOutcome.failure('The account could not be created.');
    }
  }

  /// Signs in with a phone number and PIN.
  Future<AuthOutcome> signInWithPhone({
    required String phoneDigits,
    required String pin,
  }) async {
    state = const AsyncLoading<void>();
    try {
      final String uid = await _auth.signInWithPhone(
        phoneDigits: phoneDigits,
        pin: pin,
      );
      state = const AsyncData<void>(null);
      await _adoptSession();
      return AuthOutcome.success(uid);
    } on AuthException catch (error) {
      state = AsyncError<void>(error, StackTrace.current);
      return AuthOutcome.failure(error.message);
    } on Object catch (error) {
      state = AsyncError<void>(error, StackTrace.current);
      return const AuthOutcome.failure('Sign-in failed. Please try again.');
    }
  }

  Future<AuthOutcome> _runOAuth(Future<OAuthResult> Function() flow) async {
    state = const AsyncLoading<void>();
    try {
      final OAuthResult result = await flow();
      final UserCredential credential = await _credentialFor(result);
      final User? user = credential.user;
      if (user == null) {
        state = const AsyncData<void>(null);
        return const AuthOutcome.failure('That sign-in did not finish.');
      }
      await _ensureProfileDocument(user, result);
      state = const AsyncData<void>(null);
      await _adoptSession();
      return AuthOutcome.success(user.uid);
    } on OAuthException catch (error) {
      state = const AsyncData<void>(null);
      return AuthOutcome.failure(error.message);
    } on FirebaseAuthException catch (error) {
      state = const AsyncData<void>(null);
      return AuthOutcome.failure(
        error.message ?? 'That sign-in did not finish.',
      );
    } on Object catch (error) {
      debugPrint('OAuth sign-in failed: $error');
      state = const AsyncData<void>(null);
      return const AuthOutcome.failure('That sign-in did not finish.');
    }
  }

  /// Turns an [OAuthResult] into a Firebase credential and signs in.
  ///
  /// The switch is exhaustive over [OAuthProvider] on purpose: with Google as
  /// the only value it compiles without a `default`, so re-adding a provider
  /// cannot be forgotten here — it fails the build until it is handled.
  Future<UserCredential> _credentialFor(OAuthResult result) {
    final AuthCredential credential = switch (result.provider) {
      OAuthProvider.google => GoogleAuthProvider.credential(
          idToken: result.idToken,
          accessToken: result.accessToken.isEmpty ? null : result.accessToken,
        ),
    };
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  /// Makes sure a first-time OAuth user gets a profile document and their
  /// handles claimed, exactly like an email signup does.
  Future<void> _ensureProfileDocument(User user, OAuthResult result) async {
    await _auth.ensureProfileForExternalUser(
      uid: user.uid,
      name: result.name.isNotEmpty
          ? result.name
          : (user.displayName ?? 'Imo LIVE user'),
      email: result.email.isNotEmpty ? result.email : (user.email ?? ''),
      photoUrl: result.photoUrl,
    );
  }

  Future<void> signOut() async {
    state = const AsyncLoading<void>();
    // `FirebaseAuthService.signOut` marks presence offline and clears the
    // session. The local wipe runs after it so the offline-presence write still
    // has an authenticated request behind it.
    await _auth.signOut();
    await _resetSessionState();
    state = const AsyncData<void>(null);
  }

  /// Erases everything this account left on the device.
  ///
  /// Two halves, and **both** are required:
  ///
  /// 1. **Storage** — [SessionReset.wipeLocalData] clears every Hive box, every
  ///    SharedPreferences key, the Firestore offline cache and the in-memory
  ///    image cache.
  /// 2. **In-memory state** — the repository and notifier providers were built
  ///    for the previous account and hold their data in Dart objects, not in
  ///    Hive. Clearing storage alone leaves the old chat list on screen until
  ///    the process restarts, which is exactly the "old data leaking into the
  ///    new account" the wipe exists to stop. Invalidating each provider
  ///    disposes it and rebuilds it from the (now empty) store on next read.
  ///
  /// `currentUidProvider` needs no invalidation: it derives from
  /// `authStateProvider`, so it is already `''` by the time this runs.
  Future<void> _resetSessionState() async {
    // The pre-per-uid E2EE key must not survive to be adopted by whoever signs
    // in next. The per-uid keys *do* survive — signing back in has to be able
    // to read the account's own history.
    await ref.read(e2eeServiceProvider).purgeLegacyKeys();

    await SessionReset.wipeLocalData();

    _invalidateUserProviders();
  }

  /// Drops every provider that was built for a particular account.
  ///
  /// Called on the way out (after the wipe) *and* on the way in: a session that
  /// was adopted while an old container still held the previous account's rows
  /// would show them under the new uid.
  void _invalidateUserProviders() {
    // Repositories — these own the in-memory caches.
    ref.invalidate(chatRepositoryProvider);
    ref.invalidate(messageRepositoryProvider);
    ref.invalidate(contactRepositoryProvider);
    ref.invalidate(groupRepositoryProvider);
    ref.invalidate(communityRepositoryProvider);
    ref.invalidate(channelRepositoryProvider);
    ref.invalidate(statusRepositoryProvider);
    ref.invalidate(callRepositoryProvider);
    ref.invalidate(settingsRepositoryProvider);

    // Content notifiers.
    ref.invalidate(chatsProvider);
    ref.invalidate(contactsProvider);
    ref.invalidate(selfProfileProvider);
    ref.invalidate(groupsProvider);
    ref.invalidate(communitiesProvider);
    ref.invalidate(channelsProvider);
    ref.invalidate(statusesProvider);
    ref.invalidate(callsProvider);
    ref.invalidate(starredMessagesProvider);
    ref.invalidate(messageSelectionProvider);
    ref.invalidate(chatFilterProvider);

    // Live mirrors — the family variants are invalidated wholesale.
    ref.invalidate(liveChatsStreamProvider);
    ref.invalidate(firestoreChatsStreamProvider);
    ref.invalidate(messagesProvider);
    ref.invalidate(chatMirrorProvider);
    ref.invalidate(chatByIdProvider);
    ref.invalidate(chatStreamProvider);
    ref.invalidate(remoteProfileProvider);

    // Device preferences live in the same settings box that was just cleared,
    // so their notifiers have to re-read rather than keep serving the old
    // account's values.
    ref.invalidate(appearanceProvider);
    ref.invalidate(notificationSettingsProvider);
    ref.invalidate(privacySettingsProvider);
    ref.invalidate(chatSettingsProvider);
    ref.invalidate(wallpaperProvider);
    ref.invalidate(languageProvider);
  }

  // NOTE: `resendVerification` and `confirmEmailVerified` were removed with the
  // OTP screen on 2026-10-06 — there is no email verification step left.

  /// Runs once a session is adopted: gives the local stores a clean slate for
  /// the new user and starts mirroring the remote conversation list.
  ///
  /// The wipe belongs to sign-out, but the invalidation belongs here too: a
  /// provider that survived the previous session — a repository that was still
  /// mounted, a notifier nothing had disposed — would otherwise answer the new
  /// account's first read with the old account's rows.
  Future<void> _adoptSession() async {
    _invalidateUserProviders();
  }
}
