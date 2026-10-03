import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/l10n.dart';
import 'theme/app_tokens.dart';
import '../core/services/ad_service.dart';
import '../features/chats/presentation/providers.dart';
import '../features/earn/presentation/providers.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget.
///
/// Theme, locale and navigation all derive from persisted settings, so a
/// restart restores the exact appearance and language the user chose.
class ImoLiveApp extends ConsumerStatefulWidget {
  const ImoLiveApp({super.key});

  @override
  ConsumerState<ImoLiveApp> createState() => _ImoLiveAppState();
}

class _ImoLiveAppState extends ConsumerState<ImoLiveApp>
    with WidgetsBindingObserver {
  /// The session-wide ad service, resolved once so [dispose] can release it
  /// without touching `ref` while the element is unmounting.
  ///
  /// ⚠️ It must be disposed from here, not left to the provider container:
  /// `AdService` owns a five-minute foreground timer and a bounded SDK-init
  /// timer, and `flutter_test` asserts that no timer outlives the widget tree.
  /// The container's own `onDispose` fires later than that check.
  late final AdService _ads;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ads = ref.read(adServiceProvider);
    // Bring the ads SDK up once, off the first frame, and start the
    // continuous-foreground clock that gates the foreground interstitial.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_ads.init());
      _ads.startForegroundClock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ads.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Restarted rather than resumed: the interval measures *continuous*
        // foreground time, so backgrounding for four minutes and returning must
        // not immediately produce an ad.
        _ads.startForegroundClock();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _ads.stopForegroundClock();
      case AppLifecycleState.inactive:
        // Transient (a permission dialog, the app switcher). Leave the clock
        // running — the user has not really left.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final Color accent = ref.watch(accentColorProvider);
    final String language =
        ref.watch(languageProvider).valueOrNull ?? 'en';

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      themeMode: themeMode,
      theme: AppTheme.light(accent: accent),
      darkTheme: AppTheme.dark(accent: accent),
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (BuildContext context, Widget? child) {
        // Publish the live localisations for the service layer, which has no
        // BuildContext. This runs on every rebuild, so a language change is
        // picked up by the services on the same frame the widgets see it.
        L10nRef.publish(
          Localizations.of<AppLocalizations>(context, AppLocalizations) ??
              L10nRef.current,
        );
        // Respect the accessibility "reduce motion" preference.
        final bool reduceMotion = MediaQuery.of(context).disableAnimations;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.of(context).textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.6,
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ReducedMotionScope(
              reduceMotion: reduceMotion,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

/// Provides a global "reduce motion" flag to descendants.
///
/// Public so tests can reproduce the real chain — `prefersReducedMotion` reads
/// this scope, which `ImoLiveApp` publishes from `MaterialApp.builder`, so a
/// test that wraps in a bare `MediaQuery(disableAnimations: true)` proves
/// nothing.
class ReducedMotionScope extends InheritedWidget {
  const ReducedMotionScope({
    super.key,
    required this.reduceMotion,
    required super.child,
  });

  final bool reduceMotion;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReducedMotionScope>()
          ?.reduceMotion ??
      false;

  @override
  bool updateShouldNotify(ReducedMotionScope oldWidget) =>
      oldWidget.reduceMotion != reduceMotion;
}

/// Public accessor for the reduce-motion flag.
bool prefersReducedMotion(BuildContext context) =>
    ReducedMotionScope.of(context);

/// Animates a widget in on first build — used by screens for a subtle entrance.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 12,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.slow + delay,
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? c) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * offset),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

/// The page transition every pushed route uses.
///
/// ### Why this exists rather than `MaterialPage`
///
/// `builder:` gives each platform's default transition, so the same push slides
/// from the right on Android, the left on iOS, and fades on web — and a screen
/// reached from a deep link animates differently from one reached by a tap. A
/// single transition makes navigation feel like one app.
///
/// ### Reduce motion
///
/// Honoured here, not in the route table: when the platform asks for reduced
/// motion the child is returned with no transition at all, which is the
/// accessibility contract. Doing it per-route would invite a route that forgets.
///
/// The curve is [AppDurations.emphasized] — an ease-out-back — because a push
/// is a deliberate user action and a little overshoot reads as responsive
/// rather than sluggish.
Page<void> appPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppDurations.normal,
    reverseTransitionDuration: AppDurations.fast,
    child: child,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      if (prefersReducedMotion(context)) return child;

      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final Animation<double> outgoing = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          // The screen being covered drifts very slightly the other way. Kept
          // small on purpose: a large counter-slide is the parallax that makes
          // a fast back-navigation feel like it is throwing the page away.
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.02, 0),
            ).animate(outgoing),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Staggers its children in, one after another, when a list first appears.
///
/// ### Why a wrapper rather than animating each row
///
/// A list that fades every row in at once reads as a single flash; one that
/// staggers reads as the list *assembling*. The stagger has to be the row's
/// index, which only the list builder knows — so this takes the index and
/// computes the delay, keeping the call site to one line.
///
/// ### The cap is deliberate
///
/// Beyond [maxStaggered] rows the delay stops growing. A 500-row list where
/// row 500 waits 12 seconds is not a nice animation, it is a bug. Rows past the
/// cap simply appear with the last delay.
///
/// Reduced motion returns the child unchanged, so the accessibility setting
/// turns every entrance off at once.
class ListStagger extends StatelessWidget {
  const ListStagger({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 26),
    this.maxStaggered = 9,
    this.offset = 10,
  });

  /// The row's position. Only the first [maxStaggered] positions are staggered.
  final int index;
  final Widget child;
  final Duration step;
  final int maxStaggered;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final int capped = index < 0 ? 0 : (index > maxStaggered ? maxStaggered : index);
    return FadeSlideIn(
      delay: step * capped,
      offset: offset,
      child: child,
    );
  }
}

/// A scale-and-fade used for content that swaps in place — a counter, a badge,
/// a stat that changes. Cheaper than a route transition and reads as the value
/// arriving rather than the screen changing.
class ValueSwap extends StatelessWidget {
  const ValueSwap({
    super.key,
    required this.child,
    this.duration = AppDurations.normal,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: prefersReducedMotion(context) ? Duration.zero : duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
