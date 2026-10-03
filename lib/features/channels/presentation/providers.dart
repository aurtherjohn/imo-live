import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/channel_models.dart';
import '../../../core/models/group.dart';
import '../../../core/services/channel_service.dart';

/// The signed-in uid, or an empty string when signed out / Firebase is absent.
///
/// Kept local to the channel feature so it does not depend on the chats
/// feature's provider graph.
final Provider<String> channelViewerUidProvider = Provider<String>((Ref ref) {
  try {
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  } on Object {
    return '';
  }
});

/// The live channel document from Firestore.
///
/// Emits null when the document does not exist — which is how the screen
/// distinguishes "not found" from "still loading".
final StreamProviderFamily<Channel?, String> channelDocProvider =
    StreamProvider.family<Channel?, String>(
  (Ref ref, String channelId) =>
      ref.watch(channelFirestoreProvider).watchChannel(channelId),
);

/// A channel's posts, newest first.
final StreamProviderFamily<List<ChannelPost>, String> channelPostsProvider =
    StreamProvider.family<List<ChannelPost>, String>(
  (Ref ref, String channelId) =>
      ref.watch(channelFirestoreProvider).watchPosts(channelId),
);

/// The viewer's own reactions across all channels, keyed by post id.
final StreamProvider<Map<String, ChannelReactionKind>>
    myChannelReactionsProvider =
    StreamProvider<Map<String, ChannelReactionKind>>(
  (Ref ref) => ref
      .watch(channelFirestoreProvider)
      .watchMyReactions(ref.watch(channelViewerUidProvider)),
);

/// The last 28 days of analytics buckets.
final StreamProviderFamily<List<ChannelDayStats>, String>
    channelAnalyticsProvider =
    StreamProvider.family<List<ChannelDayStats>, String>(
  (Ref ref, String channelId) =>
      ref.watch(channelFirestoreProvider).watchAnalytics(channelId),
);

/// Pending join requests for a private channel.
final StreamProviderFamily<List<ChannelJoinRequest>, String>
    channelJoinRequestsProvider =
    StreamProvider.family<List<ChannelJoinRequest>, String>(
  (Ref ref, String channelId) =>
      ref.watch(channelFirestoreProvider).watchJoinRequests(channelId),
);

/// Whether the viewer may read a private channel.
final StreamProviderFamily<bool, String> channelMembershipProvider =
    StreamProvider.family<bool, String>(
  (Ref ref, String channelId) => ref
      .watch(channelFirestoreProvider)
      .watchMembership(channelId, ref.watch(channelViewerUidProvider)),
);

/// The channel's follower uids.
final StreamProviderFamily<List<String>, String> channelFollowerIdsProvider =
    StreamProvider.family<List<String>, String>(
  (Ref ref, String channelId) =>
      ref.watch(channelFirestoreProvider).watchFollowerIds(channelId),
);

/// Whether the signed-in user may review monetization applications.
///
/// Read from `users/{uid}.isAdmin`, which is not writable from the client — it
/// is set out of band, so a tampered build cannot promote itself. Defaults to
/// false, so a missing document or an offline device simply hides the admin
/// screen rather than showing an empty one.
final StreamProvider<bool> isAppAdminProvider = StreamProvider<bool>((Ref ref) {
  final String uid = ref.watch(channelViewerUidProvider);
  if (uid.isEmpty) return Stream<bool>.value(false);
  // ⚠️ A `try`/`catch` around this is useless: `snapshots()` returns
  // synchronously, so a *listener* error — a denied read, a dropped
  // connection — never reaches it. That mattered here because a Firestore
  // snapshot stream **closes when it errors**, and every consumer reads this
  // as `.valueOrNull ?? false`: the admin entry points would just quietly
  // disappear with nothing in the log. Handling the error explicitly keeps the
  // degradation to `false` *and* makes it visible.
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map(
        (DocumentSnapshot<Map<String, dynamic>> doc) =>
            doc.data()?['isAdmin'] as bool? ?? false,
      )
      .handleError((Object error) {
        debugPrint('isAppAdminProvider($uid) failed: $error');
      });
});

/// Channels waiting on a monetization decision, for the admin screen.
final StreamProvider<List<Channel>> pendingMonetizationProvider =
    StreamProvider<List<Channel>>(
  (Ref ref) => ref.watch(channelFirestoreProvider).watchPendingMonetization(),
);
