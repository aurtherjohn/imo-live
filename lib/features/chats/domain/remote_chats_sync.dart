import 'dart:async';

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
/// Every remote chat document is mirrored into Hive, and the emitted list
/// always comes from the local store — which is what makes a conversation
/// created on another device appear here without a refresh, *and* what lets a
/// local mutation reach the UI at once. See [_liveChats] for why that second
/// half matters.
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
///
/// ### Why this is a controller and not an `async*` generator
///
/// The generator form had exactly one source of change: the Firestore snapshot.
/// That is the bug behind "deleting a chat does not delete it". A Firestore
/// `chats` query does not change when *this* device removes a row — no snapshot
/// arrives — so the stream never re-emitted and the deleted chat stayed on
/// screen until something unrelated happened to change the collection. Waiting
/// for the server to confirm a purely local act is exactly the wrong way round.
///
/// The list is therefore driven by the **local store's own change stream**, and
/// the Firestore mirror runs alongside it as a background writer. A delete, a
/// pin or a mark-read is visible on the next tick, and the mirror can only ever
/// write rows the user has not removed — `ChatRepository.save` refuses a chat
/// that is in the deleted-chat index.
Stream<List<Chat>> _liveChats({
  required String uid,
  required ChatRepository repo,
  required FirestoreChatService firestore,
  required ContactRepository contacts,
  required RemoteContactService directory,
}) {
  late final StreamController<List<Chat>> out;
  StreamSubscription<List<Chat>>? localSub;
  StreamSubscription<List<RemoteChat>>? remoteSub;

  Future<void> start() async {
    // The cache paints the first frame, before any subscription work.
    try {
      if (!out.isClosed) out.add(await repo.getAll());
    } on Object catch (error) {
      debugPrint('chat list read failed: $error');
    }
    if (out.isClosed) return;

    localSub = repo.watchAll().listen(
          (List<Chat> list) {
            if (!out.isClosed) out.add(list);
          },
          onError: (Object error) =>
              debugPrint('local chat stream failed: $error'),
        );

    if (uid.isEmpty) return;

    // Detached from the emitted list on purpose: the mirror's only job is to
    // write into the local store, and the store's own stream carries the result
    // to the UI. An error here must not tear down the list.
    remoteSub = firestore.watchChats(uid).listen(
          (List<RemoteChat> remote) async {
            for (final RemoteChat chat in remote) {
              await mirrorRemoteChat(
                chat,
                uid: uid,
                repo: repo,
                contacts: contacts,
                directory: directory,
              );
            }
          },
          onError: (Object error) => debugPrint('chat mirror failed: $error'),
        );
  }

  out = StreamController<List<Chat>>(
    onListen: () => unawaited(start()),
    onCancel: () async {
      await localSub?.cancel();
      await remoteSub?.cancel();
      localSub = null;
      remoteSub = null;
    },
  );
  return out.stream;
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
///
/// A chat the user has deleted never reaches the store: `repo.save` refuses it.
/// See `LocalChatRepository`.
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
  String? avatarUrl;
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
      avatarUrl = peer.avatarUrl.isEmpty ? null : peer.avatarUrl;
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
      avatarUrl: avatarUrl ?? base.avatarUrl,
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
/// person has never been saved on this device — or when the row we have carries
/// no remote avatar yet.
///
/// The avatar is the one directory field that cannot be resolved from anything
/// already on the device: [Contact.avatarPath] is a path *here*, so for anyone
/// but yourself it is always null, and a chat list that renders it shows
/// initials for the whole world. So a peer whose local row predates the
/// `avatarUrl` field (or who set a picture afterwards) is re-read from the
/// directory and the row is upgraded in place.
Future<Contact?> _resolvePeer(
  String uid, {
  required ContactRepository contacts,
  required RemoteContactService directory,
}) async {
  final Contact? local = await contacts.findById(uid);
  if (local != null &&
      (local.avatarUrl.isNotEmpty || _avatarlessPeers.contains(uid))) {
    return local;
  }

  final LookupResult result = await directory.findByUid(uid);
  final RemoteProfile? profile = result.profile;
  if (profile == null) return local;

  // Nothing to add, and a local row already exists: remember the miss so the
  // next snapshot does not re-read this person, and keep the row untouched.
  if (profile.avatarUrl.isEmpty && local != null) {
    _avatarlessPeers.add(uid);
    return local;
  }

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
    // Local-only presentation state must survive the upgrade.
    avatarPath: local?.avatarPath,
    avatarUrl: profile.avatarUrl,
    isFavorite: local?.isFavorite ?? false,
    isBlocked: local?.isBlocked ?? false,
    isOnline: profile.isOnline,
    lastSeen: profile.lastSeen,
    isSyncedToDevice: local?.isSyncedToDevice ?? false,
  );

  try {
    return await contacts.save(cached);
  } on Object catch (error) {
    debugPrint('Caching directory profile $uid failed: $error');
    return cached;
  }
}

/// Peers already consulted in this process whose directory profile carries no
/// avatar.
///
/// Without this, [mirrorRemoteChat] would issue one Firestore read per peer per
/// snapshot for every contact who simply has not set a picture. A restart
/// clears it, so a picture set later is picked up on the next launch — and the
/// contact-info screen watches `users/{uid}` live in the meantime.
final Set<String> _avatarlessPeers = <String>{};
