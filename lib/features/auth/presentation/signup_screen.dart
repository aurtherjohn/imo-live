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
import 'widgets/auth_settings_button.dart';
import 'widgets/auth_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Account creation, in the same style as the login screen.
///
/// ### Why there is no email form
///
/// Email/password sign-up was removed on 2026-10-06, together with the
/// verification screen it led to. Creating the account worked; the emailed
/// confirmation link never arrived on a real device, so the account was created
/// and then permanently unverifiable. Google and phone both complete inside the
/// app, so those are the two ways in.
///
/// There is no verification step to hand off to any more: a Google account is
/// verified by Google, and a phone account's derived address has no mailbox to
/// confirm. The auth gate therefore sends a new user straight on — to profile
/// setup if the profile has no name yet, otherwise into the app.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  bool _googleBusy = false;
  String? _error;

  bool get _anyBusy => _googleBusy;

  Future<void> _google() async {
    setState(() {
      _googleBusy = true;
      _error = null;
    });
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
    // Otherwise the auth gate takes over; a Google account arrives verified.
  }

  /// Opens the phone flow, which starts on its "Create Account" half — the same
  /// thing this screen does, minus the email address.
  void _phone() {
    setState(() => _error = null);
    // A real route, not a bare `Navigator.push` — see the note in
    // `login_screen.dart::_phone`. A pushed `MaterialPageRoute` is invisible to
    // the router's redirect, which is what let the auth change replace the page
    // underneath and bounce the user back to login.
    context.push(AppRoutes.phoneLogin);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      topRight: const AuthSettingsButton(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: context.l10n.back,
                onPressed: _anyBusy
                    ? null
                    : () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.login);
                        }
                      },
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FadeSlideIn(
              child: Center(
                child: BrandLockup(
                  size: 72,
                  showTagline: false,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: Column(
                children: <Widget>[
                  Text(
                    context.l10n.createAccount,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.joinImoLIVEInA,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ------------------------------------------------ providers
            FadeSlideIn(
              delay: const Duration(milliseconds: 90),
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

            AnimatedSize(
              duration: AppDurations.fast,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm + 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: AppRadius.rMd,
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.4),
                          ),
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
                                _error!,
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
                      ),
                    ),
            ),

            const SizedBox(height: AppSpacing.xl),
            AuthFooterLink(
              prompt: context.l10n.alreadyHaveAnAccount,
              action: 'Login',
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.login);
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
