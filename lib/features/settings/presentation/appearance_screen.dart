import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/settings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Appearance: theme mode, accent colour, font scale, chat theme, app icon.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  static List<({String id, String label})> _chatThemes(BuildContext context) =>
      <({String id, String label})>[
    (id: 'default', label: context.l10n.defaultLabel),
    (id: 'bubbles', label: context.l10n.roundedBubbles),
    (id: 'compact', label: context.l10n.compact),
    (id: 'outline', label: context.l10n.outlined),
  ];

  static List<({String id, String label})> _appIcons(BuildContext context) =>
      <({String id, String label})>[
    (id: 'default', label: context.l10n.imoRose),
    (id: 'mono', label: context.l10n.monochrome),
    (id: 'dark', label: context.l10n.midnight),
    (id: 'classic', label: context.l10n.classic),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppearanceSettings s =
        ref.watch(appearanceProvider).valueOrNull ?? const AppearanceSettings();
    final AppearanceNotifier notifier = ref.read(appearanceProvider.notifier);

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.appearance, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          SectionHeader(title: context.l10n.theme),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: <Widget>[
                _ThemePreview(
                  label: context.l10n.system,
                  mode: AppThemeMode.system,
                  selected: s.themeMode == AppThemeMode.system,
                  accent: Color(s.accentColor),
                  onTap: () => notifier.setThemeMode(AppThemeMode.system),
                ),
                const SizedBox(width: AppSpacing.md),
                _ThemePreview(
                  label: context.l10n.themeLight,
                  mode: AppThemeMode.light,
                  selected: s.themeMode == AppThemeMode.light,
                  accent: Color(s.accentColor),
                  onTap: () => notifier.setThemeMode(AppThemeMode.light),
                ),
                const SizedBox(width: AppSpacing.md),
                _ThemePreview(
                  label: context.l10n.themeDark,
                  mode: AppThemeMode.dark,
                  selected: s.themeMode == AppThemeMode.dark,
                  accent: Color(s.accentColor),
                  onTap: () => notifier.setThemeMode(AppThemeMode.dark),
                ),
              ],
            ),
          ),

          SectionHeader(title: context.l10n.accentColour),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: accentChoices
                  .map(
                    (({String name, int value}) choice) => _AccentSwatch(
                      name: choice.name,
                      color: Color(choice.value),
                      selected: s.accentColor == choice.value,
                      onTap: () => notifier.setAccent(choice.value),
                    ),
                  )
                  .toList(),
            ),
          ),

          SettingsGroup(
            title: context.l10n.textSize,
            footer:
                context.l10n.textSizeScalesEveryScreen,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      context.l10n.a,
                      style: context.t.bodySmall?.copyWith(
                        color: context.c.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: s.fontScale.clamp(0.8, 1.4),
                        min: 0.8,
                        max: 1.4,
                        divisions: 6,
                        label: '${(s.fontScale * 100).round()}%',
                        onChanged: (double v) => notifier.setFontScale(v),
                      ),
                    ),
                    Text(
                      context.l10n.a,
                      style: context.t.titleLarge?.copyWith(
                        color: context.c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: context.c.bubbleIn,
                    borderRadius: AppRadius.rLg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.l10n.preview,
                        style: context.t.bodyMedium?.copyWith(
                          fontSize: (context.t.bodyMedium?.fontSize ?? 14) *
                              s.fontScale,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        context.l10n.thisIsHowYourMessages2((s.fontScale * 100).round()),
                        style: context.t.bodySmall?.copyWith(
                          fontSize:
                              (context.t.bodySmall?.fontSize ?? 12) * s.fontScale,
                          color: context.c.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SettingsValueRow(
                label: context.l10n.resetTextSize,
                value: '${(s.fontScale * 100).round()}%',
                leadingIcon: Icons.restart_alt_rounded,
                onTap: () => notifier.setFontScale(1.0),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.chatTheme,
            children: _chatThemes(context)
                .map(
                  (({String id, String label}) theme) => SettingsTile(
                    title: theme.label,
                    trailing: s.chatTheme == theme.id
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: AppIconSizes.md,
                            color: context.c.accent,
                          )
                        : null,
                    onTap: () => notifier.setChatTheme(theme.id),
                  ),
                )
                .toList(),
          ),

          SettingsGroup(
            title: context.l10n.appIcon,
            footer:
                context.l10n.changingTheLauncherIconIs2,
            children: _appIcons(context)
                .map(
                  (({String id, String label}) icon) => SettingsTile(
                    title: icon.label,
                    trailing: s.appIcon == icon.id
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: AppIconSizes.md,
                            color: context.c.accent,
                          )
                        : null,
                    onTap: () async {
                      await notifier.setAppIcon(icon.id);
                      if (context.mounted) {
                        iToast(context, context.l10n.appIconSetTo(icon.label));
                      }
                    },
                  ),
                )
                .toList(),
          ),

          SettingsGroup(
            title: context.l10n.reset,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.restoreDefaultAppearance,
                subtitle: context.l10n.darkThemeRoseAccent100,
                leadingIcon: Icons.restart_alt_rounded,
                onTap: () async {
                  await ref
                      .read(appearanceProvider.notifier)
                      .apply((AppearanceSettings _) => const AppearanceSettings());
                  if (context.mounted) {
                    iToast(context, context.l10n.appearanceRestoredToDefaults);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// A tappable theme-mode preview swatch.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.label,
    required this.mode,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final AppThemeMode mode;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = switch (mode) {
      AppThemeMode.dark => true,
      AppThemeMode.light => false,
      AppThemeMode.system => MediaQuery.of(context).platformBrightness ==
          Brightness.dark,
    };
    final Color bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final Color surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final Color text = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: <Widget>[
            AnimatedContainer(
              duration: AppDurations.fast,
              height: 84,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppRadius.rMd,
                border: Border.all(
                  color: selected ? accent : context.c.divider,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      height: 12,
                      width: 34,
                      decoration: BoxDecoration(
                        color: text.withValues(alpha: 0.85),
                        borderRadius: AppRadius.rSm,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs + 2),
                    Container(
                      height: 9,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: AppRadius.rSm,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        height: 9,
                        width: 30,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.85),
                          borderRadius: AppRadius.rSm,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: AppIconSizes.sm,
                  color: selected ? accent : context.c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: context.t.bodySmall?.copyWith(
                    color: selected ? accent : context.c.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable accent colour swatch.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedContainer(
            duration: AppDurations.fast,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? context.c.textPrimary : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, size: 22, color: Colors.white)
                : null,
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          SizedBox(
            width: 58,
            child: Text(
              name,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelSmall?.copyWith(
                color: selected ? context.c.textPrimary : context.c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
