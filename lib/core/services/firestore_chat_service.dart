import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'e2ee_service.dart';
import 'onesignal_service.dart';
import '../utils/stream_retry.dart';

/// Transport-level state of an outgoing message, mirrored in Firestore.
///
/// Kept separate from `MessageStatus` because this is the *wire* contract
/// (`sent` → `delivered` → `read`) and must stay stable even if the UI model
/// gains more display states.
class FirestoreMessageStatus {
  const FirestoreMessageStatus._();

  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String read = 'read';
}

/// A chat document as stored in `chats/{chatId}`.
@immutable
class RemoteChat {
  const RemoteChat({
    required this.id,
    required this.participants,
    this.lastMessage = '',
    this.lastMessageTime,
    this.lastMessageSenderId = '',
    this.isGroup = false,
    this.groupName = '',
    this.groupIcon = '',
    this.unreadCount = const <String, int>{},
    this.typing = const <String, bool>{},
  });

  final String id;
  final List<String> participants;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final String lastMessageSenderId;
  final bool isGroup;
  final String groupName;
  final String groupIcon;

  /// uid → unread count.
  final Map<String, int> unreadCount;

  /// uid → currently typing.
  final Map<String, bool> typing;

  static RemoteChat? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    return RemoteChat(
      id: doc.id,
      participants:
          (data['participants'] as List<dynamic>?)?.cast<String>() ??
              const <String>[],
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageTime: _date(data['lastMessageTime']),
      lastMessageSenderId: data['lastMessageSenderId'] as String? ?? '',
      isGroup: data['isGroup'] as bool? ?? false,
      groupName: data['groupName'] as String? ?? '',
      groupIcon: data['groupIcon'] as String? ?? '',
      unreadCount: _intMap(data['unreadCount']),
      typing: _boolMap(data['typing']),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const <String, int>{};
    return value.map<String, int>((Object? k, Object? v) =>
        MapEntry<String, int>('$k', (v as num?)?.toInt() ?? 0));
  }

  static Map<String, bool> _boolMap(Object? value) {
    if (value is! Map) return const <String, bool>{};
    return value.map<String, bool>((Object? k, Object? v) =>
        MapEntry<String, bool>('$k', v as bool? ?? false));
  }
}

/// A message document as stored in `chats/{chatId}/messages/{messageId}`.
@immutable
class RemoteMessage {
  const RemoteMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.text = '',
    this.type = 'text',
    this.mediaUrl = '',
    this.durationMs,
    this.timestamp,
    this.status = FirestoreMessageStatus.sent,
    this.replyTo,
    this.isEncrypted = false,
    this.deleted = false,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final String type;
  final String mediaUrl;

  /// Length of a voice note in milliseconds, from the sender.
  ///
  /// Null for everything that is not a voice note, and for voice notes written
  /// by a build that predates this field. The receiver has no way to know the
  /// duration until the player loads the audio, so without it a bubble shows
  /// `0:00` for however long that takes — and forever if the note is never
  /// played, or if it is played but the platform never reports a duration.
  final int? durationMs;

  final DateTime? timestamp;
  final String status;
  final String? replyTo;

  /// True when `text` holds a sealed envelope rather than a readable body.
  ///
  /// Set from the document, *before* decryption: it is what tells the read path
  /// there is something to open. Once [FirestoreChatService.watchMessages] has
  /// decrypted the body the flag stays true — it records how the message was
  /// stored, not what is currently in [text].
  final bool isEncrypted;

  /// True when the author retracted this message for everyone.
  ///
  /// Set by [FirestoreChatService.retractMessage], which is the only writer.
  /// It is a **flag rather than a deletion of the document**, on purpose: the
  /// recipient has to learn that the message was withdrawn, and a missing
  /// document is indistinguishable from a message that was never sent or has
  /// not synced yet. The tombstone is what lets the recipient's device replace
  /// the bubble with "This message was deleted" instead of silently keeping a
  /// copy the author believes is gone.
  ///
  /// Defaults to `false`, so every document written before this field existed
  /// reads as a normal message.
  final bool deleted;

