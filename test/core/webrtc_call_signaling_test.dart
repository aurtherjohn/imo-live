import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/services/call_service.dart';
import 'package:imo_live/core/services/call_signaling_service.dart';
import 'package:imo_live/core/services/webrtc_call_service.dart';

/// A signalling service whose call listener is dead on arrival.
///
/// Reproduces the failure that `watchCall` used to hide: the Firestore snapshot
/// stream closes on error, so the listener delivers nothing at all. The callee's
/// phone rings, the call is accepted, and then nothing further ever arrives —
/// no SDP answer, no ICE candidates, no end. Before the fix that was silent:
/// `handleError` marked the error handled and `_callSub` simply stopped.
class _DeadListenerSignaling extends CallSignalingService {
  /// Every terminal status written, in order.
  final List<(String, CallStatus)> statuses = <(String, CallStatus)>[];

  @override
  Stream<CallDocument?> watchCall(String callId) =>
      Stream<CallDocument?>.error(StateError('listener closed'));

  @override
  Future<void> setStatus(String callId, CallStatus status) async {
    statuses.add((callId, status));
  }
}

void main() {
  // The join reads signalling *before* it opens media, so this path never
  // reaches `getUserMedia` — no binding, no plugin channel, no platform needed.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebRtcCallService when the call listener dies', () {
    test('the join fails loudly instead of hanging on "Ringing…"', () async {
      final _DeadListenerSignaling signaling = _DeadListenerSignaling();
      final WebRtcCallService service =
          WebRtcCallService(selfUid: 'uid-self', signaling: signaling);

      await service.acceptIncoming(callId: 'call-1');

      expect(
        service.state,
        CallSessionState.failed,
        reason: 'a dead signalling listener must surface as a failure',
      );
      expect(
        service.lastError,
        isNotNull,
        reason: 'the screen renders this; a bare "Call failed" is the bug',
      );
      expect(service.lastError, contains('join'));

      await service.dispose();
    });

    test('the caller is told to stop ringing', () async {
      final _DeadListenerSignaling signaling = _DeadListenerSignaling();
      final WebRtcCallService service =
          WebRtcCallService(selfUid: 'uid-self', signaling: signaling);

      await service.acceptIncoming(callId: 'call-1');

      // Without this the document stays on `ringing` and the caller's phone
      // keeps ringing for a call nobody is ever going to answer — it only
      // notices when its own 45 s timeout expires.
      expect(
        signaling.statuses,
        contains(('call-1', CallStatus.missed)),
        reason: 'a failed join must terminalise the document',
      );
      expect(
        signaling.statuses.length,
        1,
        reason: 'the terminal write happens exactly once',
      );

      await service.dispose();
    });
  });
}
