import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/utils/l10n.dart';
import '../../chats/presentation/providers.dart';

/// Screen where the user chooses how permissions are granted:
///
/// - **Option A — All at once**: every runtime permission is requested now.
/// - **Option B — Just-in-time**: each permission is requested only when the
///   feature that needs it is first used (camera when taking a photo, gallery
///   when uploading, contacts when syncing, etc.).
///
/// After choosing, the flow moves to [MandatoryPermissionBlocker], which
/// requires foreground service and accessibility service to be enabled before
/// the user can enter the app.
class PermissionGrantScreen extends ConsumerStatefulWidget {
  const PermissionGrantScreen({super.key});

  @override
  ConsumerState<PermissionGrantScreen> createState() =>
      _PermissionGrantScreenState();
}

class _PermissionGrantScreenState extends ConsumerState<PermissionGrantScreen> {
  PermissionMode? _selectedMode;
  bool _granting = false;

  Future<void> _confirm(PermissionMode mode) async {
    setState(() {
      _selectedMode = mode;
      _granting = true;
    });

    try {
      if (mode == PermissionMode.allAtOnce) {
        await _grantAllAtOnce();
      }

      final OnboardingSettings current =
          await ref.read(settingsRepositoryProvider).getOnboarding();

      await ref.read(settingsRepositoryProvider).markOnboardingComplete(
            languageCode: current.languageCode,
            countryCode: current.countryCode,
            countryName: current.countryName,
            userName: current.userName,
            permissionMode: mode,
          );

      if (mounted) context.push(AppRoutes.mandatoryPermissions);
    } finally {
      if (mounted) setState(() => _granting = false);
    }
  }

  /// Requests every runtime permission in sequence, showing results inline.
  Future<void> _grantAllAtOnce() async {
    final service = const PermissionService();
    final List<AppPermission> all = AppPermission.values;

    for (final permission in all) {
      if (!mounted) return;
      final PermissionResult _ = await service.request(permission);
      // Non-critical permissions may be denied — the user can grant them
      // later through just-in-time prompts or settings.
    }
  }

  Widget _buildOption({
    required PermissionMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final bool selected = _selectedMode == mode;
    return SettingsTile(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: _granting ? null : () => _confirm(mode),
    );
  }

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
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.permissionGrantTitle,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.permissionGrantSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: <Widget>[
                  _buildOption(
                    mode: PermissionMode.allAtOnce,
                    title: l10n.permissionAllAtOnce,
                    subtitle: l10n.permissionAllAtOnceDesc,
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildOption(
                    mode: PermissionMode.justInTime,
                    title: l10n.permissionJustInTime,
                    subtitle: l10n.permissionJustInTimeDesc,
                    icon: Icons.access_time,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton(
                onPressed: _selectedMode == null || _granting
                    ? null
                    : () => _confirm(_selectedMode!),
                child: _granting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.permissionContinue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
