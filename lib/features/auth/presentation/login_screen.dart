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
import 'screens/phone_login_screen.dart';
import 'widgets/auth_widgets.dart';
import '../../../core/utils/l10n.dart';

/// The sign-in screen.
///
/// Layout, top to bottom: brand lockup, the provider buttons, a divider, the
/// email form, and the "create an account" footer. Everything animates in on
/// first build so the screen assembles rather than appearing.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  bool _googleBusy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
        await ref.read(authControllerProvider.notifier).signInWithEmail(
              email: _email.text,
              password: _password.text,
            );

    if (!mounted) return;
    setState(() => _busy = false);

    if (outcome.isFailure) {
      setState(() => _error = outcome.error);
      iToast(context, outcome.error!, isError: true);
      return;
    }
    // The router's auth gate swaps to the home shell on its own once Firebase
    // emits the signed-in user; nothing to navigate here.
  }

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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const PhoneLoginScreen(),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    final String email = _email.text.trim();
    if (email.isEmpty) {
      iToast(context, context.l10n.enterYourEmailFirstThen,
          isError: true);
      return;
    }
    final String? message = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _EmailInputDialog(initial: email),
    );
    if (message == null || !mounted) return;
    try {
      await ref
          .read(firebaseAuthServiceProvider)
          .sendPasswordReset(message);
      if (!mounted) return;
      iToast(context, context.l10n.resetLinkSentTo(message));
    } on Object catch (error) {
      if (!mounted) return;
      iToast(context, '$error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Form(
        key: _formKey,
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
              // Stacked full-width rather than side by side. With one OAuth
              // provider left, a two-up row would have been a lone button
              // stretched to fill the row, and the phone option's label does
              // not fit a half-width button without truncating.
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

              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                delay: const Duration(milliseconds: 130),
                child: AuthDivider(label: context.l10n.orContinueWithEmail),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ----------------------------------------------------- form
              FadeSlideIn(
                delay: const Duration(milliseconds: 170),
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
                delay: const Duration(milliseconds: 200),
                child: AuthField(
                  controller: _password,
                  hint: context.l10n.password,
                  iconAsset: BrandAssets.lock,
                  obscure: _obscure,
                  enabled: !_anyBusy,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.password],
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                  onSubmitted: (_) => _submit(),
                  validator: (String? value) {
                    if ((value ?? '').isEmpty) return 'Enter your password';
                    return null;
                  },
                ),
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _anyBusy ? null : _forgotPassword,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    context.l10n.forgotPassword,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentLight,
                    ),
                  ),
                ),
              ),

              // Inline error, so the reason is still on screen after the toast
              // has gone.
              AnimatedSize(
                duration: AppDurations.fast,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _InlineError(message: _error!),
                      ),
              ),

              const SizedBox(height: AppSpacing.sm),
              FadeSlideIn(
                delay: const Duration(milliseconds: 240),
                child: AuthPrimaryButton(
                  label: context.l10n.login,
                  loading: _busy,
                  onPressed: _anyBusy ? null : _submit,
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

/// Collects (or confirms) an email address before sending a reset link.
class _EmailInputDialog extends StatefulWidget {
  const _EmailInputDialog({required this.initial});

  final String initial;

  @override
  State<_EmailInputDialog> createState() => _EmailInputDialogState();
}

class _EmailInputDialogState extends State<_EmailInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rLg),
      title: Text(
        context.l10n.resetPassword,
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.weLlEmailYouA,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            cursorColor: AppColors.accent,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: context.l10n.emailAddress,
              hintStyle: TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Color(0x14FFFFFF),
              border: OutlineInputBorder(
                borderRadius: AppRadius.rMd,
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            context.l10n.cancel,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: Text(
            context.l10n.sendLink,
            style: TextStyle(
              color: AppColors.accentLight,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
