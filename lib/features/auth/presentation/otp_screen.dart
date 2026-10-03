import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_color_scheme.dart';

import '../../../app/app.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/brand_assets.dart';
import '../../../core/widgets/common_widgets.dart';
import 'auth_providers.dart';
import 'widgets/auth_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Email verification.
///
/// Shown between signup and the rest of the app. The account exists but is not
/// active, so this screen is the gate: it re-sends the verification mail, polls
/// the server for the verified flag, and animates the outcome — a scaled-in
/// checkmark on success, a shake on a wrong or expired code.
///
/// The poll (rather than a deep link) is deliberate: an email link cannot be
/// observed from inside the app, and the honest question is simply "has the
/// server flipped the flag yet?".
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen>
    with SingleTickerProviderStateMixin {
  static const int _length = 6;
  static const int _resendSeconds = 30;

  final List<TextEditingController> _controllers =
      List<TextEditingController>.generate(_length, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List<FocusNode>.generate(_length, (_) => FocusNode());

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  int _secondsLeft = _resendSeconds;
  Timer? _countdown;
  Timer? _poll;
  bool _verifying = false;
  bool _verified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    // Poll from the moment the screen opens: the user may confirm in their mail
    // client and come straight back.
    _startPolling();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _poll?.cancel();
    _shake.dispose();
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    for (final FocusNode f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((TextEditingController c) => c.text).join();

  bool get _isComplete => _code.length == _length;

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
    _poll = Timer.periodic(const Duration(seconds: 3), (Timer timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_verified) {
        timer.cancel();
        return;
      }
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
      _verifying = false;
      _error = null;
    });
    _poll?.cancel();
    // Let the checkmark finish its scale-in before moving on, so the success
    // state is actually seen rather than being a single-frame flash.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    // The auth gate now routes to profile setup when the profile is
    // incomplete, and to the chat list otherwise.
    context.go(AppRoutes.profileSetup);
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _verifying = false;
    });
    _shake.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  Future<void> _verify() async {
    if (!_isComplete) {
      _fail('Enter all $_length digits from the email.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });

    final bool done = await ref
        .read(authControllerProvider.notifier)
        .confirmEmailVerified();

    if (!mounted) return;
    if (done) {
      _onVerified();
      return;
    }
    _fail(
      'That code isn\'t confirmed yet. Tap the link in your email, then try '
      'again.',
    );
  }

  Future<void> _resend() async {
    final AuthOutcome outcome =
        await ref.read(authControllerProvider.notifier).resendVerification();
    if (!mounted) return;
    if (outcome.isFailure) {
      iToast(context, outcome.error!, isError: true);
      return;
    }
    iToast(context, context.l10n.aNewCodeIsOn);
    _startCountdown();
  }

  void _onDigitChanged(int index, String value) {
    // Pasting the whole code lands in the first box; distribute it.
    if (value.length > 1) {
      final String digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < _length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final int next = digits.length.clamp(0, _length - 1);
      _focusNodes[next].requestFocus();
      setState(() => _error = null);
      if (_isComplete) _verify();
      return;
    }

    setState(() => _error = null);
    if (value.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_isComplete) _verify();
  }

  /// Backspace in an empty box steps back rather than doing nothing.
  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_controllers[index].text.isEmpty && index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() => _error = null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
            const SizedBox(height: AppSpacing.xxl),
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
                    style: TextStyle(
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
                        TextSpan(text: context.l10n.weSentACodeTo),
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
            const SizedBox(height: AppSpacing.xxxl),

            // ------------------------------------------------- otp boxes
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: _verified
                  ? const _SuccessCheck()
                  : AnimatedBuilder(
                      animation: _shake,
                      builder: (BuildContext context, Widget? child) {
                        // A damped horizontal shake: four decreasing swings
                        // read as "no" without the violence of a full-amplitude
                        // oscillation.
                        final double t = _shake.value;
                        final double offset = _error == null
                            ? 0
                            : (1 - t) *
                                12 *
                                (t < 0.5
                                    ? (t * 8).round().isEven ? 1 : -1
                                    : (t * 8).round().isOdd ? 1 : -1);
                        return Transform.translate(
                          offset: Offset(offset, 0),
                          child: child,
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          for (int i = 0; i < _length; i++)
                            _OtpBox(
                              controller: _controllers[i],
                              focusNode: _focusNodes[i],
                              hasError: _error != null,
                              enabled: !_verifying,
                              onChanged: (String v) => _onDigitChanged(i, v),
                              onKey: (KeyEvent event) => _onKey(i, event),
                            ),
                        ],
                      ),
                    ),
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

            const SizedBox(height: AppSpacing.xxl),

            // Not a code field — an email confirmation link — so be explicit
            // about what "verify" checks.
            Text(
              context.l10n.openTheLinkInThe2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

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
                      onPressed: _resend,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.l10n.resendNow,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentLight,
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: AppSpacing.xl),
            AuthPrimaryButton(
              label: context.l10n.verify,
              loading: _verifying,
              icon: Icons.verified_rounded,
              onPressed: _verified ? null : _verify,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

/// One digit of the code.
class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.enabled,
    required this.onChanged,
    required this.onKey,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(KeyEvent) onKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 58,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: AppRadius.rMd,
          border: Border.all(
            color: hasError
                ? context.c.onDanger
                : focusNode.hasFocus
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.12),
            width: focusNode.hasFocus || hasError ? 1.6 : 1,
          ),
        ),
        child: Focus(
          onKeyEvent: (FocusNode node, KeyEvent event) => onKey(event),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: false,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            cursorColor: AppColors.accent,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: onChanged,
          ),
        ),
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
      height: 58,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AppDurations.slow,
          curve: Curves.easeOutBack,
          builder: (BuildContext context, double value, Widget? child) =>
              Transform.scale(scale: value, child: child),
          child: Container(
            width: 58,
            height: 58,
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
              size: 34,
            ),
          ),
        ),
      ),
    );
  }
}
