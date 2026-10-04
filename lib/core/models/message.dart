import 'package:flutter/foundation.dart';

import 'message_parts.dart';

/// The central message model.
///
/// Immutable, JSON-serialisable, and deliberately free of any transport
/// concerns — the local repository persists it, and a future remote data
/// source can map it one-to-one.
@immutable
class Message {
  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.direction = MessageDirection.incoming,
    this.type = MessageType.text,
    this.status = MessageStatus.read,
    this.attachment,
    this.replyTo,
    this.reactions = const <MessageReaction>[],
    this.poll,
    this.event,
    this.isForwarded = false,
    this.isStarred = false,
    this.isPinned = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.localOnly = true,
    this.deliveredAt,
    this.readAt,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final MessageDirection direction;
  final MessageType type;
  final MessageStatus status;
  final Attachment? attachment;
  final ReplyPreview? replyTo;
  final List<MessageReaction> reactions;
  final Poll? poll;
  final EventInfo? event;
  final bool isForwarded;
  final bool isStarred;

  /// Pinned to the top of the chat. Local-first, like [isStarred]: the pin is
  /// stored on the message row and the chat screen derives the banner from it,
  /// so pinning works with no backend. A real backend would additionally write
  /// `pinnedMessageIds` on the chat document so the other participant sees it.
  final bool isPinned;
  final bool isEdited;
  final bool isDeleted;

  /// True while the message exists only on this device.
  final bool localOnly;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  bool get isOutgoing => direction == MessageDirection.outgoing;

  /// How long after sending a message its author may still retract it for
  /// everyone.
  ///
  /// The window is the whole point of the feature: without it "delete for
  /// everyone" is a tool for rewriting a conversation's history at any time,
  /// including after the other person has read, quoted or screenshotted it.
  ///
  /// Two days is this product's chosen allowance — long enough that a message
  /// sent over a weekend can still be taken back on Monday, short enough that
  /// it is not a general-purpose edit of someone else's record of the
  /// conversation. Past it the only option is "Delete for me", which is local
  /// and cannot touch the other person's copy at all.
  static const Duration deleteForEveryoneWindow = Duration(days: 2);

  /// Whether [now] is still inside [deleteForEveryoneWindow] for this message.
  ///
  /// Takes `now` rather than reading the clock so the rule is testable without
  /// waiting two days or faking time globally.
  ///
  /// A [timestamp] slightly in the *future* (the two devices' clocks disagree)
  /// yields a negative difference, which is inside the window — deliberately
  /// lenient, because refusing to delete a message the user just sent is a far
  /// worse failure than allowing a retraction a few seconds late.
  bool canDeleteForEveryoneAt(DateTime now) {
    if (isDeleted) return false;
    // Only the author may retract. A recipient retracting someone else's
    // message would be a different, and much worse, feature.
    if (!isOutgoing) return false;
    return now.difference(timestamp) < deleteForEveryoneWindow;
  }

  /// [canDeleteForEveryoneAt] against the current clock.
  bool get canDeleteForEveryone => canDeleteForEveryoneAt(DateTime.now());

  /// The retracted form of this message: identity and ordering survive, the
  /// content does not.
  ///
  /// This is the **single** definition of what a tombstone looks like. It is
  /// used by the local retraction, by the receive path when a tombstone arrives
  /// from Firestore, and by the upsert that protects a retraction from a stale
  /// snapshot — so those three cannot drift apart.
  ///
  /// ⚠️ Built by construction rather than with [copyWith], deliberately.
  /// `copyWith` cannot clear a field — every parameter is `x ?? this.x` — so
  /// `copyWith(poll: null)` silently *keeps* the poll. A retracted poll would
  /// then still hold its question, its options and its voters, on a message
  /// whose bubble reads "This message was deleted".
  Message retracted() => Message(
        id: id,
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        content: '',
        timestamp: timestamp,
        direction: direction,
        type: MessageType.text,
        status: status,
        isDeleted: true,
        // Kept so a merge that preserves them cannot resurrect the body, and
        // harmless visually: `getStarred`/`getPinned` both skip deleted rows.
        isStarred: isStarred,
        isPinned: isPinned,
        localOnly: localOnly,
        deliveredAt: deliveredAt,
        readAt: readAt,
      );

