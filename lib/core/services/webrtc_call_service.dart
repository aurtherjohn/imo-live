import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/app_secrets.dart';
import '../permissions/permission_service.dart';
import 'call_service.dart';
import 'call_signaling_service.dart';

/// ICE server configuration.
///
/// ---------------------------------------------------------------------------
/// STUN and TURN are both configured, and the TURN relay is the load-bearing
/// one. STUN alone is enough for two peers on the same LAN or behind friendly
/// NAT; it is **not** enough across symmetric NAT or carrier-grade NAT, which is
/// most mobile connections. Without a relay those two callers negotiate and
/// then never connect — which is the failure this configuration exists to
/// prevent.
///
/// Values come from [AppSecrets] and are overridable per build, so moving to a
/// Cloudflare TURN deployment needs no code change:
///
///   flutter build apk --release --split-per-abi \
///     --dart-define=CALLS_TURN_URL=turns:turn.example.com:5349 \
///     --dart-define=CALLS_TURN_USERNAME=... \
///     --dart-define=CALLS_TURN_PASSWORD=...
///
/// ⚠️ The default relay is Metered's **Open Relay** — a shared, rate-limited
/// public test service. It is there so the plumbing works out of the box, not
/// because it is fit to ship. See the warning in [AppSecrets].
/// ---------------------------------------------------------------------------
abstract final class WebRtcIce {
  static const String stunUrl = String.fromEnvironment(
    'CALLS_STUN_URL',
    defaultValue: AppSecrets.callStunUrl,
  );
  static const String turnUrl = String.fromEnvironment(
    'CALLS_TURN_URL',
    defaultValue: AppSecrets.callTurnUrl,
  );
  static const String turnUsername = String.fromEnvironment(
    'CALLS_TURN_USERNAME',
    defaultValue: AppSecrets.callTurnUsername,
  );
  static const String turnPassword = String.fromEnvironment(
    'CALLS_TURN_PASSWORD',
    defaultValue: AppSecrets.callTurnPassword,
  );

  /// True once a TURN relay has been supplied.
  static bool get hasTurn =>
      turnUrl.isNotEmpty && turnUsername.isNotEmpty && turnPassword.isNotEmpty;

  /// The `iceServers` block handed to [createPeerConnection].
  static List<Map<String, dynamic>> get servers => <Map<String, dynamic>>[
        if (stunUrl.isNotEmpty)
          <String, dynamic>{'urls': <String>[stunUrl]},
        if (hasTurn)
          <String, dynamic>{
            'urls': <String>[turnUrl],
            'username': turnUsername,
            'credential': turnPassword,
          },
      ];

  static Map<String, dynamic> get configuration => <String, dynamic>{
        'iceServers': servers,
        // Unified Plan is the only SDP shape WebRTC still supports for
        // multi-track sessions; Plan B was removed from the spec and from
        // libwebrtc.
        'sdpSemantics': 'unified-plan',
      };
}

/// Media streams a call can render.
///
/// Optional on [CallService] on purpose: [LocalCallService] has no real media,
/// and the call screen asks for this interface by type check rather than every
/// implementation being forced to depend on `flutter_webrtc`.
abstract interface class VideoCallStreams {
  /// Local camera preview, or null for a voice call.
  RTCVideoRenderer? get localRenderer;

  /// The peer's video, or null until the remote track arrives.
  RTCVideoRenderer? get remoteRenderer;
}

/// A real WebRTC call.
///
/// Implements the app's [CallService] contract, so the call screen needs no
/// changes to use it beyond asking for [VideoCallStreams].
///
/// ### How a call is set up
///
/// 1. `getUserMedia` opens the microphone (and camera, for a video call).
/// 2. A `RTCPeerConnection` is created with [WebRtcIce.configuration].
/// 3. The caller creates an SDP **offer** and publishes it through
///    [CallSignalingService]; the callee answers. SDP describes codecs and
///    transport — it is the only part that needs a server.
/// 4. Each side gathers **ICE candidates** (its own network addresses) and
///    swaps them the same way. Once a pair works, media flows peer to peer.
/// 5. Firestore is involved only in steps 3 and 4. Audio and video never pass
///    through it.
///
/// ### Status
///
/// The negotiation, the media pipeline and the call lifecycle — including the
/// ring timeout that marks an unanswered call `missed` — are real. What is not
/// done: no reconnection after a network change, and no call-quality reporting.
/// See the TODOs below.
class WebRtcCallService implements CallService, VideoCallStreams {
  WebRtcCallService({
    required this.selfUid,
    CallSignalingService? signaling,
    PermissionService permissions = const PermissionService(),
    this.iceServers,
  })  : _signaling = signaling ?? CallSignalingService(),
        _injectedPermissions = permissions;

