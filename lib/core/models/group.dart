import 'package:flutter/foundation.dart';

/// Whether a group member is a plain member, an admin, or the creator.
enum GroupRole { member, admin, owner }

@immutable
class GroupMember {
  const GroupMember({
    required this.contactId,
    this.role = GroupRole.member,
    this.joinedAt,
    this.canSendMessages = true,
    this.canEditInfo = false,
  });

  final String contactId;
  final GroupRole role;
  final DateTime? joinedAt;
  final bool canSendMessages;
  final bool canEditInfo;

  bool get isAdmin => role == GroupRole.admin || role == GroupRole.owner;

  GroupMember copyWith({
    GroupRole? role,
    DateTime? joinedAt,
    bool? canSendMessages,
    bool? canEditInfo,
  }) =>
      GroupMember(
        contactId: contactId,
        role: role ?? this.role,
        joinedAt: joinedAt ?? this.joinedAt,
        canSendMessages: canSendMessages ?? this.canSendMessages,
        canEditInfo: canEditInfo ?? this.canEditInfo,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contactId': contactId,
        'role': role.name,
        'joinedAt': joinedAt?.toIso8601String(),
        'canSendMessages': canSendMessages,
        'canEditInfo': canEditInfo,
      };

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        contactId: json['contactId'] as String? ?? '',
        role: GroupRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => GroupRole.member,
        ),
        joinedAt: json['joinedAt'] == null
            ? null
            : DateTime.tryParse(json['joinedAt'] as String),
        canSendMessages: json['canSendMessages'] as bool? ?? true,
        canEditInfo: json['canEditInfo'] as bool? ?? false,
      );
}

/// Group-level permission toggles surfaced in Group Info.
@immutable
class GroupPermissions {
  const GroupPermissions({
    this.sendMessages = true,
    this.editGroupInfo = false,
    this.addMembers = false,
    this.inviteViaLink = true,
    this.approvalRequired = false,
  });

  final bool sendMessages;
  final bool editGroupInfo;
  final bool addMembers;
  final bool inviteViaLink;
  final bool approvalRequired;

  GroupPermissions copyWith({
    bool? sendMessages,
    bool? editGroupInfo,
    bool? addMembers,
    bool? inviteViaLink,
    bool? approvalRequired,
  }) =>
      GroupPermissions(
        sendMessages: sendMessages ?? this.sendMessages,
        editGroupInfo: editGroupInfo ?? this.editGroupInfo,
        addMembers: addMembers ?? this.addMembers,
        inviteViaLink: inviteViaLink ?? this.inviteViaLink,
        approvalRequired: approvalRequired ?? this.approvalRequired,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sendMessages': sendMessages,
        'editGroupInfo': editGroupInfo,
        'addMembers': addMembers,
        'inviteViaLink': inviteViaLink,
        'approvalRequired': approvalRequired,
      };

  factory GroupPermissions.fromJson(Map<String, dynamic> json) =>
      GroupPermissions(
        sendMessages: json['sendMessages'] as bool? ?? true,
        editGroupInfo: json['editGroupInfo'] as bool? ?? false,
        addMembers: json['addMembers'] as bool? ?? false,
        inviteViaLink: json['inviteViaLink'] as bool? ?? true,
        approvalRequired: json['approvalRequired'] as bool? ?? false,
      );
}

/// A locally created group.
@immutable
class Group {
  const Group({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarPath,
    this.avatarColor,
    this.members = const <GroupMember>[],
    this.permissions = const GroupPermissions(),
    this.createdAt,
    this.inviteCode = '',
    this.communityId,
    this.disappearingSeconds = 0,
  });

  final String id;
  final String name;
  final String description;
  final String? avatarPath;
  final int? avatarColor;
  final List<GroupMember> members;
  final GroupPermissions permissions;
  final DateTime? createdAt;
  final String inviteCode;
  final String? communityId;
  final int disappearingSeconds;

  int get memberCount => members.length;

  List<GroupMember> get admins =>
      members.where((m) => m.isAdmin).toList(growable: false);

