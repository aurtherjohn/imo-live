import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart';
import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/l10n.dart';
import '../../../core/widgets/brand_assets.dart';
import '../../../core/widgets/common_widgets.dart';
import 'auth_providers.dart';
import 'widgets/auth_widgets.dart';

/// Email verification.
///
/// ### What this screen is, and what it is not
///
/// It used to be an OTP screen — six digit boxes. That was wrong: Firebase's
/// `sendEmailVerification()` sends a **link**, not a code, so there was nothing
/// for those boxes to receive. A user could sit there typing a code that never
/// existed, with no way forward.
///
/// What replaces them is an honest description of the real flow:
///
///   1. the account exists but is not active;
///   2. a confirmation link is sitting in the user's inbox;
///   3. the link is what verifies the address — the app cannot do it;
///   4. the app finds out by asking the server (`user.reload()`), because the
///      click happens outside the process and cannot be observed directly.
///
/// So there is one job here: tell the user what to do, and watch for the flag
/// to flip. Two paths do the watching — a 5-second poll, and the "I've confirmed
/// my email" button for a user who does not want to wait for the next tick.
///
/// ### Why the route is still called `otp`
///
/// `AppRoutes.otp` and the auth gate's redirect both name this screen, and the
/// gate is what actually holds an unverified user here. Renaming the route
/// would mean touching the gate's route sets for a cosmetic gain, so the path
/// keeps its name while the screen no longer has anything to do with codes.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  /// Firebase throttles re-sends to roughly one a minute, so the cooldown
  /// matches it: a shorter button would just invite a request the backend
  /// refuses.
  static const int _resendSeconds = 60;

  /// How often the screen asks the server whether the address is verified yet.
  ///
  /// Five seconds is the balance this needs: fast enough that a user who
  /// confirms in their mail app and switches back sees the screen move on its
  /// own, slow enough that an idle screen is not a busy loop against the auth
  /// backend.
  static const Duration _pollInterval = Duration(seconds: 5);

  int _secondsLeft = _resendSeconds;
  Timer? _countdown;
  Timer? _poll;
  bool _checking = false;
  bool _resending = false;
  bool _verified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    // Poll from the moment the screen opens: the user may have already
    // confirmed in their mail client before this screen was even reached.
    _startPolling();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  /// Watches for the server-side verified flag flipping.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (Timer timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_verified) {
        timer.cancel();
        return;
      }
      // Never overlaps the manual check: both call `user.reload()`, and two
      // reloads in flight at once is a wasted round trip, not a faster answer.
      if (_checking) return;
      final bool done = await ref
          .read(authControllerProvider.notifier)
          .confirmEmailVerified();
      if (!mounted) return;
      if (done) _onVerified();
    });
  }

  Future<void> _onVerified() async {
    if (_verified) return;
    setState(() {
      _verified = true;
      _checking = false;
      _error = null;
    });
    _poll?.cancel();
    _countdown?.cancel();
    // Let the checkmark finish its scale-in before moving on, so the success
    // state is actually seen rather than being a single-frame flash.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    // The auth gate now routes to profile setup when the profile is
    // incomplete, and to the chat list otherwise.
    context.go(AppRoutes.profileSetup);
  }

  /// The manual "I've confirmed my email" path.
  Future<void> _checkNow() async {
    if (_verified || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final bool done = await ref
        .read(authControllerProvider.notifier)
        .confirmEmailVerified();

    if (!mounted) return;
    if (done) {
      await _onVerified();
      return;
    }
    setState(() {
      _checking = false;
      _error = context.l10n.emailNotConfirmedYet;
    });
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });

    final AuthOutcome outcome =
        await ref.read(authControllerProvider.notifier).resendVerification();

    if (!mounted) return;
    setState(() => _resending = false);
    if (outcome.isFailure) {
      iToast(context, outcome.error!, isError: true);
      return;
    }
    iToast(context, context.l10n.emailResent);
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final String email = ref.watch(verificationEmailProvider);

    return AuthScaffold(
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
                onPressed: () async {
                  await ref.read(authControllerProvider.notifier).signOut();
                  if (context.mounted) context.go(AppRoutes.login);
                },
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              child: Center(
                child: BrandIcon(
                  BrandAssets.mail,
                  size: 62,
                  color: AppColors.accent,
                  semanticLabel: 'Verify your email',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: Column(
                children: <Widget>[
                  Text(
                    context.l10n.verifyYourEmail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(text: context.l10n.weSentAConfirmationLinkTo),
                        TextSpan(
                          text: email.isEmpty ? 'your email' : email,
                          style: const TextStyle(
                            color: AppColors.accentLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ------------------------------------------------ instructions
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: _verified
                  ? const _SuccessCheck()
                  : const _InstructionsCard(),
            ),

            AnimatedSize(
              duration: AppDurations.fast,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.c.onDanger,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // ------------------------------------------------------ resend
            Center(
              child: _secondsLeft > 0
                  ? Text(
                      context.l10n.resendInS(_secondsLeft),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    )
                  : TextButton(
                      onPressed: _resending ? null : _resend,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.l10n.resendEmail,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentLight,
                        ),
                      ),
                    ),
            ),

            const Spacer(),
            const SizedBox(height: AppSpacing.lg),
            AuthPrimaryButton(
              label: context.l10n.iHaveConfirmedMyEmail,
              loading: _checking,
              icon: Icons.verified_rounded,
              onPressed: _verified ? null : _checkNow,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

/// The three-step explanation of what the user has to do.
///
/// A numbered card rather than a paragraph: the user is looking for the one
/// action they are missing, and three lines they can scan find it faster than
/// prose they have to read.
class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard();

  @override
  Widget build(BuildContext context) {
    final List<String> steps = <String>[
      context.l10n.openYourInboxAndClickLink,
      context.l10n.checkYourSpamFolder,
      context.l10n.returnToAppAfterConfirming,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: AppRadius.rLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < steps.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: AppColors.accentLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The scaled-in success state.
class _SuccessCheck extends StatelessWidget {
  const _SuccessCheck();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AppDurations.slow,
          curve: Curves.easeOutBack,
          builder: (BuildContext context, double value, Widget? child) =>
              Transform.scale(scale: value, child: child),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: kAuthPrimaryGradient,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.4),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}
