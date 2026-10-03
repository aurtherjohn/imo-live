import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/permissions/permission_service.dart';
import 'package:imo_live/core/services/agora_call_service.dart';
import 'package:imo_live/core/services/audio_location_service.dart';
import 'package:imo_live/core/services/call_service.dart';
import 'package:imo_live/local/storage/file_storage_service.dart';
import 'package:record/record.dart';

/// A stand-in for the native engine.
///
/// `RtcEngine` is abstract, so `implements` plus `noSuchMethod` is enough: the
/// service only ever calls a dozen of its members, and the interesting
/// behaviour is which of them were reached and in what order. Without this the
/// release paths could not be tested at all — reaching the real engine needs a
/// platform channel, which is why the microphone leak shipped unnoticed.
class _FakeRtcEngine implements RtcEngine {
  _FakeRtcEngine({this.joinThrows = false});

  /// Makes `joinChannel` fail the way a refused join does.
  final bool joinThrows;

  int initializeCalls = 0;
  int enableAudioCalls = 0;
  int leaveChannelCalls = 0;
  int releaseCalls = 0;

  /// True once the engine was released, i.e. the capture is back with the OS.
  bool get captureReleased => releaseCalls > 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #initialize:
        initializeCalls++;
        return Future<void>.value();
      case #enableAudio:
        enableAudioCalls++;
        return Future<void>.value();
      case #joinChannel:
        if (joinThrows) {
          throw StateError('join refused by the SDK');
        }
        return Future<void>.value();
      case #leaveChannel:
        leaveChannelCalls++;
        return Future<void>.value();
      case #release:
        releaseCalls++;
        return Future<void>.value();
      // Everything else the service may touch on the way: video setup, mute,
      // speaker, camera switches. None of them matter to the leak.
      case #registerEventHandler:
        return null;
      default:
        return Future<void>.value();
    }
  }
}

/// Grants everything, so the recording path reaches the recorder itself.
class _ScriptedPermissions extends PermissionService {
  @override
  Future<PermissionResult> request(AppPermission permission) async =>
      PermissionResult.granted;
}

/// A recorder that refuses to start, the way Android does when another capture
/// already holds the device.
class _RefusingRecorder implements AudioRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #hasPermission:
        return Future<bool>.value(true);
      case #start:
        throw Exception('AudioRecord: start failed, device busy');
      default:
        return Future<void>.value();
    }
  }
}

/// Skips the filesystem, which is not what these tests are about.
class _StubStorage extends FileStorageService {
  @override
  Future<String> reservePath(String folderName, String extension) async =>
      '/tmp/imo_test_voice.$extension';
}

/// A configured build with a build-time token, so the join reaches the engine
/// without touching the token server.
const AgoraCallConfig _configured = AgoraCallConfig(
  appId: 'test-app-id',
  token: 'test-token',
);

/// A configured App ID but no token source, to exercise the token failure path.
const AgoraCallConfig _noTokenSource = AgoraCallConfig(
  appId: 'test-app-id',
  token: '',
  tokenEndpoint: '',
);

AgoraCallService _service({
  required RtcEngine Function() engineFactory,
  AgoraCallConfig config = _configured,
}) {
  final AgoraCallService service = AgoraCallService(
    selfUid: 'uid-self',
    config: config,
    permissions: _ScriptedPermissions(),
    engineFactory: engineFactory,
  );
  // The callee path needs no Firestore: an empty call id means nothing is ever
  // written to the signalling service.
  service.prepareIncoming(
    peerUid: 'uid-peer',
    isVideo: false,
    callId: '',
    channelName: 'imo_uid-peer_uid-self',
  );
  return service;
}

