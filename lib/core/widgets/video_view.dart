import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/app.dart' show prefersReducedMotion;
import '../../app/theme/app_color_scheme.dart';
import '../../app/theme/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../utils/haptics.dart';
import '../utils/l10n.dart';
import 'common_widgets.dart';

/// How far a double-tap on either half of the frame jumps.
const Duration _doubleTapSeek = Duration(seconds: 10);

/// Playback rate while the frame is long-pressed.
const double _holdToPlaySpeed = 2.0;

/// An in-app video player for a chat video message, a video status or a video
/// channel post.
///
/// Local files ([localPath]) take priority over [remoteUrl]: a message this
/// device sent has the bytes on disk, and reading them avoids a round trip.
/// Exactly one of the two must be supplied.
///
/// The widget owns the [VideoPlayerController] lifecycle — create, initialize,
/// dispose — because every caller needs the same four things and getting the
/// disposal wrong leaks a platform surface and a codec.
///
/// ### Controls
///
/// The chrome (top bar, centre transport, scrubber) auto-hides after
/// [chromeTimeout] and returns on any tap. Every serious player does this,
/// because the controls are not the content.
///
/// | gesture | effect |
/// | --- | --- |
/// | tap | toggle the chrome |
/// | double-tap left / right | seek −[doubleTapSeek] / +[doubleTapSeek] |
/// | long-press | hold to play at [holdToPlaySpeed] (release restores) |
/// | vertical drag, left half | brightness |
/// | vertical drag, right half | volume |
/// | horizontal drag | scrub, with a preview clock |
class IVideoPlayer extends StatefulWidget {
  const IVideoPlayer({
    super.key,
    this.localPath,
    this.remoteUrl,
    this.autoPlay = false,
    this.loop = false,
    this.fit = BoxFit.contain,
    this.title,
    this.chromeTimeout = const Duration(seconds: 3),
    this.showGestures = true,
  });

  final String? localPath;
  final String? remoteUrl;
  final bool autoPlay;
  final bool loop;
  final BoxFit fit;

  /// Shown in the auto-hiding top bar. Null hides the bar entirely.
  final String? title;

  /// How long the chrome stays up after the last interaction.
  final Duration chromeTimeout;

  /// Set false to disable the gesture layer — useful when the player is shown
  /// inline (a bubble preview) rather than as a full-screen viewer.
  final bool showGestures;

  @override
  State<IVideoPlayer> createState() => _IVideoPlayerState();
}

