import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
// `widgets.dart` re-exports `foundation.dart`, so `debugPrint` comes from here
// and a separate foundation import would be redundant.
import 'package:flutter/widgets.dart';

import '../config/app_secrets.dart';
import '../permissions/permission_service.dart';
import 'agora_token_client.dart';
import 'call_service.dart';
import 'call_signaling_service.dart';

/// Configuration for the Agora call provider.
///
/// ### Auth: a token server, not a certificate in the APK
///
/// Agora authorises a channel join either with an App ID alone (*testing mode*)
/// or with a signed RTC token (*secured mode*). The project is in secured mode:
/// [tokenEndpoint] mints a per-call token over HTTP, and the App Certificate
/// that signs it lives only in the token server's environment.
///
/// [token] still exists, but only as a manual escape hatch for a single
/// short-lived token injected at build time:
///
///   flutter build apk --debug --dart-define=AGORA_TOKEN=`<token>`
///
/// It is empty in every normal build, so the token server is the only path. Do
/// not "simplify" this by embedding the App Certificate — that would put the
/// token-signing key inside the APK. It is no longer present in `AppSecrets` at
/// all, precisely so that there is nothing convenient to reach for.
class AgoraCallConfig {
  const AgoraCallConfig({
    this.appId = AppSecrets.agoraAppId,
    this.token = defaultToken,
    this.tokenEndpoint = defaultTokenEndpoint,
  });

  /// Build-time token override, read from `--dart-define=AGORA_TOKEN`.
  ///
  /// Declared as a `static const` rather than written inline: the analyzer
  /// rejects `String.fromEnvironment` in a default-parameter position, but
  /// accepts it as a constant field initializer — the shape `R2Config` uses.
  static const String defaultToken = String.fromEnvironment('AGORA_TOKEN');

  /// Token server URL, overridable with `--dart-define=AGORA_TOKEN_SERVER`.
  ///
  /// Declared as a constant field for the same reason as [defaultToken], and
  /// read after [AppSecrets.agoraTokenServerUrl] so flipping to a production
  /// worker is a build-flag change rather than a code change.
  static const String defaultTokenEndpoint = String.fromEnvironment(
    'AGORA_TOKEN_SERVER',
    defaultValue: AppSecrets.agoraTokenServerUrl,
  );

  /// Agora App ID. Public by design — it identifies the project.
  final String appId;

  /// Build-time RTC token, or empty to mint one from [tokenEndpoint].
  final String token;

  /// The token server that mints an RTC token for a channel join.
  final String tokenEndpoint;

  /// True once an App ID is present, i.e. a channel join can be attempted.
  bool get isConfigured => appId.trim().isNotEmpty;

  /// True when a token can actually be obtained for a join.
  bool get hasTokenSource =>
      token.trim().isNotEmpty || tokenEndpoint.trim().isNotEmpty;

  /// A client bound to [tokenEndpoint], or null when no server is configured.
  AgoraTokenClient? get tokenClient => tokenEndpoint.trim().isEmpty
      ? null
      : AgoraTokenClient(baseUrl: tokenEndpoint);
}

/// A real voice/video call carried by Agora's managed SFU.
///
/// ### Why this exists alongside [WebRtcCallService]
///
/// The two solve the same problem differently, and both are kept:
///
///   * `WebRtcCallService` is peer-to-peer. It needs STUN, and across
///     carrier-grade NAT it needs a TURN relay the project does not have — so
///     two mobile networks negotiate and then never connect.
///   * `AgoraCallService` relays every stream through Agora's infrastructure.
///     No TURN server to run, and connectivity across mobile networks works out
///     of the box, at the cost of a third party in the media path.
///
/// `providers.dart` selects between them, so the call screen is unchanged.
///
/// ### Signalling
///
/// The SFU owns the *media* session: both peers derive the same
/// [channelIdFor] channel and Agora matches them, so no SDP and no ICE
/// candidates cross Firestore on this path.
///
/// Firestore is still used for the *call*, via [CallSignalingService], and that
/// is not optional. A channel join is silent — nothing tells the other phone to
/// ring — so without a `calls/{callId}` document the callee would never learn a
/// call was happening. The document is what rings the phone; the channel is
/// only where the media ends up.
///
/// ### Status
///
/// The join/leave lifecycle, the audio/video controls and the call document are
/// implemented against the real SDK. Not done: reconnect after a network change,
/// and call-quality reporting.
class AgoraCallService implements CallService, CallVideoSurface {
  AgoraCallService({
    required this.selfUid,
    this.config = const AgoraCallConfig(),
    CallSignalingService? signaling,
    PermissionService permissions = const PermissionService(),
    @visibleForTesting RtcEngine Function()? engineFactory,
  })  : _signaling = signaling ?? CallSignalingService(),
        _injectedPermissions = permissions,
        _engineFactory = engineFactory ?? createAgoraRtcEngine;

