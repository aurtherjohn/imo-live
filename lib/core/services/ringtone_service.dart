import 'dart:async';

import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Rings the **device's own ringtone** while an incoming call is on screen.
///
/// ## Why this is not the notification sound
///
/// [NotificationService] owns the notification-channel sound, which the OS
/// plays **once**, for a few seconds, when the push lands. A phone call rings
/// until somebody answers it. Those are different requirements, so they are
/// different players: the channel sound announces the push, this rings for as
/// long as the incoming-call screen is up.
///
/// ## Why it is a static class
///
/// There is exactly one ringtone on the device, so there is nothing to
/// instantiate or scope. The call screen is also the only caller, and it can
/// be rebuilt freely while the same call is ringing — a static guard is what
/// keeps a rebuild from stacking a second ring on top of the first.
///
/// Every entry point fails silently. A ringtone is a courtesy; if the platform
/// refuses to play it (a silent profile, a missing channel, a plugin error on
/// an OEM build) the incoming call must still be answerable. Throwing here
/// would take down the call screen over a sound effect.
class RingtoneService {
  const RingtoneService._();

  /// True while a ringtone is believed to be playing.
  ///
  /// Guarding on this rather than on the call state is deliberate: the call
  /// state can be `ringing` while the user has already silenced the device,
  /// and the cost of a redundant [stop] is zero, while the cost of a redundant
  /// [start] is a second ringtone layered over the first.
  static bool _isPlaying = false;

  /// Starts the incoming-call ring, looping until [stop] is called.
  ///
  /// Safe to call more than once — the second call is a no-op.
  static void startIncoming() {
    if (_isPlaying) return;
    _isPlaying = true;
    // ⚠️ `playRingtone` is async, so a `try`/`catch` around the call would
    // catch nothing — the platform error surfaces on the returned future, not
    // at the call site. `catchError` is what actually keeps a plugin failure
    // from becoming an unhandled exception, and it clears the guard so the
    // next incoming call still tries.
    unawaited(
      FlutterRingtonePlayer()
          .playRingtone(looping: true, volume: 1.0, asAlarm: false)
          .catchError((Object _) => _isPlaying = false),
    );
  }

  /// Stops the ring. Safe to call when nothing is playing.
  ///
  /// Called on accept, on decline/end, and from the call screen's `dispose` —
  /// the last of which is what stops the ring when the user leaves by the
  /// system back gesture rather than by tapping a button.
  static void stop() {
    if (!_isPlaying) return;
    _isPlaying = false;
    // The guard is cleared before the platform call, so a failing `stop()`
    // cannot leave the service permanently deaf to the next `startIncoming()`.
    unawaited(FlutterRingtonePlayer().stop().catchError((Object _) {}));
  }
}

