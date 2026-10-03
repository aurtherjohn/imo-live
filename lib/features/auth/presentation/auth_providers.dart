import 'dart:async';

// `OAuthProvider` also exists in firebase_auth; ours describes the *in-app*
// flow, so the plugin's version is hidden to keep the name unambiguous.
import 'package:firebase_auth/firebase_auth.dart' hide OAuthProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/e2ee_service.dart';
import '../../../core/services/firebase_auth_service.dart';
import '../../../core/services/firestore_chat_service.dart';
import '../../../core/services/in_app_oauth_service.dart';
import '../../../core/services/remote_contact_service.dart';
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

/// The address a just-created account must verify.
///
/// Set by the signup screen immediately before the auth gate swaps in the OTP
/// screen, so the OTP screen can say "we sent a code to <address>" instead of
/// "your email". Falls back to the signed-in user's own address, which covers
/// the case where the app is restarted mid-verification.
final StateProvider<String> pendingVerificationEmailProvider =
    StateProvider<String>((Ref ref) => '');

/// The address the OTP screen should name.
final Provider<String> verificationEmailProvider = Provider<String>((Ref ref) {
  final String pending = ref.watch(pendingVerificationEmailProvider);
  if (pending.isNotEmpty) return pending;
  return ref.watch(authStateProvider).valueOrNull?.email ?? '';
});

/// True when the signed-in account still has to verify its email.
///
/// OAuth users arrive verified, so this is false for them; password signups
/// start true and flip once the server reports the address as confirmed.
final Provider<bool> needsEmailVerificationProvider = Provider<bool>((Ref ref) {
  // Depend on the stream so a reload-triggered auth event re-evaluates this.
  ref.watch(authStateProvider);
  final FirebaseAuthService service = ref.watch(firebaseAuthServiceProvider);
  final User? user = service.currentUser;
  if (user == null) return false;
  // Google accounts are verified by the provider itself.
  final bool isPasswordAccount = user.providerData.any(
    (UserInfo info) => info.providerId == 'password',
  );
  // A phone account is *also* a `password` account, but its address is derived
  // from the number and can never be confirmed — no mailbox exists. Without
  // this it would sit on the OTP screen forever with no way forward.
  final bool isPhoneAccount = AppConstants.isPhoneAuthEmail(user.email);
  return isPasswordAccount && !isPhoneAccount && !user.emailVerified;
});

// ============================================================================
// Controller
// ============================================================================

/// The result of an auth attempt, so screens can branch without try/catch
/// noise in the widget tree.
@immutable
class AuthOutcome {
  const AuthOutcome.success([this.uid = ''])
      : error = null,
        needsVerification = false;
  const AuthOutcome.failure(String message)
      : uid = '',
        error = message,
        needsVerification = false;

  /// Signed up, but the email still has to be verified on the OTP screen.
  const AuthOutcome.verifyEmail(this.uid)
      : error = null,
        needsVerification = true;

  final String uid;
  final String? error;
  final bool needsVerification;

  bool get isSuccess => error == null && !needsVerification;
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

  Future<AuthOutcome> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading<void>();
    try {
      final String uid = await _auth.signInWithEmail(
        email: email,
        password: password,
      );
      state = const AsyncData<void>(null);
      await _adoptSession();
      return AuthOutcome.success(uid);
    } on AuthException catch (error) {
      state = AsyncError<void>(error, StackTrace.current);
      return AuthOutcome.failure(error.message);
    } on Object catch (error) {
      state = AsyncError<void>(error, StackTrace.current);
      return AuthOutcome.failure('Sign-in failed. Please try again.');
    }
  }

  /// Creates an account. The result asks the caller to run email verification.
  Future<AuthOutcome> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading<void>();
    try {
      final String uid = await _auth.signUpWithEmail(
        name: name,
        email: email,
        password: password,
      );
      state = const AsyncData<void>(null);
      await _adoptSession();
      return AuthOutcome.verifyEmail(uid);
    } on AuthException catch (error) {
      state = AsyncError<void>(error, StackTrace.current);
      return AuthOutcome.failure(error.message);
    } on Object catch (error) {
      state = AsyncError<void>(error, StackTrace.current);
      return AuthOutcome.failure('The account could not be created.');
    }
  }

  /// Completes a Google sign-in started from the login or signup screen.
  Future<AuthOutcome> signInWithGoogle() => _runOAuth(_oauth.signInWithGoogle);

  /// Creates an account from a phone number and a PIN.
  ///
  /// There is no verification step to hand back: the number is not confirmed by
  /// SMS, and the derived sign-in address has no mailbox to confirm. The account
  /// is usable the moment this returns, so unlike [signUpWithEmail] the result
  /// is a plain success and the gate sends the user straight into the app.
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
    await _auth.signOut();
    state = const AsyncData<void>(null);
  }

  /// Re-sends the verification email from the OTP screen.
  Future<AuthOutcome> resendVerification() async {
    try {
      await _auth.resendVerificationEmail();
      return const AuthOutcome.success();
    } on AuthException catch (error) {
      return AuthOutcome.failure(error.message);
    } on Object {
      return const AuthOutcome.failure('The code could not be sent again.');
    }
  }

  /// The OTP screen's "Verify" button: reloads the account and reports whether
  /// the server now considers the email verified.
  Future<bool> confirmEmailVerified() => _auth.isEmailVerified();

  /// Runs once a session is adopted: gives the local stores a clean slate for
  /// the new user and starts mirroring the remote conversation list.
  Future<void> _adoptSession() async {
    ref.invalidate(remoteProfileProvider);
    ref.invalidate(chatsProvider);
    ref.invalidate(contactsProvider);
  }
}
