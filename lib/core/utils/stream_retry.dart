import 'dart:async';

/// Re-opens a stream that failed, instead of letting the failure end it.
///
/// ### The bug this exists to kill
///
/// `stream.handleError((e) { debugPrint(e); })` looks like "log the error and
/// carry on". It is not. A handler that **returns normally marks the error as
/// handled**, and a `Stream` that has delivered an error is **done** — the
/// subscription is closed and no further events will ever arrive. So the
/// innocent-looking line
///
/// ```dart
/// firestore.snapshots().handleError((Object e) => debugPrint('$e'));
/// ```
///
/// turns one transient failure — a moment of no network, a token refresh, a
/// Firestore `UNAVAILABLE` — into a listener that is **silently dead for the
/// rest of the screen's life**. The UI does not error; it simply stops
/// updating. That is the single worst failure mode a real-time app can have,
/// and it is invisible in testing on a good connection.
///
/// This helper is the fix: run the source, and if it errors, wait and open a
/// fresh one. The consumer sees one continuous stream, and a blip costs a
/// couple of seconds rather than the session.
///
/// ### Why `await for` and not `yield*`
///
/// An error from a `yield*` source is forwarded straight to the consumer and
/// the `yield*` expression itself completes normally — so a `catch` around it
/// never fires and the retry silently never happens. `await for` rethrows into
/// the enclosing `try`, where it can actually be handled. This is the same
/// trap `CallSignalingService.retrying` documents, and the reason this helper
/// is shared rather than re-written per service.
///
/// [attempts] is the number of *opens* to try. `0` means "keep trying for as
/// long as the consumer is listening", which is what a long-lived listener
/// wants: the subscription is cancelled by its owner (a screen's `dispose`),
/// so an unbounded retry cannot outlive the thing that needs it. The delay
/// grows so a hard failure does not hammer the network.
Stream<T> retryStream<T>(
  Stream<T> Function() open, {
  int attempts = 3,
  Duration delay = const Duration(seconds: 2),
  Duration maxDelay = const Duration(seconds: 30),
  void Function(Object error, int attempt)? onError,
}) async* {
  int attempt = 0;
  Duration wait = delay;

  while (true) {
    attempt++;
    try {
      await for (final T value in open()) {
        yield value;
      }
      // The source completed on its own. There is nothing to retry — a
      // Firestore snapshot stream only completes when its listener is closed.
      return;
    } on Object catch (error) {
      onError?.call(error, attempt);
      if (attempts > 0 && attempt >= attempts) rethrow;
    }
    await Future<void>.delayed(wait);
    final Duration doubled = wait * 2;
    if (doubled > maxDelay) {
      wait = maxDelay;
    } else {
      wait = doubled;
    }
  }
}
