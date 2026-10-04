import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/message.dart';
import '../../../core/models/message_parts.dart';
import '../../../core/models/settings.dart';
import '../../../core/services/firestore_chat_service.dart';
import '../../../core/services/remote_contact_service.dart';
import '../../../core/services/storage_service.dart';
import '../../auth/presentation/auth_providers.dart';
import '../presentation/providers.dart';
import 'repositories.dart';

/// Bridges the shared Imo LIVE directory to the app's own contact and chat
/// stores.
///
/// This is the piece that makes the WhatsApp behaviour work end to end:
///
/// * a directory profile is mirrored into the local contact list, so the person
///   appears in the Chats, Contacts and Calls tabs immediately;
/// * a 1:1 chat doc is created in Firestore under a deterministic id, so both
///   participants compute the same conversation;
/// * outgoing and incoming messages are written to and read from
///   `chats/{chatId}/messages`.
///
/// The local store stays the source of truth for rendering, which is what keeps
/// the UI instant and fully usable offline; Firestore is the transport.
class ChatService {
  ChatService(this.ref);

  final Ref ref;

  FirestoreChatService get _firestore => ref.read(firestoreChatServiceProvider);
  String get _uid => ref.read(currentUidProvider);

  // ------------------------------------------------------------- contacts

  /// Mirrors a directory profile into the local contact list and returns the
  /// local contact id.
  ///
  /// Idempotent: the profile's uid is used as the contact id, so saving the
  /// same person twice updates one row instead of creating duplicates. Fields
  /// the user controls locally (favourite, blocked, a custom avatar) are
  /// preserved.
  Future<String> saveDirectoryContact(RemoteProfile profile) async {
    final Contact? existing =
        await ref.read(contactRepositoryProvider).findById(profile.uid);

    final List<String> parts = profile.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    final String firstName = parts.isEmpty
        ? (profile.username.isNotEmpty ? profile.username : profile.phone)
        : parts.first;
    final String lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';

    final Contact contact = Contact(
      id: profile.uid,
      firstName: firstName,
      lastName: lastName,
      username: profile.username,
      phone: profile.phone,
      bio: profile.bio,
      // A provider avatar is remote; a local one the user picked wins.
      avatarPath: existing?.avatarPath,
      isFavorite: existing?.isFavorite ?? false,
      isBlocked: existing?.isBlocked ?? false,
      isOnline: profile.isOnline,
      lastSeen: profile.lastSeen,
      isSyncedToDevice: existing?.isSyncedToDevice ?? false,
    );

    await ref.read(contactsProvider.notifier).persist(contact);

    // Persist to `contacts/{uid}/list/{contactId}` so the address book comes
    // back after a reinstall and follows the user to another device.
    if (_uid.isNotEmpty) {
      unawaited(
        _firestore.saveContact(
          ownerUid: _uid,
          contactId: contact.id,
          name: contact.fullName,
          phone: contact.phone,
          uid: profile.uid,
          username: contact.username,
          avatarUrl: profile.avatarUrl,
          bio: contact.bio,
        ),
      );
    }
    return profile.uid;
  }

  /// Saves a contact that was added manually by phone number.
  ///
  /// When [remoteUid] is set the person is on Imo LIVE and their directory
  /// fields are used; otherwise the entry is local-only until they join.
  Future<String> saveContact({
    required String contactId,
    required String name,
    String phone = '',
    String avatarPath = '',
    String avatarUrl = '',
    String remoteUid = '',
    String username = '',
    String bio = '',
    String countryCode = '',
    String countryIso = '',
  }) async {
    final Contact? existing =
        await ref.read(contactRepositoryProvider).findById(contactId);

    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();

    final Contact contact = Contact(
      id: contactId,
      firstName: parts.isEmpty ? phone : parts.first,
      lastName: parts.length > 1 ? parts.skip(1).join(' ') : '',
      username: username,
      phone: phone,
      countryCode: countryCode,
      countryIso: countryIso,
      bio: bio,
      avatarPath: avatarPath.isEmpty ? existing?.avatarPath : avatarPath,
      isFavorite: existing?.isFavorite ?? false,
      isBlocked: existing?.isBlocked ?? false,
      isSyncedToDevice: existing?.isSyncedToDevice ?? false,
    );

    await ref.read(contactsProvider.notifier).persist(contact);

    // Mirror to `contacts/{uid}/list/{contactId}`. For a number that is not on
    // Imo LIVE yet this preserves just the name and phone, so the entry still
    // reappears on the user's other devices.
    if (_uid.isNotEmpty) {
      unawaited(
        _firestore.saveContact(
          ownerUid: _uid,
          contactId: contactId,
          name: contact.fullName,
          phone: contact.phone,
          uid: remoteUid,
          username: username,
          bio: bio,
        ),
      );
    }
    return contactId;
  }