  /// This device's account uid — the caller or callee side of the channel.
  final String selfUid;

  final AgoraCallConfig config;

  /// Creates the SDK engine. Injected so a test can hand back a fake and prove
  /// that every terminal path releases it — the mic leak was invisible to tests
  /// precisely because `_ensureEngine()` could never be reached without a real
  /// platform channel.
  final RtcEngine Function() _engineFactory;

  /// Asks the OS for camera/microphone before a join.
  ///
  /// The native Agora SDK captures media itself, so — unlike the WebRTC path,
  /// where `getUserMedia` makes Android raise the prompt implicitly — nothing
  /// here prompts unless we do it. Injected so tests can stub it.
  ///
  /// Named `_injectedPermissions` rather than `_permissions` on purpose:
  /// `_permissions = permissions` in the initializer list is exactly what
  /// `prefer_initializing_formals` flags, and a distinct name is a real fix
  /// rather than a suppression — the same shape as `AgoraTokenClient`.
  final PermissionService _injectedPermissions;

  /// The `calls/{callId}` rendezvous, shared with the WebRTC path.
  ///
  /// Injected so the app has one instance; constructed on demand otherwise.
  /// Touching Firestore is deferred to the first write, so building this
  /// service stays safe on a device where Firebase is not initialised.
  final CallSignalingService _signaling;

  final StreamController<CallSessionState> _stateController =
      StreamController<CallSessionState>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  RtcEngine? _engine;
  bool _engineFailed = false;

  /// The engine teardown currently running, if any.
  ///
  /// Awaited before a new engine is built: the SDK allows only one engine per
  /// App ID, so creating the next one while the previous is still being
  /// released can fail. Deferring teardown out of the SDK callbacks is what
  /// makes an overlap possible in the first place.
  Future<void>? _teardownInFlight;

  CallSessionState _state = CallSessionState.idle;
  Timer? _durationTimer;
  Timer? _ringTimer;
  DateTime? _connectedAt;

  bool _muted = false;
  bool _speaker = false;
  bool _cameraOn = true;
  bool _frontCamera = true;
  bool _isVideo = false;

  /// True once the peer actually joined, which is what separates an `ended`
  /// call from a `missed` one.
  bool _everConnected = false;

  /// Guards the terminal write so the leave callbacks and an explicit hang-up
  /// cannot both record an outcome.
  bool _finalised = false;

  String _channelId = '';
  int _localUid = 0;
  int _remoteUid = 0;

  /// The `calls/{callId}` document this session owns, once it exists.
  String _callId = '';

  /// Why the last join attempt failed, or null when it did not.
  ///
  /// Set by [_resolveToken] and read through [lastError]. The call screen shows
  /// a generic "call failed" otherwise, which tells a user nothing about
  /// whether to check their connection or stop trying.
  String? _lastError;

  /// The document id for an inbound call, known before this side accepts.
  String _pendingCallId = '';

  /// How long to let the other phone ring before giving up on it.
  ///
  /// Without this the document stays `ringing` forever after an unanswered
  /// call, and the caller's UI has nothing to move to.
  static const Duration ringTimeout = Duration(seconds: 45);

  // ------------------------------------------------------------ CallService

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

