import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/message.dart';
import '../../../core/models/message_parts.dart';
import '../../../core/models/settings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../../core/widgets/video_view.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/chat_service.dart';
import '../domain/repositories.dart';
import 'dialogs/chat_dialogs.dart';
import 'providers.dart';
import 'widgets/chat_tile.dart';
import 'widgets/message_action_sheet.dart';
import 'widgets/message_bubble_parts.dart';
import 'widgets/message_bubbles.dart';
import 'widgets/message_composer.dart';
import '../../../core/utils/l10n.dart';

/// The conversation screen.
///
/// Everything here is functional: sending, replying, editing, deleting,
/// reacting, forwarding, starring, voting in polls, RSVPing to events, jumping
/// to quoted messages, in-chat search and wallpapers all operate on the local
/// store. Nothing is a placeholder.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  ReplyPreview? _replyTo;
  Message? _editing;
  bool _showScrollToBottom = false;

  /// Ids of locally-created messages so they animate in only once.
  final Set<String> _animated = <String>{};

  /// Live subscription to the remote message stream.
  StreamSubscription<void>? _mirror;

  /// Clears the "typing" flag a moment after the user stops typing.
  Timer? _typingDebounce;

  /// True when the route carried no usable chat id.
  ///
  /// GoRouter defaults a missing path parameter to `''`, and the chat list
  /// would happily persist messages under that empty id where no chat row
  /// exists — they become permanently invisible. Refuse to send instead of
  /// silently losing the message.
  bool get _hasValidChatId => widget.chatId.trim().isNotEmpty;

  /// Set once the opening scroll to the newest message has happened.
  ///
  /// Without it the opening scroll would fight the user: every rebuild would
  /// yank the viewport back to the bottom.
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markRead();
      _subscribeToRemote();
      _scrollToBottomOnOpen();
    });
  }

  /// Scrolls to the newest message once, when the list first has content.
  ///
  /// The reported "chat opens at the middle" bug: the list is a plain
  /// top-down `ListView` and nothing ever moved the viewport, so a long
  /// conversation opened on its *oldest* message — the user had to scroll all
  /// the way down to find the conversation they came for.
  ///
  /// Retried across frames until the list has layout and content, because on
  /// the first frame the list has not been laid out yet and `maxScrollExtent`
  /// is still 0. `jumpTo` and not `animateTo`: the user must never watch the
  /// list scroll past them on entry. Never gives up while the widget is
  /// mounted — an empty chat stops retrying when the first message arrives
  /// through the `ref.listen` path below instead.
  void _scrollToBottomOnOpen() {
    if (_didInitialScroll || !mounted) return;
    if (_scrollController.hasClients) {
      final double target = _scrollController.position.maxScrollExtent;
      if (target > 0) {
        _scrollController.jumpTo(target);
        _didInitialScroll = true;
        return;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottomOnOpen());
  }

  /// Listens to `chats/{chatId}/messages` for the lifetime of the screen.
  ///
  /// Firestore pushes every message the other participant writes; the mirror
  /// writes them into the local store and the existing `messagesProvider`
  /// stream repaints the list. No polling, no manual refresh.
  void _subscribeToRemote() {
    if (!_hasValidChatId) return;
    _mirror = ref.read(chatMirrorProvider(widget.chatId)).listen(
      (_) {},
      onError: (Object error) {
        // A missing network is not an error worth surfacing: the local store
        // still renders and the writes are queued by Firestore.
        debugPrint('Chat mirror for ${widget.chatId} failed: $error');
      },
    );
  }

  @override
  void dispose() {
    _mirror?.cancel();
    _typingDebounce?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final double distanceFromBottom =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    final bool shouldShow = distanceFromBottom > 240;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _markRead() {
    // Local first (clears the badge immediately), then Firestore so the sender
    // sees the blue ticks.
    unawaited(ref.read(chatServiceProvider).markRead(widget.chatId));
  }

  /// Publishes the typing flag, clearing it shortly after the user stops.
  void _publishTyping(bool isTyping) {
    if (!_hasValidChatId) return;
    _typingDebounce?.cancel();
    final ChatService service = ref.read(chatServiceProvider);
    unawaited(service.setTyping(widget.chatId, isTyping));
    if (!isTyping) return;
    _typingDebounce = Timer(const Duration(seconds: 3), () {
      unawaited(service.setTyping(widget.chatId, false));
    });
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final double target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: AppDurations.normal,
        curve: AppDurations.curve,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  // --------------------------------------------------------------- sending

  Future<void> _handleSend(
    String text,
    Attachment? attachment,
    ReplyPreview? replyTo,
  ) async {
    // Internal signals from the composer that open a sheet instead of sending.
    if (text == '__pick_contact__') {
      await _shareContactMessage();
      return;
    }
    if (text.startsWith('__open_') && text.endsWith('__')) {
      await _handleSpecialAttachment(text);
      return;
    }

    // Sending into a non-existent conversation would write an orphaned row
    // that can never be opened again.
    if (!_hasValidChatId) {
      if (mounted) {
        iToast(context, context.l10n.thisConversationIsNoLonger,
            isError: true);
      }
      return;
    }

    if (_editing != null) {
      // A single write. `edit` already persists the new body and sets
      // `isEdited`. Saving `_editing!.copyWith(...)` afterwards wrote the stale
      // pre-edit content back over it, so the edit appeared to revert.
      await ref.read(messageRepositoryProvider).edit(_editing!.id, text);
      if (mounted) {
        setState(() => _editing = null);
        iToast(context, context.l10n.messageUpdated);
      }
      return;
    }

    final MessageType type = attachment?.type ?? MessageType.text;

    // Go through ChatService so the message lands in Firestore as well as in
    // the local store: the local write is what paints the bubble instantly,
    // the Firestore write is what the other participant receives. When this
    // device is offline Firestore queues it and replays on reconnect.
    // Sealing a body needs to know who it is for. `Chat.peerUid` answers null
    // for a group chat — which is exactly the signal to leave it in the clear,
    // because a group has no single peer to exchange a key with.
    final Chat? chat = ref.read(chatByIdProvider(widget.chatId)).valueOrNull;
    final String? peerUid = chat?.peerUid(ref.read(currentUidProvider));

    final Message message = await ref.read(chatServiceProvider).sendMessage(
          chatId: widget.chatId,
          text: text,
          type: type,
          attachment: attachment,
          replyTo: replyTo,
          peerUid: peerUid,
        );

    if (mounted) {
      setState(() => _replyTo = null);
      _scrollToBottom();
    }

    // Delivery and read are now driven by Firestore (`chatMirrorProvider`
    // promotes a message to delivered as soon as it is written, and the
    // recipient's `markChatRead` promotes it to read), so nothing is faked
    // here — only the local bubble's "sent" acknowledgement is immediate.
    unawaited(_confirmSent(message));
  }

  /// Marks the bubble as handed to the transport.
  Future<void> _confirmSent(Message message) async {
    await ref
        .read(messageRepositoryProvider)
        .updateStatus(message.id, MessageStatus.sent);
    await ref.read(chatsProvider.notifier).refresh();
  }

  Future<void> _handleSpecialAttachment(String signal) async {
    final String kind = signal.replaceAll('__', '').replaceAll('open_', '');
    switch (kind) {
      case 'poll':
        await _createPoll();
      case 'quiz':
        await _createQuiz();
      case 'event':
        await _createEvent();
      case 'sticker':
        await _sendSticker();
      case 'wallpaper':
        if (mounted) context.push(AppRoutes.wallpaper);
    }
  }

  Future<void> _createPoll() async {
    final PollDraft? draft = await showPollComposer(context);
    if (draft == null || !mounted) return;
    await _sendPollDraft(draft);
  }

  Future<void> _createQuiz() async {
    final PollDraft? draft = await showPollComposer(context, asQuiz: true);
    if (draft == null || !mounted) return;
    await _sendPollDraft(draft);
  }

  /// Persists a poll or quiz draft as a message.
  Future<void> _sendPollDraft(PollDraft draft) async {
    final Contact sender =
        ref.read(selfProfileProvider).valueOrNull ??
            const Contact(id: 'self', firstName: 'You');

    final int stamp = DateTime.now().microsecondsSinceEpoch;
    final List<PollOption> options = List<PollOption>.generate(
      draft.options.length,
      (int index) => PollOption(
        id: 'opt_${index}_$stamp',
        text: draft.options[index],
      ),
    );

    final Message message = Message(
      id: 'msg_$stamp',
      chatId: widget.chatId,
      senderId: sender.id,
      senderName: sender.fullName.isEmpty ? 'You' : sender.fullName,
      content: draft.question,
      timestamp: DateTime.now(),
      direction: MessageDirection.outgoing,
      type: MessageType.poll,
      status: MessageStatus.sent,
      poll: Poll(
        question: draft.question,
        allowMultiple: draft.allowMultiple,
        // Map the composer's option index onto the generated option id so the
        // bubble can grade answers without a second lookup.
        correctOptionId: draft.correctIndex == null
            ? null
            : options[draft.correctIndex!].id,
        options: options,
      ),
    );
    await ref.read(messageRepositoryProvider).save(message);
    await ref
        .read(chatsProvider.notifier)
        .touch(widget.chatId, message);
    if (mounted) _scrollToBottom();
  }

  Future<void> _createEvent() async {
    final EventDraft? draft = await showEventComposer(context);
    if (draft == null || !mounted) return;

    final Contact sender =
        ref.read(selfProfileProvider).valueOrNull ??
            const Contact(id: 'self', firstName: 'You');

    final Message message = Message(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      chatId: widget.chatId,
      senderId: sender.id,
      senderName: sender.fullName.isEmpty ? 'You' : sender.fullName,
      content: draft.title,
      timestamp: DateTime.now(),
      direction: MessageDirection.outgoing,
      type: MessageType.event,
      status: MessageStatus.sent,
      event: EventInfo(
        title: draft.title,
        start: draft.start,
        end: draft.end,
        location: draft.location,
        description: draft.description,
      ),
    );
    await ref.read(messageRepositoryProvider).save(message);
    await ref.read(chatsProvider.notifier).touch(widget.chatId, message);
    if (mounted) _scrollToBottom();
  }

  Future<void> _sendSticker() async {
    final String? sticker = await showStickerPicker(context);
    if (sticker == null || !mounted) return;

    final Contact sender =
        ref.read(selfProfileProvider).valueOrNull ??
            const Contact(id: 'self', firstName: 'You');

    final Message message = Message(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      chatId: widget.chatId,
      senderId: sender.id,
      senderName: sender.fullName.isEmpty ? 'You' : sender.fullName,
      content: sticker,
      timestamp: DateTime.now(),
      direction: MessageDirection.outgoing,
      type: MessageType.sticker,
      status: MessageStatus.sent,
    );
    await ref.read(messageRepositoryProvider).save(message);
    await ref.read(chatsProvider.notifier).touch(widget.chatId, message);
    if (mounted) _scrollToBottom();
  }

  Future<void> _shareContactMessage() async {
    final List<Contact> contacts =
        ref.read(contactsProvider).valueOrNull ?? <Contact>[];
    final Contact? contact = await showContactPicker(
      context,
      contacts: contacts.where((Contact c) => !c.isSelf).toList(),
    );
    if (contact == null || !mounted) return;

    final Contact sender =
        ref.read(selfProfileProvider).valueOrNull ??
            const Contact(id: 'self', firstName: 'You');

    final Message message = Message(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      chatId: widget.chatId,
      senderId: sender.id,
      senderName: sender.fullName.isEmpty ? 'You' : sender.fullName,
      content: contact.fullName,
      timestamp: DateTime.now(),
      direction: MessageDirection.outgoing,
      type: MessageType.contact,
      status: MessageStatus.sent,
      attachment: Attachment(
        id: 'att_${DateTime.now().microsecondsSinceEpoch}',
        type: MessageType.contact,
        contactName: contact.fullName,
        contactPhone: contact.phone,
      ),
    );
    await ref.read(messageRepositoryProvider).save(message);
    await ref.read(chatsProvider.notifier).touch(widget.chatId, message);
    if (mounted) _scrollToBottom();
  }

  // ------------------------------------------------------------- actions

  /// Opens the long-press menu for [message].
  ///
  /// [canRetractForEveryone] is [Message.canDeleteForEveryone] for that message
  /// — the author's own, not already deleted, inside the two-day window. It is
  /// passed in rather than re-derived because the sheet is a pure widget.
  Future<void> _handleMessageLongPress(
    Message message,
    bool canRetractForEveryone,
  ) async {
    HapticFeedback.selectionClick();
    final Object? result = await showMessageActionSheet(
      context,
      message: message,
      isGroup: false,
      canDeleteForEveryone: canRetractForEveryone,
    );
    if (result == null || !mounted) return;

    if (result is String) {
      await _toggleReaction(message, result);
      return;
    }
    if (result is! MessageAction) return;

    switch (result) {
      case MessageAction.reply:
        _startReply(message);
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.content));
        if (mounted) iToast(context, context.l10n.messageCopied);
      case MessageAction.forward:
        await _forwardMessage(message);
      case MessageAction.star:
        await ref.read(messageRepositoryProvider).toggleStar(message.id);
        await ref.read(starredMessagesProvider.notifier).refresh();
        if (mounted) {
          iToast(
            context,
            message.isStarred
                ? context.l10n.starredRemoved
                : context.l10n.starredAdded,
          );
        }
      case MessageAction.pin:
        await _togglePin(message);
      case MessageAction.edit:
        setState(() {
          _replyTo = null;
          _editing = message;
        });
      case MessageAction.select:
        ref.read(messageSelectionProvider.notifier).add(message.id);
      case MessageAction.info:
        await showMessageInfoSheet(context, message);
      case MessageAction.deleteForMe:
        await _deleteForMe(message);
      case MessageAction.deleteForEveryone:
        final bool confirmed = await confirmDeleteForEveryone(context);
        if (!confirmed || !mounted) return;
        // The repository re-checks the author and the two-day window and
        // reports a refusal instead of pretending to succeed — a menu left open
        // past the deadline is a real way to get here. `retractForEveryone`
        // writes the local tombstone first and pushes the remote one detached,
        // so nothing here waits on the other participant.
        final bool retracted =
            await ref.read(chatServiceProvider).retractForEveryone(message);
        if (!mounted) return;
        if (retracted) {
          await _resyncLastMessage(message);
        } else {
          iToast(
            context,
            context.l10n.thatMessageIsTooOld,
            isError: true,
          );
        }
      case MessageAction.save:
        await _saveAttachment(message);
      case MessageAction.share:
        await _shareMessage(message);
    }
  }

  /// Removes one message from **this device**, after confirming.
  ///
  /// "Delete for me" is local-only and unilateral: nothing is sent, nobody is
  /// told, and the other person keeps their copy. It is confirmed because it
  /// sits directly above "Delete for everyone" in the sheet, which does the
  /// opposite — and because the removal cannot be undone here.
  Future<void> _deleteForMe(Message message) async {
    final bool confirmed = await confirmDeleteForMe(context);
    if (!confirmed || !mounted) return;
    await ref
        .read(messageRepositoryProvider)
        .deleteForMe(message.id, chatId: message.chatId);
    if (!mounted) return;
    await _resyncLastMessage(message);
  }

  /// Arms the composer with a quote of [message].
  ///
  /// Shared by the long-press menu's Reply action and the swipe-right gesture,
  /// so both produce an identical reply preview and cancel any in-flight edit.
  void _startReply(Message message) {
    if (message.isDeleted) return;
    setState(() {
      _editing = null;
      _replyTo = ReplyPreview(
        messageId: message.id,
        senderName: message.isOutgoing ? context.l10n.you : message.senderName,
        preview: TextUtils.truncate(message.previewText, 120),
        type: message.type,
      );
    });
  }

  /// Keeps the chat index consistent after a message is removed.
  Future<void> _resyncLastMessage(Message removed) async {
    final List<Message> remaining =
        await ref.read(messageRepositoryProvider).getForChat(widget.chatId);
    final ChatRepository repo = ref.read(chatRepositoryProvider);
    final Chat? chat = await repo.findById(widget.chatId);
    if (chat == null) return;

    if (remaining.isEmpty) {
      await repo.save(
        chat.copyWith(lastMessage: '', lastTimestamp: DateTime.now()),
      );
    } else {
      final Message last = remaining.last;
      await repo.updateLastMessage(widget.chatId, last);
    }
    await ref.read(chatsProvider.notifier).refresh();
  }

  Future<void> _toggleReaction(Message message, String emoji) async {
    const String selfId = 'self';
    final bool already = message.reactions
        .any((MessageReaction r) => r.emoji == emoji && r.senderId == selfId);
    if (already) {
      await ref
          .read(messageRepositoryProvider)
          .removeReaction(message.id, emoji, selfId);
    } else {
      await ref.read(messageRepositoryProvider).addReaction(
            message.id,
            MessageReaction(
              emoji: emoji,
              senderId: selfId,
              senderName: context.l10n.you,
            ),
          );
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _forwardMessage(Message message) async {
    final List<Chat> chats = ref.read(chatsProvider).valueOrNull ?? <Chat>[];
    final Chat? target = await showModalBottomSheet<Chat>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext sheetContext) => FractionallySizedBox(
        heightFactor: 0.72,
        child: Column(
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: sheetContext.c.divider,
                borderRadius: AppRadius.rPill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.l10n.forwardTo, style: sheetContext.t.titleMedium),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: chats.length,
                itemBuilder: (BuildContext context, int index) {
                  final Chat chat = chats[index];
                  return ContactSelectTile(
                    name: chat.title,
                    subtitle: chat.lastMessage,
                    imagePath: chat.avatarPath,
                    imageUrl: chat.avatarUrl,
                    colorSeed: chat.avatarColor,
                    selected: false,
                    isOnline: chat.isOnline,
                    trailing: const SizedBox.shrink(),
                    onChanged: (_) => Navigator.pop(sheetContext, chat),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;

    final Message forwarded = Message(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      chatId: target.id,
      senderId: message.senderId,
      senderName: message.senderName,
      content: message.content,
      timestamp: DateTime.now(),
      direction: MessageDirection.outgoing,
      type: message.type,
      status: MessageStatus.sent,
      attachment: message.attachment,
      poll: message.poll,
      event: message.event,
      isForwarded: true,
    );
    await ref.read(messageRepositoryProvider).save(forwarded);
    await ref.read(chatsProvider.notifier).touch(target.id, forwarded);
    if (mounted) iToast(context, context.l10n.forwardedTo(target.title));
  }

  Future<void> _showChatMenu(Chat chat) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: sheetContext.c.divider,
                borderRadius: AppRadius.rPill,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SettingsTile(
              title: context.l10n.viewContact,
              leadingIcon: Icons.person_outline_rounded,
              onTap: () {
                Navigator.pop(sheetContext);
                _openChatInfo(chat);
              },
            ),
            SettingsTile(
              title: context.l10n.mediaLinksAndDocs,
              leadingIcon: Icons.photo_library_outlined,
              onTap: () {
                Navigator.pop(sheetContext);
                // Lands on the real shared-media strip with the Photos filter
                // already applied. This entry used to toast "Shared media
                // appears here as you send it" and do nothing.
                context.push(
                  '${AppRoutes.chatSearch}?id=${chat.id}&type=image',
                );
              },
            ),
            SettingsTile(
              title: context.l10n.searchInChat,
              leadingIcon: Icons.search_rounded,
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('${AppRoutes.chatSearch}?id=${chat.id}');
              },
            ),
            SettingsTile(
              title: chat.isMuted ? context.l10n.unmuteNotifications : context.l10n.muteNotifications,
              leadingIcon: chat.isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              onTap: () {
                Navigator.pop(sheetContext);
                ref.read(chatsProvider.notifier).toggleMute(chat.id);
              },
            ),
            SettingsTile(
              title: context.l10n.wallpaper,
              leadingIcon: Icons.wallpaper_rounded,
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(AppRoutes.wallpaper);
              },
            ),
            SettingsTile(
              title: context.l10n.clearChat,
              leadingIcon: Icons.cleaning_services_outlined,
              titleColor: context.c.onDanger,
              leadingIconColor: context.c.onDanger,
              onTap: () async {
                Navigator.pop(sheetContext);
                final bool ok = await confirmClearMessages(context);
                if (!ok) return;
                await ref.read(chatsProvider.notifier).clearChat(chat.id);
                if (mounted) iToast(context, context.l10n.chatCleared);
              },
            ),
            SettingsTile(
              title: context.l10n.deleteChat,
              leadingIcon: Icons.delete_outline_rounded,
              titleColor: context.c.onDanger,
              leadingIconColor: context.c.onDanger,
              onTap: () async {
                Navigator.pop(sheetContext);
                final bool ok = await confirmClearMessages(context);
                if (!ok) return;
                await ref.read(chatsProvider.notifier).deleteChat(chat.id);
                if (mounted) context.pop();
              },
              showDivider: false,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Chat?> chatAsync = ref.watch(chatByIdProvider(widget.chatId));
    final AsyncValue<List<Message>> messagesAsync =
        ref.watch(messagesProvider(widget.chatId));
    final ChatSettings chatSettings =
        ref.watch(chatSettingsProvider).valueOrNull ?? const ChatSettings();
    final Wallpaper wallpaper =
        ref.watch(wallpaperProvider).valueOrNull ??
            const Wallpaper(id: 'default', name: 'Default', kind: WallpaperKind.defaultPattern);
    final Set<String> selection = ref.watch(messageSelectionProvider);

    final Chat? chat = chatAsync.valueOrNull;
    final List<Message> messages = messagesAsync.valueOrNull ?? <Message>[];

    // A message arriving — the peer's, not just the user's own — puts the view
    // back on the newest line. Gated on `_didInitialScroll` so it cannot fight
    // the opening scroll, and fired post-frame so the new row exists in the
    // layout before the offset is measured.
    ref.listen<AsyncValue<List<Message>>>(messagesProvider(widget.chatId),
        (AsyncValue<List<Message>>? previous, AsyncValue<List<Message>> next) {
      final int before = previous?.valueOrNull?.length ?? 0;
      final int after = next.valueOrNull?.length ?? 0;
      // First load: chat just opened and messages appeared for the first time.
      // Scroll straight to the newest message so the user sees the end of the
      /// conversation, not the middle.
      if (before == 0 && after > 0 && !_didInitialScroll) {
        _didInitialScroll = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
      // A new message arrived while viewing — scroll to bottom only when the
      /// user is already at or near the bottom, so we never yank the viewport
      /// away while they are reading older messages.
      else if (after > before && _didInitialScroll) {
        if (!_scrollController.hasClients) return;
        final double distanceFromBottom =
            _scrollController.position.maxScrollExtent -
            _scrollController.offset;
        if (distanceFromBottom < 200) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      }
    });

    // The banner shows the most recently pinned message. Derived from the
    // already-loaded list rather than a separate query, so pinning costs no
    // extra read and updates the instant the repository write lands.
    final Message? pinnedMessage = messages
        .where((Message m) => m.isPinned && !m.isDeleted)
        .fold<Message?>(
          null,
          (Message? best, Message m) =>
              best == null || m.timestamp.isAfter(best.timestamp) ? m : best,
        );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.c.bg,
      appBar: selection.isNotEmpty
          ? _SelectionAppBar(
              count: selection.length,
              messages: messages,
              onClose: () => ref.read(messageSelectionProvider.notifier).clear(),
              onDelete: () => _deleteSelected(selection),
              onStar: () => _starSelected(selection),
            )
          : AppTopBar(
              height: 62,
              leading: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                tooltip: context.l10n.back,
                color: context.c.textPrimary,
              ),
              titleWidget: chat == null
                  ? const SizedBox.shrink()
                  : _ChatHeader(
                      chat: chat,
                      onTap: () => _openChatInfo(chat),
                    ),
              actions: <Widget>[
                TopBarAction(
                  icon: Icons.videocam_rounded,
                  tooltip: context.l10n.videoCall,
                  onPressed: () => _startCall(chat, video: true),
                ),
                TopBarAction(
                  icon: Icons.call_rounded,
                  tooltip: context.l10n.voiceCall,
                  onPressed: () => _startCall(chat, video: false),
                ),
                TopBarAction(
                  icon: Icons.more_vert_rounded,
                  tooltip: context.l10n.more,
                  onPressed: () {
                    if (chat != null) _showChatMenu(chat);
                  },
                ),
              ],
            ),
      body: _ChatBackground(
        wallpaper: wallpaper,
        isDark: context.c.isDark,
        child: Column(
          children: <Widget>[
            if (pinnedMessage != null)
              _PinnedBanner(
                message: pinnedMessage,
                onTap: () => _jumpToMessage(_replyPreviewOf(pinnedMessage)),
                onUnpin: () => _togglePin(pinnedMessage),
              ),
            Expanded(
              child: messagesAsync.isLoading && messages.isEmpty
                  ? const Center(child: ILoader(size: 26))
                  : messages.isEmpty
                      ? _EmptyConversation(chat: chat)
                      : _MessageList(
                          messages: messages,
                          chat: chat,
                          controller: _scrollController,
                          animated: _animated,
                          selection: selection,
                          onTapMessage: (Message m) {
                            if (selection.isNotEmpty) {
                              ref
                                  .read(messageSelectionProvider.notifier)
                                  .toggle(m.id);
                            }
                          },
                          onDoubleTap: (Message m) =>
                              _toggleReaction(m, '❤️'),
                          onLongPress: (Message m) => _handleMessageLongPress(
                            m,
                            // ⚠️ This used to be `chat?.isGroup ?? false`, so
                            // "Delete for everyone" was offered **only in group
                            // chats** and was missing from every 1:1 chat —
                            // which is exactly the reported bug. The right
                            // question is not "is this a group" but "may *this*
                            // message be retracted": the author's own, not
                            // already deleted, and inside the one-hour window.
                            m.canDeleteForEveryone,
                          ),
                          onQuoteTap: _jumpToMessage,
                          onSwipeReply: _startReply,
                          onPollVote: (Message m, String optionId) =>
                              _vote(m, optionId),
                          onRsvp: (Message m, RsvpStatus status) =>
                              _rsvp(m, status),
                          onOpenMedia: (Message m) => _openMedia(m),
                          onOpenLocation: (Message m) => _openLocation(m),
                          onOpenContact: (Message m) =>
                              _openContactMessage(m),
                          onOpenDocument: (Message m) => _openDocument(m),
                          onSave: (Message m) => _saveAttachment(m),
                        ),
            ),
            if (chat?.isTyping ?? false)
              _TypingRow(name: chat?.title ?? ''),
            // With no resolvable chat there is nothing to send into — showing
            // the composer would invite a message that can never be delivered.
            if (_hasValidChatId)
              MessageComposer(
                chatId: widget.chatId,
                enterKeySends: chatSettings.enterKeySends,
                replyTo: _replyTo,
                editing: _editing,
                onCancelReply: () => setState(() => _replyTo = null),
                onCancelEdit: () => setState(() => _editing = null),
                onSend: _handleSend,
                onTyping: _publishTyping,
              ),
          ],
        ),
      ),
      floatingActionButton: _showScrollToBottom
          ? FloatingActionButton.small(
              onPressed: () => _scrollToBottom(),
              backgroundColor: context.c.elevated,
              foregroundColor: context.c.textPrimary,
              elevation: 2,
              child: const Icon(Icons.keyboard_arrow_down_rounded, size: 24),
            )
          : null,
    );
  }

  /// Opens the info page behind the chat header.
  ///
  /// A direct chat's [Chat.id] is the composite `uidA_uidB`, not a uid, so it
  /// can never load `users/{uid}` — that lookup misses and the profile screen
  /// reports "not found". The peer is resolved from `memberIds`, the only field
  /// that actually carries uids.
  void _openChatInfo(Chat chat) {
    if (chat.isGroup) {
      context.push('${AppRoutes.groupInfo}/${chat.id}');
      return;
    }
    final String? peerUid = chat.peerUid(ref.read(currentUidProvider));
    if (peerUid == null) {
      iToast(
        context,
        context.l10n.thisChatHasNoLinked,
        isError: true,
      );
      return;
    }
    context.push('${AppRoutes.contactInfo}/$peerUid');
  }

  /// Starts a voice or video call with the chat's peer.
  ///
  /// The `calls/{callId}` document stores `callerId` / `receiverId` as uids, so
  /// the route must carry a uid. Passing the composite chat id here would write
  /// a receiver that no account matches — the same wrong-identifier mistake that
  /// broke the profile screen.
  void _startCall(Chat? chat, {required bool video}) {
    final String? peerUid = chat?.peerUid(ref.read(currentUidProvider));
    if (peerUid == null) {
      iToast(
        context,
        (chat?.isDirect ?? false)
            ? context.l10n.thisChatHasNoOne
            : context.l10n.groupCallsAreNotAvailable,
        isError: true,
      );
      return;
    }
    final String name = chat?.title ?? 'Unknown';
    context.push(
      '${AppRoutes.call}?id=$peerUid&name=${Uri.encodeComponent(name)}&video=$video',
    );
  }

  /// Removes every selected message from **this device**, after confirming.
  ///
  /// The multi-select toolbar reaches the same repository method as the
  /// long-press menu's "Delete for me", so it is the same local-only mode and
  /// gets the same gate — worded for the plural case.
  Future<void> _deleteSelected(Set<String> ids) async {
    if (ids.isEmpty) return;
    final bool confirmed = await confirmDeleteForMe(context, count: ids.length);
    if (!confirmed || !mounted) return;
    for (final String id in ids) {
      // The chat id is known here, so each removal is one read and two writes
      // rather than a scan of every conversation on the device — which is what
      // made a large selection feel like it had hung.
      await ref
          .read(messageRepositoryProvider)
          .deleteForMe(id, chatId: widget.chatId);
    }
    ref.read(messageSelectionProvider.notifier).clear();
    if (mounted) iToast(context, context.l10n.messageSDeleted(ids.length));
  }

  Future<void> _starSelected(Set<String> ids) async {
    await ref.read(messageRepositoryProvider).starAll(ids.toList(), true);
    await ref.read(starredMessagesProvider.notifier).refresh();
    ref.read(messageSelectionProvider.notifier).clear();
    if (mounted) iToast(context, context.l10n.messageSStarred(ids.length));
  }

  Future<void> _vote(Message message, String optionId) async {
    await ref
        .read(messageRepositoryProvider)
        .votePoll(message.id, optionId, 'self');
    HapticFeedback.lightImpact();
  }

  Future<void> _rsvp(Message message, RsvpStatus status) async {
    await ref
        .read(messageRepositoryProvider)
        .setRsvp(message.id, 'self', status);
    HapticFeedback.lightImpact();
    if (mounted) {
      iToast(context, switch (status) {
        RsvpStatus.going => context.l10n.youAreGoing,
        RsvpStatus.maybe => context.l10n.markedAsMaybe,
        RsvpStatus.notGoing => context.l10n.markedAsNotGoing,
        RsvpStatus.none => context.l10n.responseCleared,
      });
    }
  }

  /// The [ReplyPreview] shape [_jumpToMessage] expects, built from a message.
  ///
  /// Lets the pinned banner reuse the existing "highlight the message" path
  /// instead of duplicating the lookup and the 1.4 s highlight animation.
  ReplyPreview _replyPreviewOf(Message message) => ReplyPreview(
        messageId: message.id,
        senderName: message.senderName,
        preview: message.content,
        type: message.type,
      );

  /// Flips the pin flag on [message] and reports the new state.
  ///
  /// [message] carries the state *before* the write, so the label inverts.
  Future<void> _togglePin(Message message) async {
    await ref.read(messageRepositoryProvider).togglePin(message.id);
    if (!mounted) return;
    iToast(
      context,
      message.isPinned ? context.l10n.unpinnedFromThisChat : context.l10n.pinnedToThisChat,
    );
  }

  /// Writes the attachment to a destination the user picks.
  ///
  /// Android's document picker owns the destination URI, so the bytes have to
  /// be handed over in memory — passing only a path is a silent no-op there.
  Future<void> _saveAttachment(Message message) async {
    final Attachment? attachment = message.attachment;
    // Read both labels before the first `await`. `context` must not be touched
    // across an async gap, and `dialogTitle:` sits in the same argument list as
    // `await source.readAsBytes()`, which the lint flags even though the label
    // is evaluated first.
    final String nothingToSave = context.l10n.thisMessageHasNothingTo;
    final String saveTitle = context.l10n.saveAttachment;
    if (attachment == null) {
      iToast(context, nothingToSave, isError: true);
      return;
    }
    try {
      // A message the *user* sent has a local file; one they received usually
      // does not — only the R2 URL. The old version refused in that case, which
      // made "save" useless on exactly the messages worth keeping. Fetch it
      // instead.
      File? source = _existingFile(attachment.localPath);
      source ??= await _downloadToCache(attachment);
      if (source == null) {
        if (!mounted) return;
        iToast(context, nothingToSave, isError: true);
        return;
      }

      final String name = attachment.fileName ??
          source.path.split(Platform.pathSeparator).last;
      final String? saved = await FilePicker.platform.saveFile(
        dialogTitle: saveTitle,
        fileName: name,
        bytes: await source.readAsBytes(),
      );
      if (!mounted || saved == null) return; // null == the user cancelled
      iToast(context, context.l10n.savedToDeviceStorage);
    } on Exception catch (e) {
      if (!mounted) return;
      iToast(context, context.l10n.couldNotSaveTheFile(e), isError: true);
    }
  }

  /// A [File] for [path] if it exists on disk, otherwise null.
  static File? _existingFile(String? path) {
    final String trimmed = (path ?? '').trim();
    if (trimmed.isEmpty) return null;
    final File file = File(trimmed);
    return file.existsSync() ? file : null;
  }

  /// Fetches a remote-only attachment into the cache directory.
  ///
  /// Returns null on any failure — no URL, no network, a non-200 — so the
  /// caller reports "nothing to save" rather than throwing mid-save.
  Future<File?> _downloadToCache(Attachment attachment) async {
    final String url = (attachment.remoteUrl ?? '').trim();
    if (url.isEmpty) return null;
    try {
      final http.Response response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        debugPrint('Attachment download returned ${response.statusCode}');
        return null;
      }
      final Directory dir = await getTemporaryDirectory();
      final String fallback =
          url.split('/').last.split('?').first;
      final String name = attachment.fileName?.trim().isNotEmpty == true
          ? attachment.fileName!.trim()
          : (fallback.isEmpty ? 'attachment' : fallback);
      final File file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } on Object catch (error) {
      debugPrint('Attachment download failed: $error');
      return null;
    }
  }

  /// Hands the message — attachment first, text otherwise — to the system
  /// share sheet.
  Future<void> _shareMessage(Message message) async {
    final Attachment? attachment = message.attachment;
    final String? path = attachment?.localPath;
    final Rect? origin = _shareOrigin();
    final String text = message.content.trim();
    try {
      if (path != null && await File(path).exists()) {
        await Share.shareXFiles(
          <XFile>[XFile(path, mimeType: attachment?.mimeType)],
          text: text.isEmpty ? null : text,
          sharePositionOrigin: origin,
        );
        return;
      }
      if (text.isEmpty) {
        if (!mounted) return;
        iToast(context, context.l10n.thisMessageHasNothingTo2, isError: true);
        return;
      }
      await Share.share(text, sharePositionOrigin: origin);
    } on Exception catch (e) {
      if (!mounted) return;
      iToast(context, context.l10n.couldNotShare(e), isError: true);
    }
  }

  /// iPad anchors the share popover to this rectangle. Android ignores it, so a
  /// null result there is harmless — but a missing anchor *crashes* on iPad.
  Rect? _shareOrigin() {
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _jumpToMessage(ReplyPreview reply) async {
    final Message? target =
        await ref.read(messageRepositoryProvider).findById(reply.messageId);
    if (target == null || !mounted) {
      if (mounted) iToast(context, context.l10n.thatMessageIsNoLonger);
      return;
    }
    ref.read(highlightedMessageProvider.notifier).state = target.id;
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    ref.read(highlightedMessageProvider.notifier).state = null;
  }

  void _openMedia(Message message) {
    final Attachment? attachment = message.attachment;
    if (attachment == null || !_hasViewableSource(message)) {
      iToast(context, context.l10n.thisMediaIsNotAvailable, isError: true);
      return;
    }

    // Every other viewable image in this conversation, so the viewer can swipe
    // between them. Videos are excluded — they get a player, not a gallery.
    final bool isVideo = message.type == MessageType.video;
    final List<Message> siblings = isVideo
        ? <Message>[message]
        : (ref.read(messagesProvider(widget.chatId)).valueOrNull ?? const <Message>[])
            .where((Message m) =>
                m.type == MessageType.image && _hasViewableSource(m))
            .toList(growable: false);
    final List<Message> images =
        siblings.isEmpty ? <Message>[message] : siblings;
    final int index = images.indexWhere((Message m) => m.id == message.id);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _MediaViewer(
          images: images,
          initialIndex: index < 0 ? 0 : index,
          onForward: () {
            Navigator.pop(context);
            _forwardMessage(message);
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  /// Whether [message] has something the viewer can actually open.
  ///
  /// A *received* image has no local path at all — only the R2 URL — so a
  /// check for `localPath != null` alone is what made tapping a received photo
  /// do nothing but toast "not available on this device".
  static bool _hasViewableSource(Message message) {
    final Attachment? a = message.attachment;
    if (a == null) return false;
    final String? local = a.localPath;
    if (local != null && local.isNotEmpty && File(local).existsSync()) return true;
    return (a.remoteUrl ?? '').trim().isNotEmpty;
  }

  Future<void> _openLocation(Message message) async {
    final Attachment? a = message.attachment;
    if (a?.latitude == null || a?.longitude == null) {
      iToast(context, context.l10n.coordinatesAreUnavailable, isError: true);
      return;
    }
    final bool opened = await ref
        .read(locationServiceProvider)
        .openInMaps(a!.latitude!, a.longitude!);
    if (!opened && mounted) {
      iToast(context, context.l10n.noMapApplicationIsInstalled, isError: true);
    }
  }

  void _openContactMessage(Message message) {
    final String name = message.attachment?.contactName ?? message.content;
    final List<Contact> contacts =
        ref.read(contactsProvider).valueOrNull ?? <Contact>[];
    final Contact? match = contacts
        .where((Contact c) => c.fullName.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (match == null) {
      iToast(context, context.l10n.thisContactIsNotIn);
      return;
    }
    context.push('${AppRoutes.contactInfo}/${match.id}');
  }

  Future<void> _openDocument(Message message) async {
    final String? path = message.attachment?.localPath;
    if (path == null) {
      iToast(context, context.l10n.thisFileIsNotAvailable, isError: true);
      return;
    }
    await ref
        .read(shareServiceProvider)
        .shareFile(path, text: message.attachment?.fileName);
  }
}

// ==========================================================================
// Header
// ==========================================================================

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.chat, required this.onTap});

  final Chat chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final String subtitle = chat.isTyping
        ? 'typing...'
        : chat.isGroup
            ? '${chat.memberCount} members'
            : chat.isOnline
                ? 'online'
                : chat.lastSeen != null
                    ? DateFormatter.lastSeen(chat.lastSeen!)
                    : 'tap for contact info';

    return InkWell(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          IAvatar(
            name: chat.title,
            imagePath: chat.avatarPath,
            imageUrl: chat.avatarUrl,
            colorSeed: chat.avatarColor,
            size: 38,
            isOnline: chat.isOnline,
            showPresence: !chat.isGroup,
            isGroup: chat.isGroup,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  chat.title,
                  style: context.t.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: context.t.labelMedium?.copyWith(
                    color: chat.isTyping ? c.accent : c.textSecondary,
                    fontStyle: chat.isTyping ? FontStyle.italic : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// App bar shown while multi-select is active.
class _SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SelectionAppBar({
    required this.count,
    required this.messages,
    required this.onClose,
    required this.onDelete,
    required this.onStar,
  });

  final int count;
  final List<Message> messages;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onStar;

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return AppBar(
      backgroundColor: c.surface,
      elevation: 0,
      toolbarHeight: 62,
      automaticallyImplyLeading: false,
      leading: IconButton(
        onPressed: onClose,
        icon: const Icon(Icons.close_rounded, size: 22),
        tooltip: context.l10n.cancelSelection,
      ),
      title: Text(context.l10n.countSelected(count), style: context.t.titleMedium),
      actions: <Widget>[
        TopBarAction(
          icon: Icons.star_border_rounded,
          tooltip: context.l10n.star,
          onPressed: onStar,
        ),
        TopBarAction(
          icon: Icons.delete_outline_rounded,
          tooltip: context.l10n.delete,
          color: context.c.onDanger,
          onPressed: onDelete,
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

// ==========================================================================
// Message list
// ==========================================================================

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.messages,
    required this.chat,
    required this.controller,
    required this.animated,
    required this.selection,
    required this.onTapMessage,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.onQuoteTap,
    required this.onSwipeReply,
    required this.onPollVote,
    required this.onRsvp,
    required this.onOpenMedia,
    required this.onOpenLocation,
    required this.onOpenContact,
    required this.onOpenDocument,
    required this.onSave,
  });

  final List<Message> messages;
  final Chat? chat;
  final ScrollController controller;
  final Set<String> animated;
  final Set<String> selection;
  final ValueChanged<Message> onTapMessage;
  final ValueChanged<Message> onDoubleTap;
  final ValueChanged<Message> onLongPress;
  final ValueChanged<ReplyPreview> onQuoteTap;
  final ValueChanged<Message> onSwipeReply;
  final void Function(Message, String) onPollVote;
  final void Function(Message, RsvpStatus) onRsvp;
  final ValueChanged<Message> onOpenMedia;
  final ValueChanged<Message> onOpenLocation;
  final ValueChanged<Message> onOpenContact;
  final ValueChanged<Message> onOpenDocument;
  final ValueChanged<Message> onSave;


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? highlighted = ref.watch(highlightedMessageProvider);

    // The message list is now the row list: the app carries no banner
    // inventory, so nothing is interleaved and a row index *is* a message
    // index. Grouping, day separators and the previous/next lookups below all
    // rely on that, which is why the previous sentinel machinery is gone
    // rather than merely unused.
    final List<int> rows = List<int>.generate(messages.length, (int i) => i);

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int row) {
        final int index = rows[row];

        final Message message = messages[index];
        final Message? previous = index > 0 ? messages[index - 1] : null;
        final Message? next =
            index < messages.length - 1 ? messages[index + 1] : null;

        final bool showDaySeparator = previous == null ||
            !_sameDay(previous.timestamp, message.timestamp);

        final bool isGrouped = !showDaySeparator &&
            previous.senderId == message.senderId &&
            previous.direction == message.direction &&
            message.timestamp.difference(previous.timestamp).inMinutes < 5 &&
            previous.type != MessageType.system &&
            message.type != MessageType.system;

        final bool isLastInGroup = next == null ||
            next.senderId != message.senderId ||
            next.direction != message.direction ||
            next.timestamp.difference(message.timestamp).inMinutes >= 5;

        final bool isSystem = message.type == MessageType.system;
        final bool isSelected = selection.contains(message.id);
        final bool isHighlighted = highlighted == message.id;

        MediaQueryData media = MediaQuery.of(context);
        final double maxWidth =
            media.size.width * AppSizes.maxBubbleWidthFactor + 40;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showDaySeparator) DaySeparator(date: message.timestamp),
            if (isSystem)
              SystemNotice(text: message.content)
            else
              Padding(
                padding: EdgeInsets.only(
                  top: isGrouped ? 1.5 : AppSpacing.sm,
                  bottom: isLastInGroup ? 1.5 : 0,
                ),
                child: Align(
                  alignment: message.isOutgoing
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: _SwipeToReply(
                      enabled: !isSystem && !message.isDeleted,
                      onReply: () => onSwipeReply(message),
                      child: _AnimatedBubble(
                        messageId: message.id,
                        animated: animated,
                        isOutgoing: message.isOutgoing,
                        child: GestureDetector(
                          onTap: () => onTapMessage(message),
                          onDoubleTap: () => onDoubleTap(message),
                          onLongPress: () => onLongPress(message),
                          child: AnimatedContainer(
                            duration: AppDurations.fast,
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.rXl,
                              color: isSelected
                                  ? context.c.accent.withValues(alpha: 0.12)
                                  : Colors.transparent,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: MessageBubble(
                              message: message,
                              showSenderName: !message.isOutgoing &&
                                  (chat?.isGroup ?? false) &&
                                  !isGrouped,
                              isHighlighted: isHighlighted,
                              isSelected: isSelected,
                              onPollVote: (String optionId) =>
                                  onPollVote(message, optionId),
                              onRsvp: (RsvpStatus status) =>
                                  onRsvp(message, status),
                              onOpenMedia: () => onOpenMedia(message),
                              onOpenLocation: () => onOpenLocation(message),
                              onOpenContact: () => onOpenContact(message),
                              onOpenDocument: () => onOpenDocument(message),
                              onSave: () => onSave(message),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// WhatsApp-style swipe-to-reply.
///
/// Dragging a bubble to the right uncovers a reply arrow. Releasing past
/// [_trigger] arms a reply and springs the bubble back; a shorter drag just
/// springs back. Only the horizontal axis is claimed here, so the vertical list
/// scroll and the bubble's own tap / double-tap / long-press keep working.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.enabled,
    required this.onReply,
    required this.child,
  });

  /// False for system notices and already-deleted bubbles, which have no reply
  /// target.
  final bool enabled;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  /// How far the bubble must travel before the reply is armed.
  static const double _trigger = 56;

  /// Hard stop, so a fast fling cannot drag the bubble off screen.
  static const double _maxDrag = 92;

  double _offset = 0;
  bool _dragging = false;

  bool get _armed => _offset >= _trigger;

  void _onUpdate(DragUpdateDetails details) {
    final double next = (_offset + details.delta.dx).clamp(0.0, _maxDrag);
    if (next == _offset) return;
    setState(() {
      _offset = next;
      _dragging = true;
    });
  }

  /// Returns the bubble to rest, firing the reply if the drag armed it.
  void _settle() {
    final bool fire = _armed;
    setState(() {
      _offset = 0;
      _dragging = false;
    });
    if (fire) {
      HapticFeedback.selectionClick();
      widget.onReply();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final double progress = (_offset / _trigger).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: (DragEndDetails _) => _settle(),
      onHorizontalDragCancel: _settle,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: <Widget>[
          Opacity(
            opacity: progress,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Icon(
                Icons.reply_rounded,
                size: 20,
                color: _armed ? context.c.accent : context.c.textSecondary,
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _offset),
            // Zero while the finger is down so the bubble tracks it exactly;
            // the spring-back on release is animated.
            duration: _dragging ? Duration.zero : AppDurations.fast,
            curve: Curves.easeOut,
            builder: (BuildContext context, double value, Widget? child) =>
                Transform.translate(offset: Offset(value, 0), child: child),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Plays the entrance animation only the first time a message is seen.
class _AnimatedBubble extends StatelessWidget {
  const _AnimatedBubble({
    required this.messageId,
    required this.animated,
    required this.isOutgoing,
    required this.child,
  });

  final String messageId;
  final Set<String> animated;
  final bool isOutgoing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animated.add(messageId)) return child;
    return BubbleEntrance(isOutgoing: isOutgoing, child: child);
  }
}

// ==========================================================================
// Chrome
// ==========================================================================

/// Renders the wallpaper behind the message list.
class _ChatBackground extends StatelessWidget {
  const _ChatBackground({
    required this.wallpaper,
    required this.isDark,
    required this.child,
  });

  final Wallpaper wallpaper;
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final List<Color> colors =
        wallpaper.colors.map((int v) => Color(v)).toList();

    Widget background;
    switch (wallpaper.kind) {
      case WallpaperKind.gradient:
        background = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.length >= 2 ? colors : <Color>[colors.first, colors.first],
            ),
          ),
        );
      case WallpaperKind.solid:
        background = ColoredBox(color: colors.first);
      case WallpaperKind.pattern:
        background = CustomPaint(
          painter: _PatternPainter(
            index: wallpaper.patternIndex,
            base: colors.first,
            accent: context.c.accent,
          ),
        );
      case WallpaperKind.image:
        background = ColoredBox(
          color: wallpaper.imagePath == null
              ? colors.first
              : context.c.bg,
        );
      case WallpaperKind.defaultPattern:
        background = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors.length >= 2
                  ? colors
                  : <Color>[context.c.bg, context.c.bg],
            ),
          ),
        );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        background,
        if (wallpaper.kind == WallpaperKind.defaultPattern && isDark)
          Opacity(
            opacity: 0.5,
            child: CustomPaint(
              painter: _FaintDoodlePainter(color: context.c.accent),
            ),
          ),
        child,
      ],
    );
  }
}

/// Subtle dotted background used by the pattern wallpapers.
class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.index,
    required this.base,
    required this.accent,
  });

  final int index;
  final Color base;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = base,
    );
    final Paint paint = Paint()..color = accent.withValues(alpha: 0.07);

    switch (index) {
      case 1: // grid
        for (double x = 0; x < size.width; x += 28) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
        }
        for (double y = 0; y < size.height; y += 28) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
        }
      case 2: // waves
        final Path path = Path();
        for (double y = 0; y < size.height; y += 34) {
          path.moveTo(0, y);
          for (double x = 0; x <= size.width; x += 24) {
            path.quadraticBezierTo(
              x + 12,
              y + 12,
              x + 24,
              y,
            );
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = accent.withValues(alpha: 0.10)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      case 3: // bubbles
        for (double y = 20; y < size.height; y += 54) {
          for (double x = 20; x < size.width; x += 54) {
            canvas.drawCircle(
              Offset(x + (y % 108 == 0 ? 10 : 0), y),
              7,
              Paint()..color = accent.withValues(alpha: 0.08),
            );
          }
        }
      default: // dots
        for (double y = 14; y < size.height; y += 22) {
          for (double x = 14; x < size.width; x += 22) {
            canvas.drawCircle(Offset(x, y), 1.4, paint);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter oldDelegate) =>
      oldDelegate.index != index || oldDelegate.base != base;
}

/// Very faint "doodle" layer for the default wallpaper.
class _FaintDoodlePainter extends CustomPainter {
  _FaintDoodlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // Deterministic little icons scattered across the background.
    for (double y = 40; y < size.height; y += 130) {
      for (double x = 30; x < size.width; x += 120) {
        final double offset = ((x + y) % 240) / 240;
        final Offset centre = Offset(x + offset * 30, y);
        canvas.drawCircle(centre, 9, paint);
        canvas.drawCircle(centre, 3.5, paint);
        final Path arc = Path()
          ..moveTo(centre.dx + 18, centre.dy - 6)
          ..quadraticBezierTo(
            centre.dx + 26,
            centre.dy + 6,
            centre.dx + 16,
            centre.dy + 12,
          );
        canvas.drawPath(arc, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FaintDoodlePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TypingRow extends StatelessWidget {
  const _TypingRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: context.c.surface,
      child: Row(
        children: <Widget>[
          const TypingIndicator(dotSize: 5, spacing: 3),
          const SizedBox(width: AppSpacing.sm),
          Text(
            context.l10n.nameIsTyping(name),
            style: context.t.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

/// The "Pinned message" strip above the conversation.
///
/// Tapping it jumps to the message (reusing the highlight animation the quote
/// replies already use); the trailing button unpins. Only the newest pin is
/// shown, which is what every messenger does — a stack of them would eat the
/// screen on a chat with many pins.
class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({
    required this.message,
    required this.onTap,
    required this.onUnpin,
  });

  final Message message;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final String preview = message.content.trim().isEmpty
        ? switch (message.type) {
            MessageType.image => 'Photo',
            MessageType.video => 'Video',
            MessageType.voice => 'Voice message',
            MessageType.audio => 'Audio',
            MessageType.document => 'Document',
            MessageType.location => 'Location',
            MessageType.contact => 'Contact',
            _ => 'Attachment',
          }
        : message.content.trim();

    return Material(
      color: c.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.accent, width: 3)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.push_pin_rounded, size: 16, color: c.accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      context.l10n.pinnedMessage,
                      style: context.t.bodySmall?.copyWith(
                        color: c.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.unpin,
                visualDensity: VisualDensity.compact,
                onPressed: onUnpin,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({this.chat});

  final Chat? chat;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.waving_hand_rounded,
      title: chat == null ? context.l10n.sayHello : context.l10n.startTheConversation,
      message: chat?.disappearingSeconds != 0
          ? context.l10n.messagesInThisChatDisappear
          : context.l10n.messagesYouSendAreStored,
      compact: true,
    );
  }
}

// ==========================================================================
// Media viewer
// ==========================================================================

/// Fullscreen viewer for an image or video attachment.
///
/// ### Images — a gallery, not a single picture
///
/// [images] is every viewable image in the conversation and [initialIndex] says
/// which one was tapped, so a horizontal swipe moves between them the way
/// WhatsApp does. `photo_view` supplies pinch-zoom and double-tap-zoom.
///
/// This replaced an `InteractiveViewer` that only ever rendered
/// `Image.file(localPath)`. A picture *received* over the network has no local
/// path — only the R2 URL — so tapping it hit `path == null` and showed
/// "Media unavailable": the reported "tapping an image does nothing".
///
/// A vertical drag closes the viewer, but only once the page is back at
/// fit-to-screen scale — a zoomed-in picture still pans instead of dismissing.
class _MediaViewer extends StatefulWidget {
  const _MediaViewer({
    required this.images,
    required this.initialIndex,
    required this.onForward,
  });

  final List<Message> images;
  final int initialIndex;
  final VoidCallback onForward;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  final PhotoViewController _photo = PhotoViewController();
  final PhotoViewScaleStateController _scaleState =
      PhotoViewScaleStateController();

  late int _index = widget.initialIndex;
  double _dragOffset = 0;
  bool _chromeVisible = true;

  @override
  void dispose() {
    _pages.dispose();
    _photo.dispose();
    _scaleState.dispose();
    super.dispose();
  }

  Message get _current =>
      widget.images[_index.clamp(0, widget.images.length - 1)];

  /// The picture to render: the local copy when there is one, the remote URL
  /// otherwise. Never throws on a missing file — a stale local path falls
  /// through to the network copy.
  ImageProvider? _providerFor(Message message) {
    final Attachment? a = message.attachment;
    if (a == null) return null;
    final String local = (a.localPath ?? '').trim();
    if (local.isNotEmpty && File(local).existsSync()) {
      return FileImage(File(local));
    }
    final String remote = (a.remoteUrl ?? '').trim();
    if (remote.isNotEmpty) return CachedNetworkImageProvider(remote);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Attachment? attachment = _current.attachment;
    final bool isVideo = _current.type == MessageType.video;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chromeVisible
          ? AppBar(
              backgroundColor: Colors.black54,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: context.l10n.close,
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                attachment?.fileName ?? (isVideo ? context.l10n.video : context.l10n.photo),
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: <Widget>[
                IconButton(
                  onPressed: widget.onForward,
                  icon: const Icon(Icons.forward_rounded),
                  tooltip: context.l10n.forward,
                ),
              ],
            )
          : null,
      body: isVideo ? _buildVideo(attachment) : _buildGallery(),
    );
  }

  Widget _buildVideo(Attachment? attachment) {
    final String local = (attachment?.localPath ?? '').trim();
    final String remote = (attachment?.remoteUrl ?? '').trim();
    final String name = (attachment?.fileName ?? '').trim();
    if (local.isNotEmpty && File(local).existsSync()) {
      return IVideoPlayer(
        localPath: local,
        autoPlay: true,
        loop: false,
        title: name.isEmpty ? null : name,
      );
    }
    if (remote.isNotEmpty) {
      return IVideoPlayer(
        remoteUrl: remote,
        autoPlay: true,
        loop: false,
        title: name.isEmpty ? null : name,
      );
    }
    return Center(
      child: Text(context.l10n.mediaUnavailable, style: TextStyle(color: Colors.white54)),
    );
  }

  Widget _buildGallery() {
    return GestureDetector(
      onTap: () => setState(() => _chromeVisible = !_chromeVisible),
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Opacity(
          opacity: (1 - (_dragOffset.abs() / 400)).clamp(0.35, 1.0),
          child: GestureDetector(
            // Claims *vertical* drags only; the gallery's own PageView keeps the
            // horizontal ones, so swiping between pictures is unaffected.
            onVerticalDragUpdate: (DragUpdateDetails d) {
              // Zoomed in: the picture pans, the viewer must not dismiss.
              if ((_photo.scale ?? 1) > 1.02) return;
              setState(() => _dragOffset += d.delta.dy);
            },
            onVerticalDragEnd: (DragEndDetails d) {
              if (_dragOffset.abs() > 110) {
                Navigator.pop(context);
                return;
              }
              setState(() => _dragOffset = 0);
            },
            child: PhotoViewGallery.builder(
              itemCount: widget.images.length,
              pageController: _pages,
              backgroundDecoration:
                  const BoxDecoration(color: Colors.transparent),
              onPageChanged: (int i) => setState(() => _index = i),
              loadingBuilder: (BuildContext context, ImageChunkEvent? event) =>
                  const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
              builder: (BuildContext context, int i) {
                final Message message = widget.images[i];
                final ImageProvider? provider = _providerFor(message);
                if (provider == null) {
                  // `builder` must return page *options*, not a widget, so the
                  // "nothing to show" case is expressed as a custom-child page
                  // rather than a plain widget return.
                  return PhotoViewGalleryPageOptions.customChild(
                    child: Center(
                      child: Text(
                        context.l10n.mediaUnavailable,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  );
                }
                final bool isCurrent = i == _index;
                return PhotoViewGalleryPageOptions(
                  imageProvider: provider,
                  heroAttributes:
                      PhotoViewHeroAttributes(tag: 'media-${message.id}'),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 4,
                  // Only the visible page gets the controllers. A
                  // [PhotoViewController] may be attached to one [PhotoView] at
                  // a time; handing the same instance to every page throws.
                  controller: isCurrent ? _photo : null,
                  scaleStateController: isCurrent ? _scaleState : null,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stack,
                  ) =>
                      Center(
                    child: Text(
                      context.l10n.thisImageCouldNotBe,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
