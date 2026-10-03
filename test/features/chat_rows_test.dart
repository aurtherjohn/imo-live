import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/chat.dart';
import 'package:imo_live/core/models/group.dart';
import 'package:imo_live/features/chats/domain/chat_rows.dart';

/// Builds a conversation with just the fields the merge reads.
Chat _chat({
  required String id,
  required String title,
  required DateTime at,
  int unread = 0,
}) =>
    Chat(
      id: id,
      title: title,
      lastMessage: 'hello',
      lastTimestamp: at,
      unreadCount: unread,
    );

/// Builds a channel, marking it followed so it earns a chat-list row.
Channel _channel({
  required String id,
  required String name,
  DateTime? lastMessageAt,
  DateTime? lastReadAt,
  String lastMessage = 'a post',
  int followers = 0,
  bool muted = false,
}) =>
    Channel(
      id: id,
      name: name,
      isFollowing: true,
      isMuted: muted,
      followerCount: followers,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      lastReadAt: lastReadAt,
    );

void main() {
  group('mergeChatRows', () {
    test('orders by activity, newest first, across both kinds', () {
      final DateTime base = DateTime(2026, 10, 1, 12);
      final List<ChatRow> rows = mergeChatRows(
        chats: <Chat>[
          _chat(id: 'c1', title: 'Adil', at: base.subtract(const Duration(hours: 3))),
        ],
        channels: <Channel>[
          _channel(
            id: 'ch1',
            name: 'News',
            lastMessageAt: base.subtract(const Duration(hours: 1)),
          ),
        ],
      );

      expect(rows.length, 2);
      expect(rows.first, isA<ChatRowChannel>(),
          reason: 'the channel posted more recently than the chat');
      expect(rows.last, isA<ChatRowConversation>());
    });

    test('interleaves the two kinds rather than grouping them', () {
      final DateTime base = DateTime(2026, 10, 1, 12);
      final List<ChatRow> rows = mergeChatRows(
        chats: <Chat>[
          _chat(id: 'c1', title: 'A', at: base),
          _chat(id: 'c2', title: 'B', at: base.subtract(const Duration(hours: 4))),
        ],
        channels: <Channel>[
          _channel(
            id: 'ch1',
            name: 'C',
            lastMessageAt: base.subtract(const Duration(hours: 2)),
          ),
        ],
      );

      expect(
        rows.map((ChatRow r) => r.rowKey).toList(),
        <String>['chat:c1', 'channel:ch1', 'chat:c2'],
        reason: 'a single recency-ordered list is the whole point of the merge',
      );
    });

    test('is stable when two rows share a timestamp', () {
      final DateTime same = DateTime(2026, 10, 1, 12);
      // Same inputs, run twice: the order must not depend on sort internals.
      List<String> run() => mergeChatRows(
            chats: <Chat>[
              _chat(id: 'b', title: 'B', at: same),
              _chat(id: 'a', title: 'A', at: same),
            ],
            channels: <Channel>[
              _channel(id: 'z', name: 'Z', lastMessageAt: same),
              _channel(id: 'y', name: 'Y', lastMessageAt: same),
            ],
          ).map((ChatRow r) => r.rowKey).toList();

      expect(run(), run());
      // Conversations lead an exact tie — the more actionable row first.
      expect(run().take(2).toList(), <String>['chat:a', 'chat:b']);
    });

    test('row keys are prefixed by kind so a shared id cannot collide', () {
      final DateTime at = DateTime(2026, 10, 1, 12);
      final List<ChatRow> rows = mergeChatRows(
        chats: <Chat>[_chat(id: 'X', title: 'chat', at: at)],
        channels: <Channel>[_channel(id: 'X', name: 'channel', lastMessageAt: at)],
      );

      final Set<String> keys = rows.map((ChatRow r) => r.rowKey).toSet();
      expect(keys.length, 2, reason: 'two rows with id X must not share a key');
      expect(keys, containsAll(<String>['chat:X', 'channel:X']));
    });

    test('an empty channel list leaves the conversations untouched', () {
      final DateTime at = DateTime(2026, 10, 1, 12);
      final List<ChatRow> rows = mergeChatRows(
        chats: <Chat>[_chat(id: 'c1', title: 'A', at: at)],
        channels: const <Channel>[],
      );
      expect(rows.length, 1);
      expect(rows.single, isA<ChatRowConversation>());
    });
  });

  group('Channel unread and activity rules', () {
    test('a channel with a post after the read marker is unread', () {
      final Channel channel = _channel(
        id: 'ch1',
        name: 'News',
        lastMessageAt: DateTime(2026, 10, 1, 12),
        lastReadAt: DateTime(2026, 10, 1, 11),
      );
      expect(channel.hasUnread, isTrue);
    });

    test('a channel read after its last post is not unread', () {
      final Channel channel = _channel(
        id: 'ch1',
        name: 'News',
        lastMessageAt: DateTime(2026, 10, 1, 11),
        lastReadAt: DateTime(2026, 10, 1, 12),
      );
      expect(channel.hasUnread, isFalse);
    });

    test('a channel never opened is unread once it has a post', () {
      final Channel channel = _channel(
        id: 'ch1',
        name: 'News',
        lastMessageAt: DateTime(2026, 10, 1, 12),
      );
      expect(channel.hasUnread, isTrue);
    });

    test('a channel with no posts is never unread', () {
      final Channel channel = _channel(id: 'ch1', name: 'News');
      expect(channel.hasUnread, isFalse);
    });

    test('activityAt falls back to lastUpdateAt when there are no posts', () {
      // A channel created but never posted to still needs a sort position.
      final Channel channel = Channel(
        id: 'ch1',
        name: 'New',
        isFollowing: true,
        lastUpdateAt: DateTime(2026, 10, 1, 9),
      );
      expect(channel.activityAt, DateTime(2026, 10, 1, 9));
    });

    test('activityAt is the epoch when a channel has no timestamps at all', () {
      const Channel channel = Channel(id: 'ch1', name: 'Bare');
      expect(channel.activityAt, DateTime(1970));
    });
  });
}
