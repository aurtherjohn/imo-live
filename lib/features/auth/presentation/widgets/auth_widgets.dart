import 'package:flutter/material.dart';
import '../../../../app/theme/app_color_scheme.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/widgets/brand_assets.dart';

/// The shared look of the auth screens.
///
/// Login, signup and OTP are three steps of one flow, so they share a palette,
/// a background treatment and a set of controls rather than each inventing
/// their own. Everything here is self-contained and hard-coded to the brand
/// dark surface: the auth screens are shown *before* the user has any settings,
/// so they must not depend on the persisted theme (which may be light).

// ---------------------------------------------------------------- palette

/// Near-black page background with the brand glow behind the header.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.showGlow = true,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget child;
  final bool showGlow;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: Stack(
        children: <Widget>[
          if (showGlow) ...<Widget>[
            // A soft halo behind the logo, plus a second, much dimmer one low
            // down. Two light sources stop the page reading as flat. Both use
            // the mark's own hues rather than the UI accent — the logo sits on
            // top of them, and a pink halo under a blue/green mark reads as two
            // different brands.
            Positioned(
              top: -140,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 420,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.35),
                      radius: 0.75,
                      colors: <Color>[
                        AppColors.brandBlue.withValues(alpha: 0.24),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -180,
              left: -80,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  height: 380,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.7,
                      colors: <Color>[
                        AppColors.brandGreen.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          // The whole page is scrollable: with a software keyboard open on a
          // short device, the form is taller than the viewport and would
          // otherwise overflow.
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    // `IntrinsicHeight` is what makes `Spacer()` legal inside
                    // the page's Column. A scroll view hands its child an
                    // unbounded height, and a flex child (Spacer/Expanded) in an
                    // unbounded Column asserts:
                    //
                    //   "RenderFlex children have non-zero flex but incoming
                    //    height constraints are unbounded"
                    //
                    // IntrinsicHeight measures the content, then imposes a
                    // *finite* height of max(content, viewport), so the Spacer
                    // has something to divide up — and the page still scrolls
                    // when the keyboard makes the content taller than the
                    // screen.
                    child: IntrinsicHeight(child: child),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The pink gradient fill shared by every primary action in the flow.
const LinearGradient kAuthPrimaryGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: <Color>[AppColors.accentLight, AppColors.accent, AppColors.accentDark],
);

/// Full-width primary button with the brand gradient and an inline spinner.
///
/// The spinner replaces the label in place, which keeps the button the same
/// size while the request is in flight — a button that resizes mid-tap reads as
/// a glitch.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    return AnimatedOpacity(
      duration: AppDurations.fast,
      opacity: enabled ? 1 : 0.55,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: kAuthPrimaryGradient,
            borderRadius: AppRadius.rPill,
            boxShadow: enabled
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.38),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: AppRadius.rPill,
              onTap: enabled ? onPressed : null,
              child: Center(
                child: AnimatedSwitcher(
                  duration: AppDurations.fast,
                  child: loading
                      ? const SizedBox(
                          key: ValueKey<String>('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Row(
                          key: const ValueKey<String>('label'),
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (icon != null) ...<Widget>[
                              Icon(icon, size: 19, color: Colors.white),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white, rounded provider button.
///
/// Either a vector brand mark ([logoAsset]) or a plain [icon] leads the label —
/// the third-party providers ship artwork, while a first-party option like phone
/// sign-in has nothing to draw and uses a Material glyph.
///
/// Deliberately **not** wrapped in `Expanded`: it sizes to whatever the parent
/// gives it, so it can be a full-width row in a stretched `Column` or one half
/// of a `Row` (the caller wraps it). Baking the `Expanded` in here meant the
/// button could not be used outside a `Row` at all.
class AuthProviderButton extends StatelessWidget {
  const AuthProviderButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.logoAsset,
    this.icon,
    this.loading = false,
  }) : assert(
          logoAsset != null || icon != null,
          'AuthProviderButton needs a logoAsset or an icon',
        );

  final String label;
  final String? logoAsset;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.rMd,
          border: Border.all(color: Colors.white24, width: 0.8),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.rMd,
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (loading)
                    const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.accent),
                      ),
                    )
                  else if (icon != null)
                    Icon(icon, size: 20, color: const Color(0xFF1F1F23))
                  else
                    BrandIcon(logoAsset!, size: 21),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F1F23),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The `─── Or continue with email ───` rule between providers and the form.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final Color line = Colors.white.withValues(alpha: 0.14);
    return Row(
      children: <Widget>[
        Expanded(child: Container(height: 1, color: line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: line)),
      ],
    );
  }
}

/// A labelled input with an SVG leading icon and an optional trailing action.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.iconAsset,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.textInputAction,
    this.capitalization = TextCapitalization.none,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.focusNode,
    this.prefixText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String iconAsset;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization capitalization;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final FocusNode? focusNode;
  final String? prefixText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: capitalization,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      cursorColor: AppColors.accent,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        prefixText: prefixText,
        prefixStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 10),
          child: BrandIcon(
            iconAsset,
            size: 19,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: onToggleObscure == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  tooltip: obscure ? 'Show password' : 'Hide password',
                  onPressed: onToggleObscure,
                  icon: BrandIcon(
                    obscure ? BrandAssets.eyeOff : BrandAssets.eye,
                    size: 19,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
        suffixIconConstraints:
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
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
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

/// The `Don't have an account? Create one` footer line.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // `Wrap`, not `Row`: the two labels are both unbounded text, so a `Row`
    // overflows as soon as they do not fit on one line — which happens at large
    // accessibility text scales and in longer localisations. Wrapping keeps the
    // sentence readable instead of painting it outside the screen.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 5,
      children: <Widget>[
        Text(
          prompt,
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Text(
            action,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.accentLight,
            ),
          ),
        ),
      ],
    );
  }
}
