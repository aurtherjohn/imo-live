import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/services/push_notification_service.dart';

void main() {
  group('PushPayload.fromData', () {
    test('reads a well-formed message payload', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'chatId': 'uidA_uidB',
        'title': 'Nadia',
        'body': 'Are we still on for 8?',
        'type': 'message',
      });

      expect(payload.chatId, 'uidA_uidB');
      expect(payload.title, 'Nadia');
      expect(payload.body, 'Are we still on for 8?');
      expect(payload.kind, PushKind.message);
    });

    test('falls back to snake_case chat_id', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'chat_id': 'uidA_uidB',
        'type': 'call',
      });

      expect(payload.chatId, 'uidA_uidB');
      expect(payload.kind, PushKind.call);
    });

    test('prefers chatId over chat_id when both are present', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'chatId': 'camel',
        'chat_id': 'snake',
      });

      expect(payload.chatId, 'camel');
    });

    test('skips an empty chatId and uses the next spelling', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'chatId': '   ',
        'chat_id': 'snake',
      });

      expect(payload.chatId, 'snake');
    });

    test('an unrecognised type degrades to unknown instead of throwing', () {
      expect(
        PushPayload.fromData(<String, dynamic>{'type': 'carrier_pigeon'}).kind,
        PushKind.unknown,
      );
      expect(
        PushPayload.fromData(<String, dynamic>{'type': 'MESSAGE '}).kind,
        PushKind.message,
        reason: 'type matching is case- and whitespace-insensitive',
      );
    });

    test('a missing type defaults to unknown', () {
      expect(
        PushPayload.fromData(<String, dynamic>{'chatId': 'x'}).kind,
        PushKind.unknown,
      );
    });

    test('an empty payload yields empty strings, never null', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{});

      expect(payload.chatId, isEmpty);
      expect(payload.title, isEmpty);
      expect(payload.body, isEmpty);
      expect(payload.kind, PushKind.unknown);
    });

    test('non-string values are coerced rather than cast', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'chatId': 42,
        'title': null,
        'body': true,
        'type': 'status',
      });

      expect(payload.chatId, '42');
      expect(payload.title, isEmpty);
      expect(payload.body, 'true');
      expect(payload.kind, PushKind.status);
    });

    test('values are trimmed', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'chatId': '  uidA_uidB  ',
        'type': '  message ',
      });

      expect(payload.chatId, 'uidA_uidB');
      expect(payload.kind, PushKind.message);
    });
  });

  group('PushPayload call fields', () {
    test('a call payload carries the caller, and needs no chatId', () {
      // The case that used to go nowhere: a call has no chat, so the tap
      // handler's `chatId.isEmpty` guard dropped it entirely.
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'type': 'call',
        'callerId': 'uidA',
        'title': 'Nadia',
      });

      expect(payload.kind, PushKind.call);
      expect(payload.callerId, 'uidA');
      expect(payload.chatId, isEmpty);
      expect(payload.title, 'Nadia', reason: 'the title is the caller name');
      expect(payload.isVideo, isFalse, reason: 'absent isVideo means voice');
    });

    test('reads the snake_case caller_id', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'type': 'call',
        'caller_id': 'uidA',
      });

      expect(payload.callerId, 'uidA');
    });

    test('prefers callerId over caller_id', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'callerId': 'camel',
        'caller_id': 'snake',
      });

      expect(payload.callerId, 'camel');
    });

    test('reads isVideo as a real bool', () {
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': true}).isVideo,
        isTrue,
      );
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': false}).isVideo,
        isFalse,
      );
    });

    test('reads isVideo as a string, because FCM delivers strings', () {
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': 'true'}).isVideo,
        isTrue,
      );
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': 'TRUE'}).isVideo,
        isTrue,
      );
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': '1'}).isVideo,
        isTrue,
      );
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': 'false'}).isVideo,
        isFalse,
      );
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': '0'}).isVideo,
        isFalse,
      );
    });

    test('an unreadable isVideo is false, never a throw', () {
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': 'maybe'}).isVideo,
        isFalse,
      );
      expect(
        PushPayload.fromData(<String, dynamic>{'isVideo': 42}).isVideo,
        isFalse,
      );
    });

    test('a message payload has no caller', () {
      final PushPayload payload = PushPayload.fromData(<String, dynamic>{
        'type': 'message',
        'chatId': 'uidA_uidB',
      });

      expect(payload.callerId, isEmpty);
      expect(payload.isVideo, isFalse);
    });
  });

  group('PushNotificationService', () {
    test('attaching an empty uid is a no-op', () async {
      // Guards the guard: without an early return the service would write a
      // token to `users/`, which is exactly the invalid path to avoid.
      final PushNotificationService service = PushNotificationService(
        notifications: null,
      );

      await service.attachUser('');
      await service.detachUser();

      expect(service.attachedUid, isEmpty);
      expect(service.token, isNull);
    });
  });
}
