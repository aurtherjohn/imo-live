import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_color_scheme.dart';

import '../../../app/app.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/brand_assets.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/oauth_webview_sheet.dart';
import 'auth_providers.dart';
import 'widgets/auth_widgets.dart';
import '../../../core/utils/l10n.dart';

/// The sign-in screen.
///
/// Layout, top to bottom: brand lockup, the two provider buttons, the
/// "create an account" footer.
///
/// ### Why there is no email form
///
/// Email/password sign-in was removed on 2026-10-06. It was the only provider
/// whose flow depended on an emailed link arriving — and on a real device that
/// link never did, which left accounts created but permanently unverifiable.
/// Google and phone are the two flows that complete inside the app, so they are
/// the two the app offers. See `auth_gate.dart` for the matching redirect rule.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _googleBusy = false;
  String? _error;

  bool get _anyBusy => _googleBusy;

  Future<void> _google() async {
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    // The OAuth service presents its sheet from this screen's context.
    final AuthOutcome outcome = await OAuthWebViewHost.withContext(
      context,
      () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
    );
    if (!mounted) return;
    setState(() => _googleBusy = false);
    if (outcome.isFailure) {
      setState(() => _error = outcome.error);
      iToast(context, outcome.error!, isError: true);
    }
  }

  /// Opens the phone sign-in / sign-up flow.
  ///
  /// Pushed rather than routed: the phone screen is a sub-step of login, not a
  /// destination, and the auth gate would have to be told about a new
  /// signed-out route otherwise. It pops itself on success and the gate takes
  /// over from there.
  void _phone() {
    setState(() => _error = null);
    // Pushed as a real `go_router` route rather than a bare `Navigator.push`.
    //
    // This matters beyond the transition. `GoRouter`'s redirect only rewrites
    // locations it owns; a `MaterialPageRoute` pushed on top of the login route
    // is invisible to it, so when the auth state changed mid-signup the router
    // re-evaluated `/login` underneath and the pushed screen was left stacked
    // over a page that had already been replaced — the user saw the app for an
    // instant and then the login screen again. Registering the phone flow as a
    // route keeps the redirect and the visible screen in agreement.
    context.push(AppRoutes.phoneLogin);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xxl,
          AppSpacing.xxl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              child: const Center(child: BrandLockup(size: 86)),
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // ------------------------------------------------ providers
            //
            // Stacked full-width rather than side by side. With two options
            // left, a two-up row would truncate the phone label — Bengali
            // labels are longer than English ones, so that bites in `bn` first.
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AuthProviderButton(
                    label: context.l10n.google,
                    logoAsset: BrandAssets.google,
                    loading: _googleBusy,
                    onPressed: _anyBusy ? null : _google,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthProviderButton(
                    label: context.l10n.continueWithPhone,
                    icon: Icons.phone_rounded,
                    onPressed: _anyBusy ? null : _phone,
                  ),
                ],
              ),
            ),

            // Inline error, so the reason is still on screen after the toast
            // has gone.
            AnimatedSize(
              duration: AppDurations.fast,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: _InlineError(message: _error!),
                    ),
            ),

            const Spacer(),
            const SizedBox(height: AppSpacing.xl),
            AuthFooterLink(
              prompt: context.l10n.donTHaveAnAccount,
              action: 'Create an Account',
              onTap: _anyBusy
                  ? () {}
                  : () => context.push(AppRoutes.signup),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.byContinuingYouAgreeTo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dismissible inline error strip.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: context.c.onDanger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.c.onDanger,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