void main() {
  group('AgoraCallService releases the capture', () {
    test('a service with no call up is not holding the microphone', () {
      final AgoraCallService service =
          _service(engineFactory: _FakeRtcEngine.new);
      expect(service.holdsMicrophone, isFalse);
    });

    test('a join that throws still hands the microphone back', () async {
      // The reported bug, in one test. `enableAudio()` opens the capture before
      // `joinChannel()`, so a join that fails used to leave the singleton engine
      // holding it: Android then refused every later `AudioRecord` while the app
      // believed no call was up.
      final _FakeRtcEngine engine = _FakeRtcEngine(joinThrows: true);
      final AgoraCallService service =
          _service(engineFactory: () => engine);

      await service.accept();

      expect(
        engine.enableAudioCalls,
        1,
        reason: 'the capture really was opened before the join failed',
      );
      expect(service.state, CallSessionState.failed);
      expect(engine.leaveChannelCalls, 1);
      expect(engine.releaseCalls, 1);
      expect(engine.captureReleased, isTrue);
      expect(
        service.holdsMicrophone,
        isFalse,
        reason: 'a failed call must not leave the microphone held',
      );

      await service.dispose();
    });

    test('hanging up hands the microphone back', () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraCallService service =
          _service(engineFactory: () => engine);

      await service.accept();
      expect(service.holdsMicrophone, isTrue);

      await service.end();

      expect(engine.leaveChannelCalls, 1);
      expect(engine.releaseCalls, 1);
      expect(service.holdsMicrophone, isFalse);
      expect(service.state, CallSessionState.ended);

      await service.dispose();
    });

    test('declining an incoming call hands the microphone back', () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraCallService service =
          _service(engineFactory: () => engine);

      await service.accept();
      expect(service.holdsMicrophone, isTrue);

      await service.decline();

      expect(engine.releaseCalls, 1);
      expect(service.holdsMicrophone, isFalse);

      await service.dispose();
    });

    test('a token failure releases the engine it had already built', () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraCallService service = _service(
        engineFactory: () => engine,
        config: _noTokenSource,
      );

      await service.accept();

      expect(service.state, CallSessionState.failed);
      expect(engine.initializeCalls, 1, reason: 'the engine was built');
      expect(
        engine.enableAudioCalls,
        0,
        reason: 'no capture is opened without a token',
      );
      expect(
        engine.releaseCalls,
        1,
        reason: 'a half-initialised engine must not be left behind',
      );
      expect(service.holdsMicrophone, isFalse);

      await service.dispose();
    });

    test('dispose releases the engine and is safe to call twice', () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraCallService service =
          _service(engineFactory: () => engine);

      await service.accept();
      expect(service.holdsMicrophone, isTrue);

      await service.dispose();
      expect(engine.releaseCalls, 1);
      expect(service.holdsMicrophone, isFalse);

      // Riverpod disposes the provider after the screen has usually torn the
      // session down already, so a second call is the normal case, not an edge.
      await service.dispose();
      expect(engine.releaseCalls, 1, reason: 'a closed engine is not re-released');
    });

    test('a failed call does not poison the next one', () async {
      // The leak's second-order effect: the SDK permits one engine per App ID,
      // so an unreleased engine is handed to the next call rather than replaced.
      // A fresh engine here is proof the previous one was actually released.
      final List<_FakeRtcEngine> engines = <_FakeRtcEngine>[];
      final AgoraCallService service = _service(
        engineFactory: () {
          final _FakeRtcEngine engine =
              _FakeRtcEngine(joinThrows: engines.isEmpty);
          engines.add(engine);
          return engine;
        },
      );

      await service.accept();
      expect(service.state, CallSessionState.failed);
      expect(engines, hasLength(1));
      expect(engines.first.releaseCalls, 1);

      service.prepareIncoming(
        peerUid: 'uid-peer',
        isVideo: false,
        callId: '',
        channelName: 'imo_uid-peer_uid-self',
      );
      await service.accept();

      expect(engines, hasLength(2), reason: 'the first engine was released');
      expect(engines.last.releaseCalls, 0);
      expect(service.holdsMicrophone, isTrue);

      await service.dispose();
      expect(engines.last.releaseCalls, 1);
    });
  });

  group('voice recording explains a busy microphone', () {
    Future<({bool ok, String? error})> startWith({
      required bool Function() callHoldsMicrophone,
    }) {
      final AudioRecorderService recorder = AudioRecorderService(
        recorder: _RefusingRecorder(),
        storage: _StubStorage(),
        permissions: _ScriptedPermissions(),
        callHoldsMicrophone: callHoldsMicrophone,
      );
      return recorder.start();
    }

    test('names the call when the call layer still holds the capture', () async {
      final ({bool ok, String? error}) result =
          await startWith(callHoldsMicrophone: () => true);

      expect(result.ok, isFalse);
      expect(result.error, contains('Hang up'));
    });

    test('keeps the platform error when no call is holding it', () async {
      final ({bool ok, String? error}) result =
          await startWith(callHoldsMicrophone: () => false);

      expect(result.ok, isFalse);
      expect(result.error, contains('Could not start recording'));
    });

    test('with no call layer wired the platform error is reported as-is',
        () async {
      final AudioRecorderService recorder = AudioRecorderService(
        recorder: _RefusingRecorder(),
        storage: _StubStorage(),
        permissions: _ScriptedPermissions(),
      );

      final ({bool ok, String? error}) result = await recorder.start();

      expect(result.ok, isFalse);
      expect(result.error, contains('Could not start recording'));
    });

    test('the probe is consulted live, not captured at construction', () async {
      // A stored boolean is what the app got wrong: it kept saying "in a call"
      // long after the call was gone. The probe has to be read at the moment of
      // failure, so flipping the answer must flip the message.
      bool held = true;
      final AudioRecorderService recorder = AudioRecorderService(
        recorder: _RefusingRecorder(),
        storage: _StubStorage(),
        permissions: _ScriptedPermissions(),
        callHoldsMicrophone: () => held,
      );

      final ({bool ok, String? error}) whileHeld = await recorder.start();
      expect(whileHeld.error, contains('Hang up'));

      held = false;
      final ({bool ok, String? error}) afterRelease = await recorder.start();
      expect(afterRelease.error, contains('Could not start recording'));
    });
  });
}