  /// This device's uid — the caller or callee side of the signalling document.
  final String selfUid;

  /// Overrides [WebRtcIce.servers]. Only used by tests; production builds read
  /// the servers from `--dart-define` and [AppSecrets].
  final List<Map<String, dynamic>>? iceServers;

  final CallSignalingService _signaling;

  /// Asks the OS for the microphone and camera.
  ///
  /// Injected so a test can drive the refusal path without a platform channel.
  /// Named `_injectedPermissions` rather than `_permissions` because
  /// `_permissions = permissions` in the initializer list is exactly what
  /// `prefer_initializing_formals` flags, and a distinct name is a real fix
  /// rather than a suppression — the same shape as `AgoraCallService`.
  final PermissionService _injectedPermissions;

  /// Why the last call attempt failed, or null when there is nothing to report.
  ///
  /// Set on the permission refusal and on a media-open failure, both of which
  /// the user can act on. The call screen captures this on the transition into
  /// [CallSessionState.failed] and renders it, so a call that dies has a
  /// sentence next to it instead of a bare "Call failed".
  String? _lastError;

  final StreamController<CallSessionState> _stateController =
      StreamController<CallSessionState>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription<CallDocument?>? _callSub;
  Timer? _durationTimer;
  Timer? _ringTimer;
  DateTime? _connectedAt;

  CallSessionState _state = CallSessionState.idle;
  String _callId = '';
  bool _isVideo = false;
  bool _muted = false;
  bool _speaker = false;
  bool _cameraOn = true;
  bool _frontCamera = true;

  /// True once the peer connection actually reached `connected`.
  ///
  /// Separates an `ended` call from a `missed` one, which is what the call
  /// log's missed badge is built from.
  bool _everConnected = false;

  /// Guards the terminal write so the hang-up and the ring timeout cannot both
  /// record an outcome.
  bool _finalised = false;

  /// True once this service has torn a call down.
  ///
  /// ⚠️ **This is the fix for the recurring "video keeps running after a call"
  /// report.** See [_startedFromClean]: `_isVideo` is sticky state on a service
  /// that outlives every call, so the *next* call must not inherit it.
  bool _tornDownOnce = false;

  /// How long to let the other phone ring before giving up on it.
  ///
  /// Without this an unanswered call leaves the document on `ringing` forever,
  /// so the callee's device keeps a ring on screen for a call nobody is on.
  static const Duration ringTimeout = Duration(seconds: 45);

  /// Candidates already fed to the peer connection, so a candidate that
  /// Firestore re-delivers is not added twice.
  final Set<String> _appliedCandidates = <String>{};

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  /// The call an incoming ring refers to. Set by the incoming-call UI before
  /// calling [accept], because the [CallService.accept] contract takes no
  /// arguments.
  String? pendingCallId;

  @override
  RTCVideoRenderer? get localRenderer => _renderersReady ? _localRenderer : null;

  @override
  RTCVideoRenderer? get remoteRenderer =>
      _renderersReady ? _remoteRenderer : null;

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
  bool get isRealCallAvailable => true;

  /// True while the local capture is live.
  ///
  /// The stream *is* the microphone, and the teardown nulls it, so this cannot
  /// outlive the resource it reports.
  @override
  bool get holdsMicrophone => _localStream != null;

  /// A user-facing reason for the last failure, or null when there is none.
  ///
  /// WebRTC signalling has no token-server step, so the reportable failures are
  /// the local ones: a refused permission and a capture that would not open.
  /// Both are things the user can act on, which is the test for whether this
  /// string should exist at all.
  @override
  String? get lastError => _lastError;

  /// The signalling document this call is running on.
  String get callId => _callId;

  @override
  Duration get elapsed {
    final DateTime? start = _connectedAt;
    return start == null ? Duration.zero : DateTime.now().difference(start);
  }

