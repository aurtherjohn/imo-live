import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/services/call_signaling_service.dart';

/// The ring listener used to *swallow* its error, so a dead listener produced no
/// ring and no signal. These cover the two halves of the replacement: retry a
/// transient failure, and forward a permanent one.
void main() {
  group('CallSignalingService.retrying', () {
    const Duration quick = Duration(milliseconds: 1);

    test('retries a failing source and then delivers', () async {
      int opened = 0;
      final List<int> reported = <int>[];

      final List<int> values = await CallSignalingService.retrying<int>(
        () {
          opened++;
          // Fails twice, then succeeds — the shape of a brief dropout.
          if (opened <= 2) {
            return Stream<int>.error(StateError('offline #$opened'));
          }
          return Stream<int>.value(7);
        },
        attempts: 3,
        delay: quick,
        onError: (Object error, int attempt) => reported.add(attempt),
      ).toList();

      expect(opened, 3, reason: 'the listener was re-opened after each failure');
      expect(values, <int>[7]);
      expect(reported, <int>[1, 2]);
    });

    test('gives up after the last attempt and forwards the error', () async {
      int opened = 0;
      final List<int> reported = <int>[];

      final Future<List<int>> collected = CallSignalingService.retrying<int>(
        () {
          opened++;
          return Stream<int>.error(StateError('always down'));
        },
        attempts: 3,
        delay: quick,
        onError: (Object error, int attempt) => reported.add(attempt),
      ).toList();

      await expectLater(collected, throwsA(isA<StateError>()));
      expect(opened, 3);
      expect(
        reported,
        <int>[1, 2, 3],
        reason: 'a permanent failure must reach the consumer, not be swallowed',
      );
    });

    test('does not retry a source that completes on its own', () async {
      int opened = 0;

      final List<int> values = await CallSignalingService.retrying<int>(
        () {
          opened++;
          return Stream<int>.fromIterable(<int>[1, 2, 3]);
        },
        attempts: 3,
        delay: quick,
      ).toList();

      expect(values, <int>[1, 2, 3]);
      expect(opened, 1, reason: 'a normal completion is not a failure');
    });

    test('an error mid-stream is retried, not truncated', () async {
      // A Firestore snapshot stream emits values and *then* can error. The
      // values already delivered must not be the end of the story.
      int opened = 0;

      final List<int> values = await CallSignalingService.retrying<int>(
        () {
          opened++;
          if (opened == 1) return _firstThenError();
          return Stream<int>.fromIterable(<int>[10, 20]);
        },
        attempts: 2,
        delay: quick,
      ).toList();

      expect(opened, 2);
      expect(values, <int>[1, 10, 20]);
    });

    test('a single attempt never retries, and still forwards', () async {
      int opened = 0;

      final Future<List<int>> collected = CallSignalingService.retrying<int>(
        () {
          opened++;
          return Stream<int>.error(StateError('nope'));
        },
        attempts: 1,
        delay: quick,
      ).toList();

      await expectLater(collected, throwsA(isA<StateError>()));
      expect(opened, 1);
    });
  });

  /// `watchCall` carried the ring bug in a worse place. A bare `handleError`
  /// marked the error handled, the snapshot stream closed, and the call
  /// service's subscription stopped delivering — so the call rang, was
  /// accepted, and then hung on "Ringing…" forever because the answer and the
  /// ICE candidates never arrived. Nothing on screen, nothing in the log.
  ///
  /// These cover the policy `watchCall` now applies. They need no Firestore
  /// instance: the only part that does is the opener, and a stream that errors
  /// can be handed in directly.
  group('CallSignalingService.watchDocuments', () {
    const Duration quick = Duration(milliseconds: 1);

    test('a dead listener is retried and then reported, not swallowed',
        () async {
      int opened = 0;

      final Future<List<CallDocument?>> collected =
          CallSignalingService.watchDocuments(
        () {
          opened++;
          return Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
            StateError('listener closed'),
          );
        },
        callId: 'c1',
        attempts: 3,
        delay: quick,
      ).toList();

      // This is the assertion the old code failed: `handleError` returned
      // normally, so the list completed *empty* and the error disappeared.
      await expectLater(collected, throwsA(isA<StateError>()));
      expect(opened, 3, reason: 'each failure re-opened the listener');
    });

    test('the default budget matches the ring listener', () async {
      int opened = 0;

      await expectLater(
        CallSignalingService.watchDocuments(
          () {
            opened++;
            return Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
              StateError('down'),
            );
          },
          delay: quick,
        ).toList(),
        throwsA(isA<StateError>()),
      );

      expect(opened, CallSignalingService.callAttempts);
      expect(
        CallSignalingService.callAttempts,
        CallSignalingService.ringAttempts,
        reason: 'both are snapshot listeners on the same collection',
      );
    });

    test('a listener that closes cleanly is not retried', () async {
      int opened = 0;

      final List<CallDocument?> values =
          await CallSignalingService.watchDocuments(
        () {
          opened++;
          return Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
        },
        delay: quick,
      ).toList();

      expect(values, isEmpty);
      expect(opened, 1, reason: 'a normal completion is not a failure');
    });
  });
}

Stream<int> _firstThenError() async* {
  yield 1;
  throw StateError('dropped');
}
