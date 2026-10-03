import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/theme/app_tokens.dart';
import '../services/in_app_oauth_service.dart';
import '../utils/l10n.dart';

/// A place for [InAppOAuthService] to find a live [BuildContext].
///
/// The service is a plain class invoked from `ref.read(...)`, so it has no
/// context of its own. Screens that offer Google sign-in publish theirs here
/// for the duration of a tap, which keeps the service free of any widget
/// dependency while still being able to present the sign-in sheet over the
/// screen the user is looking at.
class OAuthWebViewHost {
  const OAuthWebViewHost._();

  static BuildContext? _context;

  /// The context a sign-in sheet should be presented from, or null.
  static BuildContext? get context => _context;

  /// Runs [action] with [context] published, and always clears it afterwards so
  /// a disposed context is never reused by a later attempt.
  static Future<T> withContext<T>(
    BuildContext context,
    Future<T> Function() action,
  ) async {
    _context = context;
    try {
      return await action();
    } finally {
      _context = null;
    }
  }
}

/// The in-app OAuth window.
///
/// Presented as a modal bottom sheet over the login screen: the user never
/// leaves Imo LIVE, and the app's own chrome (close button, progress bar,
/// provider name) frames the provider's pages so it is obvious where they are.
class OAuthWebViewSheet extends StatefulWidget {
  const OAuthWebViewSheet({
    super.key,
    required this.controller,
    required this.provider,
    required this.progress,
    required this.canGoBack,
    required this.onCancel,
  });

  final WebViewController controller;
  final OAuthProvider provider;

  /// Page-load progress, 0–100.
  final int progress;

  /// Whether the embedded browser has somewhere to go back to.
  final bool canGoBack;
  final VoidCallback onCancel;

  @override
  State<OAuthWebViewSheet> createState() => _OAuthWebViewSheetState();
}

class _OAuthWebViewSheetState extends State<OAuthWebViewSheet> {
  String get _title => switch (widget.provider) {
        OAuthProvider.google => context.l10n.signInWithGoogle,
      };

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.of(context).size.height * 0.86;
    return SizedBox(
      height: height,
      child: Column(
        children: <Widget>[
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.thisWindowIsInsideImo,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.cancel,
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white70,
                ),
              ],
            ),
          ),
          if (widget.progress < 100)
            LinearProgressIndicator(
              value: widget.progress == 0 ? null : widget.progress / 100,
              minHeight: 2,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            )
          else
            const SizedBox(height: 2),
          Expanded(
            child: WebViewWidget(controller: widget.controller),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  if (widget.canGoBack)
                    TextButton.icon(
                      onPressed: () async {
                        await widget.controller.goBack();
                      },
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(context.l10n.back),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    context.l10n.secureSignIn,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
