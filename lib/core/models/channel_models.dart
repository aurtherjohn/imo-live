import 'package:flutter/foundation.dart';

import '../utils/firestore_values.dart';
import 'group.dart';

/// The reaction set a channel post accepts.
///
/// The wire value is the enum name, so the set can grow without breaking
/// documents written by an older build — an unknown name degrades to [like].
enum ChannelReactionKind { like, love, wow, sad, angry }

/// The emoji rendered for each reaction kind.
String channelReactionEmoji(ChannelReactionKind kind) => switch (kind) {
      ChannelReactionKind.like => '👍',
      ChannelReactionKind.love => '❤️',
      ChannelReactionKind.wow => '😮',
      ChannelReactionKind.sad => '😢',
      ChannelReactionKind.angry => '😠',
    };

/// A single post published by a channel owner.
///
/// Followers may react but never post — the composer is only reachable by the
/// channel owner, and the reaction writes go to a per-user subcollection so two
/// devices cannot clobber each other's counts.
@immutable
class ChannelPost {
  const ChannelPost({
    required this.id,
    required this.channelId,
    required this.authorId,
    this.authorName = '',
    this.text = '',
    this.mediaUrl = '',
    this.mediaType = 'text',
    this.mediaName = '',
    this.reactions = const <ChannelReactionKind, int>{},
    this.viewCount = 0,
    this.myReaction,
    this.createdAt,
  });

  final String id;
  final String channelId;
  final String authorId;
  final String authorName;
  final String text;

  /// Public URL of the attached media, or empty for a text post.
  final String mediaUrl;

  /// `text`, `image`, `video`, or `file`.
  final String mediaType;

  /// Original filename, for a `file` post. Empty for every other type.
  final String mediaName;

  /// Per-kind tally, denormalised onto the post for cheap rendering.
  final Map<ChannelReactionKind, int> reactions;

  /// How many times the post has been rendered to a follower — the "reach"
  /// series plotted in the analytics dashboard.
  final int viewCount;

  /// The local user's own reaction, if any.
  final ChannelReactionKind? myReaction;

  final DateTime? createdAt;

  bool get hasMedia => mediaUrl.isNotEmpty;

  bool get isImage => mediaType == 'image' && hasMedia;

  bool get isVideo => mediaType == 'video' && hasMedia;

  bool get isFile => mediaType == 'file' && hasMedia;

  int get totalReactions =>
      reactions.values.fold<int>(0, (int sum, int n) => sum + n);

  int countOf(ChannelReactionKind kind) => reactions[kind] ?? 0;

  ChannelPost copyWith({
    String? id,
    String? channelId,
    String? authorId,
    String? authorName,
    String? text,
    String? mediaUrl,
    String? mediaType,
    String? mediaName,
    Map<ChannelReactionKind, int>? reactions,
    int? viewCount,
    ChannelReactionKind? myReaction,
    bool clearMyReaction = false,
    DateTime? createdAt,
  }) =>
      ChannelPost(
        id: id ?? this.id,
        channelId: channelId ?? this.channelId,
        authorId: authorId ?? this.authorId,
        authorName: authorName ?? this.authorName,
        text: text ?? this.text,
        mediaUrl: mediaUrl ?? this.mediaUrl,
        mediaType: mediaType ?? this.mediaType,
        mediaName: mediaName ?? this.mediaName,
        reactions: reactions ?? this.reactions,
        viewCount: viewCount ?? this.viewCount,
        myReaction: clearMyReaction ? null : (myReaction ?? this.myReaction),
        createdAt: createdAt ?? this.createdAt,
      );

  /// Builds a post from a `channels/{id}/posts/{pid}` document.
  ///
  /// [myReaction] is resolved separately from the reactions subcollection,
  /// because a query cannot join the two. [createdAt] is passed in already
  /// converted, so this model stays free of the cloud_firestore import.
  static ChannelPost? fromDoc(
    String id,
    Map<String, dynamic> data, {
    ChannelReactionKind? myReaction,
    DateTime? createdAt,
  }) {
    final String channelId = data['channelId'] as String? ?? '';
    if (channelId.isEmpty) return null;

    final Map<String, dynamic> raw =
        (data['reactions'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<ChannelReactionKind, int> tally = <ChannelReactionKind, int>{};
    for (final ChannelReactionKind kind in ChannelReactionKind.values) {
      final int n = asInt(raw[kind.name]);
      if (n > 0) tally[kind] = n;
    }

    return ChannelPost(
      id: id,
      channelId: channelId,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      text: data['text'] as String? ?? '',
      mediaUrl: data['mediaUrl'] as String? ?? '',
      mediaType: data['mediaType'] as String? ?? 'text',
      mediaName: data['mediaName'] as String? ?? '',
      reactions: tally,
      viewCount: asInt(data['viewCount']),
      myReaction: myReaction,
      createdAt: createdAt ?? _date(data['createdAt']),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// A pending request to join a private channel.
@immutable
class ChannelJoinRequest {
  const ChannelJoinRequest({
    required this.uid,
    this.name = '',
    this.username = '',
    this.avatarUrl = '',
    this.message = '',
    this.createdAt,
  });

  final String uid;
  final String name;
  final String username;
  final String avatarUrl;
  final String message;
  final DateTime? createdAt;

  String get displayName => name.isNotEmpty ? name : (username.isNotEmpty ? '@$username' : uid);
}

/// One day of channel analytics.
///
/// Stored at `channels/{id}/analytics/{yyyy-MM-dd}` so the 28-day view is a
/// single ordered range read rather than an aggregation over every post.
@immutable
class ChannelDayStats {
  const ChannelDayStats({
    required this.day,
    this.followersGained = 0,
    this.followersLost = 0,
    this.reach = 0,
    this.reactions = 0,
    this.posts = 0,
  });

  /// `yyyy-MM-dd`, the document id, so it sorts lexicographically = chronologically.
  final String day;
  final int followersGained;
  final int followersLost;
  final int reach;
  final int reactions;
  final int posts;

  int get netFollowers => followersGained - followersLost;

  /// The day as a local [DateTime] at midnight, for chart axes.
  DateTime get date => DateTime.tryParse(day) ?? DateTime(1970);

  static ChannelDayStats fromDoc(String day, Map<String, dynamic> data) =>
      ChannelDayStats(
        day: day,
        followersGained: asInt(data['followersGained']),
        followersLost: asInt(data['followersLost']),
        reach: asInt(data['reach']),
        reactions: asInt(data['reactions']),
        posts: asInt(data['posts']),
      );
}

/// Convenience so a channel doc read from Firestore can be typed without the
/// caller importing the model file twice.
typedef ChannelDoc = Channel;
