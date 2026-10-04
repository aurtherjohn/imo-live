import 'package:flutter/foundation.dart';

/// A person the local user can message.
@immutable
class Contact {
  const Contact({
    required this.id,
    required this.firstName,
    this.lastName = '',
    this.username = '',
    this.phone = '',
    this.countryCode = '',
    this.countryIso = '',
    this.bio = '',
    this.avatarPath,
    this.avatarUrl = '',
    this.avatarColor,
    this.isFavorite = false,
    this.isBlocked = false,
    this.isOnline = false,
    this.lastSeen,
    this.isTyping = false,
    this.isSyncedToDevice = false,
    this.isSelf = false,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final String phone;
  final String countryCode;
  final String countryIso;
  final String bio;
  final String? avatarPath;

  /// The peer's **remote** avatar — `users/{uid}.avatarUrl` in Firestore, i.e.
  /// the R2 public URL written when they picked a photo.
  ///
  /// [avatarPath] is a path on *this* device and can therefore only ever be
  /// non-null for the signed-in user's own picture. Before this field existed a
  /// peer's [Contact] carried no image at all, so every list that rendered
  /// `imagePath: contact.avatarPath` fell through to initials for everyone but
  /// yourself — which is exactly the reported "other users never see the
  /// picture". Read this for anyone who is not you; prefer [avatarPath] first
  /// when both are present (see [IAvatar]).
  final String avatarUrl;

  final int? avatarColor;
  final bool isFavorite;
  final bool isBlocked;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isTyping;
  final bool isSyncedToDevice;
  final bool isSelf;

  String get fullName => <String>[firstName, lastName]
      .where((s) => s.trim().isNotEmpty)
      .join(' ')
      .trim();

  /// Initials used when no avatar image is available.
  String get initials {
    final String f = firstName.trim();
    final String l = lastName.trim();
    if (f.isEmpty && l.isEmpty) return '?';
    if (l.isEmpty) return f.substring(0, f.length >= 2 ? 2 : 1).toUpperCase();
    return '${f[0]}${l[0]}'.toUpperCase();
  }

  String get sortedKey => fullName.isEmpty ? '#' : fullName.toUpperCase();

  String get aboutText => bio.isEmpty ? 'Hey there! I am using Imo LIVE.' : bio;

  /// Human-readable presence string used in the chat header.
  String get presenceLabel {
    if (isTyping) return 'typing...';
    if (isOnline) return 'online';
    if (lastSeen == null) return 'offline';
    final Duration diff = DateTime.now().difference(lastSeen!);
    if (diff.inMinutes < 1) return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return 'last seen today at ${lastSeen!.hour.toString().padLeft(2, '0')}:${lastSeen!.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'last seen yesterday';
    if (diff.inDays < 7) return 'last seen ${diff.inDays} days ago';
    return 'last seen recently';
  }

  Contact copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? username,
    String? phone,
    String? countryCode,
    String? countryIso,
    String? bio,
    String? avatarPath,
    String? avatarUrl,
    int? avatarColor,
    bool? isFavorite,
    bool? isBlocked,
    bool? isOnline,
    DateTime? lastSeen,
    bool? isTyping,
    bool? isSyncedToDevice,
    bool? isSelf,
  }) {
    return Contact(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      countryCode: countryCode ?? this.countryCode,
      countryIso: countryIso ?? this.countryIso,
      bio: bio ?? this.bio,
      avatarPath: avatarPath ?? this.avatarPath,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarColor: avatarColor ?? this.avatarColor,
      isFavorite: isFavorite ?? this.isFavorite,
      isBlocked: isBlocked ?? this.isBlocked,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isTyping: isTyping ?? this.isTyping,
      isSyncedToDevice: isSyncedToDevice ?? this.isSyncedToDevice,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'username': username,
        'phone': phone,
        'countryCode': countryCode,
        'countryIso': countryIso,
        'bio': bio,
        'avatarPath': avatarPath,
        'avatarUrl': avatarUrl,
        'avatarColor': avatarColor,
        'isFavorite': isFavorite,
        'isBlocked': isBlocked,
        'isOnline': isOnline,
        'lastSeen': lastSeen?.toIso8601String(),
        'isTyping': isTyping,
        'isSyncedToDevice': isSyncedToDevice,
        'isSelf': isSelf,
      };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'] as String? ?? '',
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        username: json['username'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        countryCode: json['countryCode'] as String? ?? '',
        countryIso: json['countryIso'] as String? ?? '',
        bio: json['bio'] as String? ?? '',
        avatarPath: json['avatarPath'] as String?,
        avatarUrl: json['avatarUrl'] as String? ?? '',
        avatarColor: (json['avatarColor'] as num?)?.toInt(),
        isFavorite: json['isFavorite'] as bool? ?? false,
        isBlocked: json['isBlocked'] as bool? ?? false,
        isOnline: json['isOnline'] as bool? ?? false,
        lastSeen: json['lastSeen'] == null
            ? null
            : DateTime.tryParse(json['lastSeen'] as String),
        isTyping: json['isTyping'] as bool? ?? false,
        isSyncedToDevice: json['isSyncedToDevice'] as bool? ?? false,
        isSelf: json['isSelf'] as bool? ?? false,
      );
}
