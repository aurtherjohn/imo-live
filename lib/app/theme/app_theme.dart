import 'package:flutter/material.dart';

import 'app_color_scheme.dart';
import 'app_tokens.dart';

/// Builds the Material 3 themes for Imo LIVE.
///
/// The theme is intentionally restrained: flat dark surfaces, a single bright
/// accent, no gratuitous gradients, and consistent typography.
class AppTheme {
  const AppTheme._();

  static ThemeData dark({Color accent = AppColors.accent}) =>
      _base(Brightness.dark, accent);

  static ThemeData light({Color accent = AppColors.accent}) =>
      _base(Brightness.light, accent);

  static ThemeData _base(Brightness brightness, Color accent) {
    final bool isDark = brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final Color surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final Color card = isDark ? AppColors.darkCard : AppColors.lightCard;
    final Color divider =
        isDark ? AppColors.darkDivider : AppColors.lightDivider;
    final Color textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final Color textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: accent,
      onPrimaryContainer: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: bg,
      onSurface: textPrimary,
      surfaceContainerHighest: card,
      surfaceContainerHigh: surface,
      onSurfaceVariant: textSecondary,
      error: AppColors.danger,
      onError: Colors.white,
      outline: divider,
      outlineVariant: divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? Colors.white : Colors.black,
      onInverseSurface: isDark ? Colors.black : Colors.white,
    );

    final TextTheme text = _textTheme(textPrimary, textSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: divider,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: null,
      textTheme: text,
      primaryTextTheme: text,
      extensions: <ThemeExtension<dynamic>>[
        isDark ? AppColorScheme.dark.withAccent(accent) : AppColorScheme.light.withAccent(accent),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: textPrimary, size: AppIconSizes.md),
        toolbarHeight: AppSizes.topBarHeight,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: card,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        showDragHandle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkElevated : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rXl),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.darkElevated : const Color(0xFF2B2B30),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        contentPadding: AppSpacing.listTile,
        minVerticalPadding: AppSpacing.sm,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        hintStyle: TextStyle(color: textSecondary, fontSize: 15),
        labelStyle: TextStyle(color: textSecondary, fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, AppSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rPill),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, AppSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          side: BorderSide(color: accent.withValues(alpha: 0.5)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rPill),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, 40),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        selectedColor: accent.withValues(alpha: 0.18),
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: accent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rPill),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? const Color(0xFF8E8E96) : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return isDark ? AppColors.darkElevated : const Color(0xFFCFCFD6);
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return textSecondary;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        side: BorderSide(color: textSecondary, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: isDark ? AppColors.darkElevated : const Color(0xFFDDDDE3),
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.15),
        trackHeight: 3,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: isDark ? AppColors.darkElevated : const Color(0xFFE6E6EB),
        circularTrackColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppColors.darkElevated : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
        textStyle: TextStyle(color: textPrimary, fontSize: 15),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 0.6,
        space: 0.6,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: AppSizes.bottomBarHeight,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  static TextTheme _textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.8),
      displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.6),
      displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.4),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.3),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: primary, letterSpacing: -0.2),
      titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: primary, height: 1.35),
      bodyMedium: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: primary, height: 1.35),
      bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: secondary, height: 1.3),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: secondary),
    );
  }
}
