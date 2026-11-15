import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../chats/presentation/providers.dart';

/// First-run permission screen.
///
/// Everything the app can ask the OS for is listed in one place, with a single
/// primary action that requests them in order. This replaces the earlier
/// all-at-once / just-in-time choice: the flow the product wants is
/// "show what is needed, ask for all of it, then move on to the system-level
/// settings screen".
///
/// Skipping is a first-class outcome — nothing here is mandatory for the app to
/// start, and a denial can be re-granted later from Settings.
class PermissionGrantScreen extends ConsumerStatefulWidget {
  const PermissionGrantScreen({super.key});

  @override
  ConsumerState<PermissionGrantScreen> createState() =>
      _PermissionGrantScreenState();
}

class _PermissionGrantScreenState extends ConsumerState<PermissionGrantScreen> {
  bool _busy = false;

  /// Result per permission once the bulk request has run. Empty until then.
  final Map<AppPermission, PermissionResult> _results =
      <AppPermission, PermissionResult>{};

  static const Map<AppPermission, IconData> _icons = <AppPermission, IconData>{
    AppPermission.camera: Icons.photo_camera_outlined,
    AppPermission.microphone: Icons.mic_none_rounded,
    AppPermission.photos: Icons.photo_library_outlined,
    AppPermission.videos: Icons.video_library_outlined,
    AppPermission.audio: Icons.audiotrack_rounded,
    AppPermission.contacts: Icons.contacts_outlined,
    AppPermission.location: Icons.location_on_outlined,
    AppPermission.notifications: Icons.notifications_outlined,
    AppPermission.bluetooth: Icons.bluetooth_rounded,
  };

  String _label(AppLocalizations l10n, AppPermission permission) =>
      switch (permission) {
        AppPermission.camera => l10n.camera,
        AppPermission.microphone => l10n.microphone,
        AppPermission.photos => l10n.photos,
        AppPermission.videos => l10n.videos,
        AppPermission.audio => l10n.audioFiles,
        AppPermission.contacts => l10n.contacts,
        AppPermission.location => l10n.location,
        AppPermission.notifications => l10n.notifications,
        AppPermission.bluetooth => l10n.bluetooth,
      };

  /// Requests every listed permission in sequence, painting each row as its
  /// answer arrives, then moves on to the final settings step.
  Future<void> _requestAll() async {
    setState(() => _busy = true);
    const PermissionService service = PermissionService();
    for (final AppPermission permission in AppPermission.values) {
      final PermissionResult result = await service.request(permission);
      if (!mounted) return;
      setState(() => _results[permission] = result);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _advance();
  }

  /// Persists the onboarding state and pushes the system-settings step.
  ///
  /// Every permission outcome — granted, denied or skipped — lands here: the
  /// flow must be able to finish on a device where the user says no.
  Future<void> _advance() async {
    try {
      final OnboardingSettings current =
          await ref.read(settingsRepositoryProvider).getOnboarding();
      await ref.read(settingsRepositoryProvider).markOnboardingComplete(
            languageCode: current.languageCode,
            countryCode: current.countryCode,
            countryName: current.countryName,
            userName: current.userName,
            permissionMode: PermissionMode.allAtOnce,
          );
    } on Object catch (error) {
      // Failing to persist must not trap the user in the first-run flow; the
      // gate re-reads the flag and will show onboarding again next launch.
      debugPrint('Could not persist onboarding state: $error');
    }
    if (mounted) context.push(AppRoutes.mandatoryPermissions);
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
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: <Widget>[
                  for (final AppPermission permission
                      in AppPermission.values)
                    _permissionCard(context, l10n, permission),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _requestAll,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.grantAllPermissions),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: _busy ? null : _advance,
                    child: Text(l10n.skip),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionCard(
    BuildContext context,
    AppLocalizations l10n,
    AppPermission permission,
  ) {
    final PermissionResult? result = _results[permission];
    final bool granted = result?.isGranted ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: AppRadius.rLg,
        border: Border.all(
          color: granted ? Colors.green : context.c.divider,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            _icons[permission],
            size: 22,
            color: context.c.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _label(l10n, permission),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (result != null)
            Icon(
              granted ? Icons.check_circle_rounded : Icons.cancel_outlined,
              size: 20,
              color: granted ? Colors.green : context.c.textSecondary,
            ),
        ],
      ),
    );
  }
}
