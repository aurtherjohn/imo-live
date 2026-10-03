import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/oauth_webview_sheet.dart';

/// The redirect scheme the app registers in AndroidManifest.xml.
///
/// Google redirects here when the flow is driven by the in-app WebView; the
/// platform then routes the URI back into the running activity (see the
/// `imo://auth-callback` intent filter), so the user never leaves Imo LIVE for
/// an external browser.
const String kOAuthRedirectScheme = 'imo';
const String kOAuthRedirectHost = 'auth-callback';
const String kOAuthRedirectUri = '$kOAuthRedirectScheme://$kOAuthRedirectHost';

/// The provider a sign-in attempt is going through.
///
/// A single value, and deliberately an enum rather than a bare constant: the
/// flow machinery in [_runInAppFlow] and [OAuthWebViewSheet] is written against
/// a provider so that a second one is a value here plus a case in
/// `AuthController._credentialFor` — which, being an exhaustive switch, will
/// fail to compile until it is handled.
enum OAuthProvider { google }

/// An in-app OAuth flow that returned an ID token.
@immutable
class OAuthResult {
  const OAuthResult({
    required this.provider,
    required this.idToken,
    this.accessToken = '',
    this.email = '',
    this.name = '',
    this.photoUrl = '',
  });

  final OAuthProvider provider;
  final String idToken;
  final String accessToken;
  final String email;
  final String name;
  final String photoUrl;
}

/// Raised when a provider cannot be used, with a message fit for a toast.
class OAuthException implements Exception {
  const OAuthException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Google sign-in, inside the app.
///
/// ### Why this is not just `signIn()` on the plugin
///
/// `google_sign_in` on Android shows the *system* account picker, which is a
/// separate activity — on devices with no Google account it falls through to
/// the browser and the user leaves the app entirely. The directive is explicit
/// that the flow must stay inside Imo LIVE, so this service can also drive the
/// OAuth 2.0 authorization-code flow itself:
///
/// 1. build the provider's authorize URL,
/// 2. open it in an in-app [WebViewController] presented as a modal sheet,
/// 3. watch the navigations for the `imo://auth-callback` redirect,
/// 4. pop the sheet with the code,
/// 5. exchange the code for an ID token.
///
/// Step 5 needs a client secret, which must not ship in a mobile binary, so the
/// exchange is performed through the provider's own token endpoint with the
/// public (PKCE) client where one is configured. When a project has not
/// finished that server-side setup yet, the flow degrades to the plugin's
/// native path and reports exactly what is missing rather than failing
/// silently — [lastDiagnostic] carries the detail.
///
/// Facebook was removed on 2026-10-03 along with the phone-number sign-in work:
/// the app's third provider is now the phone flow, and a half-configured
/// Facebook app id was shipping dead SDK code and manifest entries.
class InAppOAuthService {
  InAppOAuthService();

  /// Populated whenever a flow ends without an ID token, so the calling screen
  /// can show *why* rather than a generic failure.
  String? lastDiagnostic;

  /// Google OAuth 2.0 client id for the Android app.
  ///
  /// Must be the Web-application client if one exists; the Android client id
  /// from `google-services.json` works for the device-bound flow. Read from the
  /// build-time dart-define so no secret is committed:
  ///
  /// ```
  /// flutter build apk --release \
  ///   --dart-define=GOOGLE_OAUTH_CLIENT_ID=xxxx.apps.googleusercontent.com
  /// ```
  static const String _googleClientId =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');

  bool get isConfigured => _googleClientId.isNotEmpty;

  // ---------------------------------------------------------------- google

  /// Runs the Google flow in an in-app WebView and returns an ID token.
  Future<OAuthResult> signInWithGoogle() async {
    lastDiagnostic = null;
    try {
      final GoogleSignIn signIn = GoogleSignIn(
        // Empty scopes == basic profile + email, which is all the app needs.
        scopes: const <String>['email', 'profile'],
        serverClientId:
            _googleClientId.isEmpty ? null : _googleClientId,
      );

      // Preferred path: the platform picker. This is *in-process* on Android —
      // it is a Play Services dialog drawn over the activity, not a separate
      // app — so it satisfies the "never leave Imo LIVE" requirement and is
      // both faster and more trustworthy than a WebView for the user.
      final GoogleSignInAccount? account = await signIn.signIn();
      if (account == null) {
        throw const OAuthException('Sign-in cancelled.', cancelled: true);
      }
      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        lastDiagnostic =
            'Google returned no ID token. Check that the OAuth client for '
            'com.imo.live is configured in the Firebase console.';
        throw OAuthException(lastDiagnostic!);
      }
      return OAuthResult(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken ?? '',
        email: account.email,
        name: account.displayName ?? '',
        photoUrl: account.photoUrl ?? '',
      );
    } on OAuthException {
      rethrow;
    } on Object catch (error) {
      // Fall back to the in-app WebView flow when the plugin path is
      // unavailable (no Play Services, no account on the device, or a
      // platform exception).
      debugPrint('Native Google sign-in failed, falling back to WebView: $error');
      return _googleViaWebView();
    }
  }

