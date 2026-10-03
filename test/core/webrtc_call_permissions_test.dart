import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/permissions/permission_service.dart';
import 'package:imo_live/core/services/call_service.dart';
import 'package:imo_live/core/services/call_signaling_service.dart';
import 'package:imo_live/core/services/webrtc_call_service.dart';

/// Records what was asked for and answers from a script.
///
/// `PermissionService` is subclassed rather than mocked because the production
/// class is a thin, stateless wrapper — overriding `request` is the whole
/// surface [WebRtcCallService] touches.
class _ScriptedPermissions extends PermissionService {
  _ScriptedPermissions(this._results);

  final Map<AppPermission, PermissionResult> _results;
  final List<AppPermission> requested = <AppPermission>[];

  @override
  Future<PermissionResult> request(AppPermission permission) async {
    requested.add(permission);
    return _results[permission] ?? PermissionResult.granted;
  }
}

/// Records the call documents that were opened.
///
/// Subclassed so the *blocking* cases can prove a document was never written.
/// `createCall` is the write that makes the other phone ring, so "not called"
/// is the machine-checkable form of "the other phone was never rung".
class _RecordingSignaling extends CallSignalingService {
  final List<String> opened = <String>[];

  @override
  Future<String> createCall({
    required String callerId,
    required String calleeId,
    required bool isVideo,
    String channelName = '',
  }) async {
    opened.add(calleeId);
    return 'call-1';
  }
}

/// Serves a single call document, so the *accept* path can be driven.
///
/// `acceptIncoming` blocks on `watchCall(...).firstWhere((d) => d.hasOffer)`,
/// so a fake that emits the document once is enough to walk the callee's path
/// up to the permission gate — which is past `_prepareRenderers`, the step the
/// camera-leak test needs to observe.
class _FakeSignaling extends CallSignalingService {
  _FakeSignaling({required this.document});

  final CallDocument document;

  @override
  Stream<CallDocument?> watchCall(String callId) =>
      Stream<CallDocument?>.value(document);

  @override
  Future<String> createCall({
    required String callerId,
    required String calleeId,
    required bool isVideo,
    String channelName = '',
  }) async =>
      'call-1';
}

/// Starts an outgoing call, which is the path the permission gate fronts.
///
/// Mostly used with a **refusing** script, where `start()` returns at the gate
/// and never reaches `getUserMedia`. The `notApplicable` case is the exception:
/// it walks on into the capture on purpose, to show the gate did not block —
/// under `flutter_tester` there is no plugin behind that channel, so it fails
/// immediately rather than hanging.
Future<WebRtcCallService> _startWith({
  required _ScriptedPermissions permissions,
  required _RecordingSignaling signaling,
  required bool isVideo,
}) async {
  final WebRtcCallService service = WebRtcCallService(
    selfUid: 'uid-self',
    signaling: signaling,
    permissions: permissions,
  );
  await service.start(
    contactId: 'uid-peer',
    contactName: 'Nadia',
    isVideo: isVideo,
  );
  return service;
}

