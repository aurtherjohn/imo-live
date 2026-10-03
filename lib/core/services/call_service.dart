import 'dart:async';

import 'package:flutter/widgets.dart';

/// Lifecycle of a call session.
enum CallSessionState {
  idle,
  dialling,
  ringing,
  connecting,
  connected,
  ended,
  failed,
}

/// A VoIP call session handle.
///
/// This abstraction exists so the UI is written once and a WebRTC / SFU /
/// Twilio / custom stack can be slotted in behind [CallService] without
/// touching a single widget. Three implementations exist:
///
///   * [WebRtcCallService] — a real peer-to-peer call, and the one selected for
///     a signed-in user. Firestore carries the SDP offer/answer and the ICE
///     candidates; media does not pass through it.
///   * [LocalCallService] — a simulator with no network and no capture, used
///     when there is no session so every screen stays exercisable.
///   * `AgoraCallService` — a real managed-SFU call, retained on disk but no
///     longer reachable. See `callServiceProvider` in
///     `features/chats/presentation/providers.dart`.
abstract interface class CallService {
  /// Current session state.
  CallSessionState get state;

  /// State changes for the active session.
  Stream<CallSessionState> get stateStream;

  /// Elapsed connected time.
  Stream<Duration> get durationStream;

  Future<void> start({
    required String contactId,
    required String contactName,
    required bool isVideo,
  });

  Future<void> accept();
  Future<void> decline();
  Future<void> end();

  Future<void> toggleMute();
  Future<void> toggleSpeaker();
  Future<void> toggleCamera();
  Future<void> switchCamera();

  bool get isMuted;
  bool get isSpeakerOn;
  bool get isCameraOn;
  bool get isFrontCamera;

  Duration get elapsed;

  /// Whether a real network call can be placed.
  ///
  /// Always false until a VoIP provider is configured.
  bool get isRealCallAvailable;

  /// Whether this service currently holds the device's microphone.
  ///
  /// Reported from the live media state — an open capture, a live stream — and
  /// never from a remembered flag. A flag and the device can disagree, and the
  /// disagreement is invisible: the app believes no call is up while Android
  /// still refuses `AudioRecord` because a capture was never released. That is
  /// precisely the shape of the "can't record a voice note" report, so the
  /// answer has to come from whatever actually holds the resource.
  ///
  /// Consumers use this to *explain* a recording failure, never to pre-empt one.
  bool get holdsMicrophone;

  /// Why the last call attempt failed, or null when there is nothing to report.
  ///
  /// A call can fail for reasons the user can act on — no connection, a token
  /// server that timed out — and for ones they cannot. The call screen shows
  /// this string when it is present so a failure is explained rather than
  /// merely announced. Implementations with no such detail return null.
  String? get lastError;

  Future<void> dispose();
}

/// A [CallService] that renders its own video surfaces.
///
/// [VideoCallStreams] in `webrtc_call_service.dart` is typed to
/// `flutter_webrtc`'s `RTCVideoRenderer`, so only a WebRTC implementation can
/// satisfy it. A managed-SFU provider such as Agora renders through its own
/// native view instead, and returns finished widgets here rather than a renderer
/// the screen would have to know how to drive.
///
/// Optional, exactly like [VideoCallStreams]: the call screen type-checks for it
/// and falls back to the avatar placeholder when it is absent.
abstract interface class CallVideoSurface {
  /// The peer's video, or null until the remote track has arrived.
  Widget? buildRemoteVideo(BuildContext context);

  /// The local self-view, or null before capture has started or while the
  /// camera is off.
  Widget? buildLocalVideo(BuildContext context);

  /// Whether this side is currently publishing video.
  bool get isPublishingVideo;
}

/// REMOTE INTEGRATION POINT.
///
/// Implement [CallService] against your provider:
///
/// ```dart
/// class WebRtcCallService implements CallService { ... }
/// ```
///
/// Then swap the provider binding — the call screens need no changes.
class CallServiceConfig {
  const CallServiceConfig({
    this.provider = 'none',
    this.signallingUrl = '',
    this.apiKey = '',
  });

  /// 'none' | 'webrtc' | 'agora' | 'twilio'
  final String provider;
  final String signallingUrl;
  final String apiKey;

  bool get isConfigured => provider != 'none';
}

/// LOCAL MODE implementation.
///
/// Simulates the call lifecycle with timers so every call screen, control and
/// transition is genuinely exercised. Clearly labelled in the UI as a local
/// simulation — it does not pretend to be a real call.
class LocalCallService implements CallService {
  LocalCallService({this.config = const CallServiceConfig()});

  final CallServiceConfig config;

  final StreamController<CallSessionState> _stateController =
      StreamController<CallSessionState>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  CallSessionState _state = CallSessionState.idle;
  Timer? _connectTimer;
  Timer? _durationTimer;
  DateTime? _connectedAt;

  bool _muted = false;
  bool _speaker = false;
  bool _cameraOn = true;
  bool _frontCamera = true;

  @override
  CallSessionState get state => _state;
  @override
  Stream<CallSessionState> get stateStream => _stateController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  bool get isMuted => _muted;
  @override
  bool get isSpeakerOn => _speaker;
  @override
  bool get isCameraOn => _cameraOn;
  @override
  bool get isFrontCamera => _frontCamera;
  @override
  bool get isRealCallAvailable => config.isConfigured;

  /// The simulator opens no capture at all, so it never holds the microphone.
  @override
  bool get holdsMicrophone => false;

  /// The simulator never reaches a network, so it has no failure detail.
  @override
  String? get lastError => null;

  @override
  Duration get elapsed {
    if (_connectedAt == null) return Duration.zero;
    return DateTime.now().difference(_connectedAt!);
  }

  void _emit(CallSessionState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  @override
  Future<void> start({
    required String contactId,
    required String contactName,
    required bool isVideo,
  }) async {
    _emit(CallSessionState.dialling);
    _connectTimer?.cancel();
    // Simulate the peer picking up. A real implementation would wait for the
    // signalling layer to report the remote answer.
    _connectTimer = Timer(const Duration(seconds: 3), () {
      if (_state == CallSessionState.dialling ||
          _state == CallSessionState.ringing) {
        _markConnected();
      }
    });
  }

  void _markConnected() {
    _emit(CallSessionState.connected);
    _connectedAt = DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_durationController.isClosed) {
        _durationController.add(elapsed);
      }
    });
  }

  @override
  Future<void> accept() async {
    _emit(CallSessionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _markConnected();
  }

  @override
  Future<void> decline() async {
    _connectTimer?.cancel();
    _teardown();
    _emit(CallSessionState.ended);
  }

  @override
  Future<void> end() async {
    _teardown();
    _emit(CallSessionState.ended);
  }

  void _teardown() {
    _connectTimer?.cancel();
    _connectTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  @override
  Future<void> toggleMute() async => _muted = !_muted;

  @override
  Future<void> toggleSpeaker() async => _speaker = !_speaker;

  @override
  Future<void> toggleCamera() async => _cameraOn = !_cameraOn;

  @override
  Future<void> switchCamera() async => _frontCamera = !_frontCamera;

  @override
  Future<void> dispose() async {
    _teardown();
    await _stateController.close();
    await _durationController.close();
  }
}
