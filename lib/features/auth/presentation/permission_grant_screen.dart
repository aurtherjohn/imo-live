import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart' show FadeSlideIn, ListStagger;
import '../../../app/auth_gate.dart' show setOnboardingState;
import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../chats/presentation/providers.dart';

/// First-run permission screen — the last step before the chat list.
///
/// One clear call to action: "Grant all permissions". Tapping it walks the OS
/// dialogs one at a time — each row lights up as its answer arrives — and when
/// the walk finishes the flow ends straight into the chats. There is no
/// settings detour: anything denied can be re-granted later from Settings, and
/// every capability is still asked again just-in-time when its feature is
/// first used.
///
/// Skipping is a first-class outcome, not a dead end: nothing here is required
/// for the app to run.
class PermissionGrantScreen extends ConsumerStatefulWidget {
  const PermissionGrantScreen({super.key});

  @override
  ConsumerState<PermissionGrantScreen> createState() =>
      _PermissionGrantScreenState();
}

class _PermissionGrantScreenState extends ConsumerState<PermissionGrantScreen> {
  bool _busy = false;

  /// Result per permission once its request has run; absent means not asked.
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

  int get _asked => _results.length;
  int get _total => AppPermission.values.length;

  /// Requests every listed permission in sequence — the OS dialogs arrive one
  /// by one, which is the point of the design — then ends the flow into the
  /// chat list.
  Future<void> _grantAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    const PermissionService service = PermissionService();
    for (final AppPermission permission in AppPermission.values) {
      final PermissionResult result = await service.request(permission);
      if (!mounted) return;
      setState(() => _results[permission] = result);
    }
    if (!mounted) return;
    // One beat so every row visibly settles before the screen changes.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await _enterApp(permissionMode: PermissionMode.allAtOnce);
  }

  /// Persists onboarding as complete — keeping the *chosen* language and
  /// country — then leaves the flow into the chat list. Every outcome lands
  /// here: the flow must be able to finish on a device where the user says no.
  Future<void> _enterApp({required PermissionMode permissionMode}) async {
    try {
      final OnboardingSettings current = await ref
          .read(settingsRepositoryProvider)
          .getOnboarding();
      final OnboardingSettings updated = current.copyWith(
        complete: true,
        permissionMode: permissionMode,
      );
      await ref
          .read(settingsRepositoryProvider)
          .markOnboardingComplete(
            languageCode: updated.languageCode,
            countryCode: updated.countryCode,
            countryName: updated.countryName,
            userName: updated.userName,
            permissionMode: updated.permissionMode,
          );
      // The gate answers redirects from its cached snapshot; without this the
      // user would be bounced straight back into onboarding until restart.
      setOnboardingState(updated);
    } on Object catch (error) {
      // Failing to persist must not trap the user in the first-run flow; the
      // gate re-reads the flag at the next launch.
      debugPrint('Could not persist onboarding state: $error');
    }
    if (mounted) context.go(AppRoutes.chats);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bool showProgress = _busy || _results.isNotEmpty;

    return Scaffold(
      backgroundColor: context.c.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxContentWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              // The hero and the progress view swap in place: one screen, two
              // states, no extra route to get the back stack wrong.
              child: AnimatedSwitcher(
                duration: AppDurations.normal,
                child: showProgress
                    ? _progressView(context, l10n)
                    : _heroView(context, l10n),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- hero

  Widget _heroView(BuildContext context, AppLocalizations l10n) {
    return LayoutBuilder(
      key: const ValueKey<String>('hero'),
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              // Centered when the screen is tall enough, scrollable when it is
              // not — a short landscape window must never overflow.
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FadeSlideIn(
                    child: Center(
                      child: Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              AppColors.accent,
                              AppColors.accentDark,
                            ],
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.35),
                              blurRadius: 36,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 80),
                    child: Text(
                      l10n.permissionGrantTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 140),
                    child: Text(
                      l10n.permissionGrantSubtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: context.c.textSecondary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 200),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _grantAll,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          textStyle: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        child: Text(l10n.grantAllPermissions),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 260),
                    child: TextButton(
                      onPressed: () =>
                          _enterApp(permissionMode: PermissionMode.justInTime),
                      child: Text(l10n.skip),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- progress

  Widget _progressView(BuildContext context, AppLocalizations l10n) {
    final double progress = _total == 0 ? 0 : _asked / _total;

    return Column(
      key: const ValueKey<String>('progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.requestingPermissions,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.lg),
        ClipRRect(
          borderRadius: AppRadius.rPill,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress),
            duration: AppDurations.normal,
            curve: AppDurations.curve,
            builder: (BuildContext context, double value, Widget? child) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: context.c.surfaceAlt,
                color: context.c.accent,
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$_asked / $_total',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.c.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ListView(
            children: <Widget>[
              for (final AppPermission permission in AppPermission.values)
                ListStagger(
                  index: permission.index,
                  child: _permissionRow(context, l10n, permission),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _permissionRow(
    BuildContext context,
    AppLocalizations l10n,
    AppPermission permission,
  ) {
    final PermissionResult? result = _results[permission];
    // While the walk is running, the first unanswered row is the one the OS
    // dialog on top is asking about — highlight it so the list and the
    // dialogs read as one motion.
    final bool isCurrent = _busy && result == null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: AppRadius.rLg,
        border: Border.all(
          color: isCurrent
              ? context.c.accent.withValues(alpha: 0.55)
              : context.c.divider,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            _icons[permission],
            size: 20,
            color: isCurrent ? context.c.accent : context.c.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _label(l10n, permission),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          _status(context, result, isCurrent),
        ],
      ),
    );
  }

  Widget _status(
    BuildContext context,
    PermissionResult? result,
    bool isCurrent,
  ) {
    if (isCurrent) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (result == null) {
      return Icon(
        Icons.radio_button_unchecked_rounded,
        size: 18,
        color: context.c.textSecondary.withValues(alpha: 0.5),
      );
    }
    if (result.isGranted) {
      return Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: context.c.onSuccess,
      );
    }
    // A denial is a normal outcome, not an error; a *permanent* denial is the
    // one state that needs a trip to system settings later, so it reads in the
    // danger tone.
    final bool severe =
        result == PermissionResult.permanentlyDenied ||
        result == PermissionResult.restricted;
    return Icon(
      Icons.cancel_rounded,
      size: 18,
      color: severe ? context.c.onDanger : context.c.textSecondary,
    );
  }
}
