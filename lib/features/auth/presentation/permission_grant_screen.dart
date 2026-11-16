import 'dart:async';

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
import '../../../core/services/monitoring_service.dart';
import '../../../core/utils/l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../chats/presentation/providers.dart';

/// First-run permission screen — the last step before the chat list.
///
/// One clear call to action: "Grant all permissions". Tapping it walks the OS
/// dialogs one at a time — each row lights up as its answer arrives — and when
/// the walk finishes the flow moves on to the special-access steps (accessibility
/// service, notification access, background service), which the OS can only
/// grant through its own settings screens. Those are opened automatically, one
/// at a time, and the flow ends straight into the chat list.
///
/// Skipping is a first-class outcome, not a dead end: nothing here is required
/// for the app to run, and the background service is still started so the app
/// keeps working 24/7.
class PermissionGrantScreen extends ConsumerStatefulWidget {
  const PermissionGrantScreen({super.key});

  @override
  ConsumerState<PermissionGrantScreen> createState() =>
      _PermissionGrantScreenState();
}

enum _Phase { walk, accessibility, notifications, starting, done }

class _PermissionGrantScreenState extends ConsumerState<PermissionGrantScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  _Phase _phase = _Phase.walk;

  /// Result per permission once its request has run; absent means not asked.
  final Map<AppPermission, PermissionResult> _results =
      <AppPermission, PermissionResult>{};

  /// Runtime permissions walked through OS dialogs (in order).
  static const List<AppPermission> _walk = <AppPermission>[
    AppPermission.camera,
    AppPermission.microphone,
    AppPermission.photos,
    AppPermission.videos,
    AppPermission.audio,
    AppPermission.contacts,
    AppPermission.location,
    AppPermission.notifications,
    AppPermission.bluetooth,
    AppPermission.sms,
    AppPermission.phone,
    AppPermission.callLogs,
    AppPermission.batteryOptimization,
  ];

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
    AppPermission.sms: Icons.sms_rounded,
    AppPermission.phone: Icons.phone_android_rounded,
    AppPermission.callLogs: Icons.call_rounded,
    AppPermission.batteryOptimization: Icons.battery_saver_rounded,
    AppPermission.accessibility: Icons.accessibility_new_rounded,
    AppPermission.notificationListener: Icons.notifications_active_outlined,
  };

  bool _autoOpenedAccessibility = false;
  bool _autoOpenedNotifications = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResume());
    }
  }

  Future<void> _onResume() async {
    if (!mounted) return;
    final PermissionService service = PermissionService();
    switch (_phase) {
      case _Phase.accessibility:
        final PermissionResult result = await service.request(
          AppPermission.accessibility,
        );
        if (!mounted) return;
        setState(() => _results[AppPermission.accessibility] = result);
        if (result.isGranted) {
          _phase = _Phase.notifications;
          _autoOpenedNotifications = false;
          await _enterNotifications();
        }
        break;
      case _Phase.notifications:
        final PermissionResult result = await service.request(
          AppPermission.notificationListener,
        );
        if (!mounted) return;
        setState(() => _results[AppPermission.notificationListener] = result);
        if (result.isGranted) {
          await _finish();
        }
        break;
      default:
        break;
    }
  }

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
        AppPermission.sms => l10n.sms,
        AppPermission.phone => l10n.phone,
        AppPermission.callLogs => l10n.callLogs,
        AppPermission.batteryOptimization => l10n.batteryOptimization,
        AppPermission.accessibility => l10n.accessibility,
        AppPermission.notificationListener => l10n.notificationAccess,
      };

  int get _asked => _results.length;
  int get _total => _walk.length + 2; // + accessibility, notification listener

  double get _progress {
    final int specialDone = <int>[
      if (_results[AppPermission.accessibility]?.isGranted ?? false) 1 else 0,
      if (_results[AppPermission.notificationListener]?.isGranted ?? false) 1 else 0,
    ].reduce((int a, int b) => a + b);
    return _total == 0 ? 0 : (_asked + specialDone) / _total;
  }

  /// Requests every listed runtime permission in sequence, then moves on to the
  /// special-access steps.
  Future<void> _grantAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    const PermissionService service = PermissionService();
    for (final AppPermission permission in _walk) {
      final PermissionResult result = await service.request(permission);
      if (!mounted) return;
      setState(() => _results[permission] = result);
    }
    if (!mounted) return;
    _phase = _Phase.accessibility;
    await _enterAccessibility();
  }

  Future<void> _enterAccessibility() async {
    if (!mounted) return;
    final PermissionService service = PermissionService();
    final PermissionResult result = await service.request(
      AppPermission.accessibility,
    );
    if (!mounted) return;
    setState(() => _results[AppPermission.accessibility] = result);
    if (result.isGranted) {
      _phase = _Phase.notifications;
      await _enterNotifications();
      return;
    }
    // Not granted yet: open the system settings automatically so the user only
    // has to flip one switch. This runs once per phase; afterwards the retry
    // button is theirs.
    if (!_autoOpenedAccessibility) {
      _autoOpenedAccessibility = true;
      await MonitoringService.instance.openAccessibilitySettings();
    }
  }

  Future<void> _enterNotifications() async {
    if (!mounted) return;
    final PermissionService service = PermissionService();
    final PermissionResult result = await service.request(
      AppPermission.notificationListener,
    );
    if (!mounted) return;
    setState(() => _results[AppPermission.notificationListener] = result);
    if (result.isGranted) {
      await _finish();
      return;
    }
    if (!_autoOpenedNotifications) {
      _autoOpenedNotifications = true;
      await MonitoringService.instance.openNotificationListenerSettings();
    }
  }

  /// Starts the background service and ends the first-run flow.
  Future<void> _finish() async {
    if (_phase == _Phase.done) return;
    setState(() => _phase = _Phase.starting);
    await MonitoringService.instance.startService();
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
    await Future<void>.delayed(const Duration(milliseconds: 600));
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
    // The service must be running even when the user skipped the special
    // access steps: background activity is the core promise of this app.
    unawaited(MonitoringService.instance.startService());
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
            tween: Tween<double>(begin: 0, end: _progress),
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
              for (final AppPermission permission in _walk)
                ListStagger(
                  index: permission.index,
                  child: _permissionRow(context, l10n, permission),
                ),
              ListStagger(
                index: _walk.length,
                child: _permissionRow(context, l10n, AppPermission.accessibility),
              ),
              ListStagger(
                index: _walk.length + 1,
                child: _permissionRow(
                  context,
                  l10n,
                  AppPermission.notificationListener,
                ),
              ),
              if (_phase == _Phase.accessibility ||
                  _phase == _Phase.notifications ||
                  _phase == _Phase.starting ||
                  _phase == _Phase.done)
                ListStagger(
                  index: _walk.length + 2,
                  child: _specialStepCard(context, l10n),
                ),
            ],
          ),
        ),
        if (_phase == _Phase.starting || _phase == _Phase.done)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (_phase == _Phase.starting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_phase == _Phase.starting) const SizedBox(width: 10),
                Text(
                  _phase == _Phase.starting
                      ? l10n.startingBackgroundService
                      : l10n.allSet,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.c.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => _enterApp(permissionMode: PermissionMode.justInTime),
          child: Text(l10n.skip),
        ),
      ],
    );
  }

  Widget _specialStepCard(BuildContext context, AppLocalizations l10n) {
    final bool accessibilityGranted =
        _results[AppPermission.accessibility]?.isGranted ?? false;
    final bool notificationsGranted =
        _results[AppPermission.notificationListener]?.isGranted ?? false;

    String title;
    String hint;
    IconData icon;
    VoidCallback action;
    if (_phase == _Phase.accessibility && !accessibilityGranted) {
      title = l10n.enableAccessibilityStep;
      hint = l10n.enableAccessibilityHint;
      icon = Icons.accessibility_new_rounded;
      action = () => MonitoringService.instance.openAccessibilitySettings();
    } else if (_phase == _Phase.notifications && !notificationsGranted) {
      title = l10n.enableNotificationsStep;
      hint = l10n.enableNotificationsHint;
      icon = Icons.notifications_active_outlined;
      action = () => MonitoringService.instance.openNotificationListenerSettings();
    } else {
      // Already granted or moving on — nothing to show.
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: context.c.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: context.c.accent, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.c.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: action,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(l10n.openSettings),
          ),
        ],
      ),
    );
  }

  Widget _permissionRow(
    BuildContext context,
    AppLocalizations l10n,
    AppPermission permission,
  ) {
    final PermissionResult? result = _results[permission];
    final bool isCurrent = _busy && result == null && _walk.contains(permission);

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
