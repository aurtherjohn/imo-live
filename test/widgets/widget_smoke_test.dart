import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/app/theme/app_color_scheme.dart';
import 'package:imo_live/app/theme/app_tokens.dart';
import 'package:imo_live/app/theme/app_theme.dart';
import 'package:imo_live/core/constants/app_constants.dart';
import 'package:imo_live/core/widgets/common_widgets.dart';
import 'package:imo_live/core/widgets/i_avatar.dart';

/// Pumps a widget inside the app's real dark theme so `context.c` / `context.t`
/// resolve exactly as they do at runtime.
///
/// The theme's `splashFactory` is overridden to `InkSplash.splashFactory`
/// because `AppTheme` sets `InkSparkle.splashFactory`, which lazily loads
/// `shaders/ink_sparkle.frag` the first time any Material is tapped. That
/// shader is not part of the test asset manifest, so a physical tap fails with
/// `Asset 'shaders/ink_sparkle.frag' not found`. Flutter's own
/// `ink_sparkle_test.dart` is tagged out of normal CI for the same reason.
/// The override affects only the splash animation; every colour, text style and
/// layout value still comes from the real `AppTheme.dark()`.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ThemeData theme = AppTheme.dark().copyWith(
    splashFactory: InkSplash.splashFactory,
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  group('Theme', () {
    test('dark theme is the default and never light-flipped', () {
      final ThemeData theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);

      final AppColorScheme scheme = theme.extension<AppColorScheme>()!;
      expect(scheme.isDark, isTrue);
      expect(scheme.accent, const Color(0xFFFF2D55));
      // Near-black background, light text.
      expect(scheme.bg.computeLuminance(), lessThan(0.05));
      expect(scheme.textPrimary.computeLuminance(), greaterThan(0.7));
    });

    test('light theme inverts surfaces and keeps the same accent', () {
      final ThemeData theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);

      final AppColorScheme scheme = theme.extension<AppColorScheme>()!;
      expect(scheme.isDark, isFalse);
      expect(scheme.accent, const Color(0xFFFF2D55));
      expect(scheme.bg.computeLuminance(), greaterThan(0.8));
      expect(scheme.textPrimary.computeLuminance(), lessThan(0.3));
    });
  });

  group('Design tokens', () {
    test('spacing scale is monotonically increasing', () {
      expect(AppSpacing.xxs, lessThan(AppSpacing.xs));
      expect(AppSpacing.xs, lessThan(AppSpacing.sm));
      expect(AppSpacing.sm, lessThan(AppSpacing.md));
      expect(AppSpacing.md, lessThan(AppSpacing.lg));
      expect(AppSpacing.lg, lessThan(AppSpacing.xl));
      expect(AppSpacing.xl, lessThan(AppSpacing.xxl));
      expect(AppSpacing.xxl, lessThan(AppSpacing.xxxl));
    });

    test('radius scale is monotonically increasing', () {
      expect(AppRadius.xs, lessThan(AppRadius.sm));
      expect(AppRadius.sm, lessThan(AppRadius.md));
      expect(AppRadius.md, lessThan(AppRadius.lg));
      expect(AppRadius.lg, lessThan(AppRadius.pill));
    });

    test('avatar sizes increase and stay within sensible bounds', () {
      expect(AppSizes.avatarSm, lessThan(AppSizes.avatarMd));
      expect(AppSizes.avatarMd, lessThan(AppSizes.avatarLg));
      expect(AppSizes.avatarLg, lessThan(AppSizes.avatarXl));
      expect(AppSizes.avatarXl, lessThan(AppSizes.avatarXxl));
      expect(AppSizes.avatarSm, greaterThan(0));
    });
  });

  group('IAvatar', () {
    testWidgets('renders initials derived from the display name', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const IAvatar(name: 'Ada Lovelace'));

      expect(find.text('AL'), findsOneWidget);
    });

    testWidgets('a single-word name produces up to two initials', (
      WidgetTester tester,
    ) async {
      // A short single word yields its single letter; longer words yield two.
      await pumpThemed(tester, const IAvatar(name: 'Prince'));
      expect(find.text('PR'), findsOneWidget);
    });

    testWidgets('an unread badge is drawn when a count is supplied', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const IAvatar(name: 'Ada Lovelace', badgeCount: 7),
      );

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a group avatar shows the group icon instead of initials', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const IAvatar(
          name: 'Design team',
          isGroup: true,
          icon: Icons.groups_rounded,
        ),
      );

      // The group glyph appears as the avatar icon; the same constant is also
      // referenced elsewhere in the widget tree, so match at least one.
      expect(find.byIcon(Icons.groups_rounded), findsWidgets);
    });

    test('colorFor is deterministic for the same seed', () {
      expect(
        IAvatar.colorFor('Ada Lovelace'),
        IAvatar.colorFor('Ada Lovelace'),
      );
      expect(IAvatar.palette, isNotEmpty);
    });
  });

  group('Common widgets', () {
    testWidgets('SettingsTile shows a title, subtitle and reacts to a tap', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpThemed(
        tester,
        SettingsTile(
          title: 'Privacy',
          subtitle: 'Blocked contacts and last seen',
          leadingIcon: Icons.lock_outline_rounded,
          onTap: () => taps++,
        ),
      );

      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Blocked contacts and last seen'), findsOneWidget);

      await tester.tap(find.text('Privacy'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('EmptyState renders its copy and a working action button', (
      WidgetTester tester,
    ) async {
      int actions = 0;
      await pumpThemed(
        tester,
        EmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'No chats yet',
          message: 'Start a conversation to see it here.',
          actionLabel: 'New chat',
          onAction: () => actions++,
        ),
      );

      expect(find.text('No chats yet'), findsOneWidget);
      expect(find.text('Start a conversation to see it here.'), findsOneWidget);

      await tester.tap(find.text('New chat'));
      await tester.pump();
      expect(actions, 1);
    });

    testWidgets('IPill renders its label', (WidgetTester tester) async {
      await pumpThemed(
        tester,
        const IPill(label: 'Admin', filled: true),
      );

      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('AppTopBar shows the title and a back affordance', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const AppTopBar(title: 'Settings', showBack: true),
      );

      expect(find.text('Settings'), findsOneWidget);
      // The back affordance uses the iOS-style chevron icon.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    });

    testWidgets('ILoader renders without overflowing a small box', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const Center(child: ILoader(size: 26)),
      );
      expect(find.byType(ILoader), findsOneWidget);
    });

    testWidgets('AppConstants drive the visible brand name', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const Text(AppConstants.appName));
      expect(find.text('Imo LIVE'), findsOneWidget);
    });
  });
}