void main() {
  // `getUserMedia` reaches a method channel. Without the binding that fails
  // with a framework-misuse error rather than a clean "no plugin here", which
  // would make the assertions below pass for the wrong reason.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebRtcCallService permission gate', () {
    test('a denied microphone fails the call before it rings anyone', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.denied,
        },
      );
      final _RecordingSignaling signaling = _RecordingSignaling();

      final WebRtcCallService service = await _startWith(
        permissions: permissions,
        signaling: signaling,
        isVideo: false,
      );

      expect(service.state, CallSessionState.failed);
      expect(service.lastError, isNotNull);
      expect(service.lastError, contains('microphone'));

      // The point of gating *before* the document: an unanswerable call must
      // never reach the callee's phone.
      expect(
        signaling.opened,
        isEmpty,
        reason: 'a call this device cannot carry must not ring the other phone',
      );

      await service.dispose();
    });

    test('a permanently denied microphone explains where to fix it', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.permanentlyDenied,
        },
      );

      final WebRtcCallService service = await _startWith(
        permissions: permissions,
        signaling: _RecordingSignaling(),
        isVideo: false,
      );

      expect(service.state, CallSessionState.failed);
      expect(service.lastError, contains('system settings'));

      await service.dispose();
    });

    test('a voice call never asks for the camera', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.denied,
        },
      );

      final WebRtcCallService service = await _startWith(
        permissions: permissions,
        signaling: _RecordingSignaling(),
        isVideo: false,
      );

      expect(permissions.requested, <AppPermission>[AppPermission.microphone]);

      await service.dispose();
    });

    test('a video call asks for the camera too', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.granted,
          AppPermission.camera: PermissionResult.denied,
        },
      );

      final WebRtcCallService service = await _startWith(
        permissions: permissions,
        signaling: _RecordingSignaling(),
        isVideo: true,
      );

      expect(
        permissions.requested,
        <AppPermission>[AppPermission.microphone, AppPermission.camera],
        reason: 'a video call is useless without the camera',
      );
      expect(service.state, CallSessionState.failed);
      expect(service.lastError, contains('camera'));

      await service.dispose();
    });

    test('notApplicable does not block — a platform with no permission model',
        () async {
      // `notApplicable` is what `PermissionService` returns when the platform
      // has no permission concept at all. Treating it as a refusal would make
      // every call fail on desktop and in tests.
      //
      // Proved by what fails *next*: the gate is passed, so the failure is the
      // capture, not the permission. A blocking gate would leave the
      // permission's own wording in `lastError` instead.
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.notApplicable,
        },
      );

      final WebRtcCallService service = await _startWith(
        permissions: permissions,
        signaling: _RecordingSignaling(),
        isVideo: false,
      );

      expect(permissions.requested, contains(AppPermission.microphone));
      expect(
        service.lastError,
        isNot(
          PermissionResult.notApplicable.messageFor(AppPermission.microphone),
        ),
      );

      await service.dispose();
    });
  });

  // ==========================================================================
  // The camera that outlived a video call.
  //
  // `WebRtcCallService` is a provider-scoped singleton: it survives every call
  // in a session. `_isVideo` was set from the first call and never cleared, so
  // after one video call *every* later call — including a voice call — asked
  // `getUserMedia` for a camera track and re-initialised the camera renderers.
  // That is the reported "camera stays on / voice messages blocked after a
  // call" symptom, and these tests pin it.
  // ==========================================================================
  group('WebRtcCallService per-call cleanup', () {
    test('a voice call after a video call does not ask for the camera', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          // Denied so `start` returns at the gate: the assertion is about what
          // was *requested*, not about the capture, which has no plugin here.
          AppPermission.microphone: PermissionResult.denied,
        },
      );

      final WebRtcCallService service = WebRtcCallService(
        selfUid: 'uid-self',
        signaling: _RecordingSignaling(),
        permissions: permissions,
      );

      // Call 1 — video. Reaches the camera permission, then is torn down.
      await service.start(
        contactId: 'uid-peer',
        contactName: 'Nadia',
        isVideo: true,
      );
      await service.end();

      permissions.requested.clear();

      // Call 2 — voice, on the same service instance.
      await service.start(
        contactId: 'uid-peer',
        contactName: 'Nadia',
        isVideo: false,
      );

      expect(
        permissions.requested,
        isNot(contains(AppPermission.camera)),
        reason: 'a voice call must never ask for the camera, even after a '
            'video call ran on the same service instance',
      );

      await service.dispose();
    });

    test('an incoming VOICE call after a video call does not ask for the '
        'camera', () async {
      // ⚠️ **What this test does and does not prove.**
      //
      // It proves the *permission gate* is evaluated against this call's own
      // kind, not a leftover one: the incoming document is a voice call, so the
      // camera must not be requested even though the preceding call on the same
      // service instance was a video call.
      //
      // It does **not** prove the camera session itself is released, because
      // that needs a real `flutter_webrtc` plugin: under `flutter_tester`
      // `RTCVideoRenderer.initialize()` throws `MissingPluginException`, so
      // `_renderersReady` never becomes true and the renderer path cannot be
      // observed at all. The teardown that releases the capture is asserted by
      // inspection instead — see the audit notes on `_teardown`.
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          // Denied so the call stops at the gate, after the kind has been read
          // from the document and after `_prepareRenderers` has decided whether
          // this is a camera call.
          AppPermission.microphone: PermissionResult.denied,
          AppPermission.camera: PermissionResult.denied,
        },
      );

      final _FakeSignaling signaling = _FakeSignaling(
        document: const CallDocument(
          id: 'call-2',
          callerId: 'uid-peer',
          callerName: 'Nadia',
          calleeId: 'uid-self',
          isVideo: false,
          offer: <String, dynamic>{'sdp': 'v=0', 'type': 'offer'},
        ),
      );

      final WebRtcCallService service = WebRtcCallService(
        selfUid: 'uid-self',
        signaling: signaling,
        permissions: permissions,
      );

      // Call 1 — an outgoing VIDEO call, torn down. This is what used to leave
      // `_isVideo == true` behind for the rest of the session.
      await service.start(
        contactId: 'uid-peer',
        contactName: 'Nadia',
        isVideo: true,
      );
      await service.end();

      permissions.requested.clear();

      // Call 2 — an incoming VOICE call on the same service instance.
      service.pendingCallId = 'call-2';
      await service.accept();

      expect(
        permissions.requested,
        isNot(contains(AppPermission.camera)),
        reason: 'the incoming call is a voice call, so the camera must not be '
            'requested even though a video call ran before it',
      );

      await service.dispose();
    });

    test('teardown returns the service to a state the next call can reuse',
        () async {
      // The invariant the whole leak fix rests on: after `end()`, nothing that
      // describes the *previous* call may still be set. `holdsMicrophone` is
      // the user-visible one — it is what the recorder checks to explain
      // "microphone is in use" when a call has left the capture open.
      final WebRtcCallService service = WebRtcCallService(
        selfUid: 'uid-self',
        signaling: _RecordingSignaling(),
        permissions: _ScriptedPermissions(
          <AppPermission, PermissionResult>{
            AppPermission.microphone: PermissionResult.denied,
          },
        ),
      );

      await service.start(
        contactId: 'uid-peer',
        contactName: 'Nadia',
        isVideo: true,
      );
      await service.end();

      expect(
        service.holdsMicrophone,
        isFalse,
        reason: 'a torn-down call must not report that it holds the microphone',
      );

      await service.dispose();
    });
  });
}
