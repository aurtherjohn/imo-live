import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/message.dart';
import '../../../features/chats/domain/repositories.dart';
import 'local_database.dart';

/// Hive-backed implementation of [ChatRepository].
class LocalChatRepository implements ChatRepository {
  LocalChatRepository({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final StreamController<List<Chat>> _controller =
      StreamController<List<Chat>>.broadcast();

  static const String _key = 'all_chats';

  List<Chat> _cache = <Chat>[];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _cache = _db.readList<Chat>(
      AppConstants.boxChats,
      _key,
      Chat.fromJson,
    );
    _loaded = true;
  }

  Future<void> _persist() async {
    await _db.writeList<Chat>(
      AppConstants.boxChats,
      _key,
      _cache,
      (c) => c.toJson(),
    );
    if (!_controller.isClosed) _controller.add(List<Chat>.unmodifiable(_cache));
  }

  /// Pinned chats first, then by most recent activity.
  List<Chat> get _sorted {
    final List<Chat> copy = List<Chat>.from(_cache);
    copy.sort((Chat a, Chat b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastTimestamp.compareTo(a.lastTimestamp);
    });
    return copy;
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
    yield* _controller.stream.map((_) => _sorted);
  }

  @override
  Future<void> save(Chat chat) async {
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
    for (final Chat chat in chats) {
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
    for (final Chat c in _cache) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    await _ensureLoaded();
    _cache.removeWhere((c) => c.id == id);
    await _persist();
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    _cache = <Chat>[];
    await _persist();
  }

  Future<void> _mutate(String id, Chat Function(Chat) change) async {
    await _ensureLoaded();
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
