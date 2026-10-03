import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Playback state for the single shared voice-note player.
///
/// Only one note plays at a time — tapping a second note stops the first, which
/// is what a messaging app is expected to do. [messageId] identifies which
/// bubble the state belongs to, so every other bubble renders as idle.
@immutable
class VoicePlayback {
  const VoicePlayback({
    this.messageId,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  /// The message currently loaded, or null when nothing is playing.
  final String? messageId;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration duration;

  /// Playback position as a fraction of the total duration, clamped to 0..1.
  double get progress {
    final int total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  VoicePlayback copyWith({
    String? messageId,
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
  }) =>
      VoicePlayback(
        messageId: messageId ?? this.messageId,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        position: position ?? this.position,
        duration: duration ?? this.duration,
      );
}

/// Drives voice-note and audio playback.
///
/// The [AudioPlayer] is created lazily, on the first tap, so simply rendering a
/// chat that contains voice notes never touches a platform channel — which is
/// what keeps widget tests free of plugin initialisation.
class VoicePlayerService {
  AudioPlayer? _player;
  String? _loadedSource;

  final StreamController<VoicePlayback> _out =
      StreamController<VoicePlayback>.broadcast();

  VoicePlayback _state = const VoicePlayback();

  /// Broadcast stream of playback state, for [StreamBuilder].
  Stream<VoicePlayback> get stream => _out.stream;

  /// The current state, so a newly-built bubble can render without waiting for
  /// the next event.
  VoicePlayback get state => _state;

  AudioPlayer get _p => _player ??= _create();

  AudioPlayer _create() {
    final AudioPlayer player = AudioPlayer();

    player.playerStateStream.listen((PlayerState s) {
      if (s.processingState == ProcessingState.completed) {
        // Rewind so the next tap replays from the start instead of sitting at
        // the end. `pause()` first because `seek` on a completed player can be
        // ignored by some platform implementations.
        player.pause();
        unawaited(player.seek(Duration.zero));
        _emit(_state.copyWith(playing: false, position: Duration.zero));
      } else {
        _emit(_state.copyWith(playing: s.playing));
      }
    });

    player.positionStream.listen(
      (Duration position) => _emit(_state.copyWith(position: position)),
    );

    player.durationStream.listen((Duration? duration) {
      if (duration != null && duration > Duration.zero) {
        _emit(_state.copyWith(duration: duration));
      }
    });

    return player;
  }

  void _emit(VoicePlayback next) {
    _state = next;
    if (!_out.isClosed) _out.add(next);
  }

  /// Toggles playback of [messageId].
  ///
  /// Returns false when the note has no usable source on this device — neither
  /// a local file nor a remote URL — so the caller can say so instead of
  /// silently doing nothing.
  Future<bool> toggle({
    required String messageId,
    required String? localPath,
    required String? remoteUrl,
    int? durationMs,
  }) async {
    final String? source = _resolveSource(localPath, remoteUrl);
    if (source == null) return false;

    // Same note: pause or resume.
    if (_state.messageId == messageId) {
      if (_state.playing) {
        await _p.pause();
      } else {
        if (_p.processingState == ProcessingState.completed) {
          await _p.seek(Duration.zero);
        }
        unawaited(_p.play());
      }
      return true;
    }

    _emit(
      VoicePlayback(
        messageId: messageId,
        loading: true,
        duration: Duration(milliseconds: durationMs ?? 0),
      ),
    );

    try {
      if (_loadedSource == source) {
        await _p.seek(Duration.zero);
      } else {
        await _load(source);
        _loadedSource = source;
      }
      _emit(
        _state.copyWith(
          loading: false,
          duration: _p.duration ?? _state.duration,
        ),
      );
      unawaited(_p.play());
      return true;
    } on Object catch (error) {
      debugPrint('Voice playback failed for $messageId: $error');
      _loadedSource = null;
      _emit(const VoicePlayback());
      return false;
    }
  }

  /// Stops playback and clears the state, e.g. when leaving the chat.
  Future<void> stop() async {
    final AudioPlayer? player = _player;
    if (player == null) return;
    await player.stop();
    _emit(const VoicePlayback());
  }

  /// A local file wins because it needs no network; the remote URL is what
  /// makes a note the *other* device recorded playable here.
  static String? _resolveSource(String? localPath, String? remoteUrl) {
    if (localPath != null &&
        localPath.isNotEmpty &&
        !localPath.startsWith('http') &&
        File(localPath).existsSync()) {
      return localPath;
    }
    if (remoteUrl != null && remoteUrl.isNotEmpty) return remoteUrl;
    // A bare object key (a legacy sender with no public bucket URL) is not
    // fetchable — treat it as having no source rather than failing at play time.
    return null;
  }

  Future<void> _load(String source) async {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      await _p.setUrl(source);
    } else {
      await _p.setFilePath(source);
    }
  }

  Future<void> dispose() async {
    await _out.close();
    await _player?.dispose();
    _player = null;
  }
}

/// The single app-wide voice player.
final Provider<VoicePlayerService> voicePlayerProvider =
    Provider<VoicePlayerService>((Ref ref) {
  final VoicePlayerService service = VoicePlayerService();
  ref.onDispose(service.dispose);
  return service;
});