  RemoteMessage copyWith({String? text}) => RemoteMessage(
        id: id,
        chatId: chatId,
        senderId: senderId,
        text: text ?? this.text,
        type: type,
        mediaUrl: mediaUrl,
        durationMs: durationMs,
        timestamp: timestamp,
        status: status,
        replyTo: replyTo,
        isEncrypted: isEncrypted,
        deleted: deleted,
      );

  static RemoteMessage? fromDoc(
    String chatId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    return RemoteMessage(
      id: doc.id,
      chatId: chatId,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      mediaUrl: data['mediaUrl'] as String? ?? '',
      // Absent on documents written before the field existed, and absent on
      // every non-voice message — `as num?` would throw on a stored string, so
      // an unknown type degrades to null rather than losing the whole message.
      durationMs: (data['durationMs'] as num?)?.toInt(),
      timestamp: RemoteChat._date(data['timestamp']),
      status: data['status'] as String? ?? FirestoreMessageStatus.sent,
      replyTo: data['replyTo'] as String?,
      isEncrypted: data['e2ee'] == true,
      // Absent on every document written before retraction existed, and on
      // every message that has not been retracted — `== true` rather than a
      // cast, so a missing field is "not deleted" and never a throw.
      deleted: data['deleted'] == true,
    );
  }
}

