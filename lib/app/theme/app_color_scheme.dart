import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Theme-aware colour lookup.
///
/// Widgets should read colours through `context.c` rather than hard-coding
/// palette entries, so light/dark switching is automatic.
@immutable
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  const AppColorScheme({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.card,
    required this.elevated,
    required this.divider,
    required this.bubbleIn,
    required this.bubbleOut,
    required this.textPrimary,
    required this.textSecondary,
    required this.textOnAccent,
    required this.accent,
    required this.inputFill,
    required this.overlay,
    required this.isDark,
    required this.onSuccess,
    required this.onWarning,
    required this.onInfo,
    required this.onDanger,
    required this.online,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color card;
  final Color elevated;
  final Color divider;
  final Color bubbleIn;
  final Color bubbleOut;
  final Color textPrimary;
  final Color textSecondary;
  final Color textOnAccent;
  final Color accent;
  final Color inputFill;
  final Color overlay;
  final bool isDark;

  /// Contrast-safe semantic foregrounds.
  ///
  /// Read these instead of `AppColors.success` / `.warning` / `.info` /
  /// `.danger` / `.online` whenever the colour is a **foreground** (an icon, a
  /// label, a dot). The raw palette entries are tuned for fills; as text on a
  /// white surface they measure 1.8–3.6 against a 4.5 requirement, so a green
  /// presence dot was effectively invisible in the light theme.
  ///
  /// As *fills* (a button background, a tinted chip) the raw palette is still
  /// correct — those are reported separately by `AppColors`.
  final Color onSuccess;
  final Color onWarning;
  final Color onInfo;
  final Color onDanger;
  final Color online;

  static const AppColorScheme dark = AppColorScheme(
    bg: AppColors.darkBg,
    surface: AppColors.darkSurface,
    surfaceAlt: AppColors.darkSurfaceAlt,
    card: AppColors.darkCard,
    elevated: AppColors.darkElevated,
    divider: AppColors.darkDivider,
    bubbleIn: AppColors.darkBubbleIn,
    bubbleOut: AppColors.darkBubbleOut,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textOnAccent: Colors.white,
    accent: AppColors.accent,
    inputFill: AppColors.darkSurfaceAlt,
    overlay: Color(0x99000000),
    isDark: true,
    onSuccess: AppColors.darkSuccessFg,
    onWarning: AppColors.darkWarningFg,
    onInfo: AppColors.darkInfoFg,
    onDanger: AppColors.darkDangerFg,
    online: AppColors.darkOnlineFg,
  );

  static const AppColorScheme light = AppColorScheme(
    bg: AppColors.lightBg,
    surface: AppColors.lightSurface,
    surfaceAlt: AppColors.lightSurfaceAlt,
    card: AppColors.lightCard,
    elevated: AppColors.lightElevated,
    divider: AppColors.lightDivider,
    bubbleIn: AppColors.lightBubbleIn,
    bubbleOut: AppColors.lightBubbleOut,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textOnAccent: Colors.white,
    // ⚠️ NOT `AppColors.accent` — the brand #FF2D55 is only 3.65:1 on white, so
    // every accent link, `FilledButton` label and selected-tab text failed AA.
    // `accentDark` #D6193E is 5.16:1 on white AND gives white-on-accent 5.16:1,
    // so it is the one token that works as both text and fill.
    accent: AppColors.accentDark,
    inputFill: AppColors.lightSurfaceAlt,
    overlay: Color(0x66000000),
    isDark: false,
    onSuccess: AppColors.lightSuccessFg,
    onWarning: AppColors.lightWarningFg,
    onInfo: AppColors.lightInfoFg,
    onDanger: AppColors.lightDangerFg,
    online: AppColors.lightOnlineFg,
  );

  static AppColorScheme of(BuildContext context) =>
      Theme.of(context).extension<AppColorScheme>() ?? dark;

  /// Returns a copy with the accent replaced — used by the appearance screen.
  AppColorScheme withAccent(Color newAccent) => AppColorScheme(
        bg: bg,
        surface: surface,
        surfaceAlt: surfaceAlt,
        card: card,
        elevated: elevated,
        divider: divider,
        bubbleIn: bubbleIn,
        bubbleOut: bubbleOut,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textOnAccent: textOnAccent,
        accent: newAccent,
        inputFill: inputFill,
        overlay: overlay,
        isDark: isDark,
        onSuccess: onSuccess,
        onWarning: onWarning,
        onInfo: onInfo,
        onDanger: onDanger,
        online: online,
      );

  @override
  AppColorScheme copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? card,
    Color? elevated,
    Color? divider,
    Color? bubbleIn,
    Color? bubbleOut,
    Color? textPrimary,
    Color? textSecondary,
    Color? textOnAccent,
    Color? accent,
    Color? inputFill,
    Color? overlay,
    bool? isDark,
    Color? onSuccess,
    Color? onWarning,
    Color? onInfo,
    Color? onDanger,
    Color? online,
  }) {
    return AppColorScheme(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      card: card ?? this.card,
      elevated: elevated ?? this.elevated,
      divider: divider ?? this.divider,
      bubbleIn: bubbleIn ?? this.bubbleIn,
      bubbleOut: bubbleOut ?? this.bubbleOut,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      accent: accent ?? this.accent,
      inputFill: inputFill ?? this.inputFill,
      overlay: overlay ?? this.overlay,
      isDark: isDark ?? this.isDark,
      onSuccess: onSuccess ?? this.onSuccess,
      onWarning: onWarning ?? this.onWarning,
      onInfo: onInfo ?? this.onInfo,
      onDanger: onDanger ?? this.onDanger,
      online: online ?? this.online,
    );
  }

  @override
  AppColorScheme lerp(ThemeExtension<AppColorScheme>? other, double t) {
    if (other is! AppColorScheme) return this;
    return AppColorScheme(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      card: Color.lerp(card, other.card, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      bubbleIn: Color.lerp(bubbleIn, other.bubbleIn, t)!,
      bubbleOut: Color.lerp(bubbleOut, other.bubbleOut, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      online: Color.lerp(online, other.online, t)!,
    );
  }
}

/// Ergonomic accessor: `context.c.accent`.
extension AppColorContext on BuildContext {
  AppColorScheme get c => AppColorScheme.of(this);
  TextTheme get t => Theme.of(this).textTheme;
  bool get isDark => c.isDark;
}
