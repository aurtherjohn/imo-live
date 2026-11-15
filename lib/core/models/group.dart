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
