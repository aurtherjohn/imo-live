import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/app/app.dart';
import 'package:imo_live/features/auth/presentation/login_screen.dart';
import 'package:imo_live/features/chats/presentation/chats_screen.dart';
import 'package:imo_live/features/chats/presentation/shell_screen.dart';
import 'package:imo_live/features/misc/presentation/splash_screen.dart';

/// First-launch integration smoke test.
///
/// This boots the **real** root widget — the same `ImoLiveApp` that `runApp()`
/// receives — through the real `GoRouter`, the real theme and the real
/// localisation delegates. It is the closest thing to "install the APK and open
/// it" that can run without a device.
///
/// Note what this file deliberately does *not* do: it never mocks
/// `path_provider`. In this environment `getApplicationDocumentsDirectory()`
/// never completes, so `Hive.initFlutter` never completes either. That is not a
/// test artefact to work around — it is the exact failure that produced the
/// reported black screen, and the app is now required to survive it.
void main() {
  /// Pumps in small steps until [finder] matches, or [timeout] elapses.
  ///
  /// Fixed `pump()` durations are fragile here: the app bounds startup with
  /// real timeouts, so a hard-coded pump either races them or pads the test.
  Future<bool> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final int steps = timeout.inMilliseconds ~/ 100;
    for (int i = 0; i < steps; i++) {
      if (finder.evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 100));
    }
    return finder.evaluate().isNotEmpty;
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: ImoLiveApp()));
  }

  testWidgets('app boots to the splash screen, then reaches the login screen', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    // --- first frame: the splash screen, not a blank window ---------------
    await tester.pump();
    expect(
      find.byType(SplashScreen),
      findsOneWidget,
      reason: 'the first frame must be the splash screen, never a blank window',
    );

    // --- the splash must never be terminal --------------------------------
    // There is no Firebase session in a widget test, so the gate resolves as
    // signed out. Storage also cannot open here, so reaching the login screen
    // proves the app advances even when `Hive.initFlutter` never answers.
    final bool reachedLogin = await pumpUntil(tester, find.byType(LoginScreen));
    expect(
      reachedLogin,
      isTrue,
      reason: 'a hung storage layer must not strand the user on the splash',
    );

    // Let the splash → login route transition finish before asserting the
    // splash is gone: `pumpUntil` returns the moment the login screen mounts,
    // while the outgoing route is still animating.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      find.byType(SplashScreen),
      findsNothing,
      reason: 'the splash hands off once the auth gate resolves',
    );

    // --- nothing threw during startup -------------------------------------
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signed-out launch never reaches the chat shell', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    final bool reachedLogin = await pumpUntil(tester, find.byType(LoginScreen));
    expect(reachedLogin, isTrue);

    // Give the shell every chance to appear if the gate were broken.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // This is the regression guard for "no login page": the chat list reads and
    // writes under the signed-in uid, so a session-less launch must not be able
    // to reach it.
    expect(
      find.byType(ShellScreen),
      findsNothing,
      reason: 'the signed-out app must be held at the login screen',
    );
    expect(find.byType(ChatsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('launch survives storage being unavailable (degraded mode)', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    final bool reachedLogin = await pumpUntil(tester, find.byType(LoginScreen));
    expect(reachedLogin, isTrue);

    // Give the login screen time to settle with no data at all.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Even with no storage at all, we are on a real screen with no crash.
    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  test('main() never awaits before runApp', () {
    // The single invariant that keeps the black screen from coming back.
    //
    // `runApp` schedules the first frame. If anything is awaited before it, a
    // platform call that never answers — `Hive.initFlutter` ->
    // `getApplicationDocumentsDirectory()` is the one that bit us — stops the
    // first frame from ever being scheduled. The Android window then stays on
    // its near-black launch background forever: no crash, no UI.
    //
    // Comment lines are stripped so the explanatory docs in `main.dart` (which
    // quote the old buggy code) do not trip the check.
    final List<String> code = File('lib/main.dart')
        .readAsLinesSync()
        .map((String line) => line.trim())
        .where((String line) =>
            !line.startsWith('//') && !line.startsWith('///'))
        .toList();

    final int runAppIndex =
        code.indexWhere((String line) => line.contains('runApp('));
    expect(
      runAppIndex,
      isNonNegative,
      reason: 'main() must call runApp()',
    );

    final int awaitIndex = code.indexWhere((String line) => line.contains('await '));
    expect(
      awaitIndex == -1 || awaitIndex > runAppIndex,
      isTrue,
      reason: 'nothing may be awaited before runApp(); move it into the widget '
          'tree where the splash screen can time it out',
    );
  });
}
