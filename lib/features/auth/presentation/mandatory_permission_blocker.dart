import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/system_settings_service.dart';
import '../../../core/utils/l10n.dart';
import '../../../l10n/app_localizations.dart';

/// Last step of the first-run flow.
///
/// Runtime permissions were already handled by [PermissionGrantScreen]; this
/// screen points at the two system-level settings that have no in-app API:
///
/// - **Accessibility** — opens the OS accessibility list. This app declares no
///   accessibility service, so the list is only useful for the system's own
///   accessibility tools; nothing here reads or monitors other apps.
/// - **App settings** — the app's own settings page, where a denied runtime
///   permission or the notification toggle can be re-enabled.
///
/// Neither is required: Continue always works, because a gate the user cannot
/// pass is a gate that loses the user.
class MandatoryPermissionBlocker extends StatelessWidget {
  const MandatoryPermissionBlocker({super.key});

  static const SystemSettingsService _settings = SystemSettingsService();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: context.c.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.mandatoryTitle,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.mandatorySubtitle,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.c.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: <Widget>[
                  _settingsCard(
                    context,
                    icon: Icons.accessibility_rounded,
                    title: l10n.mandatoryAccessibilityService,
                    subtitle: l10n.mandatoryAccessibilityServiceDesc,
                    buttonLabel: l10n.mandatorySettingsAccessibilityService,
                    onPressed: _settings.openAccessibilitySettings,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _settingsCard(
                    context,
                    icon: Icons.settings_outlined,
                    title: l10n.mandatoryForegroundService,
                    subtitle: l10n.mandatoryForegroundServiceDesc,
                    buttonLabel: l10n.mandatorySettingsForegroundService,
                    onPressed: _settings.openAppSettings,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _noteBox(context, l10n),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton(
                onPressed: () => context.go(AppRoutes.chats),
                child: Text(l10n.mandatoryContinue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required Future<bool> Function() onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: context.c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 24, color: context.c.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () => onPressed(),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }

  Widget _noteBox(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.c.surfaceAlt,
        borderRadius: AppRadius.rLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.mandatoryWarningTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.mandatoryWarningDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.c.onWarning,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