  /// Text shown in chat-list previews and reply previews.
  String get previewText {
    if (isDeleted) return 'This message was deleted';
    final String body = switch (type) {
      MessageType.text => content,
      MessageType.image => content.isEmpty ? 'Photo' : content,
      MessageType.video => content.isEmpty ? 'Video' : content,
      MessageType.voice => 'Voice message',
      MessageType.audio => 'Audio',
      MessageType.document => attachment?.fileName ?? 'Document',
      MessageType.location => 'Location',
      MessageType.contact => 'Contact',
      MessageType.poll => poll?.question ?? 'Poll',
      MessageType.event => event?.title ?? 'Event',
      MessageType.sticker => 'Sticker',
      MessageType.system => content,
      MessageType.gift => content.isEmpty ? 'Gift' : content,
    };
    return body.isEmpty ? 'Message' : body;
  }

  /// Groups identical reactions so the bubble can show one chip per emoji.
  Map<String, int> get reactionCounts {
    final Map<String, int> counts = <String, int>{};
    for (final MessageReaction r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    return counts;
  }

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderName,
    String? content,
    DateTime? timestamp,
    MessageDirection? direction,
    MessageType? type,
    MessageStatus? status,
    Attachment? attachment,
    ReplyPreview? replyTo,
    bool clearReply = false,
    List<MessageReaction>? reactions,
    Poll? poll,
    EventInfo? event,
    bool? isForwarded,
    bool? isStarred,
    bool? isPinned,
    bool? isEdited,
    bool? isDeleted,
    bool? localOnly,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      direction: direction ?? this.direction,
      type: type ?? this.type,
      status: status ?? this.status,
      attachment: attachment ?? this.attachment,
      replyTo: clearReply ? null : (replyTo ?? this.replyTo),
      reactions: reactions ?? this.reactions,
      poll: poll ?? this.poll,
      event: event ?? this.event,
      isForwarded: isForwarded ?? this.isForwarded,
      isStarred: isStarred ?? this.isStarred,
      isPinned: isPinned ?? this.isPinned,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      localOnly: localOnly ?? this.localOnly,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'direction': direction.name,
        'type': type.name,
        'status': status.name,
        'attachment': attachment?.toJson(),
        'replyTo': replyTo?.toJson(),
        'reactions': reactions.map((r) => r.toJson()).toList(),
        'poll': poll?.toJson(),
        'event': event?.toJson(),
        'isForwarded': isForwarded,
        'isStarred': isStarred,
        'isPinned': isPinned,
        'isEdited': isEdited,
        'isDeleted': isDeleted,
        'localOnly': localOnly,
        'deliveredAt': deliveredAt?.toIso8601String(),
        'readAt': readAt?.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String? ?? '',
        chatId: json['chatId'] as String? ?? '',
        senderId: json['senderId'] as String? ?? '',
        senderName: json['senderName'] as String? ?? '',
        content: json['content'] as String? ?? '',
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        direction: MessageDirection.values.firstWhere(
          (e) => e.name == json['direction'],
          orElse: () => MessageDirection.incoming,
        ),
        type: MessageType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MessageType.text,
        ),
        status: MessageStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => MessageStatus.read,
        ),
        attachment: json['attachment'] == null
            ? null
            : Attachment.fromJson(json['attachment'] as Map<String, dynamic>),
        replyTo: json['replyTo'] == null
            ? null
            : ReplyPreview.fromJson(json['replyTo'] as Map<String, dynamic>),
        reactions: (json['reactions'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
            .toList(),
        poll: json['poll'] == null
            ? null
            : Poll.fromJson(json['poll'] as Map<String, dynamic>),
        event: json['event'] == null
            ? null
            : EventInfo.fromJson(json['event'] as Map<String, dynamic>),
        isForwarded: json['isForwarded'] as bool? ?? false,
        isStarred: json['isStarred'] as bool? ?? false,
        isPinned: json['isPinned'] as bool? ?? false,
        isEdited: json['isEdited'] as bool? ?? false,
        isDeleted: json['isDeleted'] as bool? ?? false,
        localOnly: json['localOnly'] as bool? ?? true,
        deliveredAt: json['deliveredAt'] == null
            ? null
            : DateTime.tryParse(json['deliveredAt'] as String),
        readAt: json['readAt'] == null
            ? null
            : DateTime.tryParse(json['readAt'] as String),
      );
}