  /// True when an App ID is configured, so a channel can actually be joined.
  @override
  bool get isRealCallAvailable => config.isConfigured;

  /// Whether the engine currently holds the device's microphone.
  ///
  /// Derived from the live engine reference, never a stored boolean: a flag can
  /// disagree with the SDK and the disagreement is invisible, which is exactly
  /// how the capture stayed busy while the app believed no call was up. A live
  /// engine has had `enableAudio()` called on it, so its presence is the honest
  /// answer, and [_teardownEngine] is the only thing that clears it.
  @override
  bool get holdsMicrophone => _engine != null;

  /// The call document id for this session, or empty before it is created.
  ///
  /// Exposed so the UI can show call details without reaching into Firestore.
  String get callId => _callId.isNotEmpty ? _callId : _pendingCallId;

  /// Why the last join attempt failed, or null when there is nothing to report.
  ///
  /// Populated from the token-server result. Cleared at the start of every new
  /// call by [_reset], so a stale reason can never be shown against a later one.
  @override
  String? get lastError => _lastError;

  @override
  Duration get elapsed {
    final DateTime? since = _connectedAt;
    if (since == null) return Duration.zero;
    return DateTime.now().difference(since);
  }

  @override
  Future<void> start({
    required String contactId,
    required String contactName,
    required bool isVideo,
  }) async {
    _emit(CallSessionState.dialling);
    _reset();
    _isVideo = isVideo;
    _channelId = channelIdFor(selfUid, contactId);

    // Ask for media permissions *before* the document exists. The document is
    // what rings the other phone, so creating it first and then failing the
    // join would ring someone for a call this device cannot carry.
    final String? denial = await _ensureMediaPermissions(isVideo: isVideo);
    if (denial != null) {
      debugPrint('Agora call not placed: $denial');
      _lastError = denial;
      _emit(CallSessionState.failed);
      return;
    }

    // Write the document *before* joining. The join is silent — it puts this
    // device in a channel nobody is listening to yet — whereas the document is
    // what makes the other phone ring. Joining first would leave a window where
    // the caller appears connected to a call the callee has not been told about.
    _callId = await _signaling.createCall(
      callerId: selfUid,
      calleeId: contactId,
      isVideo: isVideo,
      channelName: _channelId,
    );
    _startRingTimeout();

    await _join(peerUid: contactId, isVideo: isVideo);
  }

  /// The callee side: joining the channel *is* accepting the call.
  @override
  Future<void> accept() async {
    _emit(CallSessionState.connecting);
    if (_channelId.isEmpty) {
      _emit(CallSessionState.failed);
      return;
    }
    if (_callId.isEmpty) _callId = _pendingCallId;
    if (_callId.isNotEmpty) {
      // Tell the caller somebody picked up, so its ring screen can stop ringing
      // even if the media takes a moment to flow.
      unawaited(_signaling.markAccepted(_callId));
    }
    await _join(peerUid: _pendingPeerUid, isVideo: _isVideo);
  }

  /// Set by [start] so [accept] knows which channel to join. The incoming-call
  /// UI calls `start`-less `accept`, so this is filled by the screen when it
  /// seeds the service from a ringing call.
  String _pendingPeerUid = '';

  /// Seeds the peer for an inbound call, before [accept].
  ///
  /// [channelName] should be the channel recorded on the call document. It is
  /// preferred over re-deriving one locally: the caller has already joined that
  /// exact channel, and the derivation only agrees while both sides keep
  /// hashing identically.
  void prepareIncoming({
    required String peerUid,
    required bool isVideo,
    String callId = '',
    String channelName = '',
  }) {
    _reset();
    _pendingPeerUid = peerUid;
    _pendingCallId = callId;
    _isVideo = isVideo;
    _channelId =
        channelName.isNotEmpty ? channelName : channelIdFor(selfUid, peerUid);
    _emit(CallSessionState.ringing);
  }

  @override
  Future<void> decline() async {
    _finalise(CallStatus.declined);
    await _leave();
  }

