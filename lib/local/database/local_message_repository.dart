import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

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
///
/// ### "Delete for me" is local by construction, not by intention
///
/// [deleteForMe] must never reach another device. That is not enforced by a
/// rule anyone has to remember; it is a property of this class:
///
/// * It holds **no** Firestore, no client and no transport — only a
///   [LocalDatabase] — so there is nothing here that *could* write remotely.
/// * The method is handed nothing but a message id. It is not given a peer, a
///   uid or a channel, so even a future caller who wanted a remote write has
///   no recipient to address.
/// * The removal is recorded in a deletion index (below) as well as performed,
///   so the Firestore mirror cannot put the row back — see [save].
///
/// The one thing a comment *cannot* stop is a later `RemoteMessageRepository`
/// implementing this method as a network call. The interface documents the
/// requirement for that reason: `MessageRepository.deleteForMe`.
///
/// ### The deletion index
///
/// Each chat keeps the ids this user removed for themselves under
/// `deleted_ids_<chatId>` — in the **same** box as the messages
/// ([AppConstants.boxMessages]), so the two are always cleared together and can
/// never disagree about whose device the removal belongs to.
///
/// It exists because removing the row alone is not durable. `chatMirrorProvider`
/// re-saves *every* message Firestore reports, on *every* snapshot: the next
/// incoming message re-delivers the whole page, and the removed row would be
/// written straight back. The index is what makes "gone" mean gone.
class LocalMessageRepository implements MessageRepository {
  LocalMessageRepository({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final Map<String, StreamController<List<Message>>> _controllers =
      <String, StreamController<List<Message>>>{};
  final Map<String, List<Message>> _cache = <String, List<Message>>{};
  final Map<String, Set<String>> _deleted = <String, Set<String>>{};

  String _key(String chatId) => 'messages_$chatId';

  /// Key holding the ids removed for this user in [chatId].
  ///
  /// Deliberately does not start with `messages_`, so [_knownChatIds] never
  /// mistakes it for a conversation.
  String _deletedKey(String chatId) => 'deleted_ids_$chatId';

  /// The ids removed for this user in [chatId], loaded from the index once.
  Set<String> _deletedIds(String chatId) {
    final Set<String>? cached = _deleted[chatId];
    if (cached != null) return cached;

    final Set<String> ids = <String>{};
    final String? raw =
        _db.readString(AppConstants.boxMessages, _deletedKey(chatId));
    if (raw != null && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final Object? entry in decoded) {
            if (entry is String && entry.isNotEmpty) ids.add(entry);
          }
        }
      } on Object catch (error) {
        // An unreadable index must not hide the whole conversation. Losing it
        // means a previously removed message may reappear, which is a far
        // smaller failure than showing an empty chat.
        debugPrint('Unreadable local-deletion index for "$chatId": $error');
      }
    }
    return _deleted[chatId] = ids;
  }

  Future<void> _persistDeletedIds(String chatId) async {
    await _db.writeString(
      AppConstants.boxMessages,
      _deletedKey(chatId),
      jsonEncode(_deletedIds(chatId).toList()),
    );
  }

  List<Message> _read(String chatId) {
    if (_cache.containsKey(chatId)) return _cache[chatId]!;
    final Set<String> hidden = _deletedIds(chatId);
    final List<Message> list = _db
        .readList<Message>(
          AppConstants.boxMessages,
          _key(chatId),
          Message.fromJson,
        )
        // Filtered here, at the single point every reader goes through, rather
        // than at each call site: `findById`, `search`, the pinned banner and
        // the chat screen all read through this method, so a message removed
        // for this user cannot leak back into any of them.
        .where((Message m) => !hidden.contains(m.id))
        .toList();
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
    // ⚠️ The other half of "delete for me". This is the method the Firestore
    // mirror calls for every message it receives, so without this check a row
    // the user removed comes back the moment anything in the conversation
    // changes — typically the next incoming message, seconds later. The check
    // cannot live in the mirror, because the mirror is not the only writer.
    if (_deletedIds(message.chatId).contains(message.id)) return;

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
      // Same guard as [save]: a bulk write from the mirror must not resurrect
      // a locally removed message either.
      if (_deletedIds(message.chatId).contains(message.id)) continue;

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
    // Local-only — see the class docs for why that is a property of this
    // class rather than a promise in this comment.
    //
    // Two writes, both to [AppConstants.boxMessages]: the row goes, and the id
    // is recorded in the deletion index. Recording it is not belt-and-braces;
    // it is what stops the next Firestore snapshot from restoring the row.
    for (final String chatId in _knownChatIds()) {
      // Already recorded here — the row is invisible either way, so this chat
      // is done.
      if (_deletedIds(chatId).contains(id)) return;

      final List<Message> list = _read(chatId);
      final int before = list.length;
      list.removeWhere((m) => m.id == id);
      if (list.length != before) {
        _deletedIds(chatId).add(id);
        await _persistDeletedIds(chatId);
        await _persist(chatId);
        return;
      }
    }
    // No stored copy anywhere. The message may still arrive later — the user
    // removed it from this device, and this device is the only place the
    // removal was ever going to apply — but there is no chat to record it
    // against, so nothing more can be done here.
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
    // The deletion index goes with the conversation. A stale index would
    // outlive the chat it describes, and a chat that is cleared and then
    // re-synced must come back whole rather than pre-filtered by removals made
    // against the copy that was just thrown away.
    _deleted[chatId] = <String>{};
    await _db.delete(AppConstants.boxMessages, _deletedKey(chatId));
    await _persist(chatId);
  }

  @override
  Future<void> clear() async {
    for (final String chatId in _knownChatIds()) {
      _cache[chatId] = <Message>[];
      _deleted[chatId] = <String>{};
      await _persist(chatId);
    }
    // Sweep indexes belonging to a chat whose message list is already gone:
    // [_knownChatIds] only sees chats that still have a `messages_` key, so
    // those indexes would otherwise survive the wipe.
    final box = _db.maybeBox(AppConstants.boxMessages);
    if (box != null) {
      for (final Object key in box.keys.toList()) {
        final String k = key.toString();
        if (k.startsWith('deleted_ids_')) {
          await _db.delete(AppConstants.boxMessages, k);
        }
      }
    }
    _deleted.clear();
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
