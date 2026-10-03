import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/services/call_signaling_service.dart';
import 'package:imo_live/features/calls/presentation/widgets/call_listener_banner.dart';
import 'package:imo_live/features/chats/presentation/providers.dart';

/// The point of this file: a failing ring listener must be *visible*.
///
/// A missing Firestore index once made every call ring out on the caller's phone
/// while the callee's stayed silent, and the only trace was a `debugPrint`. The
/// user's reasonable conclusion was "calls are broken". This banner is what stops
/// that from being silent a second time.
const String _warning = "Incoming calls can't ring on this device right now";

/// Pumps the banner with the ring listener in a chosen state.
///
/// The provider is fed a stream rather than an `AsyncValue` because
/// `StreamProvider` has no `overrideWithValue` in riverpod 2.6.1, and driving it
/// through a stream also exercises the real path: what the banner sees is what
/// `watchIncoming` actually produced.
Future<void> _pump(
  WidgetTester tester,
  Stream<List<CallDocument>> incoming,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        incomingCallsProvider.overrideWith(
          (Ref ref) => incoming,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CallListenerBanner()),
      ),
    ),
  );
  // Let the stream deliver its first event before asserting.
  await tester.pump();
}

void main() {
  group('CallListenerBanner', () {
    testWidgets('warns when the ring listener has failed', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        Stream<List<CallDocument>>.error(
          StateError('no composite index'),
          StackTrace.empty,
        ),
      );

      expect(find.text(_warning), findsOneWidget);
    });

    testWidgets('warns for any error, not just an Exception', (
      WidgetTester tester,
    ) async {
      // Firestore, permission failures and a bare `throw` all arrive here as a
      // plain Object. Keying off a type would let some of them through silently,
      // which is the exact failure being fixed.
      await _pump(
        tester,
        Stream<List<CallDocument>>.error('permission-denied', StackTrace.empty),
      );

      expect(find.text(_warning), findsOneWidget);
    });

    testWidgets('stays out of the way while the listener is healthy', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        Stream<List<CallDocument>>.value(const <CallDocument>[]),
      );

      expect(find.text(_warning), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays out of the way while the listener is still loading', (
      WidgetTester tester,
    ) async {
      // A future that never completes: the listener is neither healthy nor
      // failed, and the banner must not cry wolf during startup.
      await _pump(
        tester,
        Stream<List<CallDocument>>.fromFuture(
          Completer<List<CallDocument>>().future,
        ),
      );

      expect(find.text(_warning), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
