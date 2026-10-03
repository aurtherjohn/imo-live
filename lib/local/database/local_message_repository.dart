import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/message.dart';
import '../../../core/models/message_parts.dart';
import '../../../features/chats/domain/repositories.dart';
import 'local_database.dart';

/// Hive-backed implementation of [MessageRepository].
///
/// Messages are stored per chat (`messages_<chatId>`) so a large conversation
/// never forces rewriting the entire message store.
class LocalMessageRepository implements MessageRepository {
  LocalMessageRepository({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final Map<String, StreamController<List<Message>>> _controllers =
      <String, StreamController<List<Message>>>{};
  final Map<String, List<Message>> _cache = <String, List<Message>>{};

  String _key(String chatId) => 'messages_$chatId';

  List<Message> _read(String chatId) {
    if (_cache.containsKey(chatId)) return _cache[chatId]!;
    final List<Message> list = _db.readList<Message>(
      AppConstants.boxMessages,
      _key(chatId),
      Message.fromJson,
    );
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _cache[chatId] = list;
    return list;
  }

  Future<void> _persist(String chatId) async {
    final List<Message> list = _cache[chatId] ?? <Message>[];
    await _db.writeList<Message>(
      AppConstants.boxMessages,
      _key(chatId),
      list,
      (m) => m.toJson(),
    );
    final StreamController<List<Message>>? controller = _controllers[chatId];
    if (controller != null && !controller.isClosed) {
      controller.add(List<Message>.unmodifiable(list));
    }
  }

  @override
  Future<List<Message>> getForChat(String chatId) async =>
      List<Message>.from(_read(chatId));

  @override
  Stream<List<Message>> watchForChat(String chatId) async* {
    _controllers.putIfAbsent(
      chatId,
      () => StreamController<List<Message>>.broadcast(),
    );
    yield List<Message>.from(_read(chatId));
    yield* _controllers[chatId]!.stream;
  }

  @override
  Future<Message?> findById(String id) async {
    for (final String chatId in _knownChatIds()) {
      for (final Message m in _read(chatId)) {
        if (m.id == id) return m;
      }
    }
    return null;
  }

  /// Chat ids that already have a message list loaded or persisted.
  List<String> _knownChatIds() {
    final Set<String> ids = <String>{..._cache.keys};
    for (final String key in _db.box(AppConstants.boxMessages).keys) {
      final String k = key.toString();
      if (k.startsWith('messages_')) ids.add(k.substring('messages_'.length));
    }
    return ids.toList();
  }

  @override
  Future<void> save(Message message) async {
    final List<Message> list = _read(message.chatId);
    final int index = list.indexWhere((m) => m.id == message.id);
    if (index == -1) {
      list.add(message);
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } else {
      list[index] = message;
    }
    await _persist(message.chatId);
  }

  @override
  Future<void> saveAll(List<Message> messages) async {
    final Set<String> touched = <String>{};
    for (final Message message in messages) {
      final List<Message> list = _read(message.chatId);
      final int index = list.indexWhere((m) => m.id == message.id);
      if (index == -1) {
        list.add(message);
      } else {
        list[index] = message;
      }
      touched.add(message.chatId);
    }
    for (final String chatId in touched) {
      _read(chatId).sort((a, b) => a.timestamp.compareTo(b.timestamp));
      await _persist(chatId);
    }
  }

  Future<Message?> _mutate(
    String id,
    Message Function(Message) change,
  ) async {
    for (final String chatId in _knownChatIds()) {
      final List<Message> list = _read(chatId);
      final int index = list.indexWhere((m) => m.id == id);
      if (index == -1) continue;
      list[index] = change(list[index]);
      await _persist(chatId);
      return list[index];
    }
    return null;
  }

  Future<void> _bulk(
    List<String> ids,
    Message Function(Message) change,
  ) async {
    final Set<String> touched = <String>{};
    final Set<String> targets = ids.toSet();
    for (final String chatId in _knownChatIds()) {
      final List<Message> list = _read(chatId);
      bool dirty = false;
      for (int i = 0; i < list.length; i++) {
        if (targets.contains(list[i].id)) {
          list[i] = change(list[i]);
          dirty = true;
        }
      }
      if (dirty) touched.add(chatId);
    }
    for (final String chatId in touched) {
      await _persist(chatId);
    }
  }

  @override
  Future<void> updateStatus(String id, dynamic status) async {
    await _mutate(
      id,
      (m) => m.copyWith(
        status: status is MessageStatus ? status : m.status,
        deliveredAt: status == MessageStatus.delivered ? DateTime.now() : m.deliveredAt,
        readAt: status == MessageStatus.read ? DateTime.now() : m.readAt,
      ),
    );
  }

  @override
  Future<void> edit(String id, String newContent) =>
      _mutate(id, (m) => m.copyWith(content: newContent, isEdited: true));

  @override
  Future<void> deleteForMe(String id) async {
    // "Delete for me" removes the row entirely.
    for (final String chatId in _knownChatIds()) {
      final List<Message> list = _read(chatId);
      final int before = list.length;
      list.removeWhere((m) => m.id == id);
      if (list.length != before) {
        await _persist(chatId);
        return;
      }
    }
  }

  @override
  Future<bool> deleteForEveryone(String id) async {
    final Message? existing = await findById(id);
    if (existing == null) return false;

    // ⚠️ Re-checked here rather than trusted from the caller. The action sheet
    // hides the option outside the window, but the sheet is only one way in —
    // a menu left open past the deadline, a queued tap, or a future call site
    // would all bypass a UI-only rule. See `Message.canDeleteForEveryoneAt`.
    if (!existing.canDeleteForEveryone) return false;

    final Message? updated = await _mutate(
      id,
      (m) => m.copyWith(
        isDeleted: true,
        content: '',
        type: MessageType.text,
        clearReply: false,
        reactions: const <MessageReaction>[],
        poll: null,
        event: null,
      ),
    );
    return updated != null;
  }

  @override
  Future<void> toggleStar(String id) =>
      _mutate(id, (m) => m.copyWith(isStarred: !m.isStarred));

  @override
  Future<void> starAll(List<String> ids, bool starred) =>
      _bulk(ids, (m) => m.copyWith(isStarred: starred));

  @override
  Future<void> togglePin(String id) =>
      _mutate(id, (m) => m.copyWith(isPinned: !m.isPinned));

  @override
  Future<List<Message>> getPinned(String chatId) async {
    final List<Message> results = _read(chatId)
        .where((m) => m.isPinned && !m.isDeleted)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  @override
  Future<void> addReaction(String id, dynamic reaction) async {
    if (reaction is! MessageReaction) return;
    await _mutate(id, (m) {
      final List<MessageReaction> next =
          m.reactions.where((r) => r.senderId != reaction.senderId).toList();
      next.add(reaction);
      return m.copyWith(reactions: next);
    });
  }

  @override
  Future<void> removeReaction(String id, String emoji, String senderId) => _mutate(
        id,
        (m) => m.copyWith(
          reactions: m.reactions
              .where((r) => !(r.emoji == emoji && r.senderId == senderId))
              .toList(),
        ),
      );

  @override
  Future<void> votePoll(String messageId, String optionId, String voterId) =>
      _mutate(messageId, (m) {
        final Poll? poll = m.poll;
        if (poll == null) return m;
        final List<PollOption> options = poll.options.map((o) {
          if (o.id == optionId) {
            final List<String> voters = List<String>.from(o.voterIds);
            if (!voters.contains(voterId)) voters.add(voterId);
            return o.copyWith(voterIds: voters);
          }
          if (!poll.allowMultiple) {
            return o.copyWith(
              voterIds: o.voterIds.where((v) => v != voterId).toList(),
            );
          }
          return o;
        }).toList();
        return m.copyWith(poll: poll.copyWith(options: options));
      });

  @override
  Future<void> setRsvp(String messageId, String contactId, dynamic status) =>
      _mutate(messageId, (m) {
        final EventInfo? event = m.event;
        if (event == null) return m;
        final Map<String, RsvpStatus> rsvps =
            Map<String, RsvpStatus>.from(event.rsvps);
        final RsvpStatus value =
            status is RsvpStatus ? status : RsvpStatus.none;
        if (value == RsvpStatus.none) {
          rsvps.remove(contactId);
        } else {
          rsvps[contactId] = value;
        }
        return m.copyWith(event: event.copyWith(rsvps: rsvps));
      });

  @override
  Future<List<Message>> search(String query, {String? chatId}) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return <Message>[];
    final List<String> scope =
        chatId != null ? <String>[chatId] : _knownChatIds();
    final List<Message> results = <Message>[];
    for (final String id in scope) {
      for (final Message m in _read(id)) {
        if (m.isDeleted) continue;
        if (m.content.toLowerCase().contains(q) ||
            m.previewText.toLowerCase().contains(q) ||
            (m.attachment?.fileName?.toLowerCase().contains(q) ?? false)) {
          results.add(m);
        }
      }
    }
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  @override
  Future<List<Message>> getStarred() async {
    final List<Message> results = <Message>[];
    for (final String chatId in _knownChatIds()) {
      results.addAll(_read(chatId).where((m) => m.isStarred && !m.isDeleted));
    }
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  @override
  Future<List<Message>> getByChats(List<String> chatIds) async {
    final List<Message> results = <Message>[];
    for (final String id in chatIds) {
      results.addAll(_read(id));
    }
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  @override
  Future<void> deleteForChat(String chatId) async {
    _cache[chatId] = <Message>[];
    await _persist(chatId);
  }

  @override
  Future<void> clear() async {
    for (final String chatId in _knownChatIds()) {
      _cache[chatId] = <Message>[];
      await _persist(chatId);
    }
  }

  @override
  Future<int> purgeExpired() async {
    int removed = 0;
    final DateTime now = DateTime.now();
    for (final String chatId in _knownChatIds()) {
      final List<Message> list = _read(chatId);
      final int before = list.length;
      list.removeWhere((m) {
        if (m.type == MessageType.system) return false;
        final int seconds = _disappearingFor(chatId);
        if (seconds <= 0) return false;
        return now.difference(m.timestamp).inSeconds > seconds;
      });
      removed += before - list.length;
      if (before != list.length) await _persist(chatId);
    }
    return removed;
  }

  /// Per-chat disappearing window; read straight from the chat index.
  int _disappearingFor(String chatId) {
    final List<Chat> chats = _db.readList<Chat>(
      AppConstants.boxChats,
      'all_chats',
      Chat.fromJson,
    );
    for (final Chat c in chats) {
      if (c.id == chatId) return c.disappearingSeconds;
    }
    return 0;
  }
}