  // ----------------------------------------------------------------- chat

  /// Opens the conversation with a directory profile, creating it if needed.
  ///
  /// Returns the local chat id, which is the deterministic `uidA_uidB` value so
  /// both sides resolve to the same Firestore document.
  ///
  /// Both stores are written before this returns: the local [Chat] row (so the
  /// conversation appears in the Chats tab immediately, even offline) and the
  /// `chats/{chatId}` document (so the other participant's list picks it up).
  /// A contact saved but never messaged still gets a row — that is what makes
  /// "add a contact and it shows up in your chats" true.
  Future<String> openDirectChat({
    required String contactId,
    required String name,
    String phone = '',
    String avatarPath = '',
    String avatarUrl = '',
    String remoteUid = '',
    String username = '',
    String bio = '',
  }) async {
    // The peer's stable id. For someone who is not on Imo LIVE yet this is the
    // local contact id, which keeps the chat id deterministic on this device
    // and upgradable later once the number resolves to a real account.
    final String peerId = remoteUid.isNotEmpty ? remoteUid : contactId;
    final String chatId =
        _uid.isEmpty ? contactId : FirestoreChatService.chatIdFor(_uid, peerId);

    // Make sure the person is in the contact list first: the chat row alone
    // would give the Chats tab a title and no profile behind it.
    if (remoteUid.isNotEmpty) {
      await saveContact(
        contactId: contactId,
        name: name,
        phone: phone,
        avatarPath: avatarPath,
        remoteUid: remoteUid,
        username: username,
        bio: bio,
      );
    }

    final Chat? existing =
        await ref.read(chatRepositoryProvider).findById(chatId);
    if (existing == null) {
      await ref.read(chatsProvider.notifier).create(
            Chat(
              id: chatId,
              title: name,
              lastMessage: '',
              lastTimestamp: DateTime.now(),
              avatarPath: avatarPath.isEmpty ? null : avatarPath,
              memberIds: <String>[
                if (_uid.isNotEmpty) _uid,
                if (peerId.isNotEmpty) peerId,
              ],
              memberCount: _uid.isEmpty ? 1 : 2,
            ),
          );
    }

    // Awaited rather than fire-and-forget: the caller reports "contact saved"
    // and offers a Message action, and both promises depend on the document
    // existing. `ensureChat` swallows its own errors, so a network failure
    // cannot break the save.
    await _firestore.ensureChat(
      chatId: chatId,
      participants: <String>[
        if (_uid.isNotEmpty) _uid,
        if (peerId.isNotEmpty) peerId,
      ],
    );

    return chatId;
  }

  /// Writes an outgoing message locally and pushes it to Firestore.
  ///
  /// The local write happens first and unconditionally, so the bubble appears
  /// the instant the user taps send. Firestore then carries it to the other
  /// participant; if the device is offline, Firestore queues the write and
  /// replays it on reconnect with no intervention from this layer.
  /// [peerUid] is the other person in a one-to-one conversation, used to seal
  /// the body before it reaches Firestore. Leave it null for a group or when
  /// the peer is unknown — the message is then stored as it is today.
  /// See [FirestoreChatService.sendMessage].
  Future<Message> sendMessage({
    required String chatId,
    required String text,
    MessageType type = MessageType.text,
    Attachment? attachment,
    ReplyPreview? replyTo,
    String? peerUid,
  }) async {
    final Contact sender = ref.read(selfProfileProvider).valueOrNull ??
        const Contact(id: 'self', firstName: 'You');

    final Message message = Message(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      chatId: chatId,
      senderId: _uid.isEmpty ? sender.id : _uid,
      senderName: sender.fullName.isEmpty ? 'You' : sender.fullName,
      content: text,
      timestamp: DateTime.now(),
      direction: MessageDirection.outgoing,
      type: type,
      status: MessageStatus.sent,
      attachment: attachment,
      replyTo: replyTo,
      // It exists locally *and* is being pushed, so it is not local-only.
      localOnly: false,
    );

    await ref.read(messageRepositoryProvider).save(message);
    await ref.read(chatsProvider.notifier).touch(chatId, message);

    // Uploading first would delay the bubble; uploading inside the Firestore
    // write would block it too. So the remote leg runs detached: the UI has the
    // message, and the copy other people receive carries the R2 URL.
    unawaited(
      _publishRemote(
        chatId: chatId,
        message: message,
        text: text,
        type: type,
        attachment: attachment,
        replyTo: replyTo,
        peerUid: peerUid,
      ),
    );

    return message;
  }

