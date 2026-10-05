import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/message.dart';
import '../../../features/chats/domain/repositories.dart';
import 'local_database.dart';

/// Hive-backed implementation of [ChatRepository].
///
/// ### Why there is a deleted-chat index
///
/// Removing a chat from the list was not durable. The chat list is fed by
/// `liveChatsStreamProvider`, which mirrors *every* Firestore `chats` document
/// into this store on *every* snapshot — see `remote_chats_sync.dart`. A local
/// delete removed the row, and the very next snapshot wrote it straight back,
/// because nothing on this side remembered that the user had removed it. The
/// visible symptom was exactly the reported one: the chat disappears, then
/// reappears seconds later, and it is still there after a restart.
///
/// The index is the fix, and it is deliberately the *same* mechanism the
/// message store already uses for "delete for me" (`deleted_ids_<chatId>`) —
/// two shapes of the same problem should not have two different solutions.
///
/// It lives in [AppConstants.boxMessages] rather than `boxChats` on purpose:
/// the message store's own index is there, and `clearUserData()` clears every
/// box on sign-out, so the two are always wiped together.
///
/// The key is scoped by uid (`deleted_chats_<uid>`) so an index written by one
/// account can never filter another account's list, even if the box outlives a
/// session for any reason.
class LocalChatRepository implements ChatRepository {
  LocalChatRepository({LocalDatabase? db, String Function()? uid})
      : _db = db ?? LocalDatabase.instance,
        _uid = uid ?? _anonymousUid;

  static String _anonymousUid() => '';

  final LocalDatabase _db;

  /// Resolves the signed-in uid at call time.
  ///
  /// Injected rather than read from `FirebaseAuth` directly: this is a local
  /// store and must not depend on the auth SDK, and a value captured at
  /// construction would be the empty string for the whole first session — see
  /// the note on `callUidProvider`.
  final String Function() _uid;

  final StreamController<List<Chat>> _controller =
      StreamController<List<Chat>>.broadcast();

  static const String _key = 'all_chats';

  List<Chat> _cache = <Chat>[];
  bool _loaded = false;