  @override
  Future<void> end() async {
    // A call that never connected was missed by whoever it was aimed at; one
    // that did connect simply ended. The distinction is what the call log's
    // "missed" badge is built from.
    _finalise(_everConnected ? CallStatus.ended : CallStatus.missed);
    await _leave();
  }

  @override
  Future<void> toggleMute() async {
    _muted = !_muted;
    try {
      await _engine?.muteLocalAudioStream(_muted);
    } on Object catch (error) {
      debugPrint('Agora mute failed: $error');
    }
  }

  @override
  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    try {
      await _engine?.setEnableSpeakerphone(_speaker);
    } on Object catch (error) {
      debugPrint('Agora speaker toggle failed: $error');
    }
  }

  @override
  Future<void> toggleCamera() async {
    _cameraOn = !_cameraOn;
    try {
      await _engine?.enableLocalVideo(_cameraOn);
    } on Object catch (error) {
      debugPrint('Agora camera toggle failed: $error');
    }
  }

  @override
  Future<void> switchCamera() async {
    _frontCamera = !_frontCamera;
    try {
      await _engine?.switchCamera();
    } on Object catch (error) {
      debugPrint('Agora switchCamera failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    // A session torn down while it was still live still has to be recorded,
    // otherwise the document is left `ringing` and the other phone never stops.
    if (!_finalised && _state != CallSessionState.idle) {
      _finalise(_everConnected ? CallStatus.ended : CallStatus.missed);
    }
    _teardownTimers();
    await _teardownEngine();
    // Idempotent on purpose: Riverpod disposes the provider after the call
    // screen has usually already torn the session down, and closing a closed
    // controller throws.
    if (!_stateController.isClosed) await _stateController.close();
    if (!_durationController.isClosed) await _durationController.close();
  }

  // -------------------------------------------------------- CallVideoSurface

  @override
  bool get isPublishingVideo => _isVideo && _cameraOn;

  @override
  Widget? buildRemoteVideo(BuildContext context) {
    final RtcEngine? engine = _engine;
    if (engine == null || _remoteUid == 0 || !_isVideo) return null;
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(uid: _remoteUid),
        connection: RtcConnection(channelId: _channelId),
      ),
    );
  }

  @override
  Widget? buildLocalVideo(BuildContext context) {
    final RtcEngine? engine = _engine;
    if (engine == null || !_isVideo || !_cameraOn) return null;
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: VideoCanvas(
          uid: _localUid,
          mirrorMode: _frontCamera
              ? VideoMirrorModeType.videoMirrorModeEnabled
              : VideoMirrorModeType.videoMirrorModeDisabled,
        ),
      ),
    );
  }

  // -------------------------------------------------------------- internals

  /// Clears per-session state so a service instance can be reused for a second
  /// call without the first one's ids or flags leaking into it.
  void _reset() {
    _finalised = false;
    _everConnected = false;
    _callId = '';
    _pendingCallId = '';
    _remoteUid = 0;
    _connectedAt = null;
    _lastError = null;
    _teardownTimers();
  }

  /// Records the terminal state exactly once.
  void _finalise(CallStatus status) {
    if (_finalised) return;
    _finalised = true;
    final String id = _callId.isNotEmpty ? _callId : _pendingCallId;
    if (id.isEmpty) return;
    unawaited(_signaling.setStatus(id, status));
  }

  /// Gives up on an unanswered call.
  void _startRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(ringTimeout, () {
      if (_state == CallSessionState.connected ||
          _state == CallSessionState.ended ||
          _state == CallSessionState.failed) {
        return;
      }
      debugPrint('Agora call $_callId rang out after ${ringTimeout.inSeconds}s');
      _finalise(CallStatus.missed);
      unawaited(_leave());
    });
  }

  /// Builds and initialises the engine once. Returns null when Agora is
  /// unconfigured or the platform refused to create an engine, so no caller has
  /// to guard the platform channel.
  Future<RtcEngine?> _ensureEngine() async {
    if (_engineFailed || !config.isConfigured) return null;
    final RtcEngine? existing = _engine;
    if (existing != null) return existing;

    // A teardown deferred out of an SDK callback may still be releasing the
    // previous engine. Only one engine may exist per App ID, so wait it out
    // rather than racing it — a race here fails the new call outright.
    final Future<void>? pending = _teardownInFlight;
    if (pending != null) await pending;

    try {
      final RtcEngine engine = _engineFactory();
      await engine.initialize(
        RtcEngineContext(
          appId: config.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            // Joined, but the peer may not be in the channel yet.
            _emit(CallSessionState.connecting);
          },
          onUserJoined: (
            RtcConnection connection,
            int remoteUid,
            int elapsed,
          ) {
            _remoteUid = remoteUid;
            _markConnected();
          },
          onUserOffline: (
            RtcConnection connection,
            int remoteUid,
            UserOfflineReasonType reason,
          ) {
            // The peer hung up — there is nobody left to talk to.
            if (remoteUid == _remoteUid) {
              _teardownTimers();
              _finalise(_everConnected ? CallStatus.ended : CallStatus.missed);
              _emit(CallSessionState.ended);
              // The call is over for this side too, so the microphone has to go
              // back as well: otherwise a caller whose callee hung up keeps the
              // capture open and cannot record a voice note afterwards.
              _teardownAfterCallback();
            }
          },
          onLeaveChannel: (RtcConnection connection, RtcStats stats) {
            _teardownTimers();
            // `_finalise` is idempotent, so this is a no-op when the hang-up
            // already recorded an outcome — which it normally has.
            _finalise(_everConnected ? CallStatus.ended : CallStatus.missed);
            _emit(CallSessionState.ended);
            // Covers the leaves this app did not initiate (kicked, network
            // drop). A no-op after our own teardown, which has already nulled
            // the reference.
            _teardownAfterCallback();
          },
          onError: (ErrorCodeType err, String msg) {
            debugPrint('Agora error $err: $msg');
            _teardownTimers();
            _finalise(_everConnected ? CallStatus.ended : CallStatus.missed);
            _emit(CallSessionState.failed);
            _teardownAfterCallback();
          },
        ),
      );
      _engine = engine;
      return engine;
    } on Object catch (error) {
      debugPrint('Agora engine could not be created: $error');
      _engineFailed = true;
      return null;
    }
  }

  Future<void> _join({required String peerUid, required bool isVideo}) async {
    if (peerUid.isEmpty || selfUid.isEmpty) {
      _emit(CallSessionState.failed);
      return;
    }

    _pendingPeerUid = peerUid;
    _isVideo = isVideo;
    _cameraOn = isVideo;
    // Never overwrite a channel that is already pinned: the callee was handed
    // the caller's channel, and re-deriving it here would silently move this
    // side to a different one if the two derivations ever disagreed.
    if (_channelId.isEmpty) _channelId = channelIdFor(selfUid, peerUid);
    _localUid = uidFor(selfUid);

    debugPrint(
      'Agora join: channel=$_channelId uid=$_localUid '
      'peer=$peerUid self=$selfUid video=$isVideo',
    );

    // Permissions come first, before the engine and before the token. The
    // native SDK captures media itself, so without a runtime grant the join
    // either fails or connects a call that carries no audio — and the other
    // phone has already been rung by then. Asking first keeps a doomed call
    // from ringing anyone.
    final String? denial = await _ensureMediaPermissions(isVideo: isVideo);
    if (denial != null) {
      debugPrint('Agora join blocked by permissions: $denial');
      _lastError = denial;
      _finalise(CallStatus.missed);
      _emit(CallSessionState.failed);
      return;
    }

    final RtcEngine? engine = await _ensureEngine();
    if (engine == null) {
      // Unconfigured, or the SDK is unavailable on this device. Fail loudly
      // rather than pretending a call is up.
      _finalise(CallStatus.missed);
      _emit(CallSessionState.failed);
      return;
    }

    // The token has to exist before the join, and it is the one step that can
    // fail for a reason outside this device. Resolve it first so a token-server
    // problem surfaces as "the call failed" rather than as a silent join into a
    // channel the server will kick this client out of.
    final String? token = await _resolveToken();
    if (token == null) {
      _finalise(CallStatus.missed);
      _emit(CallSessionState.failed);
      // The engine exists by now — `enableAudio()` has not run, so no capture is
      // held yet, but releasing it stops a failed attempt from leaving a
      // half-initialised singleton behind for the next one.
      await _teardownEngine();
      return;
    }
    debugPrint(
      'Agora token: ${token.length} chars, prefix='
      '${token.length <= 20 ? token : token.substring(0, 20)}…',
    );

    try {
      await engine.enableAudio();
      if (isVideo) {
        await engine.enableVideo();
        await engine.startPreview();
      } else {
        await engine.disableVideo();
      }

      // `joinChannel` resolves to void: the native return code is not exposed
      // by the Dart binding, so success is "no throw" and a refusal arrives
      // either as an AgoraRtcException here or via `onError` afterwards.
      await engine.joinChannel(
        token: token,
        channelId: _channelId,
        uid: _localUid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: isVideo,
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideo,
        ),
      );
      debugPrint(
        'Agora joinChannel accepted: channel=$_channelId uid=$_localUid',
      );
      _emit(CallSessionState.connecting);
    } on Object catch (error) {
      debugPrint('Agora joinChannel failed: $error');
      _lastError = 'Could not join the call.';
      _finalise(CallStatus.missed);
      _emit(CallSessionState.failed);
      // **This is the microphone leak.** `enableAudio()` above has already
      // opened the capture, so a join that throws used to leave the singleton
      // engine holding it. Android then refused `AudioRecorderService.start()`
      // with a busy-device error while the app still believed no call was up —
      // the "can't record during a phone call" report, with no call anywhere.
      await _teardownEngine();
    }
  }

  /// Asks for the runtime permissions a join needs.
  ///
  /// Returns a user-facing sentence when the call cannot proceed, or null when
  /// it may. Only [PermissionResult.denied], `permanentlyDenied` and
  /// `restricted` block: `notApplicable` means the platform has no permission
  /// model at all (desktop, tests), which is not a reason to refuse a call.
  ///
  /// `POST_NOTIFICATIONS` is requested too — on Android 13+ the incoming-call
  /// notification is silent without it — but never blocks, because the in-app
  /// ring screen does not depend on it.
  Future<String?> _ensureMediaPermissions({required bool isVideo}) async {
    final List<AppPermission> required = <AppPermission>[
      AppPermission.microphone,
      if (isVideo) AppPermission.camera,
    ];

    for (final AppPermission permission in required) {
      final PermissionResult result = await _injectedPermissions.request(permission);
      debugPrint('Agora permission $permission -> $result');
      if (result.isGranted || result == PermissionResult.notApplicable) {
        continue;
      }
      return result.messageFor(permission);
    }

    unawaited(_requestNotificationsQuietly());
    return null;
  }

  /// Best-effort notification permission; a refusal must not fail a call.
  Future<void> _requestNotificationsQuietly() async {
    try {
      final PermissionResult result =
          await _injectedPermissions.request(AppPermission.notifications);
      debugPrint('Agora permission notifications -> $result');
    } on Object catch (error) {
      debugPrint('Notification permission request failed: $error');
    }
  }

  /// The RTC token for this join, or null when one could not be obtained.
  ///
  /// Prefers a build-time [AgoraCallConfig.token] (the manual-testing escape
  /// hatch) and otherwise asks the token server. Returning null rather than an
  /// empty string matters: an empty token makes Agora attempt an APP-ID-only
  /// join, which on a secured project *appears* to succeed and then drops the
  /// client — a failure mode that is nearly impossible to diagnose from the UI.
  Future<String?> _resolveToken() async {
    final String buildTime = config.token.trim();
    if (buildTime.isNotEmpty) return buildTime;

    final AgoraTokenClient? client = config.tokenClient;
    if (client == null) {
      debugPrint(
        'Agora is in secured mode but no token server is configured. Set '
        'AppSecrets.agoraTokenServerUrl or pass --dart-define=AGORA_TOKEN_SERVER.',
      );
      _lastError = 'Calls are not configured on this build.';
      return null;
    }

    final TokenResult result = await client.fetch(
      channelName: _channelId,
      uid: _localUid,
    );
    _lastError = result.message;
    return result.token;
  }

  Future<void> _leave() async {
    _teardownTimers();
    _remoteUid = 0;
    _connectedAt = null;
    _emit(CallSessionState.ended);
    // Leaving the call screen has to hand the microphone and the camera back to
    // the OS, not merely detach this client from the channel. The engine is a
    // process-wide singleton — the SDK permits exactly one — so a `leaveChannel`
    // that keeps the engine alive keeps the capture alive with it, and the next
    // voice note is then refused by Android with no call anywhere on screen.
    await _teardownEngine();
  }

  /// Leaves the channel and releases the engine, returning the microphone and
  /// camera to the OS.
  ///
  /// This is the single teardown path: every terminal outcome routes here, so
  /// there is exactly one place that can be wrong about releasing. Idempotent,
  /// and safe to call when no engine was ever created.
  ///
  /// The reference is cleared *before* the awaits. `leaveChannel` re-enters this
  /// class through `onLeaveChannel`, and nulling first makes that callback's
  /// deferred teardown a no-op instead of a second release of a dying engine.
  /// A caller arriving mid-release is handed the in-flight future rather than
  /// starting another one.
  Future<void> _teardownEngine() {
    final RtcEngine? engine = _engine;
    if (engine == null) {
      return _teardownInFlight ?? Future<void>.value();
    }
    _engine = null;
    _cameraOn = false;
    final Future<void> work = _releaseEngine(engine);
    _teardownInFlight = work;
    return work;
  }

  Future<void> _releaseEngine(RtcEngine engine) async {
    try {
      await engine.leaveChannel();
    } on Object catch (error) {
      debugPrint('Agora leaveChannel failed: $error');
    }
    try {
      await engine.release();
    } on Object catch (error) {
      debugPrint('Agora release failed: $error');
    }
    _teardownInFlight = null;
  }

  /// Runs [teardownEngine] on the next microtask instead of inline.
  ///
  /// The SDK documents that `release` must not be called from inside one of its
  /// own callbacks: it waits for the callback to return before recycling its
  /// objects, so releasing in the handler risks a deadlock. Capturing the
  /// instance also stops a queued teardown from destroying an engine that a
  /// newer call has created in the meantime.
  void _teardownAfterCallback() {
    final RtcEngine? engine = _engine;
    if (engine == null) return;
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        if (!identical(_engine, engine)) return;
        await _teardownEngine();
      }),
    );
  }

  void _markConnected() {
    if (_state == CallSessionState.connected) return;
    _ringTimer?.cancel();
    _ringTimer = null;
    _everConnected = true;
    _emit(CallSessionState.connected);
    _connectedAt = DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_durationController.isClosed) {
        _durationController.add(elapsed);
      }
    });
  }

  void _teardownTimers() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  void _emit(CallSessionState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  /// A channel id both peers derive independently from the same pair of uids.
  ///
  /// Sorting makes the derivation symmetric, so the caller and the callee reach
  /// the same channel without exchanging anything. Agora caps a channel id at
  /// 64 bytes.
  static String channelIdFor(String a, String b) {
    final List<String> pair = <String>[a, b]..sort();
    final String joined = 'imo_${pair.first}_${pair.last}';
    return joined.length <= 64 ? joined : joined.substring(0, 64);
  }

  /// A stable 32-bit uid for an account id.
  ///
  /// Agora identifies a participant by an unsigned 32-bit integer that must be
  /// unique within the channel, so the account uid is hashed (FNV-1a) rather
  /// than used directly. `0` is reserved — it tells Agora to assign an id, which
  /// would break the peer's ability to address this user — so it is mapped to 1.
  static int uidFor(String uid) {
    int hash = 0x811c9dc5;
    for (final int unit in uid.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }
}
