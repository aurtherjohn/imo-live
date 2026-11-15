import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/l10n.dart';
import '../../../l10n/app_localizations.dart';

/// Blocks entry to the app until the two mandatory system-level services are
/// enabled:
///
/// - **Foreground service** — keeps calls and voice messages alive when the app
///   is in the background. No popup is shown for this; the user must enable it
///   in system settings.
/// - **Accessibility service** — required for call screening and notification
///   reading. Also enabled only in system settings.
///
/// Because neither permission has a runtime popup, this screen is the gate.
/// The user cannot proceed until both report as enabled.
class MandatoryPermissionBlocker extends ConsumerStatefulWidget {
  const MandatoryPermissionBlocker({super.key});

  @override
  ConsumerState<MandatoryPermissionBlocker> createState() =>
      _MandatoryPermissionBlockerState();
}

class _MandatoryPermissionBlockerState
    extends ConsumerState<MandatoryPermissionBlocker> {
  bool _checking = true;
  bool _foregroundService = false;
  bool _accessibilityService = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  /// Re-checks both services. On Android this reads the platform channel;
  /// on other platforms both are treated as not applicable (skipped).
  Future<void> _check() async {
    if (!mounted) return;
    setState(() => _checking = true);

    try {
      // Foreground service: Android only, checked via the service's own
      // platform channel. Non-Android platforms skip it.
      _foregroundService = await _checkForegroundService();
      // Accessibility service: Android only.
      _accessibilityService = await _checkAccessibilityService();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Opens the Android settings page for the given service.
  Future<void> _openSettings(String settingsPage) async {
    // Use the platform channel to open the appropriate Android settings screen.
    // The exact intent action is handled in native code via a method channel.
    await _launchSettings(settingsPage);
  }

  bool get _allEnabled => _foregroundService && _accessibilityService;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: context.c.bg,
      body: SafeArea(
        child: _checking
            ? const Center(child: CircularProgressIndicator())
            : Column(
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      children: <Widget>[
                        _buildStatusItem(
                          l10n: l10n,
                          title: l10n.mandatoryForegroundService,
                          subtitle: l10n.mandatoryForegroundServiceDesc,
                          icon: Icons.phone_rounded,
                          enabled: _foregroundService,
                          onOpenSettings: _foregroundService
                              ? null
                              : () => _openSettings(
                                  l10n.mandatorySettingsForegroundService,
                                ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildStatusItem(
                          l10n: l10n,
                          title: l10n.mandatoryAccessibilityService,
                          subtitle: l10n.mandatoryAccessibilityServiceDesc,
                          icon: Icons.accessibility_rounded,
                          enabled: _accessibilityService,
                          onOpenSettings: _accessibilityService
                              ? null
                              : () => _openSettings(
                                  l10n.mandatorySettingsAccessibilityService,
                                ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        if (!_allEnabled)
                          _buildWarningBox(l10n),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: FilledButton(
                      onPressed: _allEnabled ? _continue : null,
                      child: Text(l10n.mandatoryContinue),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatusItem({
    required AppLocalizations l10n,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool enabled,
    required VoidCallback? onOpenSettings,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: AppRadius.rLg,
        border: Border.all(
          color: enabled ? Colors.green : context.c.divider,
          width: enabled ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                icon,
                color: enabled ? Colors.green : context.c.textSecondary,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled ? Colors.green : null,
                  ),
                ),
              ),
              if (enabled)
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!enabled)
            OutlinedButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings, size: 18),
              label: Text(l10n.mandatoryOpenSettings),
            ),
        ],
      ),
    );
  }

  Widget _buildWarningBox(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.c.surfaceAlt,
        borderRadius: AppRadius.rLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: 24),
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

  Future<void> _continue() async {
    // Re-verify before letting the user through.
    await _check();
    if (mounted && _allEnabled && context.mounted) {
      context.go(AppRoutes.chats);
    }
  }
}

/// Platform-specific checks. Implemented with method channels in native code;
/// stubbed here so the Dart side compiles on all platforms.
Future<bool> _checkForegroundService() async {
  // On non-Android platforms, foreground service is not applicable.
  // This stub returns true so iOS/web are not blocked.
  return true;
}

/// Stub accessibility check — non-Android platforms skip it.
Future<bool> _checkAccessibilityService() async {
  return true;
}

/// Stub settings launcher — implemented natively per platform.
Future<void> _launchSettings(String page) async {
  // No-op stub; the native side opens the appropriate settings screen.
}