  void _emit(CallSessionState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  /// Puts the per-call fields back to their initial values.
  ///
  /// ### The bug this prevents
  ///
  /// [_isVideo] is set by the *first* call and was never cleared. This service
  /// is a provider-scoped singleton — it lives for as long as the provider
  /// container does, which is the whole signed-in session — so a build that had
  /// once placed a video call carried `_isVideo == true` into every later call.
  /// Two things then went wrong, and both match the reported symptom:
  ///
  /// * [_prepareRenderers] saw `_isVideo == true` with `_renderersReady` reset
  ///   to false by [dispose], and re-initialised the local camera renderer — a
  ///   `RTCVideoRenderer` holds a **camera capture session**. So *answering a
  ///   voice call* opened the camera.
  /// * [_openMedia] asked `getUserMedia` for `video: true`, so even a voice
  ///   call captured the camera and could hold it past the call.
  ///
  /// The teardown path itself was already correct — it stops every track and
  /// nulls both `srcObject`s. What it could not undo was the *next* call
  /// picking the camera back up on its own. Resetting the per-call state here
  /// is the whole fix.
  ///
  /// Called at the start of both [start] and [acceptIncoming], *before*
  /// anything reads [_isVideo], and only on a retry ([_tornDownOnce]) — a
  /// second `start()` on a live service is a retry, and a first call has
  /// nothing to clean up.
  void _startedFromClean() {
    if (!_tornDownOnce) return;
    _tornDownOnce = false;
    _isVideo = false;
    _cameraOn = true;
    _frontCamera = true;
    _muted = false;
    _speaker = false;
    _connectedAt = null;
    _everConnected = false;
    _lastError = null;
  }

  // ------------------------------------------------------------------ setup

  Future<void> _prepareRenderers() async {
    if (_renderersReady || !_isVideo) return;
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      _renderersReady = true;
    } on Object catch (error) {
      debugPrint('WebRTC renderer init failed: $error');
    }
  }

