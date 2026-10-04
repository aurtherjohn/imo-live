import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/contact.dart';
import '../../../core/models/status.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/webrtc_call_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../earn/presentation/providers.dart';
import '../../chats/presentation/providers.dart';
import '../../../core/utils/l10n.dart';

/// The call surface's design tokens.
///
/// Kept together and separate from `AppTheme` because a call screen is a
/// full-bleed dark surface that deliberately ignores the app's normal palette —
/// the same reason WhatsApp's call UI does not follow its chat theme.
class CallTokens {
  const CallTokens._();

  static const Color backgroundTop = Color(0xFF000000);
  static const Color backgroundBottom = Color(0xFF0D0D0D);
  static const Color end = Color(0xFFFF3B30);
  static const Color accept = Color(0xFF25D366);
  static const Color text = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFFB3B3B3);

  /// An inactive round control's fill.
  static const Color controlIdle = Color(0x26FFFFFF);

  /// A round control that is currently on (muted, speaker on, camera off).
  static const Color controlActive = Color(0xFFFFFFFF);
}

/// Active call UI for voice, video and incoming sessions.
///
/// The screen talks to [CallService] and nothing else, so it drives whichever
/// implementation [callServiceProvider] supplies. Video renders only when the
/// service implements [VideoCallStreams] (WebRTC) or [CallVideoSurface] (Agora)
/// *and* a track has actually arrived; everything else keeps the avatar, so the
/// same screen works for voice calls, for the simulator, and for a real call
/// before the remote track lands.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    super.key,
    required this.contactId,
    required this.contactName,
    this.isVideo = false,
    this.isOutgoing = true,
    this.avatarPath,
    this.avatarColor,
  });

  final String contactId;
  final String contactName;
  final bool isVideo;
  final bool isOutgoing;
  final String? avatarPath;
  final int? avatarColor;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with WidgetsBindingObserver {
  late final CallService _calls;
  StreamSubscription<CallSessionState>? _stateSub;
  StreamSubscription<Duration>? _durationSub;

  /// The service's explanation for the most recent failure, captured when the
  /// failed state arrives.
  ///
  /// Read at that moment rather than at build time because the service clears
  /// it when the next call starts — which can happen while this screen is still
  /// on its way out, and would blank the message the user is reading.
  String? _failureReason;

  CallSessionState _state = CallSessionState.idle;
  Duration _elapsed = Duration.zero;
  bool _muted = false;
  bool _speaker = false;
  bool _cameraOn = true;
  bool _frontCamera = true;
  bool _minimised = false;
  bool _logged = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _calls = ref.read(callServiceProvider);
    _stateSub = _calls.stateStream.listen(_onState);
    _durationSub = _calls.durationStream.listen((Duration d) {
      if (mounted) setState(() => _elapsed = d);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  /// Releases the capture when the app is backgrounded mid-call.
  ///
  /// ## Why this exists
  ///
  /// Android keeps a foregrounded call's capture alive across a background
  /// transition, which is correct while the call is live and wrong the moment
  /// the UI is gone. The case this closes is the one the teardown cannot see:
  /// the app is killed or backgrounded from the **recents switcher** while a
  /// call is connected. `dispose` is not guaranteed to run on that path — the
  /// process can be collected with the widget tree still nominally alive — and
  /// what is left behind is exactly the reported symptom: a microphone the OS
  /// still counts as busy, so the next voice message fails with "microphone is
  /// in use", and a camera session that outlives the call.
  ///
  /// Only `detached` is acted on. `paused` alone is left running on purpose:
  /// backgrounding a call to check a message and returning is a normal thing to
  /// do, and ending the call for it would be a worse bug than the one being
  /// fixed. `detached` means the engine is going away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) return;
    if (_state == CallSessionState.idle ||
        _state == CallSessionState.ended ||
        _state == CallSessionState.failed) {
      return;
    }
    debugPrint('Call screen detached while $_state — releasing the capture');
    unawaited(_calls.end());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    _durationSub?.cancel();
    _hideTimer?.cancel();
    // This screen is the only thing that knows the session is over *for the
    // user*. `_calls` is a provider-scoped singleton whose `ref.onDispose` fires
    // only when the whole container goes away — never when a route is popped —
    // so leaving by the system back gesture rather than the hang-up button used
    // to leave the session live and the microphone with it. Ending it here is
    // what makes "leaving the call screen" actually release the capture.
    if (_state != CallSessionState.idle &&
        _state != CallSessionState.ended &&
        _state != CallSessionState.failed) {
      unawaited(
        _state == CallSessionState.ringing && !widget.isOutgoing
            ? _calls.decline()
            : _calls.end(),
      );
    }
    super.dispose();
  }

  Future<void> _begin() async {
    if (widget.isOutgoing) {
      await _calls.start(
        contactId: widget.contactId,
        contactName: widget.contactName,
        isVideo: widget.isVideo,
      );
      // `start` drives the state through its own stream, and it can reach a
      // *terminal* state before returning — a denied permission, a token-server
      // failure and an engine failure all emit `failed` from inside `start`.
      //
      // Assigning `dialling` unconditionally here therefore overwrote that
      // failure, leaving the screen on "Ringing…" and hiding the reason the
      // call never connected: the user could not tell a missing microphone
      // permission from a dead network. Only nudge the state if nothing has
      // moved it yet.
      if (mounted && _state == CallSessionState.idle) {
        setState(() => _state = CallSessionState.dialling);
      }
    } else {
      // An incoming call is already ringing on the wire; the screen just has to
      // show the accept/decline UI.
      setState(() => _state = CallSessionState.ringing);
    }
  }

  /// The call's media streams, when a real WebRTC call is running.
  VideoCallStreams? get _streams {
    // Typed as Object so the `is` check promotes cleanly; a `CallService`
    // local does not promote to an unrelated interface here.
    final Object calls = _calls;
    return calls is VideoCallStreams ? calls : null;
  }

  /// The Agora surface, when the active provider renders its own video.
  CallVideoSurface? get _surface {
    final Object calls = _calls;
    return calls is CallVideoSurface ? calls : null;
  }

  /// True when no real call is being placed, so the UI can say so.
  ///
  /// Both real providers count: WebRTC through [VideoCallStreams] and a managed
  /// SFU through [CallVideoSurface]. Only the local simulator is neither — the
  /// previous build showed the "simulated" label on every call, including live
  /// ones.
  bool get _isSimulated => _streams == null && _surface == null;

  /// The peer's video, or null until a remote track has actually arrived.
  ///
  /// Guarded on `srcObject` rather than on the renderer existing: a renderer
  /// with no stream paints solid black, which is worse than the avatar it would
  /// replace.
  Widget? _remoteVideo(BuildContext context) {
    final CallVideoSurface? surface = _surface;
    if (surface != null) return surface.buildRemoteVideo(context);

    final RTCVideoRenderer? renderer = _streams?.remoteRenderer;
    if (renderer == null || renderer.srcObject == null) return null;
    return RTCVideoView(
      renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  /// The local self-view, or null before capture has started.
  Widget? _localVideo(BuildContext context) {
    final CallVideoSurface? surface = _surface;
    if (surface != null) return surface.buildLocalVideo(context);

    final RTCVideoRenderer? renderer = _streams?.localRenderer;
    if (renderer == null || renderer.srcObject == null) return null;
    return RTCVideoView(
      renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: _frontCamera,
    );
  }

  void _onState(CallSessionState next) {
    if (!mounted) return;
    setState(() {
      _state = next;
      _muted = _calls.isMuted;
      _speaker = _calls.isSpeakerOn;
      _cameraOn = _calls.isCameraOn;
      _frontCamera = _calls.isFrontCamera;
      // Captured here, on the transition into `failed`, while the service still
      // holds it — see [_failureReason].
      if (next == CallSessionState.failed) _failureReason = _calls.lastError;
    });
    if (next == CallSessionState.connected) _elapsed = _calls.elapsed;
    if (next == CallSessionState.ended || next == CallSessionState.failed) {
      unawaited(_finish(next));
    }
  }

  /// Writes the outcome to the local call log exactly once.
  Future<void> _finish(CallSessionState finalState) async {
    if (_logged) return;
    _logged = true;

    final CallOutcome outcome = switch (finalState) {
      CallSessionState.ended =>
        _elapsed.inSeconds > 0 ? CallOutcome.answered : CallOutcome.cancelled,
      CallSessionState.failed => CallOutcome.declined,
      _ => CallOutcome.cancelled,
    };

    final CallRecord record = CallRecord(
      id: 'call_${DateTime.now().microsecondsSinceEpoch}',
      contactId: widget.contactId,
      contactName: widget.contactName,
      kind: widget.isVideo ? CallKind.video : CallKind.voice,
      direction:
          widget.isOutgoing ? CallDirection.outgoing : CallDirection.incoming,
      outcome: outcome,
      timestamp: DateTime.now(),
      durationSeconds: _elapsed.inSeconds,
      avatarPath: widget.avatarPath,
      avatarColor: widget.avatarColor,
    );

    await ref.read(callsProvider.notifier).add(record);

    // Mirror to `calls/{callId}` so the history is shared across the user's
    // devices. Best-effort: the local log is already written.
    final String uid = ref.read(currentUidProvider);
    if (uid.isNotEmpty && widget.contactId.isNotEmpty) {
      unawaited(
        ref.read(firestoreChatServiceProvider).logCall(
              callId: record.id,
              callerId: widget.isOutgoing ? uid : widget.contactId,
              receiverId: widget.isOutgoing ? widget.contactId : uid,
              type: widget.isVideo ? 'video' : 'voice',
              status: outcome.name,
              duration: _elapsed.inSeconds,
            ),
      );
    }

    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _leave();
  }

  void _leave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/calls');
    }
  }

  /// Accepts an incoming call, and counts the accept for the ad budget.
  ///
  /// The interstitial is fired *before* `accept()` and not awaited: the user is
  /// about to be in a call, so the ad must appear while the call is still
  /// connecting, never over live audio. [AdTrigger.callAccepted] is spent at
  /// most once per session (see [_oncePerSessionTriggers]) — an ad in front of
  /// every incoming call would be indefensible.
  Future<void> _accept() async {
    unawaited(
      ref.read(adServiceProvider).noteAndMaybeShow(AdTrigger.callAccepted),
    );
    await _calls.accept();
  }

  Future<void> _hangUp() async {
    if (_state == CallSessionState.ringing && !widget.isOutgoing) {
      await _calls.decline();
    } else {
      await _calls.end();
    }
  }

  /// Auto-hides the video-call controls after four seconds of inactivity, the
  /// way WhatsApp does, and brings them back on a tap anywhere.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final Contact? contact = ref
        .watch(contactsProvider)
        .orEmpty
        .where((Contact c) => c.id == widget.contactId)
        .firstOrNull;

    final String displayName = contact?.fullName ?? widget.contactName;
    final String? imagePath = contact?.avatarPath ?? widget.avatarPath;
    final int? colorSeed = contact?.avatarColor ?? widget.avatarColor;

    if (_minimised) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _MinimisedCallBar(
            name: displayName,
            elapsed: _elapsed,
            connected: _state == CallSessionState.connected,
            onExpand: () => setState(() => _minimised = false),
            onHangUp: _hangUp,
          ),
        ),
      );
    }

    // An unanswered incoming call gets its own screen: full-bleed avatar with
    // two large actions, and it slides up into place.
    if (!widget.isOutgoing &&
        (_state == CallSessionState.ringing || _state == CallSessionState.idle)) {
      return _IncomingLayout(
        name: displayName,
        imagePath: imagePath,
        colorSeed: colorSeed,
        isVideo: widget.isVideo,
        onAccept: _accept,
        onDecline: _hangUp,
      );
    }

    if (widget.isVideo && _state == CallSessionState.connected && _cameraOn) {
      if (_controlsVisible) _scheduleHide();
      return _VideoLayout(
        name: displayName,
        imagePath: imagePath,
        colorSeed: colorSeed,
        elapsed: _elapsed,
        muted: _muted,
        speaker: _speaker,
        cameraOn: _cameraOn,
        frontCamera: _frontCamera,
        controlsVisible: _controlsVisible,
        onToggleControls: _toggleControls,
        onMute: _toggleMute,
        onSpeaker: _toggleSpeaker,
        onCamera: _toggleCamera,
        onSwitchCamera: _switchCamera,
        onMinimise: () => setState(() => _minimised = true),
        onHangUp: _hangUp,
        remoteVideo: _remoteVideo(context),
        localVideo: _localVideo(context),
        isSimulated: _isSimulated,
      );
    }

    return _VoiceLayout(
      name: displayName,
      imagePath: imagePath,
      colorSeed: colorSeed,
      state: _state,
      elapsed: _elapsed,
      failureReason: _failureReason,
      isVideo: widget.isVideo,
      isSimulated: _isSimulated,
      muted: _muted,
      speaker: _speaker,
      cameraOn: _cameraOn,
      onMute: _toggleMute,
      onSpeaker: _toggleSpeaker,
      onCamera: _toggleCamera,
      onMinimise: () => setState(() => _minimised = true),
      onHangUp: _hangUp,
    );
  }

  Future<void> _toggleMute() async {
    await _calls.toggleMute();
    if (mounted) setState(() => _muted = _calls.isMuted);
  }

  Future<void> _toggleSpeaker() async {
    await _calls.toggleSpeaker();
    if (mounted) setState(() => _speaker = _calls.isSpeakerOn);
  }

  Future<void> _toggleCamera() async {
    await _calls.toggleCamera();
    if (mounted) setState(() => _cameraOn = _calls.isCameraOn);
  }

  Future<void> _switchCamera() async {
    await _calls.switchCamera();
    if (mounted) setState(() => _frontCamera = _calls.isFrontCamera);
  }
}

