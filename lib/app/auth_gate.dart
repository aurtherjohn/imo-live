import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/models/settings.dart';

/// Routes that belong to the sign-in flow itself.
///
/// A *signed-in* user must never be left on one of these — that is what stops
/// the login screen reappearing after a successful sign-in.
const Set<String> _authRoutes = <String>{
  AppRoutes.splash,
  AppRoutes.login,
  AppRoutes.signup,
  AppRoutes.profileSetup,
  AppRoutes.onboarding,
  AppRoutes.permissionGrant,
  // The phone flow lives here because it is a route now, not an imperative
  // push. Leaving it out would make the gate itself the thing that bounces a
  // phone signup: the user is mid-flow on a route it does not recognise while
  // signed out, so it would redirect them to /login.
  AppRoutes.phoneLogin,
};

/// Routes a *signed-out* user may still reach.
///
/// Deliberately only the login screen, its signup sibling, the phone flow,
/// and the splash that precedes them. Everything else — the chat shell,
/// settings, the profile — is gated, because the whole app reads and writes
/// under the signed-in uid.
const Set<String> _signedOutRoutes = <String>{
  AppRoutes.splash,
  AppRoutes.login,
  AppRoutes.signup,
  AppRoutes.phoneLogin,
};

/// How long the gate waits for the first auth event **when Firebase never came
/// up at all** before deciding the user is signed out.
///
/// ⚠️ This deadline deliberately does *not* apply once [connectAuthStream] has
/// run. It used to: a fixed 3-second clock treated "no event yet" as
/// signed-out, which on a cold start with a slow disk or a slow network showed
/// the login screen to a user who was in fact signed in — and if they began
/// typing, they were effectively logged out. That was the reported
/// "auto-logout". `authStateChanges()` always emits at least once, so once the
/// SDK is up, waiting is always correct and the clock is unnecessary.
const Duration _authResolveDeadline = Duration(seconds: 3);

/// The safety net for the case where Firebase reported itself ready but no auth
/// event ever arrived — a wedged SDK rather than a slow one.
///
/// Generous on purpose: a false positive here is a spurious logout, which is far
/// worse than a longer splash. It exists only so the app cannot hang on the
/// splash screen forever.
const Duration _authEventSafetyNet = Duration(seconds: 20);

/// A [Listenable] that fires whenever Firebase reports an auth change.
///
/// [GoRouter.refreshListenable] needs a [Listenable], not a stream, so the
/// auth stream is adapted here once for the whole app instead of every screen
/// subscribing to `authStateChanges()` to decide where to go.
class AuthRefreshListenable extends ChangeNotifier {
  AuthRefreshListenable() {
    _subscription = authStateStream.listen(
      (_) => refresh(),
      onError: (Object error) {
        debugPrint('Auth stream error in router: $error');
      },
    );
  }

  late final StreamSubscription<User?> _subscription;

