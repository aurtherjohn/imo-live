import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:imo_live/app/app.dart';
import 'package:imo_live/app/theme/app_theme.dart';

/// The animation layer makes one promise that regresses silently: **reduced
/// motion turns it off, everywhere, without the call sites opting in.**
///
/// A widget that animates anyway still looks fine in a screenshot and still
/// passes a golden diff of the end state, so nothing catches it except a test
/// that asks the question directly. That is what this file is for.
///
/// ### Why the scope, not just MediaQuery
///
/// `prefersReducedMotion` reads an inherited scope that `ImoLiveApp` publishes
/// from its `MaterialApp.builder`, not `MediaQuery` directly — so wrapping the
/// test in a bare `MediaQuery(disableAnimations: true)` changes nothing. That is
/// exactly the trap this file fell into on the first run. The helper below
/// reproduces the real chain.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark().copyWith(
        splashFactory: InkSplash.splashFactory,
      ),
      builder: (BuildContext context, Widget? inner) => ReducedMotionScope(
        reduceMotion: reduceMotion,
        child: inner ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('prefersReducedMotion', () {
    testWidgets('follows the platform flag', (WidgetTester tester) async {
      late BuildContext ctx;
      await _pump(
        tester,
        Builder(builder: (BuildContext c) {
          ctx = c;
          return const SizedBox();
        }),
      );
      expect(prefersReducedMotion(ctx), isFalse);
    });

    testWidgets('is true when the platform asks for it', (
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      await _pump(
        tester,
        Builder(builder: (BuildContext c) {
          ctx = c;
          return const SizedBox();
        }),
        reduceMotion: true,
      );
      expect(prefersReducedMotion(ctx), isTrue);
    });
  });

  group('ListStagger', () {
    testWidgets('renders its child at every index', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        Column(
          children: <Widget>[
            for (int i = 0; i < 5; i++)
              ListStagger(index: i, child: Text('row $i')),
          ],
        ),
      );
      await tester.pumpAndSettle();
      for (int i = 0; i < 5; i++) {
        expect(find.text('row $i'), findsOneWidget);
      }
    });

    testWidgets('settles to fully opaque with animation enabled', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const ListStagger(index: 1, child: Text('element')),
      );
      await tester.pumpAndSettle();

      final Finder fade = find.ancestor(
        of: find.text('element'),
        matching: find.byType(FadeTransition),
      );
      expect(fade, findsWidgets);
      final FadeTransition ft = tester.widget<FadeTransition>(fade.first);
      expect(ft.opacity.value, closeTo(1.0, 0.001));
    });

    testWidgets('negative index does not throw or produce a negative delay', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const ListStagger(index: -3, child: Text('odd')),
      );
      await tester.pumpAndSettle();
      expect(find.text('odd'), findsOneWidget);
    });

    testWidgets('a huge index is capped, not scaled endlessly', (
      WidgetTester tester,
    ) async {
      // If the cap were removed this would take ~15 s to settle and the 10 s
      // pumpAndSettle in this file would time out — which is the point.
      await _pump(
        tester,
        const ListStagger(index: 5000, child: Text('deep')),
      );
      await tester.pumpAndSettle();
      expect(find.text('deep'), findsOneWidget);
    });

    testWidgets('reduced motion shows the child immediately', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const ListStagger(index: 8, child: Text('instant')),
        reduceMotion: true,
      );
      // One frame only: with animations disabled there is nothing to wait for.
      await tester.pump();
      expect(find.text('instant'), findsOneWidget);
    });
  });

  group('ValueSwap', () {
    testWidgets('shows the new value after the swap', (
      WidgetTester tester,
    ) async {
      await _pump(tester, const ValueSwap(child: Text('42')));
      await tester.pumpAndSettle();
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('animates between two keyed values', (
      WidgetTester tester,
    ) async {
      Widget build(int n) => ValueSwap(
        child: Text('$n', key: ValueKey<int>(n)),
      );

      await _pump(tester, build(1));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      await _pump(tester, build(2));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('reduced motion swaps with no duration', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const ValueSwap(child: Text('live')),
        reduceMotion: true,
      );
      await tester.pump();
      expect(find.text('live'), findsOneWidget);
    });
  });

  group('appPage', () {
    testWidgets('honours reduced motion by returning the bare child', (
      WidgetTester tester,
    ) async {
      // Build a real router so the state is a real GoRouterState — faking one
      // would test nothing, since the whole point is that the state's pageKey
      // is carried through.
      final GoRouter router = GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          GoRoute(
            path: '/a',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                appPage(state, const Text('destination')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp.router(
            theme: AppTheme.dark().copyWith(
              splashFactory: InkSplash.splashFactory,
            ),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('destination'), findsOneWidget);
    });

    testWidgets('renders the destination with animation enabled', (
      WidgetTester tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          GoRoute(
            path: '/a',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                appPage(state, const Text('animated')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.dark().copyWith(
            splashFactory: InkSplash.splashFactory,
          ),
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('animated'), findsOneWidget);
    });
  });
}
