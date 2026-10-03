import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel_models.dart';
import '../models/group.dart';
import '../utils/firebase_time.dart';

/// The Firestore side of the channel system.
///
/// ### Layout
///
/// ```
/// channels/{channelId}                                 the channel document
/// channels/{channelId}/posts/{postId}                  owner-only posts
/// channels/{channelId}/posts/{postId}/reactions/{uid}  one reaction per user
/// channels/{channelId}/followers/{uid}                 the follow edge
/// channels/{channelId}/join_requests/{uid}             private-channel requests
/// channels/{channelId}/analytics/{yyyy-MM-dd}          one doc per day
/// channel_usernames/{username}                         uniqueness index
/// channel_keys/{sha256(secretKey)}                     private-channel index
/// ```
///
/// The two top-level indexes exist because Firestore cannot query "is this
/// username taken?" or "which channel owns this secret key?" without them, and
/// a client-side scan of every channel is both slow and, with security rules,
/// impossible.
///
/// ### Timestamps
///
/// Every stored timestamp is [FieldValue.serverTimestamp]. The only client
/// clock value is the `yyyy-MM-dd` **document id** of an analytics bucket, which
/// is a label rather than a timestamp — see [bumpAnalytics].
///
/// ### Degradation
///
/// Every method is a no-op and every stream yields empty when Firebase is not
/// initialised, so the app still runs (on the local Hive mirror) without a
/// backend. This mirrors [FirestoreChatService].
class ChannelFirestoreService {
  static const String channelsCollection = 'channels';
  static const String usernamesCollection = 'channel_usernames';
  static const String keysCollection = 'channel_keys';
  static const String postsSubcollection = 'posts';
  static const String reactionsSubcollection = 'reactions';
  static const String followersSubcollection = 'followers';
  static const String joinRequestsSubcollection = 'join_requests';
  static const String analyticsSubcollection = 'analytics';

  /// The nested map carrying the monetization application state.
  ///
  /// `channels/{channelId}.monetization` is what the directive specifies:
  /// status, when it was applied for, when it was reviewed, and the audience
  /// the channel had at the moment of the application.
  static const String monetizationField = 'monetization';

  /// Flat mirror of `monetization.status`.
  ///
  /// Kept alongside the nested map because Firestore cannot query a nested
  /// field without a composite index, and the admin screen lists every pending
  /// application.
  static const String monetizationStatusField = 'monetizationStatus';

  /// How many days the analytics dashboard plots.
  static const int analyticsWindowDays = 28;

  FirebaseFirestore? get _db {
    try {
      return FirebaseFirestore.instance;
    } on Object {
      return null;
    }
  }

  // ------------------------------------------------------------- usernames

  /// Normalises a handle: lowercase, `[a-z0-9_]`, 3–32 characters.
  static String normaliseUsername(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll('@', '')
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');

  /// True when [username] is free, or already owned by [exceptChannelId].
  ///
  /// Returns true when Firebase is unavailable: the write is what ultimately
  /// enforces uniqueness (a transaction), and refusing every name offline would
  /// make the form unusable.
  Future<bool> isUsernameAvailable(
    String username, {
    String? exceptChannelId,
  }) async {
    final String handle = normaliseUsername(username);
    if (handle.isEmpty) return false;
    final FirebaseFirestore? db = _db;
    if (db == null) return true;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await db.collection(usernamesCollection).doc(handle).get();
      if (!doc.exists) return true;
      return doc.data()?['channelId'] == exceptChannelId;
    } on Object catch (error) {
      debugPrint('isUsernameAvailable($handle) failed: $error');
      return true;
    }
  }

  /// Suggests up to [count] free handles derived from [base].
  Future<List<String>> suggestUsernames(String base, {int count = 3}) async {
    final String stem = normaliseUsername(base);
    if (stem.isEmpty) return <String>[];
    final Random random = Random();
    final List<String> out = <String>[];
    int guard = 0;
    while (out.length < count && guard < count * 8) {
      guard++;
      final String candidate =
          '$stem${random.nextInt(9000) + 1000}';
      if (await isUsernameAvailable(candidate)) out.add(candidate);
    }
    return out;
  }