  /// The ids removed for this user, cached per key.
  Set<String>? _deletedCache;
  String _deletedCacheKey = '';

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _cache = _db.readList<Chat>(
      AppConstants.boxChats,
      _key,
      Chat.fromJson,
    );
    _loaded = true;
  }

  /// Key holding the ids this user removed from the list.
  String get _deletedKey => 'deleted_chats_${_uid()}';

  /// The ids this user has deleted, loaded from the index once per key.
  ///
  /// A different uid re-reads: the cache is keyed, not merely filled, so
  /// switching accounts inside one process cannot serve the previous user's
  /// removals to the next one.
  Set<String> _deletedIds() {
    final String key = _deletedKey;
    if (_deletedCache != null && _deletedCacheKey == key) {
      return _deletedCache!;
    }

    final Set<String> ids = <String>{};
    final String? raw = _db.readString(AppConstants.boxMessages, key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final Object? entry in decoded) {
            if (entry is String && entry.isNotEmpty) ids.add(entry);
          }
        }
      } on Object catch (error) {
        // An unreadable index must not blank the chat list. Losing it means a
        // previously deleted chat may come back, which is a far smaller failure
        // than showing an empty list.
        debugPrint('Unreadable local deleted-chat index: $error');
      }
    }
    _deletedCacheKey = key;
    return _deletedCache = ids;
  }

  Future<void> _persistDeletedIds() async {
    await _db.writeString(
      AppConstants.boxMessages,
      _deletedKey,
      jsonEncode(_deletedIds().toList()),
    );
  }

  /// Whether [id] has been removed from this user's list.
  bool isDeleted(String id) => _deletedIds().contains(id);

  /// Pinned chats first, then by most recent activity, minus the deleted ones.
  ///
  /// The filter is applied here, at the single point every reader goes through,
  /// rather than at each call site: [getAll], [watchAll] and [findById] all
  /// route through it, so a deleted chat cannot leak back into the list, the
  /// search, or a "jump to chat" tap.
  List<Chat> get _sorted {
    final Set<String> hidden = _deletedIds();
    final List<Chat> copy = _cache
        .where((Chat c) => !hidden.contains(c.id))
        .toList(growable: false);
    copy.sort((Chat a, Chat b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastTimestamp.compareTo(a.lastTimestamp);
    });
    return copy;
  }

  Future<void> _persist() async {
    await _db.writeList<Chat>(
      AppConstants.boxChats,
      _key,
      _cache,
      (c) => c.toJson(),
    );
    if (!_controller.isClosed) _controller.add(_sorted);
  }

  @override
  Future<List<Chat>> getAll() async {
    await _ensureLoaded();
    return _sorted;
  }

  @override
  Stream<List<Chat>> watchAll() async* {
    await _ensureLoaded();
    yield _sorted;
    yield* _controller.stream;
  }

  @override
  Future<void> save(Chat chat) async {
    // ⚠️ The other half of "delete chat". This is the method the Firestore
    // mirror calls for every document it receives, so without this check the
    // chat the user just removed comes back the moment anything at all changes
    // in the collection — which is the bug this index exists to fix.
    if (_deletedIds().contains(chat.id)) return;

    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == chat.id);
    if (index == -1) {
      _cache.add(chat);
    } else {
      _cache[index] = chat;
    }
    await _persist();
  }

  @override
  Future<void> saveAll(List<Chat> chats) async {
    await _ensureLoaded();
    final Set<String> hidden = _deletedIds();
    for (final Chat chat in chats) {
      // Same guard as [save]: a bulk write from the mirror must not resurrect
      // a chat the user removed.
      if (hidden.contains(chat.id)) continue;

      final int index = _cache.indexWhere((c) => c.id == chat.id);
      if (index == -1) {
        _cache.add(chat);
      } else {
        _cache[index] = chat;
      }
    }
    await _persist();
  }

  @override
  Future<Chat?> findById(String id) async {
    await _ensureLoaded();
    if (_deletedIds().contains(id)) return null;
    for (final Chat c in _cache) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Removes a chat from this device's list, durably.
  ///
  /// Two writes, and both are required: the row goes, and the id is recorded in
  /// the deletion index. Recording it is not belt-and-braces — it is the only
  /// thing that stops the next Firestore snapshot from restoring the row. See
  /// the class docs.
  @override
  Future<void> delete(String id) async {
    await _ensureLoaded();
    _deletedIds().add(id);
    await _persistDeletedIds();
    _cache.removeWhere((c) => c.id == id);
    await _persist();
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    _cache = <Chat>[];
    // A stale index would outlive the list it describes, and a chat list that
    // is rebuilt from scratch must come back whole rather than pre-filtered by
    // removals made against the copy that was just thrown away.
    _deletedIds().clear();
    await _persistDeletedIds();
    await _persist();
  }

  Future<void> _mutate(String id, Chat Function(Chat) change) async {
    await _ensureLoaded();
    if (_deletedIds().contains(id)) return;
    final int index = _cache.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _cache[index] = change(_cache[index]);
    await _persist();
  }

  @override
  Future<void> markRead(String id) => _mutate(
        id,
        (c) => c.copyWith(unreadCount: 0, isMarkedUnread: false),
      );

  @override
  Future<void> markUnread(String id) =>
      _mutate(id, (c) => c.copyWith(unreadCount: 0, isMarkedUnread: true));

  @override
  Future<void> markAllRead() async {
    await _ensureLoaded();
    _cache = _cache
        .map((c) => c.copyWith(unreadCount: 0, isMarkedUnread: false))
        .toList();
    await _persist();
  }

  @override
  Future<void> setPinned(String id, bool pinned) =>
      _mutate(id, (c) => c.copyWith(isPinned: pinned));

  @override
  Future<void> setMuted(String id, bool muted) =>
      _mutate(id, (c) => c.copyWith(isMuted: muted));

  @override
  Future<void> setArchived(String id, bool archived) =>
      _mutate(id, (c) => c.copyWith(isArchived: archived));

  @override
  Future<void> setFavorite(String id, bool favorite) =>
      _mutate(id, (c) => c.copyWith(isFavorite: favorite));

  @override
  Future<void> setDraft(String id, String draft) =>
      _mutate(id, (c) => c.copyWith(draft: draft));

  @override
  Future<void> updateLastMessage(String chatId, Message message) => _mutate(
        chatId,
        (c) => c.copyWith(
          lastMessage: message.previewText,
          lastTimestamp: message.timestamp,
          // Incoming messages have no delivery tick — the chat list reads this
          // field as "status of the last outgoing message", and storing the
          // incoming status left a stale tick next to the preview.
          lastMessageStatus: message.isOutgoing ? message.status.name : null,
          lastMessageIsOutgoing: message.isOutgoing,
        ),
      );

  /// Increments the unread counter for an incoming message.
  Future<void> incrementUnread(String chatId) => _mutate(
        chatId,
        (c) => c.copyWith(unreadCount: c.isMuted ? c.unreadCount : c.unreadCount + 1),
      );

  /// Closes the change-notification stream.
  ///
  /// Wired to `ref.onDispose` in the owning provider, so the controller is
  /// released when the [ProviderContainer] is torn down instead of leaking.
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