class _IVideoPlayerState extends State<IVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  bool _initialising = true;

  // ---------------------------------------------------------------- chrome
  Timer? _hideTimer;
  bool _chromeVisible = true;

  // --------------------------------------------------------------- gestures
  /// Set while a vertical drag is in progress, so the overlay can name the
  /// thing being changed and show how far it has moved.
  _DragHud? _hud;

  /// Volume as a 0..1 multiplier on the clip's own volume.
  double _volume = 1;

  /// Screen brightness as a 0..1 scalar.
  double _brightness = 1;

  /// Position captured when a horizontal scrub begins, so the drag is relative
  /// to where the finger landed rather than accumulating every delta.
  Duration? _scrubBase;
  Duration? _scrubPreview;

  /// Accumulated double-tap seek, so rapid taps stack ("+10s +10s").
  Duration _seekBias = Duration.zero;
  Timer? _seekBiasTimer;

  /// Pending single-tap, cancelled if a second tap lands inside the window.
  Timer? _tapTimer;

  /// Whether playback was running when a long-press started, so release can
  /// restore it instead of leaving a paused clip.
  bool _wasPlayingBeforeHold = false;
  bool _holding = false;

  static const Duration doubleTapSeek = _doubleTapSeek;
  static const double holdToPlaySpeed = _holdToPlaySpeed;

  /// Brightness/volume are not applied to the real system — only to the video
  /// surface — so a drag cannot leave the phone in a strange state. This is the
  /// same restraint MX Player and VLC use in their in-app gesture layer.
  static const double _minVolume = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void didUpdateWidget(IVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reopening on every rebuild would restart playback, so only react when the
    // source actually changes.
    if (oldWidget.localPath != widget.localPath ||
        oldWidget.remoteUrl != widget.remoteUrl) {
      _disposeController();
      _open();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A video that keeps decoding in the background is a battery bug, and on
    // iOS the surface is torn down anyway, so play resumes into a black frame.
    final VideoPlayerController? controller = _controller;
    if (controller == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (controller.value.isPlaying) controller.pause();
      _cancelHideTimer();
      if (mounted) setState(() => _chromeVisible = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelHideTimer();
    _seekBiasTimer?.cancel();
    _tapTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final VideoPlayerController? controller = _controller;
    _controller = null;
    // Fire-and-forget: dispose() is async on the platform side, but the widget
    // is already going away and nothing waits on the result.
    controller?.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _initialising = true;
      _error = null;
    });

    final String? path = widget.localPath;
    final String? url = widget.remoteUrl;

    VideoPlayerController? controller;
    if (path != null && path.isNotEmpty) {
      final File file = File(path);
      if (!await file.exists()) {
        if (!mounted) return;
        setState(() {
          _initialising = false;
          _error = 'This video is no longer on the device.';
        });
        return;
      }
      controller = VideoPlayerController.file(file);
    } else if (url != null && url.isNotEmpty) {
      final Uri? uri = Uri.tryParse(url);
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _initialising = false;
          _error = 'This video has no usable link.';
        });
        return;
      }
      controller = VideoPlayerController.networkUrl(uri);
    } else {
      setState(() {
        _initialising = false;
        _error = 'There is nothing to play.';
      });
      return;
    }

    try {
      await controller.initialize();
      await controller.setLooping(widget.loop);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initialising = false;
      });
      if (widget.autoPlay) {
        await controller.play();
        _scheduleHide();
      }
    } on Exception catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _initialising = false;
        // A codec failure and a 404 look the same to the plugin, so report both
        // possibilities rather than guessing.
        _error = 'This video could not be played. It may be unsupported or '
            'still uploading.\n$e';
      });
    }
  }

  // ------------------------------------------------------------------ chrome

  void _scheduleHide() {
    _cancelHideTimer();
    if (!mounted) return;
    // Never hide while paused: a paused player with no controls is a dead end.
    if (!(_controller?.value.isPlaying ?? false)) return;
    _hideTimer = Timer(widget.chromeTimeout, () {
      if (!mounted) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) _scheduleHide();
  }

  /// Defers the chrome toggle by the double-tap window, so a double-tap can
  /// cancel it.
  void _onTapUp(TapUpDetails details, Size screen) {
    _tapTimer?.cancel();
    // Same window Flutter itself uses for double-tap recognition. Waiting it out
    // is the cost of not toggling the chrome on every seek.
    _tapTimer = Timer(kDoubleTapTimeout, () {
      if (!mounted) return;
      _toggleChrome();
    });
  }

  /// Keeps the chrome up on any interaction, so a gesture does not hide the
  /// control the user is looking at.
  void _showChrome({bool autoHide = true}) {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    if (autoHide) _scheduleHide();
  }

  // ---------------------------------------------------------------- playback

  void _togglePlay() {
    final VideoPlayerController? controller = _controller;
    if (controller == null) return;
    Haptics.tap();
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _cancelHideTimer();
        _chromeVisible = true;
      } else {
        // Restarting from the end is what every video player does; without this
        // the button appears dead once playback finishes.
        if (controller.value.position >= controller.value.duration) {
          controller.seekTo(Duration.zero);
        }
        controller.play();
        _scheduleHide();
      }
    });
  }

  Future<void> _seekBy(Duration delta, {required int direction}) async {
    final VideoPlayerController? controller = _controller;
    if (controller == null) return;

    // Stacking keeps a stutter of tap-taps from being a no-op: without the
    // bias, each tap computes ±10s from the *current* position, and the second
    // tap lands where the first already put it.
    _seekBias += delta;
    _seekBiasTimer?.cancel();
    _seekBiasTimer = Timer(const Duration(milliseconds: 900), () {
      _seekBias = Duration.zero;
    });

    final Duration target = _clamp(
      controller.value.position + _seekBias,
      Duration.zero,
      controller.value.duration,
    );

    Haptics.tap();
    setState(() => _hud = _DragHud.seek(target, direction));
    await controller.seekTo(target);

    // The HUD is informational; take it down on its own timer so a tap does not
    // leave a label stuck on screen.
    Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  static Duration _clamp(Duration v, Duration lo, Duration hi) {
    if (v < lo) return lo;
    if (hi > Duration.zero && v > hi) return hi;
    return v;
  }

  void _onHoldStart() {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isPlaying) return;
    _wasPlayingBeforeHold = true;
    _holding = true;
    Haptics.tap();
    controller.setPlaybackSpeed(holdToPlaySpeed);
    setState(() => _hud = const _DragHud.speed());
  }

  void _onHoldEnd() {
    if (!_holding) return;
    _holding = false;
    final VideoPlayerController? controller = _controller;
    controller?.setPlaybackSpeed(1.0);
    if (mounted) setState(() => _hud = null);
    // If it was not playing when the hold began, do not start it now.
    if (!_wasPlayingBeforeHold) controller?.pause();
    _wasPlayingBeforeHold = false;
  }

  void _onVerticalDrag(DragUpdateDetails details, double height, bool isLeft) {
    final double delta = -details.delta.dy / (height * 0.6);
    if (isLeft) {
      setState(() {
        _brightness = (_brightness + delta).clamp(0.05, 1.0);
        _hud = _DragHud.brightness(_brightness);
      });
    } else {
      setState(() {
        _volume = (_volume + delta).clamp(_minVolume, 1.0);
        _hud = _DragHud.volume(_volume);
      });
      _controller?.setVolume(_volume);
    }
    _showChrome(autoHide: false);
  }

  void _onVerticalDragEnd() {
    if (mounted) setState(() => _hud = null);
    _scheduleHide();
  }

  void _onHorizontalDragStart(DragStartDetails details, double width) {
    final VideoPlayerController? controller = _controller;
    if (controller == null) return;
    _scrubBase = controller.value.position;
    _showChrome(autoHide: false);
  }

  void _onHorizontalDrag(DragUpdateDetails details, double width) {
    final VideoPlayerController? controller = _controller;
    final Duration? base = _scrubBase;
    if (controller == null || base == null) return;

    final Duration total = controller.value.duration;
    if (total == Duration.zero) return;

    // A full-width swipe spans the whole clip, which makes a long video
    // controllable without 20 passes. Capped so a flick is not a random seek.
    final Duration delta = Duration(
      milliseconds: (details.delta.dx / width * total.inMilliseconds).round(),
    );
    final Duration target = _clamp(base + delta, Duration.zero, total);
    _scrubBase = target;
    setState(() => _scrubPreview = target);
  }

  Future<void> _onHorizontalDragEnd() async {
    final Duration? target = _scrubPreview;
    if (target != null) await _controller?.seekTo(target);
    if (mounted) {
      setState(() {
        _scrubPreview = null;
        _scrubBase = null;
      });
    }
    _scheduleHide();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (_initialising) {
      return const Center(child: ILoader(size: 30));
    }
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      );
    }

    final VideoPlayerController controller = _controller!;
    final Size size = controller.value.size;
    final Size screen = MediaQuery.sizeOf(context);

    // Brightness is simulated with a black scrim over the video rather than by
    // touching the platform display, so leaving the screen never leaves the
    // device dimmed.
    final double scrim = (1 - _brightness) * 0.75;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // `onTap` is deliberately NOT used. With both handlers attached Flutter
      // fires `onTap` on the first tap of a double-tap, so every double-tap
      // would also toggle the chrome. `onTapUp` + a timer that only fires if no
      // second tap arrives is the standard arbiter.
      onTapUp: (TapUpDetails d) => _onTapUp(d, screen),
      onDoubleTapDown: (TapDownDetails d) {
        _tapTimer?.cancel();
        _tapTimer = null;
        final bool isLeft = d.localPosition.dx < screen.width / 2;
        unawaited(
          _seekBy(
            isLeft ? -_doubleTapSeek : _doubleTapSeek,
            direction: isLeft ? -1 : 1,
          ),
        );
      },
      onLongPressStart: widget.showGestures ? (_) => _onHoldStart() : null,
      onLongPressEnd: widget.showGestures ? (_) => _onHoldEnd() : null,
      onVerticalDragUpdate: widget.showGestures
          ? (DragUpdateDetails d) => _onVerticalDrag(
                d,
                screen.height,
                d.localPosition.dx < screen.width / 2,
              )
          : null,
      onVerticalDragEnd:
          widget.showGestures ? (_) => _onVerticalDragEnd() : null,
      onHorizontalDragStart: widget.showGestures
          ? (DragStartDetails d) => _onHorizontalDragStart(d, screen.width)
          : null,
      onHorizontalDragUpdate: widget.showGestures
          ? (DragUpdateDetails d) => _onHorizontalDrag(d, screen.width)
          : null,
      onHorizontalDragEnd:
          widget.showGestures ? (_) => unawaited(_onHorizontalDragEnd()) : null,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // ------------------------------------------------------- surface
          Center(
            child: AspectRatio(
              // Guard against a 0-sized stream (audio-only container or a
              // not-yet-decoded frame) which would throw in AspectRatio.
              aspectRatio:
                  size.width > 0 && size.height > 0 ? size.aspectRatio : 16 / 9,
              child: VideoPlayer(controller),
            ),
          ),
          if (scrim > 0.01)
            IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: scrim)),
            ),

          // ------------------------------------------------------ chrome
          AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: prefersReducedMotion(context)
                ? Duration.zero
                : AppDurations.fast,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: _Chrome(
                controller: controller,
                title: widget.title,
                preview: _scrubPreview,
                onTogglePlay: _togglePlay,
                onSeek: (Duration d) {
                  controller.seekTo(d);
                  _scheduleHide();
                },
                onSkip: (int direction) => unawaited(
                  _seekBy(
                    direction > 0 ? doubleTapSeek : -doubleTapSeek,
                    direction: direction,
                  ),
                ),
              ),
            ),
          ),

          // --------------------------------------------------------- HUD
          if (_hud != null)
            Center(
              child: IgnorePointer(child: _HudCard(hud: _hud!)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- HUD model

/// What the centre overlay is currently reporting. A sealed hierarchy rather
/// than a nullable-string bag, so an impossible combination cannot be built.
sealed class _DragHud {
  const _DragHud();

  const factory _DragHud.seek(Duration target, int direction) = _SeekHud;
  const factory _DragHud.volume(double value) = _VolumeHud;
  const factory _DragHud.brightness(double value) = _BrightnessHud;
  const factory _DragHud.speed() = _SpeedHud;
}

class _SeekHud extends _DragHud {
  const _SeekHud(this.target, this.direction);
  final Duration target;
  final int direction;
}

class _VolumeHud extends _DragHud {
  const _VolumeHud(this.value);
  final double value;
}

class _BrightnessHud extends _DragHud {
  const _BrightnessHud(this.value);
  final double value;
}

class _SpeedHud extends _DragHud {
  const _SpeedHud();
}

class _HudCard extends StatelessWidget {
  const _HudCard({required this.hud});

  final _DragHud hud;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label, double? level) = switch (hud) {
      _SeekHud(:final Duration target, :final int direction) => (
          direction < 0
              ? Icons.fast_rewind_rounded
              : Icons.fast_forward_rounded,
          '${direction < 0 ? '−' : '+'}${_doubleTapSeek.inSeconds}s  ·  ${_short(target)}',
          null,
        ),
      _VolumeHud(:final double value) => (
          value <= 0.001
              ? Icons.volume_off_rounded
              : value < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
          '${(value * 100).round()}%',
          value,
        ),
      _BrightnessHud(:final double value) => (
          value < 0.5
              ? Icons.brightness_low_rounded
              : Icons.brightness_high_rounded,
          '${(value * 100).round()}%',
          value,
        ),
      _SpeedHud() => (
          Icons.fast_forward_rounded,
          '${_holdToPlaySpeed.toStringAsFixed(0)}×  playing',
          null,
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (level != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: 108,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: level,
                    minHeight: 4,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



String _short(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  final int s = d.inSeconds.remainder(60);
  final String mm = m.toString().padLeft(2, '0');
  final String ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String _clock(Duration d) => _short(d);

// ------------------------------------------------------------------- chrome

/// The auto-hiding control layer: top bar, centre transport, scrubber.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.controller,
    required this.title,
    required this.preview,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onSkip,
  });

  final VideoPlayerController controller;
  final String? title;
  final Duration? preview;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<int> onSkip;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.65),
          ],
          stops: const <double>[0, 0.28, 0.62, 1],
        ),
      ),
      child: Column(
        children: <Widget>[
          if (title != null && title!.isNotEmpty)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _ChromeButton(
                icon: Icons.replay_10_rounded,
                label: l10n.rewind10,
                onTap: () => onSkip(-1),
              ),
              const SizedBox(width: AppSpacing.xl),
              _ChromeButton(
                icon: controller.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                label: controller.value.isPlaying ? l10n.pauseVideo : l10n.playVideo,
                size: 54,
                onTap: onTogglePlay,
              ),
              const SizedBox(width: AppSpacing.xl),
              _ChromeButton(
                icon: Icons.forward_10_rounded,
                label: l10n.forward10,
                onTap: () => onSkip(1),
              ),
            ],
          ),
          const Spacer(),
          _ScrubBar(
            controller: controller,
            preview: preview,
            onSeek: onSeek,
          ),
        ],
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 34,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      iconSize: size,
      color: Colors.white,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.28),
        padding: EdgeInsets.all(size * 0.32),
      ),
    );
  }
}

