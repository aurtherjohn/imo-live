import '../../../core/models/chat.dart';
import '../../../core/utils/row_keys.dart';

/// One row of the merged Chats tab.
///
/// A direct, group or broadcast conversation is a named place that receives
/// messages, with an unread badge, sorted by recency.
///
/// A sealed class rather than a nullable pair of fields, so a caller that
/// switches on the kind cannot accidentally read the wrong variant: the
/// compiler will not let it.
sealed class ChatRow {
  const ChatRow({required this.activityAt});

  /// What the list sorts on. Newest first.
  final DateTime activityAt;

  /// A stable key for the row.
  String get rowKey;

  /// The display name, for search matching.
  String get title;
}

/// A direct, group or broadcast conversation.
final class ChatRowConversation extends ChatRow {
  ChatRowConversation(this.chat) : super(activityAt: chat.lastTimestamp);

  final Chat chat;

  @override
  String get rowKey => RowKeys.chat(chat.id);

  @override
  String get title => chat.title;
}

/// Merges conversations into one list, newest activity first.
///
/// Pure and synchronous so it can be tested without a Firestore fake — the
/// interesting behaviour here is ordering and the unread rule, which are
/// exactly the parts an integration test would be slowest at pinning.
///
/// Ties are broken by id, so the order is stable across rebuilds. Without
/// that, two rows sharing a timestamp could swap places on every snapshot and
/// the list would visibly jitter.
List<ChatRow> mergeChatRows({
  required List<Chat> chats,
}) {
  final List<ChatRow> rows = <ChatRow>[
    for (final Chat chat in chats) ChatRowConversation(chat),
  ];

  rows.sort((ChatRow a, ChatRow b) {
    final int byTime = b.activityAt.compareTo(a.activityAt);
    if (byTime != 0) return byTime;
    return a.rowKey.compareTo(b.rowKey);
  });

  return rows;
}
