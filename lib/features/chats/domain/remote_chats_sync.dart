import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/services/firestore_chat_service.dart';
import '../../../core/services/remote_contact_service.dart';
import '../../auth/presentation/auth_providers.dart';
import '../presentation/providers.dart';
import 'repositories.dart';

/// The raw Firestore `chats` stream for the signed-in user.
///
/// `chats` documents carry a `participants` array, and the query filters on
/// `arrayContains: uid`, so this is exactly "every conversation I take part in"
/// — including the ones started on another device.
///
/// A plain `Provider<Stream<...>>` rather than a `StreamProvider` on purpose:
/// it hands the screen a real [Stream] to pass to a `StreamBuilder`, and the
/// provider only rebuilds (and so re-subscribes) when the signed-in user
/// changes or the caller invalidates it.
final Provider<Stream<List<RemoteChat>>> firestoreChatsStreamProvider =
    Provider<Stream<List<RemoteChat>>>((Ref ref) {
  final String uid = ref.watch(currentUidProvider);
  if (uid.isEmpty) {
    return Stream<List<RemoteChat>>.value(const <RemoteChat>[]);
  }
  return ref.watch(firestoreChatServiceProvider).watchChats(uid);
});

/// The chat list the UI renders: Firestore as the transport, the local store as
/// the cache.
///
/// Every remote chat document is mirrored into Hive before the list is
/// republished, which is what makes a conversation created on another device
/// appear here without a refresh. Local-only rows (a chat opened but not yet
/// written to) are kept, because [ChatRepository.getAll] is the source of the
/// emitted list rather than the Firestore snapshot.
///
/// If Firebase is unavailable the stream still yields the local rows, so the
/// tab degrades to the offline cache instead of erroring.
final Provider<Stream<List<Chat>>> liveChatsStreamProvider =
    Provider<Stream<List<Chat>>>((Ref ref) {
  final String uid = ref.watch(currentUidProvider);
  final ChatRepository repo = ref.read(chatRepositoryProvider);
  final FirestoreChatService firestore = ref.read(firestoreChatServiceProvider);
  final ContactRepository contacts = ref.read(contactRepositoryProvider);
  final RemoteContactService directory = ref.read(remoteContactServiceProvider);

  return _liveChats(
    uid: uid,
    repo: repo,
    firestore: firestore,
    contacts: contacts,
    directory: directory,
  );
});

/// Builds the mirroring stream. Kept as a free function so the generator is
/// testable without a `ProviderContainer`.
Stream<List<Chat>> _liveChats({
  required String uid,
  required ChatRepository repo,
  required FirestoreChatService firestore,
  required ContactRepository contacts,
  required RemoteContactService directory,
}) async* {
  // Local rows first so the list paints immediately, before the first
  // Firestore snapshot arrives.
  yield await repo.getAll();

  if (uid.isEmpty) return;

  await for (final List<RemoteChat> remote in firestore.watchChats(uid)) {
    for (final RemoteChat chat in remote) {
      await mirrorRemoteChat(
        chat,
        uid: uid,
        repo: repo,
        contacts: contacts,
        directory: directory,
      );
    }
    yield await repo.getAll();
  }
}

/// Writes one Firestore chat document into the local store.
///
/// Local-only presentation state (pin, mute, archive, draft, wallpaper) is
/// preserved: the remote document has no opinion about it, and overwriting it
/// on every snapshot would silently undo the user's own choices.
///
/// The title of a 1:1 chat is not stored in Firestore — a `chats` document only
/// knows participant uids — so it is resolved from the address book, falling
/// back to the directory profile and caching it locally so the next launch has
/// the name without a network round-trip.
@visibleForTesting
Future<void> mirrorRemoteChat(
  RemoteChat remote, {
  required String uid,
  required ChatRepository repo,
  required ContactRepository contacts,
  required RemoteContactService directory,
}) async {
  if (remote.id.isEmpty) return;

  final String peerId = remote.participants
          .where((String id) => id != uid)
          .firstOrNull ??
      '';

  String title = remote.groupName;
  String? avatarPath;
  int? avatarColor;
  bool isOnline = false;
  DateTime? lastSeen;

  if (!remote.isGroup && peerId.isNotEmpty) {
    final Contact? peer = await _resolvePeer(
      peerId,
      contacts: contacts,
      directory: directory,
    );
    if (peer != null) {
      title = peer.fullName;
      avatarPath = peer.avatarPath;
      avatarColor = peer.avatarColor;
      isOnline = peer.isOnline;
      lastSeen = peer.lastSeen;
    }
  }

  final Chat? existing = await repo.findById(remote.id);
  final Chat base = existing ??
      Chat(
        id: remote.id,
        title: title,
        lastMessage: remote.lastMessage,
        lastTimestamp: remote.lastMessageTime ?? DateTime.now(),
      );

  await repo.save(
    base.copyWith(
      // Never blank a title we already resolved — a snapshot that arrives
      // before the profile lookup must not wipe the row's name.
      title: title.isNotEmpty ? title : base.title,
      avatarPath: avatarPath ?? base.avatarPath,
      avatarColor: avatarColor ?? base.avatarColor,
      isOnline: isOnline,
      lastSeen: lastSeen ?? base.lastSeen,
      isGroup: remote.isGroup,
      memberIds: remote.participants,
      memberCount: remote.participants.length,
      unreadCount: remote.unreadCount[uid] ?? base.unreadCount,
      lastMessage: remote.lastMessage.isEmpty
          ? base.lastMessage
          : remote.lastMessage,
      lastTimestamp: remote.lastMessageTime ?? base.lastTimestamp,
      lastMessageIsOutgoing: remote.lastMessageSenderId == uid && uid.isNotEmpty,
    ),
  );
}

/// Finds the local contact behind [uid], caching the directory profile when the
/// person has never been saved on this device.
Future<Contact?> _resolvePeer(
  String uid, {
  required ContactRepository contacts,
  required RemoteContactService directory,
}) async {
  final Contact? local = await contacts.findById(uid);
  if (local != null) return local;

  final LookupResult result = await directory.findByUid(uid);
  final RemoteProfile? profile = result.profile;
  if (profile == null) return null;

  final List<String> parts = profile.name
      .trim()
      .split(RegExp(r'\s+'))
      .where((String p) => p.isNotEmpty)
      .toList();

  final Contact cached = Contact(
    id: profile.uid,
    firstName: parts.isEmpty
        ? (profile.username.isNotEmpty ? profile.username : profile.phone)
        : parts.first,
    lastName: parts.length > 1 ? parts.skip(1).join(' ') : '',
    username: profile.username,
    phone: profile.phone,
    bio: profile.bio,
    isOnline: profile.isOnline,
    lastSeen: profile.lastSeen,
  );

  try {
    return await contacts.save(cached);
  } on Object catch (error) {
    debugPrint('Caching directory profile $uid failed: $error');
    return cached;
  }
}