  /// Re-evaluates the router's redirect. Public because the gate calls it when
  /// the mirrored auth state changes — `notifyListeners` is protected.
  void refresh() => notifyListeners();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// The singleton the router listens to.
final AuthRefreshListenable authRefreshListenable = AuthRefreshListenable();

/// The live auth stream, set by `main()` once Firebase is initialised.
///
/// A late-bound global rather than a provider read because the router is
/// constructed at library load time, before any `ProviderContainer` exists.
Stream<User?> _authStream = const Stream<User?>.empty();

/// Cached onboarding state — read once at startup, updated when the user
/// completes the welcome flow. Used synchronously in [authRedirect].
OnboardingSettings _onboarding = const OnboardingSettings();

/// Sets the cached onboarding state. Called after settings are loaded at
/// startup and whenever the onboarding flow completes.
void setOnboardingState(OnboardingSettings state) {
  _onboarding = state;
}

/// True once [connectAuthStream] has run — i.e. Firebase came up and a real
/// session may still be on its way.
bool _firebaseConnected = false;

/// Wires the router's auth source. Called once, right after
/// `Firebase.initializeApp()`.
void connectAuthStream(Stream<User?> stream) {
  _authStream = stream;
  _firebaseConnected = true;
  // The short deadline no longer applies: a real answer is guaranteed to
  // arrive, so arming a signed-out timeout here is what logged people out.
  _deadline?.cancel();
  _deadline = null;
  _startSafetyNet();
  authRefreshListenable.refresh();
}

/// Marks the auth state as resolved without a Firebase session.
///
/// Called when Firebase could not be initialised — no `google-services.json`,
/// a test host, or a failed `initializeApp()`. Without this the gate stays
/// "unresolved" until [_authResolveDeadline] elapses and every navigation is
/// bounced back to the splash screen in the meantime, which would strand the
/// app on a boot screen that never advances.
void resolveAuthWithoutFirebase() {
  if (_resolved) return;
  _currentUser = null;
  _resolved = true;
  _deadline?.cancel();
  _safetyNet?.cancel();
  authRefreshListenable.refresh();
}

/// Exposed so the listenable can subscribe before [connectAuthStream] runs.
Stream<User?> get authStateStream => _authStream;

/// The most recent auth state, mirrored so [authRedirect] can answer
/// synchronously — `redirect` is called during navigation and cannot await.
User? _currentUser;
bool _resolved = false;

/// The one-shot timer that resolves the gate as signed out when Firebase never
/// came up. Started lazily from [authRedirect] so the clock only runs once the
/// router is actually asking.
Timer? _deadline;

/// The long-stop for "Firebase is up but no auth event ever arrived".
Timer? _safetyNet;

/// Starts the resolve clock on first use.
///
/// Does nothing once Firebase is connected: the auth stream is guaranteed to
/// emit, so treating a slow first event as "signed out" is the bug that logged
/// people out. See [_authResolveDeadline].
void _startDeadline() {
  if (_firebaseConnected) return;
  _deadline ??= Timer(_authResolveDeadline, () {
    if (_resolved) return;
    // No auth event arrived and Firebase never reported itself ready. Treat as
    // signed out: the login screen is shown, and a real event still arrives
    // later and corrects the state through [publishAuthState].
    _currentUser = null;
    _resolved = true;
    authRefreshListenable.refresh();
  });
}

/// Arms the long-stop. Only reached from [connectAuthStream].
void _startSafetyNet() {
  _safetyNet ??= Timer(_authEventSafetyNet, () {
    if (_resolved) return;
    debugPrint(
      'No auth event within ${_authEventSafetyNet.inSeconds}s despite a live '
      'Firebase session; falling back to signed-out.',
    );
    _currentUser = null;
    _resolved = true;
    authRefreshListenable.refresh();
  });
}

/// Updates the mirrored state and tells the router to re-evaluate.
void publishAuthState(User? user) {
  _currentUser = user;
  _resolved = true;
  _deadline?.cancel();
  _safetyNet?.cancel();
  authRefreshListenable.refresh();
}

/// The gate.
///
/// Returns the route to go to, or null to allow the requested one. Every branch
/// is a redirect rather than a push so the back button cannot re-enter the
/// auth flow after signing in.
///
/// ### Signing in is required
///
/// The app is account-first: every chat, contact and profile document lives
/// under the signed-in uid, so a session is a prerequisite rather than an
/// optional extra. A signed-out user is therefore sent to the login screen from
/// anywhere, and only the splash and the auth routes themselves are reachable
/// without a session.
String? authRedirect(BuildContext context, GoRouterState state) {
  final String location = state.matchedLocation;
  final User? user = _currentUser;
  final bool onSplash = location == AppRoutes.splash;
  final bool isAuthRoute = _authRoutes.contains(location);

  // Before the first auth event arrives the app stays on the splash screen.
  // Redirecting here would flash the login screen on every cold start for a
  // user who is in fact signed in.
  if (!_resolved) {
    _startDeadline();
    return onSplash ? null : AppRoutes.splash;
  }

  if (user == null) {
    // Signed out. The splash hands off to the login screen, and every other
    // destination is redirected there. The signup route stays reachable so the
    // "Create an Account" link works.
    if (onSplash) return AppRoutes.login;
    return _signedOutRoutes.contains(location) ? null : AppRoutes.login;
  }

  // Signed in. There is no verification step left: email sign-in and its
  // link-based verification screen were removed on 2026-10-06, because the
  // confirmation link never arrived on a real device and left accounts created
  // but permanently unusable. Google is verified by Google; a phone account's
  // address is derived from the number (`AppConstants.phoneAuthEmailFor`) and
  // has no mailbox to confirm.
  //
  // A new account therefore lands on profile setup until the profile has a
  // name; a returning user goes straight through.
  //
  // Onboarding gate: first-time sign-in goes through language/country, then
  // the permission walk, and lands straight in the chat shell.
  //
  // Onboarding flow routes: the welcome screen, then the permission screen.
  // While onboarding is incomplete the flow is the only destination, and every
  // step of it must stay reachable so it can advance — requiring
  // `location == onboarding` here was what bounced the permission screen
  // straight to the chat shell.
  const Set<String> onboardingFlowRoutes = <String>{
    AppRoutes.onboarding,
    AppRoutes.permissionGrant,
  };
  if (!_onboarding.complete) {
    return onboardingFlowRoutes.contains(location)
        ? null
        : AppRoutes.onboarding;
  }
  if (location == AppRoutes.onboarding) {
    return AppRoutes.chats;
  }
  // The permission screen runs once, immediately after the welcome screen
  // completes, pushed imperatively by that screen. Let it finish rather than
  // bouncing the user mid-flow into the chat shell.
  if (location == AppRoutes.permissionGrant) {
    return null;
  }

  final bool profileIncomplete = (user.displayName ?? '').trim().isEmpty &&
      location != AppRoutes.profileSetup;

  if (isAuthRoute || onSplash) {
    // Never leave a signed-in user on a signed-out screen.
    if (_onboarding.complete && profileIncomplete) {
      return AppRoutes.profileSetup;
    }
    return _onboarding.complete ? AppRoutes.chats : AppRoutes.onboarding;
  }
  return null;
}

/// Kept for the splash screen, which needs to know whether to hand off.
bool get authResolved => _resolved;
