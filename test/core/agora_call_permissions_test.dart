import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/permissions/permission_service.dart';
import 'package:imo_live/core/services/agora_call_service.dart';
import 'package:imo_live/core/services/call_service.dart';

/// Records what was asked for and answers from a script.
///
/// `PermissionService` is subclassed rather than mocked because the production
/// class is a thin, stateless wrapper — overriding `request` is the whole
/// surface [AgoraCallService] touches.
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

/// A config with no App ID, so `isConfigured` is false and `_ensureEngine`
/// returns null immediately.
///
/// This is what keeps the test hermetic: the permission gate runs *before* the
/// engine, so the gate is fully exercised, but nothing ever reaches a platform
/// channel (which would hang) or the token server (a real network call).
const AgoraCallConfig _noEngine = AgoraCallConfig(appId: '');

/// Drives the callee path, which needs no Firestore: an empty `callId` means
/// `accept()` never writes to the signalling service.
Future<AgoraCallService> _acceptWith({
  required _ScriptedPermissions permissions,
  required bool isVideo,
  AgoraCallConfig config = _noEngine,
}) async {
  final AgoraCallService service = AgoraCallService(
    selfUid: 'uid-self',
    config: config,
    permissions: permissions,
  );
  service.prepareIncoming(
    peerUid: 'uid-peer',
    isVideo: isVideo,
    callId: '',
    channelName: 'imo_uid-peer_uid-self',
  );
  await service.accept();
  return service;
}

void main() {
  group('AgoraCallService permission gate', () {
    test('a denied microphone blocks the join and explains why', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.denied,
        },
      );

      final AgoraCallService service = await _acceptWith(
        permissions: permissions,
        isVideo: false,
      );

      expect(service.state, CallSessionState.failed);
      expect(service.lastError, isNotNull);
      expect(service.lastError, contains('microphone'));
      expect(permissions.requested, <AppPermission>[AppPermission.microphone]);

      await service.dispose();
    });

    test('a permanently denied microphone blocks the join', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.permanentlyDenied,
        },
      );

      final AgoraCallService service = await _acceptWith(
        permissions: permissions,
        isVideo: false,
      );

      expect(service.state, CallSessionState.failed);
      expect(service.lastError, contains('system settings'));

      await service.dispose();
    });

    test('a voice call never asks for the camera', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{},
      );

      final AgoraCallService service = await _acceptWith(
        permissions: permissions,
        isVideo: false,
      );

      expect(
        permissions.requested,
        isNot(contains(AppPermission.camera)),
        reason: 'a voice call has no use for the camera',
      );
      expect(permissions.requested, contains(AppPermission.microphone));

      await service.dispose();
    });

    test('a video call asks for the camera, and a refusal blocks it', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.granted,
          AppPermission.camera: PermissionResult.denied,
        },
      );

      final AgoraCallService service = await _acceptWith(
        permissions: permissions,
        isVideo: true,
      );

      expect(
        permissions.requested,
        containsAll(<AppPermission>[
          AppPermission.microphone,
          AppPermission.camera,
        ]),
      );
      expect(service.state, CallSessionState.failed);
      expect(service.lastError, contains('camera'));

      await service.dispose();
    });

    test('a granted gate proceeds past permissions', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{},
      );

      final AgoraCallService service = await _acceptWith(
        permissions: permissions,
        isVideo: true,
      );

      expect(
        permissions.requested,
        containsAll(<AppPermission>[
          AppPermission.microphone,
          AppPermission.camera,
        ]),
      );
      // The engine is unavailable, so the session fails there. What matters is
      // that it is NOT a permission failure — the gate let it through.
      expect(service.lastError, isNull);
      expect(service.state, CallSessionState.failed);

      await service.dispose();
    });

    test('notApplicable does not block — a platform with no permission model',
        () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.microphone: PermissionResult.notApplicable,
        },
      );

      final AgoraCallService service = await _acceptWith(
        permissions: permissions,
        isVideo: false,
      );

      expect(permissions.requested, contains(AppPermission.microphone));
      expect(service.lastError, isNull);

      await service.dispose();
    });

    test('notifications are requested but never block the call', () async {
      final _ScriptedPermissions permissions = _ScriptedPermissions(
        <AppPermission, PermissionResult>{
          AppPermission.notifications: PermissionResult.denied,
        },
      );

      final AgoraCallService service = await _acceptWith(
        permissions: permissions,
        isVideo: false,
      );

      expect(permissions.requested, contains(AppPermission.notifications));
      // A refused notification permission must not fail a call: the in-app ring
      // does not depend on it.
      expect(service.lastError, isNull);

      await service.dispose();
    });
  });

  group('channel and uid derivation', () {
    test('channelIdFor is symmetric, so both peers derive the same channel', () {
      expect(
        AgoraCallService.channelIdFor('aaa', 'bbb'),
        AgoraCallService.channelIdFor('bbb', 'aaa'),
      );
      expect(AgoraCallService.channelIdFor('aaa', 'bbb'), 'imo_aaa_bbb');
    });

    test("channelIdFor stays within Agora's 64-byte channel limit", () {
      final String id = AgoraCallService.channelIdFor('u' * 80, 'v' * 80);
      expect(id.length, lessThanOrEqualTo(64));
    });

    test('each account gets its own uid, and never the reserved 0', () {
      final int a = AgoraCallService.uidFor('uid-self');
      final int b = AgoraCallService.uidFor('uid-peer');

      expect(a, isNot(b),
          reason: 'a shared uid kicks one peer out of the channel');
      expect(a, isNot(0), reason: '0 tells Agora to assign a uid, not this one');
      expect(b, isNot(0));
      expect(a, inInclusiveRange(0, 0xFFFFFFFF));
      expect(b, inInclusiveRange(0, 0xFFFFFFFF));
    });

    test('uidFor is stable across calls', () {
      expect(
        AgoraCallService.uidFor('uid-self'),
        AgoraCallService.uidFor('uid-self'),
      );
    });
  });
}
