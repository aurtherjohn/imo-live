import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/constants/app_constants.dart';
import 'package:imo_live/core/utils/row_keys.dart';

/// The row-key contract.
///
/// This is the seam between three places that must agree but cannot see each
/// other: the Cloud Function that writes a push payload
/// (`functions/channel_push.js` writes `chatId: "channel:<id>"`), the merged
/// chat list that uses the same string as a `ValueKey`, and the router that has
/// to turn it back into a screen. A change on any one side that is not mirrored
/// here is a notification tap that opens the wrong screen or nothing at all —
/// which no other test in the suite would catch.
void main() {
  group('channel keys', () {
    test('a channel key round-trips its id', () {
      final String key = RowKeys.channel('abc123');
      expect(key, 'channel:abc123');
      expect(RowKeys.isChannel(key), isTrue);
      expect(RowKeys.channelIdOf(key), 'abc123');
    });

    test('a chat key carries its own prefix', () {
      final String key = RowKeys.chat('chat-xyz');
      expect(key, 'chat:chat-xyz');
      expect(RowKeys.isChat(key), isTrue);
      expect(RowKeys.isChannel(key), isFalse);
      expect(RowKeys.chatIdOf(key), 'chat-xyz');
      expect(RowKeys.channelIdOf(key), isNull);
    });

    test('a chat and a channel sharing an id never produce the same key', () {
      // Both are Firestore document ids, so this is not hypothetical. A key
      // collision would make Flutter reuse the wrong row element.
      expect(RowKeys.chat('X'), isNot(RowKeys.channel('X')));
    });

    test('a prefix with no id is not treated as a channel', () {
      // An empty channel id would push `/channelChat/` and render "not found".
      // Falling through to the conversation route is the less-broken outcome.
      expect(RowKeys.channelIdOf('channel:'), isNull);
      expect(RowKeys.isChannel('channel:'), isTrue);
    });

    test('an id that merely contains the word channel is not a channel', () {
      expect(RowKeys.isChannel('my:channel'), isFalse);
      expect(RowKeys.channelIdOf('my:channel'), isNull);
    });
  });

  group('locationOf', () {
    test('a channel key resolves to the channel chat route', () {
      expect(
        RowKeys.locationOf('channel:abc'),
        '${AppRoutes.channelChat}/abc',
      );
    });

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

    test('the two routes are genuinely different screens', () {
      // Guards against a future rename collapsing them onto one path, which
      // would silently make channel taps open a conversation.
      expect(AppRoutes.chat, isNot(AppRoutes.channelChat));
      expect(
        RowKeys.locationOf('channel:abc'),
        isNot(RowKeys.locationOf('chat:abc')),
      );
    });
  });
}