  /// Pushes one outgoing message to Firestore, uploading its attachment to
  /// Cloudflare R2 on the way.
  ///
  /// When R2 is unconfigured or the upload fails, the local path is sent
  /// instead. That is deliberate: a text message must still arrive, and a
  /// same-device recipient can still resolve the path.
  ///
  /// A failed Firestore write is reported on the bubble as [MessageStatus.failed]
  /// rather than swallowed. Before this, a message that never reached the
  /// server kept its "sent" tick forever, so "the message didn't arrive" and
  /// "the message arrived and was ignored" looked identical from the sender's
  /// side — which is precisely how the messaging bug stayed hidden.
  Future<void> _publishRemote({
    required String chatId,
    required Message message,
    required String text,
    required MessageType type,
    Attachment? attachment,
    ReplyPreview? replyTo,
    String? peerUid,
  }) async {
    // `sendMessage` fires this detached, so an escaping error would land in
    // `PlatformDispatcher.onError` as an unhandled async error with nothing
    // pointing at the cause. The local copy is already saved by then, so the
    // honest outcome is "this message stayed on this device" — mark it and stop.
    try {
      String mediaUrl = attachment?.localPath ?? '';
      final String? localPath = attachment?.localPath;

      if (localPath != null && localPath.isNotEmpty) {
        final String? remote =
            await ref.read(storageServiceProvider).uploadChatMedia(
                  localPath,
                  chatId: chatId,
                  kind: type.name,
                );
        if (remote != null) mediaUrl = remote;
      }

      final bool written = await _firestore.sendMessage(
        chatId: chatId,
        messageId: message.id,
        senderId: message.senderId,
        text: text,
        type: type.name,
        mediaUrl: mediaUrl,
        // Carried across so the recipient's bubble can show the real length
        // immediately. The recorder already measures this; dropping it here is
        // what made an incoming voice note read `0:00` until — or unless — the
        // player resolved the duration for itself.
        durationMs: attachment?.durationMs,
        replyTo: replyTo?.messageId,
        peerUid: peerUid,
      );

      if (!written) {
        await ref
            .read(messageRepositoryProvider)
            .updateStatus(message.id, MessageStatus.failed);
        await ref.read(chatsProvider.notifier).refresh();
      }
    } on Object catch (error, stack) {
      debugPrint('_publishRemote($chatId/${message.id}) failed: $error');
      debugPrintStack(stackTrace: stack);
      await ref
          .read(messageRepositoryProvider)
          .updateStatus(message.id, MessageStatus.failed);
      await ref.read(chatsProvider.notifier).refresh();
    }
  }

  /// Publishes the typing flag for the current user.
  Future<void> setTyping(String chatId, bool isTyping) async {
    if (_uid.isEmpty) return;
    await _firestore.setTyping(
      chatId: chatId,
      uid: _uid,
      isTyping: isTyping,
    );
  }

  /// Marks every incoming message in the chat as read, locally and remotely.
  Future<void> markRead(String chatId) async {
    await ref.read(chatsProvider.notifier).markRead(chatId);
    if (_uid.isEmpty) return;
    unawaited(_firestore.markChatRead(chatId: chatId, readerUid: _uid));
  }
}

/// The chat bridge.
final Provider<ChatService> chatServiceProvider =
    Provider<ChatService>((Ref ref) => ChatService(ref));

// ============================================================================
// Real-time mirroring
// ============================================================================

