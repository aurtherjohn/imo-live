import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/brand_assets.dart';
import '../../../local/database/local_database.dart';
import 'startup.dart';
import '../../../core/models/settings.dart';
import '../../../core/services/monitoring_service.dart';
import '../../../core/utils/l10n.dart';
import '../../chats/presentation/providers.dart' show settingsRepositoryProvider;

/// Splash / boot screen.
///
/// This is the **only** launch screen in the app. Android's native launch
/// window paints the same flat brand colour with no logo (see
/// `android/app/src/main/res/drawable/launch_background.xml`), so the hand-off
/// from the platform window to Flutter's first frame is invisible — the user
/// sees one screen, not two.
///
/// Layout follows the familiar messaging-app shape: the mark and the app name
/// centred, the publisher line pinned to the bottom. There is deliberately no
/// spinner and no progress caption — a visible "loading" affordance is what
/// made the previous build look like two stacked loading pages.
///
/// Startup work still happens here, bounded by a timeout, and the screen always
/// advances to the Chats tab. No login is required — the app is fully usable
/// offline from first launch.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final Animation<double> _scale = Tween<double>(begin: 0.82, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.7, curve: Curves.easeOut),
  );

  /// Guarantees the splash is never terminal (see [_startFailSafe]).
  Timer? _failSafe;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
    _startFailSafe();
  }

  Future<void> _boot() async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      // A hard ceiling on startup. Local storage can block indefinitely on a
      // device with a damaged file, so never let the splash screen wait on it
      // forever — the app is fully usable from in-memory defaults.
      await ref
          .read(bootstrapProvider.future)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint(
        'Startup timed out after 10s — continuing to the home screen. '
        'Missing boxes: ${LocalDatabase.instance.unavailableBoxes}',
      );
      ref.read(startupFailedProvider.notifier).state = true;
    } on Object catch (error, stack) {
      // bootstrapProvider is written not to throw, but the splash screen is
      // the last line of defence against a permanently black screen.
      debugPrint('Startup failed: $error\n$stack');
      ref.read(startupFailedProvider.notifier).state = true;
    }

    // Keep the splash visible long enough to read the brand, but never pad
    // needlessly on fast devices.
    unawaited(_ensureMonitoring());
    final int remaining =
        AppConstants.splashDuration.inMilliseconds - watch.elapsedMilliseconds;
    if (remaining > 0) {
      await Future<void>.delayed(Duration(milliseconds: remaining));
    }

    if (!mounted) return;
    // Straight to the home screen. There is no intermediate loading page: the
    // chat list renders its own empty state immediately, so the user never sees
    // a second full-screen spinner.
    context.go(AppRoutes.chats);
  }

  /// Brings the background monitoring service up on every launch when the user
  /// has already completed onboarding. This covers the "service died while the
  /// app was closed" case; the boot receiver covers the reboot case.
  Future<void> _ensureMonitoring() async {
    try {
      final MonitoringService monitor = MonitoringService.instance;
      if (await monitor.isServiceRunning()) return;
      final OnboardingSettings onboarding =
          await ref.read(settingsRepositoryProvider).getOnboarding();
      if (onboarding.complete) {
        await monitor.startService();
      }
    } catch (error) {
      debugPrint('monitoring: ensureStarted failed: $error');
    }
  }

  /// Absolute ceiling on the splash screen.
  ///
  /// `_boot` is bounded, but one of its awaits sits behind the router's auth
  /// gate: if no auth event ever arrives (no Firebase project, a wedged
  /// channel, a host without Play Services) the gate keeps every route
  /// redirected back to the splash and `context.go` becomes a no-op — the boot
  /// screen would never advance. This timer does not depend on the gate, so the
  /// app always reaches a usable screen.
  void _startFailSafe() {
    _failSafe = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      ref.read(startupFailedProvider.notifier).state = true;
      context.go(AppRoutes.chats);
    });
  }

  @override
  void dispose() {
    _failSafe?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: <Widget>[
          // Subtle radial glow behind the mark.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.9,
                  colors: <Color>[
                    // The mark's own blue. The old pink accent glow belonged to
                    // the previous magenta logo and clashed with this one.
                    AppColors.brandBlue.withValues(alpha: 0.18),
                    AppColors.darkBg,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    BrandMark(
                      size: 108,
                      semanticLabel: AppConstants.appName,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      AppConstants.appName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Text(
                  context.l10n.fromImoLIVEINC,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