  String get initials {
    final String n = name.trim();
    if (n.isEmpty) return 'G';
    final List<String> parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Group copyWith({
    String? id,
    String? name,
    String? description,
    String? avatarPath,
    int? avatarColor,
    List<GroupMember>? members,
    GroupPermissions? permissions,
    DateTime? createdAt,
    String? inviteCode,
    String? communityId,
    int? disappearingSeconds,
  }) =>
      Group(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        avatarPath: avatarPath ?? this.avatarPath,
        avatarColor: avatarColor ?? this.avatarColor,
        members: members ?? this.members,
        permissions: permissions ?? this.permissions,
        createdAt: createdAt ?? this.createdAt,
        inviteCode: inviteCode ?? this.inviteCode,
        communityId: communityId ?? this.communityId,
        disappearingSeconds: disappearingSeconds ?? this.disappearingSeconds,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'avatarPath': avatarPath,
        'avatarColor': avatarColor,
        'members': members.map((m) => m.toJson()).toList(),
        'permissions': permissions.toJson(),
        'createdAt': createdAt?.toIso8601String(),
        'inviteCode': inviteCode,
        'communityId': communityId,
        'disappearingSeconds': disappearingSeconds,
      };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        avatarPath: json['avatarPath'] as String?,
        avatarColor: (json['avatarColor'] as num?)?.toInt(),
        members: (json['members'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        permissions: json['permissions'] == null
            ? const GroupPermissions()
            : GroupPermissions.fromJson(
                json['permissions'] as Map<String, dynamic>),
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
        inviteCode: json['inviteCode'] as String? ?? '',
        communityId: json['communityId'] as String?,
        disappearingSeconds: (json['disappearingSeconds'] as num?)?.toInt() ?? 0,
      );
}

/// A container of related groups with a shared announcement channel.
@immutable
class Community {
  const Community({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarPath,
    this.avatarColor,
    this.groupIds = const <String>[],
    this.memberIds = const <String>[],
    this.announcementChatId,
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String? avatarPath;
  final int? avatarColor;
  final List<String> groupIds;
  final List<String> memberIds;
  final String? announcementChatId;
  final DateTime? createdAt;

  String get initials {
    final String n = name.trim();
    if (n.isEmpty) return 'C';
    return n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
  }

  Community copyWith({
    String? id,
    String? name,
    String? description,
    String? avatarPath,
    int? avatarColor,
    List<String>? groupIds,
    List<String>? memberIds,
    String? announcementChatId,
    DateTime? createdAt,
  }) =>
      Community(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        avatarPath: avatarPath ?? this.avatarPath,
        avatarColor: avatarColor ?? this.avatarColor,
        groupIds: groupIds ?? this.groupIds,
        memberIds: memberIds ?? this.memberIds,
        announcementChatId: announcementChatId ?? this.announcementChatId,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'avatarPath': avatarPath,
        'avatarColor': avatarColor,
        'groupIds': groupIds,
        'memberIds': memberIds,
        'announcementChatId': announcementChatId,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory Community.fromJson(Map<String, dynamic> json) => Community(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        avatarPath: json['avatarPath'] as String?,
        avatarColor: (json['avatarColor'] as num?)?.toInt(),
        groupIds:
            (json['groupIds'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
        memberIds:
            (json['memberIds'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
        announcementChatId: json['announcementChatId'] as String?,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
      );
}

/// Where a channel stands in the monetization approval flow.
enum MonetizationStatus { none, pending, approved, rejected }

/// A one-to-many broadcast feed the user can follow.
@immutable
class Channel {
  const Channel({
    required this.id,
    required this.name,
    this.username = '',
    this.ownerId = '',
    this.description = '',
    this.avatarPath,
    this.avatarUrl,
    this.avatarColor,
    this.coverUrl,
    this.category = 'Other',
    this.isPublic = true,
    this.isFollowing = false,
    this.isMuted = false,
    this.isPremiumOnly = false,
    this.unreadCount = 0,
    this.followerCount = 0,
    this.totalReactions = 0,
    this.inviteCode = '',
    this.secretKeyHash = '',
    this.monetizationStatus = MonetizationStatus.none,
    this.createdAt,
    this.lastUpdateAt,
    this.lastMessage = '',
    this.lastMessageAt,
    this.lastReadAt,
  });

  final String id;
  final String name;

  /// The unique `@handle` that identifies the channel in search, without the
  /// leading `@`. Empty for channels created before usernames were required.
  final String username;

  /// The uid that created the channel. Only the owner may post or edit.
  final String ownerId;

  final String description;
  final String? avatarPath;

  /// Public URL of the channel photo, so a follower on another device can see
  /// it. The local [avatarPath] is preferred when the file is present here.
  final String? avatarUrl;

  final int? avatarColor;

  /// Public URL of the wide cover image shown behind the channel header.
  final String? coverUrl;

  final String category;
  final bool isPublic;
  final bool isFollowing;
  final bool isMuted;

  /// True when only premium members may read this channel's posts.
  ///
  /// Separate from [isPrivate]: private means "invite by secret key", premium
  /// means "open to anyone who has bought premium". A channel can be either,
  /// but not both — a key holder who is not premium would otherwise be let in by
  /// one rule and kept out by the other.
  final bool isPremiumOnly;

  final int unreadCount;
  final int followerCount;

  /// Lifetime reaction count, used with [followerCount] to gate monetization.
  final int totalReactions;

  final String inviteCode;

  /// SHA-256 of the secret key, hex encoded. Never the key itself — the plain
  /// key is shown to the owner once at creation and never stored.
  final String secretKeyHash;

  final MonetizationStatus monetizationStatus;
  final DateTime? createdAt;
  final DateTime? lastUpdateAt;

  /// Preview text for the merged chat list — the truncated body of the newest
  /// post, or a type label such as "Photo" when the post has no text.
  ///
  /// Denormalised onto the channel document by [ChannelFirestoreService.addPost]
  /// so the chat list can sort and preview every channel from one query,
  /// without a per-channel read of its posts subcollection. Empty for a channel
  /// that has never been posted to.
  final String lastMessage;

  /// When [lastMessage] was published. Null for a channel with no posts.
  final DateTime? lastMessageAt;

  /// When this user last read the channel, used to compute unread posts.
  ///
  /// Per-user, but stored on the channel document (`lastReadAtBy.<uid>`) for
  /// the same reason as [lastMessage]: the chat list must sort channels it only
  /// has the channel documents for.
  final DateTime? lastReadAt;

  /// Posts published since this user last read the channel.
  ///
  /// Derived from [lastMessageAt] versus [lastReadAt] rather than counted, so
  /// it needs no extra read. It answers "has anything happened since I looked",
  /// which is what the chat list badge means; the exact count would need the
  /// posts subcollection, which the list deliberately does not open.
  bool get hasUnread => lastMessageAt != null &&
      (lastReadAt == null || lastMessageAt!.isAfter(lastReadAt!));

  /// The timestamp the merged chat list sorts on: newest post, else last edit.
  DateTime get activityAt => lastMessageAt ?? lastUpdateAt ?? createdAt ?? DateTime(1970);

  /// A private channel requires the secret key (or an approved join request) to
  /// read.
  bool get isPrivate => !isPublic;

  bool get hasSecretKey => secretKeyHash.isNotEmpty;

  /// The `@handle` as displayed, or empty when the channel has none yet.
  String get handle => username.isEmpty ? '' : '@$username';

  bool get isMonetized => monetizationStatus == MonetizationStatus.approved;

  /// The directive's threshold for applying: 500 followers **and** 10 000
  /// reactions within the last 60 days.
  static const int monetizationFollowerThreshold = 500;
  static const int monetizationReactionThreshold = 10000;

  /// Whether the channel is currently eligible to apply for monetization.
  bool get isEligibleForMonetization =>
      followerCount >= monetizationFollowerThreshold &&
      totalReactions >= monetizationReactionThreshold &&
      monetizationStatus == MonetizationStatus.none;

  String get initials {
    final String n = name.trim();
    if (n.isEmpty) return 'C';
    return n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
  }

  Channel copyWith({
    String? id,
    String? name,
    String? username,
    String? ownerId,
    String? description,
    String? avatarPath,
    String? avatarUrl,
    int? avatarColor,
    String? coverUrl,
    String? category,
    bool? isPublic,
    bool? isFollowing,
    bool? isMuted,
    bool? isPremiumOnly,
    int? unreadCount,
    int? followerCount,
    int? totalReactions,
    String? inviteCode,
    String? secretKeyHash,
    MonetizationStatus? monetizationStatus,
    DateTime? createdAt,
    DateTime? lastUpdateAt,
    String? lastMessage,
    DateTime? lastMessageAt,
    DateTime? lastReadAt,
  }) =>
      Channel(
        id: id ?? this.id,
        name: name ?? this.name,
        username: username ?? this.username,
        ownerId: ownerId ?? this.ownerId,
        description: description ?? this.description,
        avatarPath: avatarPath ?? this.avatarPath,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        avatarColor: avatarColor ?? this.avatarColor,
        coverUrl: coverUrl ?? this.coverUrl,
        category: category ?? this.category,
        isPublic: isPublic ?? this.isPublic,
        isFollowing: isFollowing ?? this.isFollowing,
        isMuted: isMuted ?? this.isMuted,
        isPremiumOnly: isPremiumOnly ?? this.isPremiumOnly,
        unreadCount: unreadCount ?? this.unreadCount,
        followerCount: followerCount ?? this.followerCount,
        totalReactions: totalReactions ?? this.totalReactions,
        inviteCode: inviteCode ?? this.inviteCode,
        secretKeyHash: secretKeyHash ?? this.secretKeyHash,
        monetizationStatus: monetizationStatus ?? this.monetizationStatus,
        createdAt: createdAt ?? this.createdAt,
        lastUpdateAt: lastUpdateAt ?? this.lastUpdateAt,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        lastReadAt: lastReadAt ?? this.lastReadAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'username': username,
        'ownerId': ownerId,
        'description': description,
        'avatarPath': avatarPath,
        'avatarUrl': avatarUrl,
        'avatarColor': avatarColor,
        'coverUrl': coverUrl,
        'category': category,
        'isPublic': isPublic,
        'isFollowing': isFollowing,
        'isMuted': isMuted,
        'isPremiumOnly': isPremiumOnly,
        'unreadCount': unreadCount,
        'followerCount': followerCount,
        'totalReactions': totalReactions,
        'inviteCode': inviteCode,
        'secretKeyHash': secretKeyHash,
        'monetizationStatus': monetizationStatus.name,
        'monetization': <String, dynamic>{'status': monetizationStatus.name},
        'createdAt': createdAt?.toIso8601String(),
        'lastUpdateAt': lastUpdateAt?.toIso8601String(),
        'lastMessage': lastMessage,
        'lastMessageAt': lastMessageAt?.toIso8601String(),
        'lastReadAt': lastReadAt?.toIso8601String(),
      };

  /// Reads the application status, preferring the nested `monetization` map.
  ///
  /// Firestore carries both spellings: `monetization.status`, which is what the
  /// directive specifies, and the flat `monetizationStatus`, which is the
  /// queryable mirror the admin screen filters on. Documents written before the
  /// nested map existed only have the flat field, so it is still honoured.
  static MonetizationStatus monetizationStatusFromJson(
    Map<String, dynamic> json,
  ) {
    final Map<String, dynamic>? nested =
        json['monetization'] is Map<String, dynamic>
            ? json['monetization'] as Map<String, dynamic>
            : null;
    final Object? raw = nested?['status'] ?? json['monetizationStatus'];
    return MonetizationStatus.values.firstWhere(
      (MonetizationStatus s) => s.name == raw,
      orElse: () => MonetizationStatus.none,
    );
  }

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        username: json['username'] as String? ?? '',
        ownerId: json['ownerId'] as String? ?? '',
        description: json['description'] as String? ?? '',
        avatarPath: json['avatarPath'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        avatarColor: (json['avatarColor'] as num?)?.toInt(),
        coverUrl: json['coverUrl'] as String?,
        category: json['category'] as String? ?? 'Other',
        isPublic: json['isPublic'] as bool? ?? true,
        isFollowing: json['isFollowing'] as bool? ?? false,
        isMuted: json['isMuted'] as bool? ?? false,
        isPremiumOnly: json['isPremiumOnly'] as bool? ?? false,
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
        totalReactions: (json['totalReactions'] as num?)?.toInt() ?? 0,
        inviteCode: json['inviteCode'] as String? ?? '',
        secretKeyHash: json['secretKeyHash'] as String? ?? '',
        monetizationStatus: monetizationStatusFromJson(json),
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
        lastUpdateAt: json['lastUpdateAt'] == null
            ? null
            : DateTime.tryParse(json['lastUpdateAt'] as String),
        lastMessage: json['lastMessage'] as String? ?? '',
        lastMessageAt: json['lastMessageAt'] == null
            ? null
            : DateTime.tryParse(json['lastMessageAt'] as String),
        lastReadAt: json['lastReadAt'] == null
            ? null
            : DateTime.tryParse(json['lastReadAt'] as String),
      );
}
