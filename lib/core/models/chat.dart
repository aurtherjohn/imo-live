import 'package:flutter/foundation.dart';

/// Sort order for the chat list.
enum ChatSort { recent, unreadFirst, alphabetical }

/// A conversation entry shown in the Chats tab.
///
/// A [Chat] is a lightweight index over [Message]s; the messages themselves
/// live in their own store keyed by [id].
@immutable
class Chat {
  const Chat({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.lastTimestamp,
    this.avatarPath,
    this.avatarColor,
    this.isGroup = false,
    this.isChannel = false,
    this.isCommunity = false,
    this.isBroadcast = false,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.isFavorite = false,
    this.isWork = false,
    this.isTyping = false,
    this.isOnline = false,
    this.lastSeen,
    this.draft = '',
    this.memberIds = const <String>[],
    this.memberCount = 0,
    this.description = '',
    this.wallpaperId,
    this.disappearingSeconds = 0,
    this.lastMessageStatus,
    this.lastMessageIsOutgoing = false,
    this.isMarkedUnread = false,
  });

  final String id;
  final String title;
  final String lastMessage;
  final DateTime lastTimestamp;
  final String? avatarPath;
  final int? avatarColor;
  final bool isGroup;
  final bool isChannel;
  final bool isCommunity;
  final bool isBroadcast;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool isFavorite;
  final bool isWork;
  final bool isTyping;
  final bool isOnline;
  final DateTime? lastSeen;
  final String draft;
  final List<String> memberIds;
  final int memberCount;
  final String description;
  final String? wallpaperId;
  final int disappearingSeconds;

  /// Status of the newest outgoing message, for the tick indicator.
  final String? lastMessageStatus;
  final bool lastMessageIsOutgoing;

  /// Explicitly flagged unread even though no new message arrived.
  final bool isMarkedUnread;

  bool get hasUnread => unreadCount > 0 || isMarkedUnread;

  /// True for a conversation that can only ever hold two people.
  bool get isDirect =>
      !isGroup && !isChannel && !isCommunity && !isBroadcast;

  /// The other participant's **uid** in a 1:1 chat, or null when there is not
  /// exactly one.
  ///
  /// [id] is a composite (`uidA_uidB`, see `ChatService.openDirectChat`), so it
  /// must never be used as a user id: resolving `users/{uidA_uidB}` always
  /// misses, which is what made the profile screen report "not found". This is
  /// the single place that turns a [Chat] back into a real uid.
  ///
  /// Null is returned for groups/channels/broadcasts, when [selfUid] is unknown,
  /// when [selfUid] is not among [memberIds] (a chat mirrored from another
  /// account), or when the members do not resolve to exactly one other person.
  /// Callers must treat null as "no profile to open" rather than guessing.
  String? peerUid(String selfUid) {
    if (!isDirect || selfUid.isEmpty) return null;
    if (!memberIds.contains(selfUid)) return null;
    final List<String> others = memberIds
        .where((String id) => id != selfUid && id.isNotEmpty)
        .toList(growable: false);
    return others.length == 1 ? others.first : null;
  }

  Chat copyWith({
    String? id,
    String? title,
    String? lastMessage,
    DateTime? lastTimestamp,
    String? avatarPath,
    int? avatarColor,
    bool? isGroup,
    bool? isChannel,
    bool? isCommunity,
    bool? isBroadcast,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    bool? isFavorite,
    bool? isWork,
    bool? isTyping,
    bool? isOnline,
    DateTime? lastSeen,
    String? draft,
    List<String>? memberIds,
    int? memberCount,
    String? description,
    String? wallpaperId,
    int? disappearingSeconds,
    String? lastMessageStatus,
    bool? lastMessageIsOutgoing,
    bool? isMarkedUnread,
  }) {
    return Chat(
      id: id ?? this.id,
      title: title ?? this.title,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTimestamp: lastTimestamp ?? this.lastTimestamp,
      avatarPath: avatarPath ?? this.avatarPath,
      avatarColor: avatarColor ?? this.avatarColor,
      isGroup: isGroup ?? this.isGroup,
      isChannel: isChannel ?? this.isChannel,
      isCommunity: isCommunity ?? this.isCommunity,
      isBroadcast: isBroadcast ?? this.isBroadcast,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isArchived: isArchived ?? this.isArchived,
      isFavorite: isFavorite ?? this.isFavorite,
      isWork: isWork ?? this.isWork,
      isTyping: isTyping ?? this.isTyping,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      draft: draft ?? this.draft,
      memberIds: memberIds ?? this.memberIds,
      memberCount: memberCount ?? this.memberCount,
      description: description ?? this.description,
      wallpaperId: wallpaperId ?? this.wallpaperId,
      disappearingSeconds: disappearingSeconds ?? this.disappearingSeconds,
      lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
      lastMessageIsOutgoing: lastMessageIsOutgoing ?? this.lastMessageIsOutgoing,
      isMarkedUnread: isMarkedUnread ?? this.isMarkedUnread,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'lastMessage': lastMessage,
        'lastTimestamp': lastTimestamp.toIso8601String(),
        'avatarPath': avatarPath,
        'avatarColor': avatarColor,
        'isGroup': isGroup,
        'isChannel': isChannel,
        'isCommunity': isCommunity,
        'isBroadcast': isBroadcast,
        'unreadCount': unreadCount,
        'isPinned': isPinned,
        'isMuted': isMuted,
        'isArchived': isArchived,
        'isFavorite': isFavorite,
        'isWork': isWork,
        'isTyping': isTyping,
        'isOnline': isOnline,
        'lastSeen': lastSeen?.toIso8601String(),
        'draft': draft,
        'memberIds': memberIds,
        'memberCount': memberCount,
        'description': description,
        'wallpaperId': wallpaperId,
        'disappearingSeconds': disappearingSeconds,
        'lastMessageStatus': lastMessageStatus,
        'lastMessageIsOutgoing': lastMessageIsOutgoing,
        'isMarkedUnread': isMarkedUnread,
      };

  factory Chat.fromJson(Map<String, dynamic> json) => Chat(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        lastMessage: json['lastMessage'] as String? ?? '',
        lastTimestamp:
            DateTime.tryParse(json['lastTimestamp'] as String? ?? '') ??
                DateTime.now(),
        avatarPath: json['avatarPath'] as String?,
        avatarColor: (json['avatarColor'] as num?)?.toInt(),
        isGroup: json['isGroup'] as bool? ?? false,
        isChannel: json['isChannel'] as bool? ?? false,
        isCommunity: json['isCommunity'] as bool? ?? false,
        isBroadcast: json['isBroadcast'] as bool? ?? false,
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        isPinned: json['isPinned'] as bool? ?? false,
        isMuted: json['isMuted'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
        isFavorite: json['isFavorite'] as bool? ?? false,
        isWork: json['isWork'] as bool? ?? false,
        isTyping: json['isTyping'] as bool? ?? false,
        isOnline: json['isOnline'] as bool? ?? false,
        lastSeen: json['lastSeen'] == null
            ? null
            : DateTime.tryParse(json['lastSeen'] as String),
        draft: json['draft'] as String? ?? '',
        memberIds:
            (json['memberIds'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
        description: json['description'] as String? ?? '',
        wallpaperId: json['wallpaperId'] as String?,
        disappearingSeconds: (json['disappearingSeconds'] as num?)?.toInt() ?? 0,
        lastMessageStatus: json['lastMessageStatus'] as String?,
        lastMessageIsOutgoing: json['lastMessageIsOutgoing'] as bool? ?? false,
        isMarkedUnread: json['isMarkedUnread'] as bool? ?? false,
      );
}
