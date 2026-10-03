import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app.dart';
import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/country.dart';
import '../../../../core/utils/l10n.dart';
import '../../../../core/widgets/brand_assets.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../auth_providers.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/country_picker_sheet.dart';

/// Which half of the phone flow the screen is showing.
enum PhoneAuthMode {
  /// Creating a new account: names, an optional handle, a PIN.
  signUp,

  /// Returning to an existing account: just the number and the PIN.
  login,
}

/// Phone-number sign-in and sign-up.
///
/// ### Why this is not Firebase's phone auth
///
/// There is no SMS step. The number and a PIN are the credential, and the PIN is
/// handed to the ordinary email/password provider under an address *derived from
/// the number* — see `AppConstants.phoneAuthEmailFor` and
/// `FirebaseAuthService.signUpWithPhone` for the full reasoning, including why
/// the requested client-side `passwordHash` + `salt` design was rejected.
///
/// ### Navigation
///
/// Pushed with a plain [Navigator] rather than registered as a `go_router`
/// route. That is deliberate: the auth gate owns which routes a signed-out user
/// may reach, and adding a route here would mean widening `_signedOutRoutes` for
/// what is really a sub-step of the login screen. On success the screen pops
/// itself and the gate — which has already been told about the new session by
/// `authRefreshListenable` — swaps `/login` for the chat shell underneath.
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _first = TextEditingController();
  final TextEditingController _last = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _pin = TextEditingController();

  Country _country = Countries.defaultCountry;
  PhoneAuthMode _mode = PhoneAuthMode.signUp;
  bool _obscurePin = true;
  bool _busy = false;
  String? _error;

  /// The numeric tail of the suggested handle.
  ///
  /// Rolled once, when the screen is built, and then held. Deriving it per
  /// keystroke would make the suggestion flicker a different number on every
  /// letter typed, which reads as a bug rather than a suggestion.
  late final String _suggestedSuffix =
      (Random.secure().nextInt(900) + 100).toString();

  @override
  void dispose() {
    _phone.dispose();
    _first.dispose();
    _last.dispose();
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  /// `tanvir.ahmed482` for "Tanvir" + "Ahmed", or empty while both are blank.
  String get _suggestedUsername {
    String slug(String raw) =>
        raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final String first = slug(_first.text);
    final String last = slug(_last.text);
    final String base = <String>[
      if (first.isNotEmpty) first,
      if (last.isNotEmpty) last,
    ].join('.');
    if (base.isEmpty) return '';
    final String trimmed = base.length > 18 ? base.substring(0, 18) : base;
    return '$trimmed$_suggestedSuffix';
  }

  /// The E.164 digits — country code plus national number, no `+`.
  String get _fullDigits {
    String digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final String dial = _country.dialCode;
    // A pasted international number already carries the code. Treated as such
    // only when what follows is a plausible national number, so a short local
    // number that happens to begin with the same digits is not mistaken for one.
    final bool alreadyInternational = digits.startsWith(dial) &&
        digits.length - dial.length >= 6 &&
        digits.length <= 15;
    if (alreadyInternational) return digits;
    // E.164 conversion drops the national trunk prefix — `01712345678` in
    // Bangladesh is `+8801712345678`, not `+88001712345678`.
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '$dial$digits';
  }

  Future<void> _pickCountry() async {
    final Country? picked =
        await showCountryPicker(context, selected: _country);
    if (picked == null || !mounted) return;
    setState(() => _country = picked);
  }

  void _setMode(PhoneAuthMode mode) {
    if (_mode == mode || _busy) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final String digits = _fullDigits;
    final AuthController controller = ref.read(authControllerProvider.notifier);

    final AuthOutcome outcome = _mode == PhoneAuthMode.signUp
        ? await controller.signUpWithPhone(
            phoneDigits: digits,
            pin: _pin.text,
            firstName: _first.text,
            lastName: _last.text,
            // An empty field means "use the suggestion", so the handle the user
            // just saw is the handle they get.
            username: _username.text.trim().isEmpty
                ? _suggestedUsername
                : _username.text,
          )
        : await controller.signInWithPhone(
            phoneDigits: digits,
            pin: _pin.text,
          );

    if (!mounted) return;
    setState(() => _busy = false);

    if (outcome.isFailure) {
      setState(() => _error = outcome.error);
      iToast(context, outcome.error!, isError: true);
      return;
    }

    // Signed in. Drop this route so the gate's swap is what the user sees;
    // staying pushed would leave the phone form sitting on top of the app.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSignUp = _mode == PhoneAuthMode.signUp;
    return AuthScaffold(
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
                  onPressed: _busy
                      ? null
                      : () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FadeSlideIn(
                child: const Center(
                  child: BrandLockup(size: 64, showTagline: false),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: Column(
                  children: <Widget>[
                    Text(
                      context.l10n.phoneSignInTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.phoneSignInSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              FadeSlideIn(
                delay: const Duration(milliseconds: 90),
                child: _ModeSwitch(
                  mode: _mode,
                  enabled: !_busy,
                  onChanged: _setMode,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ------------------------------------------- country + number
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: _PhoneField(
                  controller: _phone,
                  country: _country,
                  enabled: !_busy,
                  onPickCountry: _pickCountry,
                  validator: (String? value) {
                    final String raw = (value ?? '').trim();
                    if (raw.isEmpty) return context.l10n.enterYourPhoneNumber;
                    final int length =
                        raw.replaceAll(RegExp(r'[^0-9]'), '').length;
                    if (length < 6 || length > 15) {
                      return context.l10n.enterAValidPhoneNumber;
                    }
                    return null;
                  },
                ),
              ),

              // ---------------------------------------------- signup extras
              AnimatedSize(
                duration: AppDurations.fast,
                child: !isSignUp
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: AuthField(
                                  controller: _first,
                                  hint: context.l10n.firstName,
                                  iconAsset: BrandAssets.userCheck,
                                  capitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  enabled: !_busy,
                                  validator: (String? value) {
                                    if ((value ?? '').trim().length < 2) {
                                      return context.l10n.enterYourFirstName;
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: AuthField(
                                  controller: _last,
                                  hint: context.l10n.lastName,
                                  iconAsset: BrandAssets.userCheck,
                                  capitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  enabled: !_busy,
                                  validator: (String? value) {
                                    if ((value ?? '').trim().isEmpty) {
                                      return context.l10n.enterYourLastName;
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AuthField(
                            controller: _username,
                            hint: context.l10n.username,
                            iconAsset: BrandAssets.userCheck,
                            textInputAction: TextInputAction.next,
                            enabled: !_busy,
                            // Rebuilds the suggestion as the names are typed.
                            onChanged: (_) => setState(() {}),
                            validator: (String? value) {
                              final String v =
                                  (value ?? '').trim().replaceAll('@', '');
                              if (v.isEmpty) return null; // optional
                              if (v.length < 3) {
                                return context.l10n.usernameInvalid;
                              }
                              if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(v)) {
                                return context.l10n.usernameInvalid;
                              }
                              return null;
                            },
                          ),
                          // Shown only while the field is empty. With a name
                          // typed it previews the handle that will be claimed;
                          // with nothing typed yet it explains the field
                          // instead, so the space is never wasted and never
                          // says the same thing twice.
                          if (_username.text.trim().isEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: <Widget>[
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _suggestedUsername.isEmpty
                                        ? context.l10n.usernameLeaveBlankToGenerate
                                        : '@$_suggestedUsername',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
              ),

              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                delay: const Duration(milliseconds: 160),
                child: AuthField(
                  controller: _pin,
                  hint: context.l10n.pin,
                  iconAsset: BrandAssets.lock,
                  obscure: _obscurePin,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onToggleObscure: () =>
                      setState(() => _obscurePin = !_obscurePin),
                  onSubmitted: (_) => _submit(),
                  validator: (String? value) {
                    final String v = (value ?? '').trim();
                    if (v.length < 6) return context.l10n.pinAtLeastSixDigits;
                    if (!RegExp(r'^[0-9]+$').hasMatch(v)) {
                      return context.l10n.pinAtLeastSixDigits;
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      context.l10n.pinStoredSecurely,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),

              AnimatedSize(
                duration: AppDurations.fast,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: _PhoneInlineError(message: _error!),
                      ),
              ),

              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                delay: const Duration(milliseconds: 200),
                child: AuthPrimaryButton(
                  label: isSignUp
                      ? context.l10n.createAccount
                      : context.l10n.loginWithPhone,
                  loading: _busy,
                  onPressed: _busy ? null : _submit,
                ),
              ),

              const Spacer(),
              const SizedBox(height: AppSpacing.xl),
              AuthFooterLink(
                prompt: isSignUp
                    ? context.l10n.alreadyHaveAnAccount
                    : context.l10n.donTHaveAnAccount,
                action: isSignUp ? context.l10n.login : context.l10n.createAccount,
                onTap: () => _setMode(
                  isSignUp ? PhoneAuthMode.login : PhoneAuthMode.signUp,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// The country selector and the number field, inside one bordered box.
///
/// One box rather than two side-by-side controls: the code and the number are a
/// single value, and two boxes with two borders read as two fields — which is
/// exactly the confusion that makes people re-type the country code.
class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.country,
    required this.validator,
    required this.onPickCountry,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Country country;
  final String? Function(String?) validator;
  final VoidCallback onPickCountry;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      // The number is digits and separators only; the keyboard cannot produce
      // letters, but a paste can.
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
        LengthLimitingTextInputFormatter(15),
      ],
      validator: validator,
      cursorColor: AppColors.accent,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
      ),
      decoration: InputDecoration(
        hintText: context.l10n.phoneNumberHint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
        ),
        prefixIcon: _CountryPrefix(
          country: country,
          enabled: enabled,
          onTap: onPickCountry,
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.055),
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
        border: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: AppColors.danger, width: 1.5),
        ),
        errorStyle: TextStyle(
          color: context.c.onDanger,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// `🇧🇩 +880 ⌄` — the tap target that opens the picker.
class _CountryPrefix extends StatelessWidget {
  const _CountryPrefix({
    required this.country,
    required this.onTap,
    this.enabled = true,
  });

  final Country country;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(width: 12),
        // A `GestureDetector` rather than an `InkWell`: the field's own fill is
        // drawn behind this, so an ink splash would be clipped oddly and the
        // tap target is small.
        GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            label: context.l10n.selectCountry,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(country.flag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 5),
                Text(
                  country.dial,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 1,
          height: 22,
          color: Colors.white.withValues(alpha: 0.12),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

/// `Create Account | Login` — the two halves of the phone flow.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.onChanged,
    this.enabled = true,
  });

  final PhoneAuthMode mode;
  final ValueChanged<PhoneAuthMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: AppRadius.rPill,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          _segment(context, PhoneAuthMode.signUp, context.l10n.createAccount),
          _segment(context, PhoneAuthMode.login, context.l10n.login),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, PhoneAuthMode value, String label) {
    final bool selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? () => onChanged(value) : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.1) : null,
            borderRadius: AppRadius.rPill,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline error strip, matching the one on the login screen.
class _PhoneInlineError extends StatelessWidget {
  const _PhoneInlineError({required this.message});

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