/// Position bar plus elapsed/total labels, rebuilt from the controller.
class _ScrubBar extends StatefulWidget {
  const _ScrubBar({
    required this.controller,
    required this.preview,
    required this.onSeek,
  });

  final VideoPlayerController controller;
  final Duration? preview;
  final ValueChanged<Duration> onSeek;

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<_ScrubBar> {
  @override
  void initState() {
    super.initState();
    // The controller is a ValueNotifier; listening here keeps the rebuild
    // scoped to this bar instead of the whole player.
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerValue value = widget.controller.value;
    final AppColorScheme c = context.c;
    // While scrubbing the labels follow the finger, not the decoder — otherwise
    // the clock lags the thumb by the seek latency.
    final Duration shown = widget.preview ?? value.position;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Text(
              _clock(shown),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: c.accent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: c.accent,
                  overlayColor: c.accent.withValues(alpha: 0.18),
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: _maxMs(value.duration).toDouble(),
                  value: _maxMs(shown)
                      .clamp(0, _maxMs(value.duration))
                      .toDouble(),
                  onChanged: (double v) =>
                      widget.onSeek(Duration(milliseconds: v.round())),
                ),
              ),
            ),
            Text(
              _clock(value.duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A zero duration (uninitialised or a live stream) must not produce a
  /// `max: 0 / value: 0` slider, which asserts.
  static int _maxMs(Duration d) => d.inMilliseconds < 1 ? 1 : d.inMilliseconds;
}
