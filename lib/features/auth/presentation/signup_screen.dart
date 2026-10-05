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
import 'widgets/signup_error_dialog.dart';
import '../../../core/utils/l10n.dart';

/// Account creation, in the same luxury style as the login screen.
///
/// On success the user is routed to the OTP screen rather than straight into
/// the app: the account exists but is not active until the email is verified.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  bool _googleBusy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _anyBusy => _busy || _googleBusy;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final AuthOutcome outcome =
        await ref.read(authControllerProvider.notifier).signUpWithEmail(
              name: _name.text,
              email: _email.text,
              password: _password.text,
            );

    if (!mounted) return;
    setState(() => _busy = false);

    if (outcome.isFailure) {
      setState(() => _error = outcome.error);
      iToast(context, outcome.error!, isError: true);
      // The dialog carries the tail of the log buffer. A failed verification
      // *send* is not a failure of `signUpWithEmail` at all — the account is
      // created and the user is routed to the verify screen — so this is the
      // path for "the account itself could not be made".
      await showSignupError(context, outcome.error!);
      return;
    }
    if (outcome.needsVerification) {
      // The router's gate has already swapped in the OTP screen; passing the
      // address through so the screen can name it is handled by the provider.
      ref.read(pendingVerificationEmailProvider.notifier).state =
          _email.text.trim();
    }
  }

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
      child: Form(
        key: _formKey,
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
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                delay: const Duration(milliseconds: 130),
                child: AuthDivider(label: context.l10n.orSignUpWithEmail),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ----------------------------------------------------- form
              FadeSlideIn(
                delay: const Duration(milliseconds: 160),
                child: AuthField(
                  controller: _name,
                  hint: context.l10n.fullName,
                  iconAsset: BrandAssets.userCheck,
                  capitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.name],
                  enabled: !_anyBusy,
                  validator: (String? value) {
                    if ((value ?? '').trim().length < 2) {
                      return 'Enter your name';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                delay: const Duration(milliseconds: 190),
                child: AuthField(
                  controller: _email,
                  hint: context.l10n.emailAddress,
                  iconAsset: BrandAssets.mail,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.email],
                  enabled: !_anyBusy,
                  validator: (String? value) {
                    final String v = (value ?? '').trim();
                    if (v.isEmpty) return 'Enter your email address';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                      return 'That email address doesn\'t look right';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                delay: const Duration(milliseconds: 220),
                child: AuthField(
                  controller: _password,
                  hint: context.l10n.password,
                  iconAsset: BrandAssets.lock,
                  obscure: _obscure,
                  enabled: !_anyBusy,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.newPassword],
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                  validator: (String? value) {
                    if ((value ?? '').length < 6) {
                      return 'Use at least 6 characters';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                delay: const Duration(milliseconds: 245),
                child: AuthField(
                  controller: _confirm,
                  hint: context.l10n.confirmPassword,
                  iconAsset: BrandAssets.lock,
                  obscure: _obscureConfirm,
                  enabled: !_anyBusy,
                  textInputAction: TextInputAction.done,
                  onToggleObscure: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  onSubmitted: (_) => _submit(),
                  validator: (String? value) {
                    if ((value ?? '') != _password.text) {
                      return 'Passwords don\'t match';
                    }
                    return null;
                  },
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
                            color:
                                AppColors.danger.withValues(alpha: 0.12),
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
              FadeSlideIn(
                delay: const Duration(milliseconds: 270),
                child: AuthPrimaryButton(
                  label: context.l10n.createAccount,
                  loading: _busy,
                  onPressed: _anyBusy ? null : _submit,
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
      ),
    );
  }
}
