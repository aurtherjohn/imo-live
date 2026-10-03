import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../app/theme/app_color_scheme.dart';

import '../../app/theme/app_tokens.dart';
import '../models/contact.dart';
import '../utils/l10n.dart';

/// A circular avatar with initials fallback and presence indicator.
///
/// Shows [imagePath] (a local file) when set, then [imageUrl] (a remote one),
/// otherwise a deterministic colour derived from [name] so the same person
/// always renders identically.
class IAvatar extends StatelessWidget {
  const IAvatar({
    super.key,
    this.name = '',
    this.imagePath,
    this.imageUrl,
    this.size = AppSizes.avatarMd,
    this.isOnline = false,
    this.showPresence = false,
    this.colorSeed,
    this.icon,
    this.onTap,
    this.badgeCount,
    this.isMuted = false,
    this.isGroup = false,
    this.ringColor,
  });

  final String name;
  final String? imagePath;

  /// A remote avatar (Firebase Storage download URL, or a provider picture).
  /// Used when [imagePath] is null, and shown with a disk cache so scrolling a
  /// contact list does not refetch the same picture.
  final String? imageUrl;
  final double size;
  final bool isOnline;
  final bool showPresence;
  final int? colorSeed;
  final IconData? icon;
  final VoidCallback? onTap;
  final int? badgeCount;
  final bool isMuted;
  final bool isGroup;
  final Color? ringColor;

  /// Stable palette used for generated avatars.
  static const List<Color> palette = <Color>[
    Color(0xFFE0577B),
    Color(0xFF7B61FF),
    Color(0xFF2BB3A3),
    Color(0xFFE08A3C),
    Color(0xFF4A8FE7),
    Color(0xFFB45FCB),
    Color(0xFF3FA45B),
    Color(0xFFD65C5C),
    Color(0xFF6C7BD1),
    Color(0xFFC08A3E),
  ];

  static Color colorFor(String seed, [int? override]) {
    if (override != null) return Color(override);
    if (seed.isEmpty) return palette.first;
    int hash = 0;
    for (final int unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  static String initialsFor(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final List<String> parts = trimmed
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final String only = parts.first;
      return only.substring(0, only.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = colorFor(name, colorSeed);
    final double dotSize = (size * 0.28).clamp(10.0, 18.0);
    final bool hasImage = imagePath != null && imagePath!.isNotEmpty;
    final bool hasRemoteImage = imageUrl != null && imageUrl!.isNotEmpty;

    // A locally stored file always wins: it is what the user just picked, so it
    // is both instant and guaranteed current. The network image is the fallback
    // for everyone else's avatar.
    final Widget inner = hasImage
        ? ClipOval(
            child: Image.file(
              File(imagePath!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext ctx, Object err, StackTrace? st) =>
                  hasRemoteImage
                      ? _networkTile(bg, dotSize)
                      : _initialTile(bg, dotSize),
            ),
          )
        : hasRemoteImage
            ? _networkTile(bg, dotSize)
            : _initialTile(bg, dotSize);

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ringColor == null
            ? null
            : Border.all(color: ringColor!, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );

    if (showPresence) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: isOnline ? context.c.online : AppColors.offline,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: dotSize * 0.18,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (isGroup) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.groups_rounded,
                size: dotSize * 0.6,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    if (badgeCount != null && badgeCount! > 0) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          avatar,
          Positioned(
            right: -4,
            top: -4,
            child: UnreadBadge(count: badgeCount!, isMuted: isMuted),
          ),
        ],
      );
    }

    if (onTap == null) return avatar;
    return GestureDetector(onTap: onTap, child: avatar);
  }

  /// A remote avatar, cached on disk.
  ///
  /// Falls back to the generated initials while the download is in flight and
  /// if it fails — an avatar is decoration, so it must never leave a hole or
  /// throw into the list it is being built for.
  Widget _networkTile(Color bg, double dotSize) => ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 180),
          placeholder: (BuildContext ctx, String url) => _initialTile(bg, dotSize),
          errorWidget: (BuildContext ctx, String url, Object err) =>
              _initialTile(bg, dotSize),
        ),
      );

  Widget _initialTile(Color bg, double dotSize) => Container(        width: size,
        height: size,
        color: bg,
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, size: size * 0.5, color: Colors.white)
            : Text(
                initialsFor(name),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
      );
}

/// Small numeric badge for unread counts.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({
    super.key,
    required this.count,
    this.isMuted = false,
    this.size = 20,
  });

  final int count;
  final bool isMuted;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final String label = count > 99 ? '99+' : '$count';
    final bool wide = label.length > 2;
    return Semantics(
      label: context.l10n.unreadMessagesCount(count),
      child: Container(
        constraints: BoxConstraints(minWidth: size, minHeight: size),
        padding: EdgeInsets.symmetric(horizontal: wide ? 5 : 0, vertical: 2),
        decoration: BoxDecoration(
          color: isMuted ? AppColors.offline : AppColors.accent,
          borderRadius: BorderRadius.circular(size),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.55,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Avatar helpers for contacts.
extension ContactAvatarX on Contact {
  String get avatarSeed => fullName.isEmpty ? initials : fullName;
}