// ===========================================================================
// Shared building blocks
// ===========================================================================

/// The black → #0d0d0d backdrop every call state sits on.
class _CallBackground extends StatelessWidget {
  const _CallBackground({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            CallTokens.backgroundTop,
            CallTokens.backgroundBottom,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// The status line: "Ringing…", "Connecting…", or the live duration.
class _StatusText extends StatelessWidget {
  const _StatusText({
    required this.state,
    required this.elapsed,
    this.failureReason,
    this.size = 15,
  });

  final CallSessionState state;
  final Duration elapsed;

  /// Why the call failed, when the service could say. Null otherwise.
  ///
  /// Passed in rather than read from the provider because this widget sits
  /// below the call screen and has no `ref` of its own.
  final String? failureReason;

  final double size;

  @override
  Widget build(BuildContext context) {
    final String label = switch (state) {
      CallSessionState.dialling => 'Ringing…',
      CallSessionState.ringing => 'Ringing…',
      CallSessionState.connecting => 'Connecting…',
      CallSessionState.connected => DateFormatter.duration(elapsed),
      CallSessionState.ended => 'Call ended',
      // A failed call is the one case where the user needs to know *why*: "Call
      // failed" on its own does not tell them whether to retry or stop. The
      // service supplies a sentence when it has one (a token-server timeout, no
      // connection) and this falls back to the generic label when it does not.
      CallSessionState.failed => failureReason ?? 'Call failed',
      CallSessionState.idle => 'Calling…',
    };
    return Text(
      label,
      style: TextStyle(
        color: CallTokens.secondary,
        fontSize: size,
        letterSpacing: 0.2,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A round control in the bottom row.
///
/// [active] paints the fill white with a dark glyph — the "this control is on"
/// state — while [danger] is used only for the end-call button.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.size = 56,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool danger;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Color fill = danger
        ? CallTokens.end
        : active
            ? CallTokens.controlActive
            : CallTokens.controlIdle;
    final Color glyph = danger
        ? Colors.white
        : active
            ? Colors.black
            : Colors.white;

    final Widget button = Material(
      color: fill,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.42, color: glyph),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Avatar with a slow pulsing halo, used while a call is ringing.
class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar({
    required this.name,
    this.imagePath,
    this.colorSeed,
    this.pulse = true,
  });

  /// Avatar diameter. Fixed rather than configurable: the call layouts are
  /// full-bleed and every use sits at the same visual weight, so a per-call-site
  /// override would only be a way for them to drift apart.
  static const double radius = 90;

  final String name;
  final String? imagePath;
  final int? colorSeed;
  final bool pulse;

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _controller.repeat();
  }

  @override
  void didUpdateWidget(_PulsingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (widget.pulse)
              Container(
                width: _PulsingAvatar.radius * 2 + 34 * t,
                height: _PulsingAvatar.radius * 2 + 34 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18 * (1 - t)),
                    width: 1.6,
                  ),
                ),
              ),
            child!,
          ],
        );
      },
      child: IAvatar(
        name: widget.name,
        imagePath: widget.imagePath,
        colorSeed: widget.colorSeed,
        size: _PulsingAvatar.radius * 2,
        icon: Icons.person_rounded,
      ),
    );
  }
}

