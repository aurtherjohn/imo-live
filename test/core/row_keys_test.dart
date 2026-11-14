import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/constants/app_constants.dart';
import 'package:imo_live/core/utils/row_keys.dart';

/// The row-key contract.
///
/// This is the seam between three places that must agree but cannot see each
/// other: the Cloud Function that writes a push payload (`chatId` in the FCM
/// data), the chat list that uses the same string as a `ValueKey`, and the
/// router that has to turn it back into a screen. A change on any one side that
/// is not mirrored here is a notification tap that opens the wrong screen or
/// nothing at all — which no other test in the suite would catch.
void main() {
  group('chat keys', () {
    test('a chat key carries its own prefix', () {
      final String key = RowKeys.chat('chat-xyz');
      expect(key, 'chat:chat-xyz');
      expect(RowKeys.isChat(key), isTrue);
      expect(RowKeys.chatIdOf(key), 'chat-xyz');
    });

    test('a prefix with no id is still a chat key but resolves to no id', () {
      expect(RowKeys.isChat('chat:'), isTrue);
      expect(RowKeys.chatIdOf('chat:'), isNull);
    });

    test('a colon in the id does not confuse the prefix check', () {
      expect(RowKeys.isChat('my:chat'), isFalse);
      expect(RowKeys.chatIdOf('my:chat'), isNull);
    });
  });

  group('locationOf', () {
    test('a prefixed chat key strips the prefix for the route', () {
      // The route takes a bare id; passing `chat:abc` through would request a
      // conversation whose id literally starts with "chat:".
      expect(RowKeys.locationOf('chat:abc'), '${AppRoutes.chat}/abc');
      expect(AppRoutes.chat, '/chat');
    });

    test('a bare id from an older sender still resolves', () {
      // A push enqueued before the prefix existed carries no prefix.
      expect(RowKeys.locationOf('abc'), '${AppRoutes.chat}/abc');
    });

    test('an empty id inside a chat prefix resolves to nothing', () {
      expect(RowKeys.locationOf('chat:'), isNull);
    });

    test('an empty key resolves to nothing', () {
      // A tap with no payload must not navigate at all.
      expect(RowKeys.locationOf(''), isNull);
    });
  });
}
