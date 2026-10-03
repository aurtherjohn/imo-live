import 'package:flutter/material.dart';

/// Design tokens shared by both themes.
///
/// The values here are deliberately centralised: spacing, radii, icon sizes,
/// motion durations and elevation all come from this file so the UI stays
/// visually consistent and is trivial to retune.
class AppColors {
  const AppColors._();

  // -------------------------------------------------------- brand accent ramp
  /// Bright pink/red accent used across the app.
  static const Color accent = Color(0xFFFF2D55);
  static const Color accentDark = Color(0xFFD6193E);
  static const Color accentLight = Color(0xFFFF5C7A);
  static const Color accentSoft = Color(0x33FF2D55);

  // ------------------------------------------------------------- logo palette
  /// The two hues of the app mark itself: a blue speech bubble carrying a green
  /// "Live" flag. Used only where the UI has to echo the logo — the glow that
  /// sits behind it on splash / auth / About. The general interface accent
  /// stays [accent]; these are not a second accent ramp.
  ///
  /// Sampled from the artwork (mean of the blue and green pixel families), not
  /// eyeballed, so the glow is the mark's own colour rather than a near-miss.
  static const Color brandBlue = Color(0xFF1FA6ED);
  static const Color brandGreen = Color(0xFF20C282);

  /// Secondary brand tint used for links and info affordances.
  static const Color info = Color(0xFF3BA9FF);
  static const Color success = Color(0xFF25D366);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF453A);

  // ------------------------------------------------------------- dark palette
  static const Color darkBg = Color(0xFF0B0B0D);
  static const Color darkSurface = Color(0xFF141417);
  static const Color darkSurfaceAlt = Color(0xFF1C1C20);
  static const Color darkCard = Color(0xFF1A1A1E);
  static const Color darkElevated = Color(0xFF232328);
  static const Color darkDivider = Color(0xFF26262B);
  static const Color darkBubbleIn = Color(0xFF1F1F24);
  static const Color darkBubbleOut = Color(0xFF2A1420);
  static const Color darkTextPrimary = Color(0xFFF5F5F7);
  static const Color darkTextSecondary = Color(0xFF9A9AA2);

  // On a dark surface the bright brand hues are already legible: every one of
  // these clears WCAG AA against `darkSurface` (green 10.6, amber 10.1,
  // blue 7.3, red 5.4, accent 5.0). So the dark theme reuses the raw palette.
  static const Color darkSuccessFg = success;
  static const Color darkWarningFg = warning;
  static const Color darkInfoFg = info;
  static const Color darkDangerFg = danger;
  static const Color darkOnlineFg = online;

  // ------------------------------------------------------------ light palette
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF7F7F9);
  static const Color lightSurfaceAlt = Color(0xFFEFEFF3);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFFFFFFF);
  static const Color lightDivider = Color(0xFFE4E4E9);
  static const Color lightBubbleIn = Color(0xFFFFFFFF);
  static const Color lightBubbleOut = Color(0xFFFFE3EA);
  static const Color lightTextPrimary = Color(0xFF111114);
  static const Color lightTextSecondary = Color(0xFF6B6B75);

  // ⚠️ The raw brand hues are **not legible as foregrounds on white**:
  // green 1.98, amber 1.83, blue 2.53, red 3.41, accent 3.65 — against a WCAG AA
  // requirement of 4.5 for body text. A green presence dot on a white list was
  // effectively invisible, and every success/error tint read as a smudge.
  //
  // These are the same hues, darkened until they clear AA on #FFFFFF (green
  // 5.4, amber 5.9, blue 5.3, red 5.7, accent 5.7). They stay close enough in
  // hue that a light/dark switch does not read as a different colour language —
  // only as the same colour at a legible weight.
  static const Color lightSuccessFg = Color(0xFF0E7A3F);
  static const Color lightWarningFg = Color(0xFF8A5A00);
  static const Color lightInfoFg = Color(0xFF0B6BCB);
  static const Color lightDangerFg = Color(0xFFC42B22);
  static const Color lightOnlineFg = Color(0xFF0E7A3F);

  // --------------------------------------------------------- status presence
  static const Color online = Color(0xFF25D366);
  static const Color offline = Color(0xFF8E8E96);
}

/// Spacing scale. Use these instead of magic numbers.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Standard horizontal page padding.
  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets listTile = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

/// Corner radii.
class AppRadius {
  const AppRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double pill = 999;

  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
}

/// Icon sizing.
class AppIconSizes {
  const AppIconSizes._();

  static const double xs = 14;
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 26;
  static const double xl = 32;
  static const double xxl = 40;
}

/// Layout metrics.
class AppSizes {
  const AppSizes._();

  static const double avatarSm = 34;
  static const double avatarMd = 48;
  static const double avatarLg = 56;
  static const double avatarXl = 96;
  static const double avatarXxl = 140;

  static const double chatTileHeight = 72;
  static const double listTileHeight = 64;
  static const double bottomBarHeight = 64;
  static const double topBarHeight = 58;
  static const double minTouchTarget = 48;

  static const double maxBubbleWidthFactor = 0.78;
  static const double maxContentWidth = 620;
}

/// Motion durations, kept short and consistent.
class AppDurations {
  const AppDurations._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
  static const Duration typingDot = Duration(milliseconds: 600);

  static const Curve curve = Curves.easeOutCubic;
  static const Curve curveInOut = Curves.easeInOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
}

/// Shadows. Dark theme uses very restrained elevation.
class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> none = <BoxShadow>[];

  static const List<BoxShadow> soft = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> medium = <BoxShadow>[
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> strong = <BoxShadow>[
    BoxShadow(
      color: Color(0x59000000),
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
  ];
}