/// A status (story) posted to `status/{statusId}`.
@immutable
class RemoteStatus {
  const RemoteStatus({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.caption,
    required this.type,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String userId;
  final String mediaUrl;
  final String caption;
  final String type;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// True once the 24-hour window has passed.
  ///
  /// Prefers a stored `expiresAt` (written by older builds) and otherwise
  /// derives the deadline from the server-stamped `createdAt`, so the window is
  /// identical for every reader regardless of their device clock. A status whose
  /// server timestamp has not resolved yet is treated as live.
  bool get hasExpired {
    final DateTime? expiry = expiresAt ??
        createdAt?.add(const Duration(hours: 24));
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  static RemoteStatus? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    final String userId = data['userId'] as String? ?? '';
    if (userId.isEmpty) return null;
    return RemoteStatus(
      id: doc.id,
      userId: userId,
      mediaUrl: data['mediaUrl'] as String? ?? '',
      caption: data['caption'] as String? ?? '',
      type: data['type'] as String? ?? 'image',
      createdAt: RemoteChat._date(data['createdAt'] ?? data['timestamp']),
      expiresAt: RemoteChat._date(data['expiresAt']),
    );
  }
}

/// The Firestore side of messaging.
///
/// Firestore is the single source of truth for conversations: the local Hive
/// store is a cache that keeps the UI instant and usable offline, and every
/// write goes to Firestore so the other participant sees it live. Firestore's
/// own persistence layer queues writes made while offline and replays them on
/// reconnect, which is what makes the app offline-first without any custom sync
/// code.
///
/// Everything here degrades gracefully: if Firebase is not configured, or the
/// device is offline, reads return empty and writes are no-ops rather than
/// throwing into the widget tree.
class FirestoreChatService {
  /// [e2ee] is optional: with no encryption service every message is stored as
  /// it is today. Passing one in turns on sealing for one-to-one conversations
  /// whose peer has published a key — see [E2eeService].
  FirestoreChatService({this.e2ee});

  /// Null disables encryption entirely; see [E2eeService].
  final E2eeService? e2ee;

  static const String chatsCollection = 'chats';
  static const String messagesSubcollection = 'messages';
  static const String callsCollection = 'calls';
  static const String statusCollection = 'status';
  static const String contactsCollection = 'contacts';
  static const String contactsListSubcollection = 'list';

  /// Deterministic id for a 1:1 conversation, so both participants compute the
  /// same document without a lookup. Sorted so `a_b` and `b_a` agree.
  static String chatIdFor(String uidA, String uidB) {
    final List<String> pair = <String>[uidA, uidB]..sort();
    return pair.join('_');
  }

  FirebaseFirestore? get _db {
    try {
      return FirebaseFirestore.instance;
    } on Object {
      return null;
    }
  }

  /// Creates the chat document if it is missing, then returns its id.
  Future<String> ensureChat({
    required String chatId,
    required List<String> participants,
    bool isGroup = false,
    String groupName = '',
    String groupIcon = '',
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return chatId;
    try {
      await db.collection(chatsCollection).doc(chatId).set(
        <String, dynamic>{
          'participants': participants,
          'isGroup': isGroup,
          if (groupName.isNotEmpty) 'groupName': groupName,
          if (groupIcon.isNotEmpty) 'groupIcon': groupIcon,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('ensureChat($chatId) failed: $error');
    }
    return chatId;
  }

  /// Live messages for one conversation, oldest first.
  ///
  /// Sealed bodies are opened here — the mirror image of [sendMessage] — so
  /// everything downstream of this stream (the local cache, the chat screen)
  /// only ever sees readable text. Decryption needs `await`, which is why this
  /// is `asyncMap` and not `map`.
  ///
  /// ⚠️ Wrapped in [retryStream], not `handleError`. This listener is the *only*
  /// way a message written on another device reaches this one, and it used to
  /// be a bare `handleError` — which, because a returning handler marks the
  /// error handled, closed the listener permanently on the first transient
  /// failure. The user-visible symptom was exactly "messages stopped arriving
  /// and only a restart brought them back". See [retryStream].
  Stream<List<RemoteMessage>> watchMessages(String chatId, {int limit = 200}) {
    final FirebaseFirestore? db = _db;
    if (db == null || chatId.isEmpty) {
      return Stream<List<RemoteMessage>>.value(const <RemoteMessage>[]);
    }
    return retryStream<List<RemoteMessage>>(
      () => db
          .collection(chatsCollection)
          .doc(chatId)
          .collection(messagesSubcollection)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .asyncMap((QuerySnapshot<Map<String, dynamic>> snapshot) async {
        final List<RemoteMessage> messages = <RemoteMessage>[];
        for (final DocumentSnapshot<Map<String, dynamic>> doc in snapshot.docs) {
          final RemoteMessage? message = RemoteMessage.fromDoc(chatId, doc);
          if (message == null) continue;
          messages.add(await _openIfSealed(message));
        }
        return messages.reversed.toList(growable: false);
      }),
      // Unbounded: the screen cancels this when it closes, and until then a
      // dropped connection must not be allowed to end the conversation.
      attempts: 0,
      onError: (Object error, int attempt) =>
          debugPrint('watchMessages($chatId) failed (attempt $attempt): $error'),
    );
  }

  /// Replaces a sealed body with its plaintext, or an honest placeholder when
  /// it cannot be opened.
  ///
  /// Unlike [sendMessage], this never fails open to a readable fallback — the
  /// ciphertext is what arrived, and showing it raw would look like corruption.
  /// A message whose key material is missing shows
  /// [E2eeService.undecryptablePreview] until the identity is available again.
  Future<RemoteMessage> _openIfSealed(RemoteMessage message) async {
    if (!message.isEncrypted) return message;
    final E2eeService? crypto = e2ee;
    if (crypto == null) return message.copyWith(text: E2eeService.sealedPreview);

    final String? plain = await crypto.open(
      message.text,
      senderId: message.senderId,
    );
    return message.copyWith(
      text: plain ?? E2eeService.undecryptablePreview,
    );
  }

  /// Live conversations the user takes part in.
  ///
  /// ⚠️ Also wrapped in [retryStream]. This one matters as much as the message
  /// listener: `liveChatsStreamProvider` consumes it with `await for`, so an
  /// error that escaped here would tear down the whole chat-list stream — a
  /// conversation started on another device would simply never appear, with no
  /// error on screen. See [retryStream].
  Stream<List<RemoteChat>> watchChats(String uid) {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty) {
      return Stream<List<RemoteChat>>.value(const <RemoteChat>[]);
    }
    return retryStream<List<RemoteChat>>(
      () => db
          .collection(chatsCollection)
          .where('participants', arrayContains: uid)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map(RemoteChat.fromDoc)
              .whereType<RemoteChat>()
              .toList(growable: false)),
      attempts: 0,
      onError: (Object error, int attempt) =>
          debugPrint('watchChats($uid) failed (attempt $attempt): $error'),
    );
  }

  /// Writes a message, marks it `sent`, and updates the chat header.
  ///
  /// ### Encryption
  ///
  /// The body is sealed at this boundary — the last point where plaintext
  /// exists — so the caller, the local cache and the bubble on screen all keep
  /// working on readable text while only Firestore holds ciphertext.
  ///
  /// [peerUid] must be the other participant of a **one-to-one** conversation.
  /// It is null for groups and for anything else that is not a 1:1, which is
  /// the signal not to encrypt: a group has no single peer to seal against.
  /// When it is present but the peer has published no key, [E2eeService.seal]
  /// returns null and the message goes out in the clear rather than not going
  /// out at all.
  ///
  /// Returns `true` when the message and the chat header were written, `false`
  /// when the write failed. The result used to be discarded, which is why a
  /// message that never reached Firestore still showed a single "sent" tick
  /// forever — indistinguishable from a delivered one. [ChatService] turns a
  /// `false` into a visible `failed` state.
  Future<bool> sendMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String text,
    String type = 'text',
    String mediaUrl = '',
    int? durationMs,
    String? replyTo,
    String? peerUid,
    String senderName = '',
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return false;
    final DocumentReference<Map<String, dynamic>> chat =
        db.collection(chatsCollection).doc(chatId);

    String payload = text;
    bool sealed = false;
    if (peerUid != null && peerUid.isNotEmpty && peerUid != senderId) {
      final String? envelope = await e2ee?.seal(peerUid, text);
      if (envelope != null) {
        payload = envelope;
        sealed = true;
      }
    }

    try {
      await chat.collection(messagesSubcollection).doc(messageId).set(
        <String, dynamic>{
          'senderId': senderId,
          'text': payload,
          // Recorded explicitly rather than inferred from the shape of `text`:
          // a reader must be able to tell "sealed" from "someone typed JSON".
          'e2ee': sealed,
          'type': type,
          'mediaUrl': mediaUrl,
          // Only meaningful for a voice note. Written as null for everything
          // else so the field is present-but-empty rather than absent, which
          // keeps the reader's `as num?` cast trivially safe.
          'durationMs': durationMs,
          'replyTo': replyTo,
          // Server-resolved, so ordering is monotonic across devices. A client
          // clock would let a device set an hour fast reorder the thread for
          // both participants. The instant local echo is provided by the Hive
          // cache, which is what keeps the UI snappy while this write is still
          // queued offline — see FirestoreChatService's class docs.
          'timestamp': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'status': FirestoreMessageStatus.sent,
        },
        SetOptions(merge: true),
      );
      await chat.set(
        <String, dynamic>{
          'participants': FieldValue.arrayUnion(<String>[senderId]),
          // The chat-list preview must not leak the message either.
          'lastMessage': sealed ? E2eeService.sealedPreview : text,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageSenderId': senderId,
          // Recorded so a retraction can tell whether this message is still the
          // one the chat list is advertising — see [retractMessage]. Absent on
          // documents written before this field existed, which simply means the
          // header is left alone.
          'lastMessageId': messageId,
        },
        SetOptions(merge: true),
      );
      // Fire and forget, and only once the message is genuinely on the server:
      // a push for a message that never landed would be a lie. A group has no
      // single peer to notify, so `peerUid` being null is the signal to skip.
      if (peerUid != null && peerUid.isNotEmpty && peerUid != senderId) {
        unawaited(
          OneSignalService.sendNotificationToUser(
            receiverUid: peerUid,
            title: senderName.isEmpty ? 'New message' : senderName,
            body: _pushPreview(type, text),
            data: <String, dynamic>{
              'type': 'chat',
              'chatId': chatId,
              'messageId': messageId,
            },
          ),
        );
      }
      return true;
    } on Object catch (error) {
      debugPrint('sendMessage($chatId/$messageId) failed: $error');
      return false;
    }
  }

  /// The one-line body shown on the recipient's lock screen.
  ///
  /// A media message is described rather than sent: the URL is useless in a
  /// notification, and the sealed envelope of an encrypted message must never
  /// be rendered. Text is passed through as-is.
  static String _pushPreview(String type, String text) {
    return switch (type) {
      'image' => '[Photo]',
      'video' => '[Video]',
      'voice' || 'audio' => '[Voice message]',
      'document' => '[File]',
      'location' => '[Location]',
      'contact' => '[Contact]',
      'poll' => '[Poll]',
      'sticker' => '[Sticker]',
      'gift' => '[Gift]',
      _ => text.trim().isEmpty ? '[Message]' : text.trim(),
    };
  }

  /// Retracts a message for everyone: the author's own message, replaced on
  /// both devices by a tombstone.
  ///
  /// ### Why this is a flag and not a document delete
  ///
  /// The document stays, with `deleted: true` and an emptied body. Deleting it
  /// would leave the recipient unable to distinguish "withdrawn" from "never
  /// arrived" — and because both sides key their local cache off the document
  /// id, a vanished document would simply leave the recipient's existing bubble
  /// sitting there untouched, which is the opposite of the intent.
  ///
  /// The body is emptied as well as flagged. A message the author has declared
  /// withdrawn should not keep its plaintext (or the sealed envelope holding
  /// it) in a document the recipient can still read.
  ///
  /// The caller must have already retracted the local copy; this is only the
  /// remote leg. Returns `true` when the tombstone was written, `false` when it
  /// was not — in which case the other participant still has the message, which
  /// is worth telling the user rather than retrying in a loop.
  Future<bool> retractMessage({
    required String chatId,
    required String messageId,
    required String senderId,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return false;
    final DocumentReference<Map<String, dynamic>> chat =
        db.collection(chatsCollection).doc(chatId);
    try {
      await chat.collection(messagesSubcollection).doc(messageId).set(
        <String, dynamic>{
          // Rewritten rather than assumed: it is the only evidence on the
          // document that the author is the person retracting.
          'senderId': senderId,
          'deleted': true,
          'text': '',
          'e2ee': false,
          'mediaUrl': '',
          'durationMs': null,
          'replyTo': null,
          // Server-resolved, like every other authoritative time here.
          'deletedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // The chat list must not keep advertising a message the author has
      // withdrawn. Only touched when the retracted message is still the newest
      // one: an older message being withdrawn changes nothing about the header,
      // and rewriting it would reorder the list for both participants.
      //
      // An empty `lastMessage` is an existing, supported state — a chat that
      // has been created but never messaged looks exactly like this — so this
      // needs no new rendering path and no translated string.
      final DocumentSnapshot<Map<String, dynamic>> header = await chat.get();
      if (header.data()?['lastMessageId'] == messageId) {
        await chat.set(
          <String, dynamic>{
            'lastMessage': '',
            'lastMessageId': '',
          },
          SetOptions(merge: true),
        );
      }
      return true;
    } on Object catch (error) {
      debugPrint('retractMessage($chatId/$messageId) failed: $error');
      return false;
    }
  }

  /// Moves a message's status forward: `sent` → `delivered` → `read`.
  ///
  /// The write really is guarded, as the contract above promises. Firestore has
  /// no conditional update, so the current status is read first and the write is
  /// skipped unless it advances. Two writers racing can still both write, but
  /// they can only ever write *forward* — which is the property that matters,
  /// because a late `delivered` must never walk back a `read`.
  Future<void> updateMessageStatus({
    required String chatId,
    required String messageId,
    required String status,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return;
    final DocumentReference<Map<String, dynamic>> doc = db
        .collection(chatsCollection)
        .doc(chatId)
        .collection(messagesSubcollection)
        .doc(messageId);
    try {
      final DocumentSnapshot<Map<String, dynamic>> current = await doc.get();
      final String existing = (current.data()?['status'] as String?) ??
          FirestoreMessageStatus.sent;
      if (statusRank(existing) >= statusRank(status)) return;
      await doc.set(
        <String, dynamic>{
          'status': status,
          if (status == FirestoreMessageStatus.delivered)
            'deliveredAt': FieldValue.serverTimestamp(),
          if (status == FirestoreMessageStatus.read)
            'readAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('updateMessageStatus($messageId) failed: $error');
    }
  }

  /// Where [status] sits in the `sent` → `delivered` → `read` sequence.
  ///
  /// Anything unrecognised ranks as `sent`, which is the safe default: an
  /// unknown wire value must not be able to block a real advance.
  ///
  /// Public only so the ordering property can be asserted without a Firestore
  /// instance; production callers are all inside this class.
  @visibleForTesting
  static int statusRank(String status) => switch (status) {
        FirestoreMessageStatus.read => 2,
        FirestoreMessageStatus.delivered => 1,
        _ => 0,
      };

  /// Marks every incoming message in the chat as read, and clears the caller's
  /// unread counter.
  ///
  /// ### The query is deliberately one inequality, not two
  ///
  /// This used to ask for `senderId != me` **and** `status != read` in a single
  /// query, and Firestore rejects that outright:
  ///
  ///     Only a single 'NOT_EQUAL', 'NOT_IN', 'IS_NOT_NAN', or 'IS_NOT_NULL'
  ///     filter allowed per query.
  ///
  /// So the query never ran. It failed with `INVALID_ARGUMENT` every time, the
  /// `catch` below swallowed it and cleared the counter instead — which is why
  /// the bug was invisible: the chat-list badge went to zero exactly as
  /// expected, and only the per-message tick silently never advanced. Found by
  /// running the query against the emulator rather than reading it; nothing
  /// about the code looks wrong.
  ///
  /// The sender half now runs in Dart, where it costs nothing: the result set
  /// is the unread messages of one conversation.
  Future<void> markChatRead({
    required String chatId,
    required String readerUid,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return;
    final DocumentReference<Map<String, dynamic>> chat =
        db.collection(chatsCollection).doc(chatId);
    try {
      final QuerySnapshot<Map<String, dynamic>> unread = await chat
          .collection(messagesSubcollection)
          .where('status', isNotEqualTo: FirestoreMessageStatus.read)
          .get();
      final WriteBatch batch = db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in unread.docs) {
        // Your own messages are not yours to mark read — the tick the sender
        // sees is the *recipient's* receipt, and a device that marked its own
        // messages read would be reporting a delivery that never happened.
        if (doc.data()['senderId'] == readerUid) continue;
        batch.set(
          doc.reference,
          <String, dynamic>{
            'status': FirestoreMessageStatus.read,
            'readAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      batch.set(
        chat,
        <String, dynamic>{
          'unreadCount': <String, int>{readerUid: 0},
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    } on Object catch (error) {
      debugPrint('markChatRead($chatId) failed: $error');
      try {
        await chat.set(
          <String, dynamic>{
            'unreadCount': <String, int>{readerUid: 0},
          },
          SetOptions(merge: true),
        );
      } on Object catch (inner) {
        debugPrint('Clearing unread count failed: $inner');
      }
    }
  }

  /// Publishes the caller's typing flag for a chat.
  Future<void> setTyping({
    required String chatId,
    required String uid,
    required bool isTyping,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return;
    try {
      await db.collection(chatsCollection).doc(chatId).set(
        <String, dynamic>{
          'typing': <String, bool>{uid: isTyping},
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('setTyping($chatId) failed: $error');
    }
  }

  /// Publishes presence, used for the chat header's online / last-seen line.
  Future<void> setPresence({
    required String uid,
    required bool isOnline,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty) return;
    try {
      await db.collection('users').doc(uid).set(
        <String, dynamic>{
          'isOnline': isOnline,
          'lastSeen': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('setPresence($uid) failed: $error');
    }
  }

  /// Appends a call record to the `calls` collection.
  Future<void> logCall({
    required String callId,
    required String callerId,
    required String receiverId,
    required String type,
    required String status,
    required int duration,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null) return;
    try {
      await db.collection('calls').doc(callId).set(
        <String, dynamic>{
          'callerId': callerId,
          'receiverId': receiverId,
          'type': type,
          'status': status,
          'duration': duration,
          'timestamp': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('logCall($callId) failed: $error');
    }
  }

  // -------------------------------------------------------------- status

  /// Publishes a status update to `status/{statusId}`.
  ///
  /// `expiresAt` is written by the client (24 h from posting) so the Updates
  /// tab can filter without a server job; anything older is simply not shown.
  Future<void> publishStatus({
    required String statusId,
    required String userId,
    String caption = '',
    String mediaUrl = '',
    String type = 'image',
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || userId.isEmpty) return;
    try {
      final DateTime now = DateTime.now();
      await db.collection(statusCollection).doc(statusId).set(
        <String, dynamic>{
          'userId': userId,
          'mediaUrl': mediaUrl,
          'caption': caption,
          'type': type,
          'timestamp': FieldValue.serverTimestamp(),
          'createdAt': Timestamp.fromDate(now),
          'expiresAt': Timestamp.fromDate(
            now.add(const Duration(hours: 24)),
          ),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('publishStatus($statusId) failed: $error');
    }
  }

  /// Streams the statuses posted by [uids] that have not expired.
  ///
  /// The expiry filter runs client-side because comparing two Firestore
  /// timestamps in one query would need a composite index the project does not
  /// have yet; the document set is small (24 h of updates from the user's
  /// contacts), so filtering here is cheap.
  ///
  /// ⚠️ [retryStream], not `handleError`: the Updates tab watches this for as
  /// long as it is on screen, so a swallowed error would leave a stale ring of
  /// statuses that never gains a new one — and a status is *only* interesting
  /// while it is fresh.
  Stream<List<RemoteStatus>> watchStatuses(List<String> uids) {
    final FirebaseFirestore? db = _db;
    if (db == null || uids.isEmpty) {
      return Stream<List<RemoteStatus>>.value(<RemoteStatus>[]);
    }
    return retryStream<List<RemoteStatus>>(
      () => db
          .collection(statusCollection)
          // Firestore caps `whereIn` at 30 values; a contact list is often
          // longer, so the newest 30 contacts are the ones tracked.
          .where('userId', whereIn: uids.take(30).toList())
          .orderBy('timestamp', descending: true)
          .limit(60)
          .snapshots()
          .map(
            (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
                .map(RemoteStatus.fromDoc)
                .whereType<RemoteStatus>()
                .where((RemoteStatus s) => !s.hasExpired)
                .toList(),
          ),
      attempts: 0,
      onError: (Object error, int attempt) =>
          debugPrint('watchStatuses failed (attempt $attempt): $error'),
    );
  }

  // ------------------------------------------------------------- contacts

  /// Mirrors one local contact into `contacts/{ownerUid}/list/{contactId}`.
  ///
  /// This is what makes the address book survive a reinstall and appear on the
  /// user's other devices. Only the presenting fields are stored; local-only
  /// state (favourite, blocked, a device-synced flag) stays on the device.
  Future<void> saveContact({
    required String ownerUid,
    required String contactId,
    required String name,
    String phone = '',
    String uid = '',
    String username = '',
    String avatarUrl = '',
    String bio = '',
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || ownerUid.isEmpty || contactId.isEmpty) return;
    try {
      await db
          .collection(contactsCollection)
          .doc(ownerUid)
          .collection(contactsListSubcollection)
          .doc(contactId)
          .set(
        <String, dynamic>{
          'name': name,
          'phone': phone,
          // `uid` is the *directory* id of the person, which is how the row is
          // matched back to a real account on the next device.
          'uid': uid.isEmpty ? contactId : uid,
          'username': username,
          'avatarUrl': avatarUrl,
          'bio': bio,
          'savedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('saveContact($ownerUid/$contactId) failed: $error');
    }
  }

  /// Deletes a mirrored contact.
  Future<void> deleteContact({
    required String ownerUid,
    required String contactId,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || ownerUid.isEmpty || contactId.isEmpty) return;
    try {
      await db
          .collection(contactsCollection)
          .doc(ownerUid)
          .collection(contactsListSubcollection)
          .doc(contactId)
          .delete();
    } on Object catch (error) {
      debugPrint('deleteContact($ownerUid/$contactId) failed: $error');
    }
  }
}