// ===========================================================================
// Incoming call
// ===========================================================================

/// The incoming-call screen: avatar, caller name, and two large actions.
///
/// It slides up from the bottom edge so an incoming call is visually distinct
/// from a call the user placed.
class _IncomingLayout extends StatelessWidget {
  const _IncomingLayout({
    required this.name,
    required this.imagePath,
    required this.colorSeed,
    required this.isVideo,
    required this.onAccept,
    required this.onDecline,
  });

  final String name;
  final String? imagePath;
  final int? colorSeed;
  final bool isVideo;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CallTokens.backgroundTop,
      body: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: 0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double slide, Widget? child) =>
            FractionalTranslation(
          translation: Offset(0, slide),
          child: child,
        ),
        child: _CallBackground(
          child: SafeArea(
            child: Column(
              children: <Widget>[
                const Spacer(flex: 2),
                _PulsingAvatar(
                  name: name,
                  imagePath: imagePath,
                  colorSeed: colorSeed,
                ),
                const SizedBox(height: 36),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CallTokens.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isVideo ? context.l10n.incomingVideoCall : context.l10n.incomingVoiceCall,
                  style: const TextStyle(
                    color: CallTokens.secondary,
                    fontSize: 15,
                  ),
                ),
                const Spacer(flex: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        _RoundButton(
                          icon: Icons.call_end_rounded,
                          danger: true,
                          size: 68,
                          tooltip: context.l10n.decline,
                          onTap: () => onDecline(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.decline,
                          style: TextStyle(
                            color: CallTokens.secondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: <Widget>[
                        _RoundButton(
                          icon: isVideo
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          danger: false,
                          size: 68,
                          tooltip: context.l10n.accept,
                          onTap: () => onAccept(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.accept,
                          style: TextStyle(
                            color: CallTokens.secondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Voice call
// ===========================================================================

class _VoiceLayout extends StatelessWidget {
  const _VoiceLayout({
    required this.name,
    required this.imagePath,
    required this.colorSeed,
    required this.state,
    required this.elapsed,
    required this.failureReason,
    required this.isVideo,
    required this.isSimulated,
    required this.muted,
    required this.speaker,
    required this.cameraOn,
    required this.onMute,
    required this.onSpeaker,
    required this.onCamera,
    required this.onMinimise,
    required this.onHangUp,
  });

  final String name;
  final String? imagePath;
  final int? colorSeed;
  final CallSessionState state;
  final Duration elapsed;

  /// Why the call failed, forwarded to [_StatusText].
  final String? failureReason;

  final bool isVideo;
  final bool isSimulated;
  final bool muted;
  final bool speaker;
  final bool cameraOn;
  final Future<void> Function() onMute;
  final Future<void> Function() onSpeaker;
  final Future<void> Function() onCamera;
  final VoidCallback onMinimise;
  final Future<void> Function() onHangUp;

  bool get _ringing =>
      state == CallSessionState.dialling ||
      state == CallSessionState.ringing ||
      state == CallSessionState.connecting;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CallTokens.backgroundTop,
      body: _CallBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 12),
              if (isSimulated)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: _SimulatedBadge(),
                ),
              const Spacer(flex: 2),
              _PulsingAvatar(
                name: name,
                imagePath: imagePath,
                colorSeed: colorSeed,
                pulse: _ringing,
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CallTokens.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _StatusText(
                state: state,
                elapsed: elapsed,
                failureReason: failureReason,
                size: 16,
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    _RoundButton(
                      icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      active: muted,
                      tooltip: muted ? context.l10n.unmute : context.l10n.mute,
                      onTap: () => onMute(),
                    ),
                    _RoundButton(
                      icon: speaker
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      active: speaker,
                      tooltip: context.l10n.speaker,
                      onTap: () => onSpeaker(),
                    ),
                    _RoundButton(
                      icon: Icons.videocam_rounded,
                      tooltip: context.l10n.video,
                      onTap: () => onCamera(),
                    ),
                    _RoundButton(
                      icon: Icons.call_end_rounded,
                      danger: true,
                      size: 68,
                      tooltip: context.l10n.endCall,
                      onTap: () => onHangUp(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              TextButton.icon(
                onPressed: onMinimise,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: CallTokens.secondary,
                ),
                label: Text(
                  context.l10n.minimise,
                  style: TextStyle(color: CallTokens.secondary),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Video call
// ===========================================================================

/// The video call: remote video full-bleed, a draggable self-view, and two
/// overlays that fade in and out together.
class _VideoLayout extends StatefulWidget {
  const _VideoLayout({
    required this.name,
    required this.imagePath,
    required this.colorSeed,
    required this.elapsed,
    required this.muted,
    required this.speaker,
    required this.cameraOn,
    required this.frontCamera,
    required this.controlsVisible,
    required this.onToggleControls,
    required this.onMute,
    required this.onSpeaker,
    required this.onCamera,
    required this.onSwitchCamera,
    required this.onMinimise,
    required this.onHangUp,
    required this.remoteVideo,
    required this.localVideo,
    required this.isSimulated,
  });

  final String name;
  final String? imagePath;
  final int? colorSeed;
  final Duration elapsed;
  final bool muted;
  final bool speaker;
  final bool cameraOn;
  final bool frontCamera;
  final bool controlsVisible;
  final VoidCallback onToggleControls;
  final Future<void> Function() onMute;
  final Future<void> Function() onSpeaker;
  final Future<void> Function() onCamera;
  final Future<void> Function() onSwitchCamera;
  final VoidCallback onMinimise;
  final Future<void> Function() onHangUp;
  final Widget? remoteVideo;
  final Widget? localVideo;
  final bool isSimulated;

  @override
  State<_VideoLayout> createState() => _VideoLayoutState();
}

class _VideoLayoutState extends State<_VideoLayout> {
  /// Self-view position, as a fraction of the free space. Held as a fraction so
  /// it survives an orientation change or a keyboard resize.
  double _dx = 1;
  double _dy = 0;

  static const double _selfWidth = 100;
  static const double _selfHeight = 140;
  static const double _margin = 16;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: widget.onToggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Remote video, or the avatar while no track has arrived.
            widget.remoteVideo ?? _RemotePlaceholder(name: widget.name),

            // Top overlay: name + duration on a dark gradient.
            AnimatedOpacity(
              opacity: widget.controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !widget.controlsVisible,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0xCC000000), Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: <Widget>[
                          const SizedBox(height: 12),
                          if (widget.isSimulated)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: _SimulatedBadge(),
                            ),
                          Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CallTokens.text,
                              fontSize: 19,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormatter.duration(widget.elapsed),
                            style: const TextStyle(
                              color: CallTokens.secondary,
                              fontSize: 14,
                              fontFeatures: <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Draggable self-view.
            if (widget.localVideo != null)
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double maxX =
                      constraints.maxWidth - _selfWidth - _margin;
                  final double maxY =
                      constraints.maxHeight - _selfHeight - _margin * 3;
                  final double left =
                      (_margin + _dx * maxX).clamp(_margin, maxX);
                  final double top =
                      (_margin + _dy * maxY).clamp(_margin, maxY);

                  return Stack(
                    children: <Widget>[
                      Positioned(
                        left: left,
                        top: top,
                        child: GestureDetector(
                          onPanUpdate: (DragUpdateDetails details) {
                            setState(() {
                              _dx = maxX <= 0
                                  ? 0
                                  : (_dx + details.delta.dx / maxX)
                                      .clamp(0.0, 1.0);
                              _dy = maxY <= 0
                                  ? 0
                                  : (_dy + details.delta.dy / maxY)
                                      .clamp(0.0, 1.0);
                            });
                          },
                          onTap: () => widget.onSwitchCamera(),
                          child: Container(
                            width: _selfWidth,
                            height: _selfHeight,
                            decoration: BoxDecoration(
                              color: const Color(0xFF26262E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white24,
                                width: 1,
                              ),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: widget.localVideo,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

            // Bottom control bar.
            AnimatedOpacity(
              opacity: widget.controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !widget.controlsVisible,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[Color(0xE6000000), Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: <Widget>[
                              _RoundButton(
                                icon: widget.muted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                active: widget.muted,
                                tooltip: context.l10n.mute,
                                onTap: () => widget.onMute(),
                              ),
                              _RoundButton(
                                icon: Icons.flip_camera_ios_rounded,
                                tooltip: context.l10n.flipCamera,
                                onTap: () => widget.onSwitchCamera(),
                              ),
                              _RoundButton(
                                icon: Icons.call_end_rounded,
                                danger: true,
                                size: 64,
                                tooltip: context.l10n.endCall,
                                onTap: () => widget.onHangUp(),
                              ),
                              _RoundButton(
                                icon: widget.cameraOn
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                active: !widget.cameraOn,
                                tooltip: context.l10n.camera,
                                onTap: () => widget.onCamera(),
                              ),
                              _RoundButton(
                                icon: widget.speaker
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_down_rounded,
                                active: widget.speaker,
                                tooltip: context.l10n.speaker,
                                onTap: () => widget.onSpeaker(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: widget.onMinimise,
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: CallTokens.secondary,
                            ),
                            label: Text(
                              context.l10n.minimise,
                              style: TextStyle(color: CallTokens.secondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What fills the video area before the remote track arrives.
class _RemotePlaceholder extends StatelessWidget {
  const _RemotePlaceholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF1B1B22), Color(0xFF08080A)],
        ),
      ),
      child: Center(
        child: IAvatar(name: name, size: 96, icon: Icons.person_rounded),
      ),
    );
  }
}

/// The "no real connection" label — only ever shown for the local simulator.
class _SimulatedBadge extends StatelessWidget {
  const _SimulatedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        context.l10n.simulated,
        style: TextStyle(
          color: CallTokens.secondary,
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ===========================================================================
// Minimised bar
// ===========================================================================

class _MinimisedCallBar extends StatelessWidget {
  const _MinimisedCallBar({
    required this.name,
    required this.elapsed,
    required this.connected,
    required this.onExpand,
    required this.onHangUp,
  });

  final String name;
  final Duration elapsed;
  final bool connected;
  final VoidCallback onExpand;
  final Future<void> Function() onHangUp;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: <Widget>[
                IAvatar(name: name, size: 34, icon: Icons.person_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CallTokens.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        connected
                            ? DateFormatter.duration(elapsed)
                            : context.l10n.ringing,
                        style: const TextStyle(
                          color: CallTokens.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _RoundButton(
                  icon: Icons.call_end_rounded,
                  danger: true,
                  size: 40,
                  tooltip: context.l10n.endCall,
                  onTap: () => onHangUp(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
