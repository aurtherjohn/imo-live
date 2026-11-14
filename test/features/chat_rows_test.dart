import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/chat.dart';
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

void main() {
  group('mergeChatRows', () {
    test('wraps every conversation in a row', () {
      final DateTime base = DateTime(2026, 10, 1, 12);
      final List<ChatRow> rows = mergeChatRows(
        chats: <Chat>[
          _chat(id: 'c1', title: 'Adil', at: base),
        ],
      );

      expect(rows.length, 1);
      expect(rows.single, isA<ChatRowConversation>());
      expect(rows.single.rowKey, 'chat:c1');
    });

    test('orders by activity, newest first', () {
      final DateTime base = DateTime(2026, 10, 1, 12);
      final List<ChatRow> rows = mergeChatRows(
        chats: <Chat>[
          _chat(id: 'old', title: 'Old', at: base.subtract(const Duration(hours: 3))),
          _chat(id: 'new', title: 'New', at: base),
          _chat(id: 'mid', title: 'Mid', at: base.subtract(const Duration(hours: 1))),
        ],
      );

      expect(
        rows.map((ChatRow r) => r.rowKey).toList(),
        <String>['chat:new', 'chat:mid', 'chat:old'],
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
          ).map((ChatRow r) => r.rowKey).toList();

      expect(run(), run());
      // Ties fall back to the row key, so the order is deterministic.
      expect(run(), <String>['chat:a', 'chat:b']);
    });

    test('an empty list produces no rows', () {
      expect(mergeChatRows(chats: const <Chat>[]), isEmpty);
    });
  });
}
