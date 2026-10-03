import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/app/theme/app_color_scheme.dart';
import 'package:imo_live/app/theme/app_tokens.dart';

/// Phase 8 contrast guard.
///
/// The raw brand palette (`AppColors.success` …) is tuned for **fills**: large
/// areas of saturated colour behind white glyphs. Used as a *foreground* on a
/// light surface it collapses — the measured ratios on `#FFFFFF` were green
/// 1.98, amber 1.83, blue 2.53, red 3.41 and accent 3.65, against the 4.5 that
/// WCAG 2.1 AA requires for body text. A presence dot on a white chat list was
/// effectively invisible.
///
/// The scheme therefore carries separate `onSuccess` / `onWarning` / `onInfo` /
/// `onDanger` / `online` foreground tokens. This test pins the maths so a future
/// palette tweak cannot silently fall back below AA.
void main() {
  /// WCAG 2.1 relative luminance.
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  /// WCAG 2.1 contrast ratio.
  double contrast(Color a, Color b) {
    final double la = luminance(a);
    final double lb = luminance(b);
    final double hi = math.max(la, lb);
    final double lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  const double aaBody = 4.5;
  const Color white = Color(0xFFFFFFFF);

  group('foreground tokens clear WCAG AA on their own surface', () {
    test('light theme semantic foregrounds are legible on white', () {
      final AppColorScheme c = AppColorScheme.light;
      final Map<String, Color> fg = <String, Color>{
        'onSuccess': c.onSuccess,
        'onWarning': c.onWarning,
        'onInfo': c.onInfo,
        'onDanger': c.onDanger,
        'online': c.online,
      };
      fg.forEach((String name, Color color) {
        final double ratio = contrast(color, white);
        expect(
          ratio,
          greaterThanOrEqualTo(aaBody),
          reason: 'light $name is $ratio:1 on white (needs $aaBody)',
        );
      });
    });

    test('light accent and text tokens are legible on white', () {
      final AppColorScheme c = AppColorScheme.light;
      expect(contrast(c.accent, white), greaterThanOrEqualTo(aaBody));
      expect(contrast(c.textPrimary, white), greaterThanOrEqualTo(aaBody));
      expect(contrast(c.textSecondary, white), greaterThanOrEqualTo(aaBody));
    });

    test('dark theme semantic foregrounds are legible on the dark surface', () {
      final AppColorScheme c = AppColorScheme.dark;
      final Map<String, Color> fg = <String, Color>{
        'onSuccess': c.onSuccess,
        'onWarning': c.onWarning,
        'onInfo': c.onInfo,
        'onDanger': c.onDanger,
        'online': c.online,
      };
      fg.forEach((String name, Color color) {
        final double ratio = contrast(color, c.surface);
        expect(
          ratio,
          greaterThanOrEqualTo(aaBody),
          reason: 'dark $name is $ratio:1 on the surface (needs $aaBody)',
        );
      });
    });
  });

  group('the raw palette is documented as fill-only', () {
    test('raw success/warning/info genuinely fail as light foregrounds', () {
      // This is the bug the foreground tokens exist to fix. If a future palette
      // change makes these legible, this test fails and the tokens can be
      // reconsidered — which is the correct moment to revisit the design.
      expect(contrast(AppColors.success, white), lessThan(aaBody));
      expect(contrast(AppColors.warning, white), lessThan(aaBody));
      expect(contrast(AppColors.info, white), lessThan(aaBody));
    });

    test('foreground tokens differ from the raw fills in the light theme', () {
      final AppColorScheme c = AppColorScheme.light;
      expect(c.onSuccess, isNot(AppColors.success));
      expect(c.onWarning, isNot(AppColors.warning));
      expect(c.onInfo, isNot(AppColors.info));
    });

    test('the dark theme keeps the brand hues for semantic foregrounds', () {
      // On the dark surface the raw hues already clear AA, so the dark theme
      // should not have drifted to a different palette.
      expect(AppColorScheme.dark.onSuccess, AppColors.success);
      expect(AppColorScheme.dark.onInfo, AppColors.info);
    });
  });

  group('scheme plumbing', () {
    test('copyWith and lerp carry the foreground tokens', () {
      const AppColorScheme base = AppColorScheme.dark;
      final AppColorScheme retinted =
          base.copyWith(onSuccess: const Color(0xFF123456));
      expect(retinted.onSuccess, const Color(0xFF123456));
      expect(retinted.onDanger, base.onDanger, reason: 'untouched fields');

      final AppColorScheme mid =
          AppColorScheme.dark.lerp(AppColorScheme.light, 0.5);
      expect(mid.onSuccess, isNot(AppColorScheme.dark.onSuccess));
      expect(mid.onSuccess, isNot(AppColorScheme.light.onSuccess));
    });

    test('withAccent preserves the foreground tokens', () {
      final AppColorScheme retinted =
          AppColorScheme.dark.withAccent(const Color(0xFFABCDEF));
      expect(retinted.accent, const Color(0xFFABCDEF));
      expect(retinted.onSuccess, AppColorScheme.dark.onSuccess);
      expect(retinted.online, AppColorScheme.dark.online);
    });
  });
}
