import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/utils/stream_retry.dart';

/// [retryStream] is the fix for the class of bug where
/// `stream.handleError((e) => log(e))` — a handler that returns normally —
/// marks the error handled and **closes the stream permanently**. That turned a
/// one-second network blip into a listener that was silently dead for the rest
/// of the session: incoming messages stopped arriving, the chat list stopped
/// updating, and nothing on screen said so.
///
/// These cover the two halves of the replacement: a transient failure is
/// retried, and a permanent one is *forwarded* rather than swallowed.
void main() {
  group('retryStream', () {
    const Duration quick = Duration(milliseconds: 1);

    test('retries a failing source and then delivers', () async {
      int opened = 0;
      final List<int> reported = <int>[];

      final List<int> values = await retryStream<int>(
        () {
          opened++;
          if (opened <= 2) {
            return Stream<int>.error(StateError('offline #$opened'));
          }
          return Stream<int>.value(7);
        },
        attempts: 3,
        delay: quick,
        onError: (Object error, int attempt) => reported.add(attempt),
      ).toList();

      expect(opened, 3, reason: 'the source was re-opened after each failure');
      expect(values, <int>[7]);
      expect(reported, <int>[1, 2]);
    });

    test('gives up after the last attempt and forwards the error', () async {
      int opened = 0;

      final Future<List<int>> collected = retryStream<int>(
        () {
          opened++;
          return Stream<int>.error(StateError('always down'));
        },
        attempts: 3,
        delay: quick,
      ).toList();

      // The assertion the old `handleError` code failed: the error must reach
      // the consumer, not be converted into a clean empty completion.
      await expectLater(collected, throwsA(isA<StateError>()));
      expect(opened, 3);
    });

    test('a source that completes on its own is not retried', () async {
      int opened = 0;

      final List<int> values = await retryStream<int>(
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
      // values already delivered must not be the end of the story — this is
      // exactly the shape of a chat listener that dies after the first page.
      int opened = 0;

      final List<int> values = await retryStream<int>(
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

    test('attempts: 0 keeps retrying past any fixed budget', () async {
      // This is what the long-lived chat and points listeners use. A bounded
      // retry would still leave them dead after the budget ran out, which is
      // the bug — just slower.
      int opened = 0;

      final List<int> values = await retryStream<int>(
        () {
          opened++;
          if (opened <= 12) {
            return Stream<int>.error(StateError('flaky #$opened'));
          }
          return Stream<int>.value(99);
        },
        attempts: 0,
        delay: quick,
        maxDelay: quick,
      ).toList();

      expect(opened, 13);
      expect(values, <int>[99]);
    });

    test('a single attempt never retries, and still forwards', () async {
      int opened = 0;

      final Future<List<int>> collected = retryStream<int>(
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
}

Stream<int> _firstThenError() async* {
  yield 1;
  throw StateError('dropped');
}