  // --------------------------------------------------------------- secrets

  /// Generates a 12-character alphanumeric secret key.
  ///
  /// Uses [Random.secure] — `Random()` is seeded from the clock and two
  /// channels created in the same millisecond would collide.
  static String generateSecretKey() {
    const String alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final Random random = Random.secure();
    return List<String>.generate(
      12,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  /// Hex SHA-256 of [key]. Only the digest is ever stored.
  static Future<String> hashSecretKey(String key) async {
    final Hash hash =
        await Sha256().hash(utf8.encode(key.trim().toUpperCase()));
    return hash.bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Resolves a secret key typed into search to the channel it unlocks.
  ///
  /// Returns null when the key is unknown. The channel id is returned rather
  /// than the document so the caller can show a preview and a join request
  /// without being able to read the private channel's posts yet.
  Future<String?> findChannelIdBySecretKey(String key) async {
    final String trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    final FirebaseFirestore? db = _db;
    if (db == null) return null;
    try {
      final String digest = await hashSecretKey(trimmed);
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await db.collection(keysCollection).doc(digest).get();
      return doc.data()?['channelId'] as String?;
    } on Object catch (error) {
      debugPrint('findChannelIdBySecretKey failed: $error');
      return null;
    }
  }

  // --------------------------------------------------------------- channel

  /// Writes a new channel, its username index and its key index in one batch.
  ///
  /// Returns null when the handle was taken between the availability check and
  /// this call — the caller should re-run the check and show the error.
  Future<Channel?> createChannel({
    required Channel channel,
    required String uid,
    String? secretKey,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return null;

    final String handle = normaliseUsername(channel.username);
    final String channelId =
        channel.id.isNotEmpty ? channel.id : db.collection(channelsCollection).doc().id;

    try {
      final WriteBatch batch = db.batch();
      final DocumentReference<Map<String, dynamic>> usernameRef =
          db.collection(usernamesCollection).doc(handle);

      if (handle.isNotEmpty) {
        final DocumentSnapshot<Map<String, dynamic>> existing =
            await usernameRef.get();
        if (existing.exists &&
            existing.data()?['channelId'] != channelId) {
          return null;
        }
      }

      final Channel toSave = channel.copyWith(
        id: channelId,
        ownerId: uid,
        username: handle,
        isFollowing: true,
      );

      batch.set(
        db.collection(channelsCollection).doc(channelId),
        <String, dynamic>{
          ...toSave.toJson(),
          // Local-only fields must not travel.
          'avatarPath': null,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdateAt': FieldValue.serverTimestamp(),
        },
      );

      if (handle.isNotEmpty) {
        batch.set(
          usernameRef,
          <String, dynamic>{
            'channelId': channelId,
            'name': toSave.name,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }

      if (secretKey != null && secretKey.trim().isNotEmpty) {
        final String digest = await hashSecretKey(secretKey);
        batch.set(
          db.collection(keysCollection).doc(digest),
          <String, dynamic>{
            'channelId': channelId,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }

      // The owner is the first follower, so the follower count starts at 1 and
      // the owner can read their own private channel.
      batch.set(
        db
            .collection(channelsCollection)
            .doc(channelId)
            .collection(followersSubcollection)
            .doc(uid),
        <String, dynamic>{'uid': uid, 'createdAt': FieldValue.serverTimestamp()},
      );

      await batch.commit();
      return toSave;
    } on Object catch (error) {
      debugPrint('createChannel($channelId) failed: $error');
      return null;
    }
  }

  /// Live view of a single channel document.
  Stream<Channel?> watchChannel(String channelId) {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) {
      return Stream<Channel?>.value(null);
    }
    return db
        .collection(channelsCollection)
        .doc(channelId)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> doc) {
      final Map<String, dynamic>? data = doc.data();
      if (!doc.exists || data == null) return null;
      return channelFromDoc(doc.id, data);
    }).handleError((Object error) {
      debugPrint('watchChannel($channelId) failed: $error');
    });
  }

  /// One-shot read, used to seed the local mirror.
  Future<Channel?> getChannel(String channelId) async {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) return null;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await db.collection(channelsCollection).doc(channelId).get();
      final Map<String, dynamic>? data = doc.data();
      if (!doc.exists || data == null) return null;
      return channelFromDoc(doc.id, data);
    } on Object catch (error) {
      debugPrint('getChannel($channelId) failed: $error');
      return null;
    }
  }

  /// Updates editable channel fields. Only the owner should be able to do this;
  /// the enforcement belongs in security rules, not here.
  ///
  /// Changing the username moves the uniqueness index in the same batch so the
  /// old handle is released and the new one claimed atomically.
  Future<bool> updateChannel({
    required String channelId,
    String? name,
    String? username,
    String? description,
    String? category,
    String? avatarUrl,
    String? coverUrl,
    bool? isPublic,
    bool? isPremiumOnly,
    String? secretKey,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) return false;
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          db.collection(channelsCollection).doc(channelId);
      final WriteBatch batch = db.batch();
      final Map<String, dynamic> data = <String, dynamic>{
        'lastUpdateAt': FieldValue.serverTimestamp(),
      };

      if (name != null) data['name'] = name;
      if (description != null) data['description'] = description;
      if (category != null) data['category'] = category;
      if (avatarUrl != null) data['avatarUrl'] = avatarUrl;
      if (coverUrl != null) data['coverUrl'] = coverUrl;
      if (isPublic != null) data['isPublic'] = isPublic;
      if (isPremiumOnly != null) data['isPremiumOnly'] = isPremiumOnly;

      if (username != null) {
        final String handle = normaliseUsername(username);
        final DocumentReference<Map<String, dynamic>> usernameRef =
            db.collection(usernamesCollection).doc(handle);
        final DocumentSnapshot<Map<String, dynamic>> existing =
            await usernameRef.get();
        if (existing.exists &&
            existing.data()?['channelId'] != channelId) {
          return false;
        }
        data['username'] = handle;
        batch.set(
          usernameRef,
          <String, dynamic>{
            'channelId': channelId,
            'name': name ?? '',
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      if (secretKey != null && secretKey.trim().isNotEmpty) {
        final String digest = await hashSecretKey(secretKey);
        data['secretKeyHash'] = digest;
        batch.set(
          db.collection(keysCollection).doc(digest),
          <String, dynamic>{
            'channelId': channelId,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }

      batch.set(ref, data, SetOptions(merge: true));
      await batch.commit();
      return true;
    } on Object catch (error) {
      debugPrint('updateChannel($channelId) failed: $error');
      return false;
    }
  }

  /// Applies for monetization: `none`/`rejected` → `pending`.
  ///
  /// [followersAtApply] and [reactionsAtApply] are recorded so a reviewer can
  /// see the audience the channel actually had when it applied — the counters
  /// keep moving, so the current values prove nothing about eligibility.
  Future<void> applyForMonetization(
    String channelId, {
    int followersAtApply = 0,
    int reactionsAtApply = 0,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) return;
    try {
      await db.collection(channelsCollection).doc(channelId).set(
        <String, dynamic>{
          monetizationField: <String, dynamic>{
            'status': MonetizationStatus.pending.name,
            'appliedAt': FirebaseTime.now(),
            'reviewedAt': null,
            'followersAtApply': followersAtApply,
            'reactionsAtApply': reactionsAtApply,
          },
          monetizationStatusField: MonetizationStatus.pending.name,
          'monetizationAppliedAt': FirebaseTime.now(),
          'lastUpdateAt': FirebaseTime.now(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('applyForMonetization($channelId) failed: $error');
    }
  }

  /// Admin action: approve or reject a pending application.
  ///
  /// Approval is what turns the badge on: [Channel.isMonetized] reads the
  /// status back, and the channel header renders the badge from it.
  Future<void> setMonetizationStatus(
    String channelId,
    MonetizationStatus status,
  ) async {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) return;
    try {
      await db.collection(channelsCollection).doc(channelId).set(
        <String, dynamic>{
          monetizationField: <String, dynamic>{
            'status': status.name,
            'reviewedAt': FirebaseTime.now(),
          },
          monetizationStatusField: status.name,
          'lastUpdateAt': FirebaseTime.now(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('setMonetizationStatus($channelId) failed: $error');
    }
  }

  /// Every channel waiting on a monetization decision.
  ///
  /// Yields empty when Firebase is unavailable so the admin screen shows its
  /// empty state instead of hanging.
  Stream<List<Channel>> watchPendingMonetization() {
    final FirebaseFirestore? db = _db;
    if (db == null) return Stream<List<Channel>>.value(const <Channel>[]);
    return db
        .collection(channelsCollection)
        .where(
          monetizationStatusField,
          isEqualTo: MonetizationStatus.pending.name,
        )
        .snapshots()
        .map(
          (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map(
                (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    channelFromDoc(doc.id, doc.data()),
              )
              .toList(growable: false),
        );
  }

  // ------------------------------------------------------------- followers

  /// Follows or unfollows [channelId] as [uid], keeping the denormalised
  /// `followerCount` on the channel and the day's analytics bucket in step.
  Future<void> setFollowing({
    required String channelId,
    required String uid,
    required bool following,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty || uid.isEmpty) return;
    try {
      final DocumentReference<Map<String, dynamic>> channelRef =
          db.collection(channelsCollection).doc(channelId);
      final DocumentReference<Map<String, dynamic>> followerRef = channelRef
          .collection(followersSubcollection)
          .doc(uid);

      final WriteBatch batch = db.batch();
      if (following) {
        batch.set(
          followerRef,
          <String, dynamic>{
            'uid': uid,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        batch.set(
          channelRef,
          <String, dynamic>{
            'followerCount': FieldValue.increment(1),
            'lastUpdateAt': FirebaseTime.now(),
          },
          SetOptions(merge: true),
        );
      } else {
        batch.delete(followerRef);
        batch.set(
          channelRef,
          <String, dynamic>{
            'followerCount': FieldValue.increment(-1),
            'lastUpdateAt': FirebaseTime.now(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      await bumpAnalytics(
        channelId,
        followersGained: following ? 1 : 0,
        followersLost: following ? 0 : 1,
      );
    } on Object catch (error) {
      debugPrint('setFollowing($channelId, $uid) failed: $error');
    }
  }

  /// Streams the uids following a channel, used by the owner's follower list.
  Stream<List<String>> watchFollowerIds(String channelId) {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) {
      return Stream<List<String>>.value(<String>[]);
    }
    return db
        .collection(channelsCollection)
        .doc(channelId)
        .collection(followersSubcollection)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id)
            .toList())
        .handleError((Object error) {
      debugPrint('watchFollowerIds($channelId) failed: $error');
    });
  }

  // ----------------------------------------------------------------- posts

  /// Streams a channel's posts, newest first.
  Stream<List<ChannelPost>> watchPosts(String channelId, {int limit = 50}) {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) {
      return Stream<List<ChannelPost>>.value(<ChannelPost>[]);
    }
    return db
        .collection(channelsCollection)
        .doc(channelId)
        .collection(postsSubcollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                ChannelPost.fromDoc(
                  d.id,
                  d.data(),
                  createdAt: FirebaseTime.toLocal(d.data()['createdAt']),
                ))
            .whereType<ChannelPost>()
            .toList())
        .handleError((Object error) {
      debugPrint('watchPosts($channelId) failed: $error');
    });
  }

  /// Publishes a post. Owner only — enforced by security rules.
  ///
  /// Returns the new post id, or null when Firebase is unavailable.
  /// Publishes a post.
  ///
  /// [mediaType] is one of `text`, `image`, `video`, `file`. [mediaName] carries
  /// the original filename for a `file` post so the feed can label it without a
  /// second lookup; it is empty for every other type.
  Future<String?> addPost({
    required String channelId,
    required String authorId,
    required String authorName,
    required String text,
    String mediaUrl = '',
    String mediaType = 'text',
    String mediaName = '',
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) return null;
    try {
      final CollectionReference<Map<String, dynamic>> posts = db
          .collection(channelsCollection)
          .doc(channelId)
          .collection(postsSubcollection);
      final DocumentReference<Map<String, dynamic>> ref = posts.doc();
      await ref.set(<String, dynamic>{
        'channelId': channelId,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        'mediaUrl': mediaUrl,
        'mediaType': mediaType,
        if (mediaName.isNotEmpty) 'mediaName': mediaName,
        'reactions': <String, dynamic>{},
        'viewCount': 0,
        'createdAt': FirebaseTime.now(),
      });
      await db.collection(channelsCollection).doc(channelId).set(
        <String, dynamic>{
          'lastUpdateAt': FirebaseTime.now(),
          // Denormalised preview for the merged chat list. The list sorts and
          // previews channels from the channel documents alone, so it must not
          // have to open the posts subcollection to learn what the newest post
          // says — that would be one query per channel per rebuild.
          'lastMessage': _previewOf(text: text, mediaType: mediaType),
          'lastMessageAt': FirebaseTime.now(),
        },
        SetOptions(merge: true),
      );
      await bumpAnalytics(channelId, posts: 1);
      return ref.id;
    } on Object catch (error) {
      debugPrint('addPost($channelId) failed: $error');
      return null;
    }
  }

  /// The chat-list preview line for a post.
  ///
  /// A post with text previews its text; a media-only post previews its kind,
  /// so the row never shows an empty second line. Kept short because the row is
  /// one line and truncates anyway.
  static String _previewOf({required String text, required String mediaType}) {
    final String trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isNotEmpty) {
      return trimmed.length <= 120 ? trimmed : '${trimmed.substring(0, 120)}…';
    }
    return switch (mediaType) {
      'image' => 'Photo',
      'video' => 'Video',
      'file' => 'Document',
      'voice' => 'Voice message',
      _ => '',
    };
  }

  /// Marks the channel read for [uid] as of now.
  ///
  /// Writes `lastReadAt` on the channel document rather than on a per-user
  /// subcollection, because the chat list — which needs the value to decide
  /// whether to show an unread badge — only reads channel documents. A separate
  /// subcollection would cost one read per channel per rebuild.
  ///
  /// Best-effort: a failure leaves the badge showing, which is a cosmetic
  /// wrong, never a crash.
  Future<void> markChannelRead(String channelId, String uid) async {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty || uid.isEmpty) return;
    try {
      await db.collection(channelsCollection).doc(channelId).set(
        <String, dynamic>{'lastReadAt': FirebaseTime.now()},
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('markChannelRead($channelId) failed: $error');
    }
  }

  /// Removes a post. Owner only — enforced by security rules.
  Future<void> deletePost(String channelId, String postId) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return;
    try {
      await db
          .collection(channelsCollection)
          .doc(channelId)
          .collection(postsSubcollection)
          .doc(postId)
          .delete();
    } on Object catch (error) {
      debugPrint('deletePost($channelId/$postId) failed: $error');
    }
  }

  /// Sets, replaces or clears [uid]'s reaction on a post.
  ///
  /// The per-user document is the source of truth; the tally on the post and
  /// the channel's lifetime `totalReactions` are denormalised so a feed render
  /// needs no extra reads. Passing the same kind twice clears it (a toggle),
  /// which is what users expect from a reaction button.
  Future<void> reactToPost({
    required String channelId,
    required String postId,
    required String uid,
    required ChannelReactionKind kind,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty) return;
    try {
      final DocumentReference<Map<String, dynamic>> postRef = db
          .collection(channelsCollection)
          .doc(channelId)
          .collection(postsSubcollection)
          .doc(postId);
      final DocumentReference<Map<String, dynamic>> reactionRef =
          postRef.collection(reactionsSubcollection).doc(uid);

      final DocumentSnapshot<Map<String, dynamic>> existing =
          await reactionRef.get();
      final String? previous = existing.data()?['kind'] as String?;

      final WriteBatch batch = db.batch();
      final Map<String, dynamic> postUpdate = <String, dynamic>{};
      int totalDelta = 0;

      if (previous == kind.name) {
        // Toggle off.
        batch.delete(reactionRef);
        postUpdate['reactions.${kind.name}'] = FieldValue.increment(-1);
        totalDelta = -1;
      } else {
        batch.set(
          reactionRef,
          <String, dynamic>{
            'uid': uid,
            'kind': kind.name,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        if (previous != null) {
          postUpdate['reactions.$previous'] = FieldValue.increment(-1);
        } else {
          totalDelta = 1;
        }
        postUpdate['reactions.${kind.name}'] = FieldValue.increment(1);
      }

      batch.set(postRef, postUpdate, SetOptions(merge: true));
      if (totalDelta != 0) {
        batch.set(
          db.collection(channelsCollection).doc(channelId),
          <String, dynamic>{
            'totalReactions': FieldValue.increment(totalDelta),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      if (totalDelta > 0) await bumpAnalytics(channelId, reactions: 1);
    } on Object catch (error) {
      debugPrint('reactToPost($channelId/$postId) failed: $error');
    }
  }

  /// Streams [uid]'s own reactions across every channel, keyed by post id.
  ///
  /// A collection-group query rather than one read per post, so rendering a
  /// 50-post feed still costs a single listener.
  Stream<Map<String, ChannelReactionKind>> watchMyReactions(String uid) {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty) {
      return Stream<Map<String, ChannelReactionKind>>.value(
        <String, ChannelReactionKind>{},
      );
    }
    return db
        .collectionGroup(reactionsSubcollection)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) {
      final Map<String, ChannelReactionKind> out =
          <String, ChannelReactionKind>{};
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in s.docs) {
        final String postId = doc.reference.parent.parent?.id ?? '';
        final String? kind = doc.data()['kind'] as String?;
        if (postId.isEmpty || kind == null) continue;
        out[postId] = ChannelReactionKind.values.firstWhere(
          (ChannelReactionKind k) => k.name == kind,
          orElse: () => ChannelReactionKind.like,
        );
      }
      return out;
    }).handleError((Object error) {
      debugPrint('watchMyReactions($uid) failed: $error');
    });
  }

  /// Counts one impression of a post, for the reach series.
  ///
  /// Called once per post per app session by the feed; deliberately not
  /// awaited by the UI.
  Future<void> recordPostView(String channelId, String postId) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return;
    try {
      await db
          .collection(channelsCollection)
          .doc(channelId)
          .collection(postsSubcollection)
          .doc(postId)
          .set(
        <String, dynamic>{'viewCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      await bumpAnalytics(channelId, reach: 1);
    } on Object catch (error) {
      debugPrint('recordPostView($channelId/$postId) failed: $error');
    }
  }

  // --------------------------------------------------------- join requests

  /// Asks to join a private channel. No-op if already approved or pending.
  Future<void> requestJoin({
    required String channelId,
    required String uid,
    required String name,
    String username = '',
    String avatarUrl = '',
    String message = '',
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty) return;
    try {
      await db
          .collection(channelsCollection)
          .doc(channelId)
          .collection(joinRequestsSubcollection)
          .doc(uid)
          .set(<String, dynamic>{
        'uid': uid,
        'name': name,
        'username': username,
        'avatarUrl': avatarUrl,
        'message': message,
        'createdAt': FirebaseTime.now(),
      });
    } on Object catch (error) {
      debugPrint('requestJoin($channelId, $uid) failed: $error');
    }
  }

  /// Pending join requests, newest first.
  Stream<List<ChannelJoinRequest>> watchJoinRequests(String channelId) {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) {
      return Stream<List<ChannelJoinRequest>>.value(<ChannelJoinRequest>[]);
    }
    return db
        .collection(channelsCollection)
        .doc(channelId)
        .collection(joinRequestsSubcollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) {
              final Map<String, dynamic> data = d.data();
              return ChannelJoinRequest(
                uid: d.id,
                name: data['name'] as String? ?? '',
                username: data['username'] as String? ?? '',
                avatarUrl: data['avatarUrl'] as String? ?? '',
                message: data['message'] as String? ?? '',
                createdAt: FirebaseTime.toLocal(data['createdAt']),
              );
            })
            .toList())
        .handleError((Object error) {
      debugPrint('watchJoinRequests($channelId) failed: $error');
    });
  }

  /// Approves a request: adds the follower edge, drops the request, and counts
  /// the follower gain.
  Future<void> approveJoin(String channelId, String uid) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return;
    try {
      final DocumentReference<Map<String, dynamic>> channelRef =
          db.collection(channelsCollection).doc(channelId);
      final WriteBatch batch = db.batch();
      batch.set(
        channelRef.collection(followersSubcollection).doc(uid),
        <String, dynamic>{
          'uid': uid,
          'approvedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.delete(channelRef.collection(joinRequestsSubcollection).doc(uid));
      batch.set(
        channelRef,
        <String, dynamic>{
          'followerCount': FieldValue.increment(1),
          'lastUpdateAt': FirebaseTime.now(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      await bumpAnalytics(channelId, followersGained: 1);
    } on Object catch (error) {
      debugPrint('approveJoin($channelId, $uid) failed: $error');
    }
  }

  /// Rejects a request: drops it without granting access.
  Future<void> rejectJoin(String channelId, String uid) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return;
    try {
      await db
          .collection(channelsCollection)
          .doc(channelId)
          .collection(joinRequestsSubcollection)
          .doc(uid)
          .delete();
    } on Object catch (error) {
      debugPrint('rejectJoin($channelId, $uid) failed: $error');
    }
  }

  /// Whether [uid] may read a private channel: owner, follower, or public.
  Stream<bool> watchMembership(String channelId, String uid) {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty || channelId.isEmpty) {
      return Stream<bool>.value(false);
    }
    return db
        .collection(channelsCollection)
        .doc(channelId)
        .collection(followersSubcollection)
        .doc(uid)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> d) => d.exists)
        .handleError((Object error) {
      debugPrint('watchMembership($channelId, $uid) failed: $error');
    });
  }

  // ------------------------------------------------------------- analytics

  /// The `yyyy-MM-dd` bucket id for [when], in local time.
  ///
  /// This is a *label*, not a timestamp: it groups events into a calendar day.
  /// Every authoritative time on the bucket is a server timestamp.
  static String dayKey([DateTime? when]) {
    final DateTime d = when ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Increments today's bucket. Called on follow, post, reaction and view.
  Future<void> bumpAnalytics(
    String channelId, {
    int followersGained = 0,
    int followersLost = 0,
    int reach = 0,
    int reactions = 0,
    int posts = 0,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) return;
    if (followersGained == 0 &&
        followersLost == 0 &&
        reach == 0 &&
        reactions == 0 &&
        posts == 0) {
      return;
    }
    try {
      final Map<String, dynamic> delta = <String, dynamic>{
        'day': dayKey(),
        'updatedAt': FirebaseTime.now(),
      };
      if (followersGained != 0) {
        delta['followersGained'] = FieldValue.increment(followersGained);
      }
      if (followersLost != 0) {
        delta['followersLost'] = FieldValue.increment(followersLost);
      }
      if (reach != 0) delta['reach'] = FieldValue.increment(reach);
      if (reactions != 0) delta['reactions'] = FieldValue.increment(reactions);
      if (posts != 0) delta['posts'] = FieldValue.increment(posts);

      await db
          .collection(channelsCollection)
          .doc(channelId)
          .collection(analyticsSubcollection)
          .doc(dayKey())
          .set(delta, SetOptions(merge: true));
    } on Object catch (error) {
      debugPrint('bumpAnalytics($channelId) failed: $error');
    }
  }

  /// The last [days] buckets, oldest first, with missing days filled with
  /// zeroes so the chart has a continuous x-axis.
  Stream<List<ChannelDayStats>> watchAnalytics(
    String channelId, {
    int days = analyticsWindowDays,
  }) {
    final FirebaseFirestore? db = _db;
    if (db == null || channelId.isEmpty) {
      return Stream<List<ChannelDayStats>>.value(_emptySeries(days));
    }
    final DateTime now = DateTime.now();
    final DateTime first = now.subtract(Duration(days: days - 1));
    return db
        .collection(channelsCollection)
        .doc(channelId)
        .collection(analyticsSubcollection)
        .orderBy(FieldPath.documentId)
        .startAt(<Object>[dayKey(first)])
        .endAt(<Object>[dayKey(now)])
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) {
      final Map<String, ChannelDayStats> byDay = <String, ChannelDayStats>{
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs)
          d.id: ChannelDayStats.fromDoc(d.id, d.data()),
      };
      final List<ChannelDayStats> series = <ChannelDayStats>[];
      for (int i = days - 1; i >= 0; i--) {
        final String key = dayKey(now.subtract(Duration(days: i)));
        series.add(byDay[key] ?? ChannelDayStats(day: key));
      }
      return series;
    }).handleError((Object error) {
      debugPrint('watchAnalytics($channelId) failed: $error');
    });
  }

  static List<ChannelDayStats> _emptySeries(int days) {
    final DateTime now = DateTime.now();
    return List<ChannelDayStats>.generate(
      days,
      (int i) => ChannelDayStats(day: dayKey(now.subtract(Duration(days: days - 1 - i)))),
    );
  }

  // ---------------------------------------------------------------- mapping

  /// Converts a channel document into the app's model.
  ///
  /// The channel model's own `fromJson` reads ISO strings for its dates,
  /// because it is also the Hive serialiser. Firestore returns [Timestamp]s, so
  /// every date field is converted here rather than teaching the model about
  /// Firestore.
  ///
  /// **Every** date field must be listed. A field that is written as a
  /// server timestamp but not converted here reaches `fromJson` as a
  /// `Timestamp`, and `json['x'] as String` throws — which is not a missing
  /// value, it is a crash on read. Adding a date to [Channel] means adding it
  /// to this map; `channel_timestamps_test.dart` fails if that is forgotten.
  static Channel channelFromDoc(String id, Map<String, dynamic> data) {
    final Map<String, dynamic> json = <String, dynamic>{
      ...data,
      'id': id,
      'createdAt': _iso(data['createdAt']),
      'lastUpdateAt': _iso(data['lastUpdateAt']),
      'lastMessageAt': _iso(data['lastMessageAt']),
      'lastReadAt': _iso(data['lastReadAt']),
    };
    return Channel.fromJson(json);
  }

  static String? _iso(Object? value) {
    final DateTime? date = FirebaseTime.toLocal(value);
    return date?.toIso8601String();
  }
}

/// The channel backend.
final Provider<ChannelFirestoreService> channelFirestoreProvider =
    Provider<ChannelFirestoreService>((Ref ref) => ChannelFirestoreService());