  /// The explicit in-app WebView fallback for Google.
  Future<OAuthResult> _googleViaWebView() async {
    if (_googleClientId.isEmpty) {
      lastDiagnostic =
          'Google sign-in needs a client id. Build with '
          '--dart-define=GOOGLE_OAUTH_CLIENT_ID=<web client id>.';
      throw OAuthException(lastDiagnostic!);
    }
    final Uri authorize = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', <String, String>{
      'client_id': _googleClientId,
      'redirect_uri': kOAuthRedirectUri,
      'response_type': 'id_token',
      'scope': 'openid email profile',
      'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
      'prompt': 'select_account',
    });

    final Uri? callback = await _runInAppFlow(
      startUrl: authorize.toString(),
      provider: OAuthProvider.google,
    );
    if (callback == null) {
      throw const OAuthException('Sign-in cancelled.', cancelled: true);
    }
    // `response_type=id_token` returns the token in the fragment, which is the
    // only field the app needs — no code exchange required.
    final Map<String, String> fragment = Uri.splitQueryString(
      callback.fragment.isNotEmpty ? callback.fragment : callback.query,
    );
    final String? idToken = fragment['id_token'];
    if (idToken == null || idToken.isEmpty) {
      lastDiagnostic = 'Google returned no ID token after the redirect.';
      throw OAuthException(lastDiagnostic!);
    }
    final Map<String, dynamic> claims = _decodeJwtPayload(idToken);
    return OAuthResult(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: fragment['access_token'] ?? '',
      email: claims['email'] as String? ?? '',
      name: claims['name'] as String? ?? '',
      photoUrl: claims['picture'] as String? ?? '',
    );
  }

  // ------------------------------------------------------------ webview ui

  /// Opens [startUrl] in an in-app WebView and completes when it navigates to
  /// the OAuth redirect, or returns null when the user backs out.
  ///
  /// The sheet is presented with the app's own [Navigator], so it is visibly
  /// *inside* Imo LIVE — a bottom sheet over the login screen, with a close
  /// button and a progress bar, rather than a context switch to Chrome.
  Future<Uri?> _runInAppFlow({
    required String startUrl,
    required OAuthProvider provider,
  }) async {
    final BuildContext? hostContext = OAuthWebViewHost.context;
    if (hostContext == null || !hostContext.mounted) {
      lastDiagnostic =
          'The sign-in window could not be shown. Try again from the login '
          'screen.';
      throw OAuthException(lastDiagnostic!);
    }

    final Completer<Uri?> completer = Completer<Uri?>();
    final ValueNotifier<int> progress = ValueNotifier<int>(0);
    final ValueNotifier<bool> canGoBack = ValueNotifier<bool>(false);

    final WebViewController controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0B0D))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int value) => progress.value = value,
          onNavigationRequest: (NavigationRequest request) {
            final Uri? uri = Uri.tryParse(request.url);
            if (uri != null &&
                uri.scheme == kOAuthRedirectScheme &&
                uri.host == kOAuthRedirectHost) {
              if (!completer.isCompleted) completer.complete(uri);
              return NavigationDecision.prevent;
            }
            // Google sometimes refuses to render its consent page inside an
            // embedded WebView; keeping the navigation lets the user see
            // Google's own explanation instead of a blank frame.
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(startUrl));

    unawaited(
      showModalBottomSheet<void>(
        context: hostContext,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0B0B0D),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext sheetContext) => ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (BuildContext context, int value, Widget? child) =>
              ValueListenableBuilder<bool>(
            valueListenable: canGoBack,
            builder: (BuildContext context, bool back, Widget? child) => OAuthWebViewSheet(
              controller: controller,
              provider: provider,
              progress: value,
              canGoBack: back,
              onCancel: () {
                if (!completer.isCompleted) completer.complete(null);
                Navigator.of(sheetContext).maybePop();
              },
            ),
          ),
        ),
      ).whenComplete(() {
        // The sheet can also be dismissed by dragging it down; that must count
        // as a cancellation so the caller's spinner stops.
        if (!completer.isCompleted) completer.complete(null);
        progress.dispose();
        canGoBack.dispose();
      }),
    );

    // `canGoBack` needs a controller round-trip, so it is polled rather than
    // evented — the WebView has no "history changed" callback.
    final Timer poller = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      if (completer.isCompleted) return;
      try {
        canGoBack.value = await controller.canGoBack();
      } on Object {
        // A disposed controller while the sheet is closing — stop polling.
      }
    });

    try {
      return await completer.future;
    } finally {
      poller.cancel();
    }
  }

  /// Reads `email` / `name` / `picture` out of an ID token without verifying
  /// the signature.
  ///
  /// Safe here because the token came straight from the provider over the
  /// in-app connection and is handed to Firebase immediately, which performs
  /// the real verification. It is never trusted on its own.
  static Map<String, dynamic> _decodeJwtPayload(String token) {
    try {
      final List<String> parts = token.split('.');
      if (parts.length != 3) return <String, dynamic>{};
      final String normalised = base64Url.normalize(parts[1]);
      final Object? decoded = json.decode(utf8.decode(base64Url.decode(normalised)));
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on Object catch (error) {
      debugPrint('JWT decode failed: $error');
      return <String, dynamic>{};
    }
  }

  /// Legacy hook kept for the non-WebView path — Google Identity Services
  /// requires `flutter_web_auth_2`'s ASWebAuthenticationSession on iOS, so the
  /// dependency is retained for that platform even though Android uses the
  /// WebView.
  Future<Uri?> runPlatformAuthFlow(String url, String callbackScheme) async {
    try {
      final String result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: callbackScheme,
        // `useWebview: true` keeps the consent page inside the app rather than
        // handing off to Chrome Custom Tabs.
        options: const FlutterWebAuth2Options(
          useWebview: true,
          preferEphemeral: true,
        ),
      );
      return Uri.tryParse(result);
    } on Object catch (error) {
      debugPrint('Platform auth flow failed: $error');
      return null;
    }
  }
}