  Future<void> _openMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(
        <String, dynamic>{
          'audio': true,
          'video': _isVideo
              ? <String, dynamic>{
                  'facingMode': _frontCamera ? 'user' : 'environment',
                }
              : false,
        },
      );
      if (_renderersReady) {
        _localRenderer.srcObject = _localStream;
      }
    } on Object catch (error) {
      // No permission, or no capture device. A call without media is pointless,
      // so this is a hard failure rather than a silent one.
      debugPrint('getUserMedia failed: $error');
      _lastError = 'Could not open the microphone'
          '${_isVideo ? ' or camera' : ''}. Check the app\'s permissions.';
      _emit(CallSessionState.failed);
      rethrow;
    }
  }

  /// Asks for the capture permissions this call needs — before it rings anyone.
  ///
  /// `getUserMedia` raises the Android prompt implicitly, so this is not the
  /// only thing standing between the call and a grant. Relying on it alone is
  /// still wrong: the prompt would arrive *after* the call document exists,
  /// i.e. after the other phone has already been rung for a call this device
  /// turns out to be unable to carry. Asking first turns that into a failure
  /// the caller sees immediately.
  ///
  /// Returns a user-facing sentence when the call cannot proceed, or null when
  /// it may. Only [PermissionResult.denied], `permanentlyDenied` and
  /// `restricted` block: `notApplicable` means the platform has no permission
  /// model at all (desktop, tests), which is not a reason to refuse a call.
  Future<String?> _ensureMediaPermissions({required bool isVideo}) async {
    final List<AppPermission> required = <AppPermission>[
      AppPermission.microphone,
      if (isVideo) AppPermission.camera,
    ];

    for (final AppPermission permission in required) {
      final PermissionResult result =
          await _injectedPermissions.request(permission);
      debugPrint('WebRTC permission $permission -> $result');
      if (result.isGranted || result == PermissionResult.notApplicable) {
        continue;
      }
      return result.messageFor(permission);
    }
    return null;
  }

  Future<RTCPeerConnection> _createPeerConnection({
    required bool fromCaller,
  }) async {
    final RTCPeerConnection pc = await createPeerConnection(
      iceServers == null
          ? WebRtcIce.configuration
          : <String, dynamic>{
              ...WebRtcIce.configuration,
              'iceServers': iceServers,
            },
      <String, dynamic>{},
    );

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final String id = _callId;
      if (id.isEmpty || candidate.candidate == null) return;
      unawaited(
        _signaling.addCandidate(id, candidate.toMap(), fromCaller: fromCaller),
      );
    };

    pc.onTrack = (RTCTrackEvent event) {
      final List<MediaStream> streams = event.streams;
      if (streams.isEmpty) return;
      if (_renderersReady) {
        _remoteRenderer.srcObject = streams.first;
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState connectionState) {
      debugPrint('ICE state: $connectionState');
      if (connectionState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          connectionState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markConnected();
      } else if (connectionState ==
              RTCIceConnectionState.RTCIceConnectionStateFailed ||
          connectionState ==
              RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (_state != CallSessionState.ended) _emit(CallSessionState.failed);
      }
    };

    final MediaStream? local = _localStream;
    if (local != null) {
      for (final MediaStreamTrack track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
    }
    return pc;
  }

  // -------------------------------------------------------------- lifecycle

  @override
  Future<void> start({
    required String contactId,
    required String contactName,
    required bool isVideo,
  }) async {
    // Clean the per-call state before assigning this call's own, so a retry
    // cannot inherit the previous call's `_isVideo`/camera flags.
    _startedFromClean();
    _isVideo = isVideo;
    _finalised = false;
    _everConnected = false;
    _lastError = null;
    _callId = '';
    _emit(CallSessionState.dialling);
    try {
      // Permissions come first, and before the call document exists. The
      // document is what rings the other phone, so creating it and *then*
      // discovering this device cannot capture would ring someone for a call
      // that can never happen.
      final String? denial = await _ensureMediaPermissions(isVideo: isVideo);
      if (denial != null) {
        debugPrint('WebRTC call not placed: $denial');
        _lastError = denial;
        _emit(CallSessionState.failed);
        return;
      }

      await _prepareRenderers();
      await _openMedia();

      final String callId = await _signaling.createCall(
        callerId: selfUid,
        calleeId: contactId,
        isVideo: isVideo,
      );
      _callId = callId;
      _startRingTimeout();

      final RTCPeerConnection pc =
          await _createPeerConnection(fromCaller: true);
      _peerConnection = pc;

      final RTCSessionDescription offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _signaling.setOffer(callId, offer.toMap());

      // The answer and the peer's candidates arrive on one stream.
      //
      // `onError` is not optional here. `watchCall` now rethrows once its
      // retries are spent, and an unhandled stream error would just be logged
      // by the zone handler while the call sat on "Ringing…" — the silent
      // failure this listener is most likely to produce. See [_onSignalingLost].
      _callSub = _signaling.watchCall(callId).listen(
        (CallDocument? doc) {
          if (doc == null) return;
          unawaited(_onCallUpdate(doc, fromCaller: true));
        },
        onError: (Object error) => unawaited(_onSignalingLost(error)),
      );
    } on Object catch (error) {
      debugPrint('WebRTC start failed: $error');
      _lastError ??= 'Could not start the call.';
      // The document exists from the moment `createCall` returned, so a failure
      // after that would otherwise leave it on `ringing` and keep the callee's
      // phone ringing for a call this device has already given up on. No-op
      // before `createCall`, when there is no id to write.
      _finalise(CallStatus.missed);
      _emit(CallSessionState.failed);
    }
  }

  /// Joins a call that is already ringing, i.e. the incoming side.
  Future<void> acceptIncoming({required String callId}) async {
    _callId = callId;
    _finalised = false;
    _everConnected = false;
    _lastError = null;
    // ⚠️ Do *not* reset `_isVideo` here: an incoming call's kind comes from the
    // document ([initial.isVideo] below), and clearing it first would let
    // `_prepareRenderers` run as a voice call for the frames before the
    // snapshot lands. What must be cleared is the previous call's camera state,
    // which `_startedFromClean` does without touching the incoming kind.
    if (_tornDownOnce) {
      _tornDownOnce = false;
      _cameraOn = true;
      _frontCamera = true;
    }
    _emit(CallSessionState.connecting);
    try {
      // Wait for the offer to *land*, not merely for the first snapshot.
      //
      // The ring is raised as soon as the call document exists, which is before
      // the caller has finished gathering its SDP. Taking `.first` here would
      // therefore read a document with no offer and fail the call on a race
      // that happens almost every time. `firstWhere` blocks until the offer
      // arrives, and the timeout is the caller having gone away.
      final CallDocument? initial = await _signaling
          .watchCall(callId)
          .firstWhere((CallDocument? doc) => doc != null && doc.hasOffer)
          .timeout(const Duration(seconds: 15));
      if (initial == null || !initial.hasOffer) {
        _emit(CallSessionState.failed);
        return;
      }
      _isVideo = initial.isVideo;

      // The ring has already happened by the time the callee taps accept, so
      // this is the earliest the grant can be settled — and it still has to be
      // before the capture opens, or the call connects carrying no audio.
      final String? denial = await _ensureMediaPermissions(isVideo: _isVideo);
      if (denial != null) {
        debugPrint('WebRTC accept blocked by permissions: $denial');
        _lastError = denial;
        _finalise(CallStatus.missed);
        _emit(CallSessionState.failed);
        return;
      }

      await _prepareRenderers();
      await _openMedia();

      final RTCPeerConnection pc =
          await _createPeerConnection(fromCaller: false);
      _peerConnection = pc;

      await pc.setRemoteDescription(_descriptionOf(initial.offer!));
      // Candidates the caller gathered before this device subscribed.
      unawaited(
        _drainCandidates(initial.candidatesFrom(caller: false)),
      );

      final RTCSessionDescription answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _signaling.setAnswer(callId, answer.toMap());

      _callSub = _signaling.watchCall(callId).listen(
        (CallDocument? doc) {
          if (doc == null) return;
          unawaited(_onCallUpdate(doc, fromCaller: false));
        },
        onError: (Object error) => unawaited(_onSignalingLost(error)),
      );
    } on Object catch (error) {
      debugPrint('WebRTC accept failed: $error');
      _lastError ??= 'Could not join the call.';
      // Failing to join must stop the caller's ring, not leave the document on
      // `ringing` until the caller's own 45 s timeout notices.
      _finalise(CallStatus.missed);
      _emit(CallSessionState.failed);
    }
  }

  @override
  Future<void> accept() async {
    final String? id = pendingCallId;
    if (id == null || id.isEmpty) {
      debugPrint('accept() with no pending call id');
      _emit(CallSessionState.failed);
      return;
    }
    await acceptIncoming(callId: id);
  }

  /// Applies whatever the other side has published.
  Future<void> _onCallUpdate(
    CallDocument doc, {
    required bool fromCaller,
  }) async {
    final RTCPeerConnection? pc = _peerConnection;
    if (pc == null) return;

    if (doc.isOver) {
      unawaited(end());
      return;
    }

    // The caller consumes the answer; the callee has already applied the offer.
    if (fromCaller &&
        doc.hasAnswer &&
        _state != CallSessionState.connected &&
        !_appliedCandidates.contains('answer')) {
      _appliedCandidates.add('answer');
      await pc.setRemoteDescription(_descriptionOf(doc.answer!));
    }

    await _drainCandidates(doc.candidatesFrom(caller: fromCaller));
  }

  /// The signalling stream died after its retries were spent.
  ///
  /// WebRTC media is peer-to-peer and does not run over Firestore, so losing the
  /// listener does not by itself stop the audio. It is still treated as the end
  /// of the call, for two reasons. The listener just lost is the only way a
  /// remote hang-up arrives, so what would be left on screen is a frozen
  /// "connected" call with a running timer and no way to learn the other side
  /// has gone. And [CallSessionState.failed] cannot be used to end it: the call
  /// screen writes its log entry and pops on `failed`, while the media is only
  /// released by the teardown that `ended` performs — so emitting `failed` with
  /// a live microphone would leak it, which is the bug this codebase has already
  /// paid for once.
  Future<void> _onSignalingLost(Object error) async {
    if (_finalised) return;
    if (_state == CallSessionState.ended || _state == CallSessionState.failed) {
      return;
    }
    debugPrint('WebRTC signalling lost for $_callId: $error');

    if (_everConnected) {
      _finalise(CallStatus.ended);
      await _teardown();
      _emit(CallSessionState.ended);
      return;
    }

    _lastError = 'Lost the connection to the call. Try again.';
    _finalise(CallStatus.missed);
    await _teardown();
    _emit(CallSessionState.failed);
  }

  Future<void> _drainCandidates(List<Map<String, dynamic>> candidates) async {
    final RTCPeerConnection? pc = _peerConnection;
    if (pc == null) return;
    for (final Map<String, dynamic> candidate in candidates) {
      final Object? key = candidate['candidate'];
      if (key == null || !_appliedCandidates.add(key.toString())) continue;
      try {
        await pc.addCandidate(
          RTCIceCandidate(
            candidate['candidate'] as String?,
            candidate['sdpMid'] as String?,
            candidate['sdpMLineIndex'] as int?,
          ),
        );
      } on Object catch (error) {
        debugPrint('addCandidate failed: $error');
      }
    }
  }

  /// Rebuilds an SDP session description from the map Firestore stored.
  ///
  /// `flutter_webrtc` has no `fromMap` for either signalling type, so both are
  /// reconstructed field by field. [CallDocument] has already checked that the
  /// `sdp` and `type` entries are non-empty strings.
  static RTCSessionDescription _descriptionOf(Map<String, dynamic> session) =>
      RTCSessionDescription(
        session['sdp'] as String,
        session['type'] as String,
      );

  void _markConnected() {
    if (_state == CallSessionState.connected) return;
    _ringTimer?.cancel();
    _ringTimer = null;
    _everConnected = true;
    _emit(CallSessionState.connected);
    _connectedAt = DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_durationController.isClosed) _durationController.add(elapsed);
    });
  }

  /// Gives up on a call nobody answered.
  void _startRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(ringTimeout, () {
      if (_state == CallSessionState.connected ||
          _state == CallSessionState.ended ||
          _state == CallSessionState.failed) {
        return;
      }
      debugPrint('WebRTC call $_callId rang out after ${ringTimeout.inSeconds}s');
      _finalise(CallStatus.missed);
      unawaited(end());
    });
  }

  /// Records the terminal state exactly once.
  ///
  /// The hang-up and the ring timeout can both fire — a user who ignores the
  /// ring for 45 s then taps End reaches both paths — and whichever arrives
  /// second must not relabel a `missed` call as `ended`.
  void _finalise(CallStatus status) {
    if (_finalised) return;
    _finalised = true;
    final String target =
        _callId.isNotEmpty ? _callId : (pendingCallId ?? '');
    if (target.isEmpty) return;
    unawaited(_signaling.setStatus(target, status));
  }

  /// Rejects an incoming call.
  ///
  /// Deliberately falls back to [pendingCallId] when there is no [_callId] yet:
  /// declining happens *before* a peer connection exists, so without this the
  /// document would stay `ringing` and the caller's phone would keep ringing
  /// for a call nobody is ever going to answer.
  @override
  Future<void> decline() async {
    _finalise(CallStatus.declined);
    await _teardown();
    _emit(CallSessionState.ended);
  }

  @override
  Future<void> end() async {
    _finalise(_everConnected ? CallStatus.ended : CallStatus.missed);
    await _teardown();
    _emit(CallSessionState.ended);
  }

  Future<void> _teardown() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    _ringTimer?.cancel();
    _ringTimer = null;
    await _callSub?.cancel();
    _callSub = null;

    final MediaStream? local = _localStream;
    if (local != null) {
      for (final MediaStreamTrack track in local.getTracks()) {
        // Both the audio and the video track: stopping only the audio leaves
        // the camera session up, which is the LED-stays-on symptom.
        await track.stop();
      }
    }
    await local?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    if (_renderersReady) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    }
    _appliedCandidates.clear();
    _callId = '';
    pendingCallId = null;

    // Tell the next call it must start from a clean slate. Set *last*, so a
    // teardown that threw part-way still leaves the flag true and the next
    // call still cleans up.
    _tornDownOnce = true;
  }

  // ---------------------------------------------------------------- controls

  @override
  Future<void> toggleMute() async {
    _muted = !_muted;
    final MediaStream? local = _localStream;
    if (local == null) return;
    for (final MediaStreamTrack track in local.getAudioTracks()) {
      track.enabled = !_muted;
    }
  }

  @override
  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } on Object catch (error) {
      debugPrint('setSpeakerphoneOn failed: $error');
    }
  }

  @override
  Future<void> toggleCamera() async {
    _cameraOn = !_cameraOn;
    final MediaStream? local = _localStream;
    if (local == null) return;
    for (final MediaStreamTrack track in local.getVideoTracks()) {
      track.enabled = _cameraOn;
    }
  }

  @override
  Future<void> switchCamera() async {
    _frontCamera = !_frontCamera;
    final MediaStream? local = _localStream;
    if (local == null) return;
    for (final MediaStreamTrack track in local.getVideoTracks()) {
      try {
        await Helper.switchCamera(track);
      } on Object catch (error) {
        debugPrint('switchCamera failed: $error');
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _teardown();
    try {
      await _localRenderer.dispose();
      await _remoteRenderer.dispose();
    } on Object catch (error) {
      debugPrint('renderer dispose failed: $error');
    }
    _renderersReady = false;
    await _stateController.close();
    await _durationController.close();
  }
}