/// Mirrors `chats/{chatId}/messages` into the local store for one conversation.
///
/// This is what makes a message sent on another device appear here: Firestore
/// pushes it, this listener writes it into Hive, and the existing
/// `messagesProvider` stream re-renders the list. No polling, no refresh button.
final ProviderFamily<Stream<void>, String> chatMirrorProvider =
    Provider.family<Stream<void>, String>((Ref ref, String chatId) {
  if (chatId.isEmpty) return Stream<void>.value(null);

  final FirestoreChatService firestore = ref.watch(firestoreChatServiceProvider);
  // Watched so this provider re-subscribes when the account changes, and kept
  // as the fallback for a snapshot that arrives before the auth stream has
  // produced its first event — see the note inside the mapping below.
  final String initialUid = ref.watch(currentUidProvider);
  final MessageRepository local = ref.read(messageRepositoryProvider);
  final ContactRepository contacts = ref.read(contactRepositoryProvider);
  final PrivacySettings privacy =
      ref.watch(privacySettingsProvider).valueOrNull ??
          const PrivacySettings();

  return firestore.watchMessages(chatId).asyncMap(
        (List<RemoteMessage> remote) async {
          // Read the uid *here*, at emission time, not once when the provider
          // was built. `currentUidProvider` is '' until the auth stream's first
          // event, and this provider is `ref.read` by the chat screen — so a
          // value captured at build time can be the empty string for the whole
          // life of the subscription. `_toLocal` decides outgoing-vs-incoming
          // from it, and getting it wrong is not cosmetic: every message the
          // *user sent* would be filed as incoming (firing a bogus delivery
          // receipt and lighting their own double tick), and every message they
          // received could be dropped by `blockUnknownSenders`.
          final String liveUid = ref.read(currentUidProvider);
          final String uid = liveUid.isNotEmpty ? liveUid : initialUid;
          for (final RemoteMessage message in remote) {
            final Message mapped = _toLocal(message, uid);

            // "Block unknown senders" is enforced here, at the only point an
            // incoming message crosses from the transport into the local store.
            // Dropping it before the write is what makes the setting mean
            // something: nothing reaches the conversation, the chat-list
            // preview, or the unread count, and the sender gets no delivery
            // receipt for it either — which is why the tick update below is
            // skipped along with the save.
            if (privacy.blockUnknownSenders &&
                !mapped.isOutgoing &&
                mapped.senderId.isNotEmpty &&
                await contacts.findById(mapped.senderId) == null) {
              continue;
            }

            await local.save(mapped);

            // Only the *recipient* can honestly report delivery, so this fires
            // for messages arriving here — never for our own, which would light
            // up our double tick the instant Firestore echoed the write back,
            // whether or not the other device ever fetched it.
            //
            // It advances `sent` → `delivered` and nothing else: once the server
            // already says delivered there is nothing left to report, and a
            // `read` must never be walked back.
            if (!mapped.isOutgoing && mapped.status == MessageStatus.sent) {
              unawaited(
                firestore.updateMessageStatus(
                  chatId: chatId,
                  messageId: mapped.id,
                  status: FirestoreMessageStatus.delivered,
                ),
              );
            }
          }
        },
      );
});

/// Converts a Firestore message into the app's own model.
///
/// Media messages carry only a `mediaUrl` on the wire, so an [Attachment] is
/// rebuilt from it. Without this the receive path produced **no attachment at
/// all**, so every incoming photo rendered as "Photo unavailable" and every
/// incoming voice note as a dead mic icon — on the recipient's device only,
/// which is exactly why the sender never saw the bug.
Message _toLocal(RemoteMessage remote, String uid) {
  final bool outgoing = remote.senderId == uid && uid.isNotEmpty;
  final MessageType type = _typeFromName(remote.type);
  return Message(
    id: remote.id,
    chatId: remote.chatId,
    senderId: remote.senderId,
    senderName: '',
    content: remote.text,
    timestamp: remote.timestamp ?? DateTime.now(),
    direction: outgoing ? MessageDirection.outgoing : MessageDirection.incoming,
    type: type,
    status: _statusFromName(remote.status),
    attachment: _attachmentFromRemote(remote, type),
    localOnly: false,
  );
}

/// Rebuilds the media descriptor for an incoming message.
///
/// Returns null for a message that carries no media. The remote URL is
/// authoritative and no local path is fabricated — the file does not exist on
/// this device, so the bubble must render from [Attachment.remoteUrl].
///
/// A sender whose R2 bucket had no public base URL stored a bare local path
/// (`chat_media/<uid>/photo-123.jpg`) instead of a URL. That value is not
/// fetchable here, so it is kept only as a non-renderable `localPath` rather
/// than being handed to `Image.network` as a broken relative URL.
///
/// [Attachment.durationMs] is carried across for voice notes so the bubble can
/// size itself before the player has loaded anything.
Attachment? _attachmentFromRemote(RemoteMessage remote, MessageType type) {
  if (type == MessageType.text || type == MessageType.system) return null;
  final String raw = remote.mediaUrl.trim();
  if (raw.isEmpty) return null;
  final bool isRemote = raw.startsWith('http://') || raw.startsWith('https://');
  return Attachment(
    id: remote.id,
    type: type,
    remoteUrl: isRemote ? raw : null,
    localPath: isRemote ? null : raw,
    durationMs: remote.durationMs,
  );
}

MessageType _typeFromName(String name) {
  for (final MessageType type in MessageType.values) {
    if (type.name == name) return type;
  }
  return MessageType.text;
}

MessageStatus _statusFromName(String name) => switch (name) {
      FirestoreMessageStatus.read => MessageStatus.read,
      FirestoreMessageStatus.delivered => MessageStatus.delivered,
      FirestoreMessageStatus.sent => MessageStatus.sent,
      _ => MessageStatus.sent,
    };
