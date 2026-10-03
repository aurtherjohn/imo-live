import '../../../core/models/chat.dart';
import '../../../core/models/group.dart';
import '../../../core/utils/row_keys.dart';

/// One row of the merged Chats tab.
///
/// ### Why the two kinds are merged rather than listed side by side
///
/// A channel and a conversation are the same thing to a user: a named place
/// that receives messages, with an unread badge, sorted by recency. Keeping
/// them in separate lists meant a channel post was easy to miss and the chat
/// list lied about being "everything that happened". The directive's ask — and
/// what WhatsApp/Telegram do — is one list, ordered by activity, with the
/// channel marked so it is still recognisable.
///
/// A sealed class rather than a nullable pair of fields, so a caller that
/// switches on the kind cannot accidentally read `chat` for a channel row: the
/// compiler will not let it.
sealed class ChatRow {
  const ChatRow({required this.activityAt});

  /// What the list sorts on. Newest first.
  final DateTime activityAt;

  /// A stable key for the row, unique across both kinds.
  ///
  /// Prefixed by kind on purpose: a channel and a chat can share an id in
  /// principle (both are Firestore doc ids), and a `ValueKey` collision would
  /// make Flutter reuse the wrong row's element and animate the wrong thing.
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

/// A channel the viewer follows or owns.
final class ChatRowChannel extends ChatRow {
  ChatRowChannel(this.channel) : super(activityAt: channel.activityAt);

  final Channel channel;

  @override
  String get rowKey => RowKeys.channel(channel.id);

  @override
  String get title => channel.name;
}

/// Merges conversations and channels into one list, newest activity first.
///
/// Pure and synchronous so it can be tested without a Firestore fake — the
/// interesting behaviour here is ordering and the unread rule, which are
/// exactly the parts an integration test would be slowest at pinning.
///
/// Ties are broken by kind (channels after conversations) and then by id, so
/// the order is stable across rebuilds. Without that, two rows sharing a
/// timestamp could swap places on every snapshot and the list would visibly
/// jitter.
List<ChatRow> mergeChatRows({
  required List<Chat> chats,
  required List<Channel> channels,
}) {
  final List<ChatRow> rows = <ChatRow>[
    for (final Chat chat in chats) ChatRowConversation(chat),
    for (final Channel channel in channels) ChatRowChannel(channel),
  ];

  rows.sort((ChatRow a, ChatRow b) {
    final int byTime = b.activityAt.compareTo(a.activityAt);
    if (byTime != 0) return byTime;
    // Conversations before channels on an exact tie — a conversation is the
    // more actionable row, and it matches the visual weight of the list.
    if (a is ChatRowConversation && b is ChatRowChannel) return -1;
    if (a is ChatRowChannel && b is ChatRowConversation) return 1;
    return a.rowKey.compareTo(b.rowKey);
  });

  return rows;
}
