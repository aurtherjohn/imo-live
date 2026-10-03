import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/services/call_signaling_service.dart';
import 'package:imo_live/core/services/webrtc_call_service.dart';

/// A minimal but well-formed SDP session description.
Map<String, dynamic> _session(String type) => <String, dynamic>{
      'type': type,
      'sdp': 'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\n',
    };

Map<String, dynamic> _candidate(String value) => <String, dynamic>{
      'candidate': value,
      'sdpMid': '0',
      'sdpMLineIndex': 0,
    };

void main() {
  group('CallDocument.fromMap', () {
    test('parses a complete call document', () {
      final CallDocument call = CallDocument.fromMap('call_1', <String, dynamic>{
        'callerId': 'alice',
        'callerName': 'Alice Rahman',
        'calleeId': 'bob',
        'isVideo': true,
        'status': 'active',
        'offer': _session('offer'),
        'answer': _session('answer'),
        'callerCandidates': <Map<String, dynamic>>[_candidate('a')],
        'calleeCandidates': <Map<String, dynamic>>[_candidate('b')],
      });

      expect(call.id, 'call_1');
      expect(call.callerId, 'alice');
      expect(call.callerName, 'Alice Rahman');
      expect(call.calleeId, 'bob');
      expect(call.isVideo, isTrue);
      expect(call.status, CallStatus.active);
      expect(call.hasOffer, isTrue);
      expect(call.hasAnswer, isTrue);
      expect(call.isNegotiated, isTrue);
      expect(call.callerCandidates, hasLength(1));
      expect(call.calleeCandidates, hasLength(1));
    });

    test('an empty document is a ringing voice call, not a crash', () {
      final CallDocument call =
          CallDocument.fromMap('call_2', <String, dynamic>{});

      expect(call.status, CallStatus.ringing);
      expect(call.isVideo, isFalse);
      expect(call.hasOffer, isFalse);
      expect(call.hasAnswer, isFalse);
      expect(call.isNegotiated, isFalse);
      expect(call.callerCandidates, isEmpty);
    });

    test('receiverId and type are honoured, as the current schema writes them', () {
      // The directive names the callee `receiverId` and the media mode `type`.
      // A document written that way must parse without the legacy `calleeId`
      // and `isVideo` fields present at all.
      final CallDocument call = CallDocument.fromMap('call_3', <String, dynamic>{
        'callerId': 'alice',
        'receiverId': 'bob',
        'type': 'video',
        'status': 'ringing',
      });

      expect(call.calleeId, 'bob');
      expect(call.isVideo, isTrue);
      expect(call.type, 'video');
    });

    test('legacy calleeId and isVideo still parse', () {
      // Documents written before the rename are still in the collection, and
      // the callee must ring for them.
      final CallDocument call = CallDocument.fromMap('call_4', <String, dynamic>{
        'calleeId': 'bob',
        'isVideo': true,
      });

      expect(call.calleeId, 'bob');
      expect(call.isVideo, isTrue);
      expect(call.type, 'video');
    });

    test('a voice call reports type voice', () {
      expect(
        CallDocument.fromMap('c', <String, dynamic>{'isVideo': false}).type,
        'voice',
      );
    });

    test('accepted is not over, and is recognised as picked up', () {
      final CallDocument call =
          CallDocument.fromMap('c', <String, dynamic>{'status': 'accepted'});

      expect(call.status, CallStatus.accepted);
      expect(call.isAccepted, isTrue);
      expect(call.isOver, isFalse);
    });

    test('the legacy active status still counts as picked up', () {
      // An older build wrote `active`; a call in progress must not look
      // unanswered to the current one.
      final CallDocument call =
          CallDocument.fromMap('c', <String, dynamic>{'status': 'active'});

      expect(call.isAccepted, isTrue);
      expect(call.isOver, isFalse);
    });

    test('ringing is not accepted', () {
      expect(
        CallDocument.fromMap('c', <String, dynamic>{'status': 'ringing'})
            .isAccepted,
        isFalse,
      );
    });

    test('channelName is carried for the Agora path', () {
      expect(
        CallDocument.fromMap(
          'c',
          <String, dynamic>{'channelName': 'imo_alice_bob'},
        ).channelName,
        'imo_alice_bob',
      );
      // Absent on the WebRTC path, where the channel is not used.
      expect(
        CallDocument.fromMap('c', <String, dynamic>{}).channelName,
        isEmpty,
      );
    });

    test('a missing caller name is empty, so the UI can say "Unknown"', () {
      // The name lookup is best-effort; a call must still ring without it.
      expect(
        CallDocument.fromMap('c', <String, dynamic>{'callerId': 'alice'})
            .callerName,
        isEmpty,
      );
      expect(
        CallDocument.fromMap('c', <String, dynamic>{'callerName': null})
            .callerName,
        isEmpty,
      );
    });

    test('an unknown status falls back to ringing', () {
      expect(
        CallDocument.fromMap('c', <String, dynamic>{'status': 'teleporting'})
            .status,
        CallStatus.ringing,
      );
    });

    test('a half-written SDP is treated as absent', () {
      // A session without a body, or without a type, is unusable — reporting it
      // as present would make the peer try setRemoteDescription and fail.
      expect(
        CallDocument.fromMap('c', <String, dynamic>{
          'offer': <String, dynamic>{'type': 'offer'},
        }).hasOffer,
        isFalse,
      );
      expect(
        CallDocument.fromMap('c', <String, dynamic>{
          'offer': <String, dynamic>{'sdp': 'v=0'},
        }).hasOffer,
        isFalse,
      );
      expect(
        CallDocument.fromMap('c', <String, dynamic>{
          'offer': <String, dynamic>{'type': 'offer', 'sdp': ''},
        }).hasOffer,
        isFalse,
      );
    });

    test('candidates without a candidate string are dropped', () {
      final CallDocument call =
          CallDocument.fromMap('c', <String, dynamic>{
        'callerCandidates': <Object?>[
          _candidate('real'),
          <String, dynamic>{'sdpMid': '0'},
          'not a map',
        ],
      });

      expect(call.callerCandidates, hasLength(1));
      expect(call.callerCandidates.single['candidate'], 'real');
    });

    test('isOver is true for every terminal status', () {
      for (final CallStatus status in <CallStatus>[
        CallStatus.ended,
        CallStatus.declined,
        CallStatus.missed,
      ]) {
        expect(
          CallDocument.fromMap('c', <String, dynamic>{'status': status.name})
              .isOver,
          isTrue,
          reason: '${status.name} should end the call',
        );
      }
      for (final CallStatus status in <CallStatus>[
        CallStatus.ringing,
        CallStatus.active,
      ]) {
        expect(
          CallDocument.fromMap('c', <String, dynamic>{'status': status.name})
              .isOver,
          isFalse,
        );
      }
    });

    test('candidatesFrom picks the other side', () {
      final CallDocument call = CallDocument.fromMap('c', <String, dynamic>{
        'callerCandidates': <Map<String, dynamic>>[_candidate('from caller')],
        'calleeCandidates': <Map<String, dynamic>>[_candidate('from callee')],
      });

      // The caller consumes the callee's candidates, and vice versa.
      expect(call.candidatesFrom(caller: true).single['candidate'],
          'from callee');
      expect(call.candidatesFrom(caller: false).single['candidate'],
          'from caller');
    });
  });

  group('WebRtcIce', () {
    test('always offers at least one ICE server', () {
      expect(WebRtcIce.servers, isNotEmpty);
      expect(WebRtcIce.servers.first['urls'], isA<List<dynamic>>());
    });

    test('configuration uses unified plan', () {
      expect(WebRtcIce.configuration['sdpSemantics'], 'unified-plan');
      expect(WebRtcIce.configuration['iceServers'], WebRtcIce.servers);
    });

    test('a TURN relay is configured, and it carries credentials', () {
      // 2026-09-29: this assertion is the inverse of what it used to be, and
      // the inversion is deliberate.
      //
      // It previously asserted `hasTurn == false` — "a build with no
      // `--dart-define` must not claim to have a relay". That was true, and
      // still wrong: with no relay, two callers on mobile networks negotiate
      // and then never connect. So "no relay configured" was not a safe
      // default, it was the call feature failing.
      //
      // What the test guards changed with the policy. Not "is a relay present"
      // but "is the relay *usable*": a TURN entry with an empty username or
      // credential fails at ICE time, silently, and presents as a NAT problem.
      expect(WebRtcIce.hasTurn, isTrue);

      final Map<String, dynamic> turn = WebRtcIce.servers.firstWhere(
        (Map<String, dynamic> s) => s.containsKey('credential'),
      );
      expect(turn['urls'], isA<List<dynamic>>());
      expect((turn['urls'] as List<dynamic>).single, startsWith('turn:'));
      expect(turn['username'], isNotEmpty);
      expect(turn['credential'], isNotEmpty);
    });

    test('the baked-in relay is the documented temporary one', () {
      // Shipping a relay is a deliberate act, not an accident of a default.
      // ⚠️ These values are Open Relay (Metered) — a shared, rate-limited
      // public test service. When Cloudflare TURN credentials replace them,
      // this test is expected to fail: update it then, on purpose.
      expect(WebRtcIce.turnUrl, contains('openrelay.metered.ca'));
      expect(WebRtcIce.turnUsername, 'openrelayproject');
      expect(WebRtcIce.stunUrl, 'stun:stun.l.google.com:19302');
    });
  });
}
