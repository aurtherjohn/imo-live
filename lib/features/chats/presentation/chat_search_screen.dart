import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/message.dart';
import '../../../core/models/message_parts.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../../core/utils/l10n.dart';

/// Matches the first http(s) URL in a message body.
///
/// Deliberately greedy up to whitespace rather than a full RFC 3986 parser:
/// chat clients paste bare links, and stopping at whitespace is what every
/// messenger does. Trailing punctuation is trimmed separately.
final RegExp _urlPattern = RegExp(r'https?://\S+');

/// In-chat search: text query, media filters and jump-to-message.
class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({super.key, required this.chatId, this.initialType});

  final String chatId;

  /// A [MessageType] name to pre-select, so the chat menu's "Media, links and
  /// docs" entry lands on real content instead of the "pick a filter" empty
  /// state. Unknown or absent values leave the filter unset.
  final String? initialType;

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final TextEditingController _query = TextEditingController();
  MessageType? _typeFilter;
  String _senderFilter = 'all';

  @override
  void initState() {
    super.initState();
    final String? requested = widget.initialType;
    if (requested != null) {
      for (final MessageType type in MessageType.values) {
        if (type.name == requested) {
          _typeFilter = type;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Highlights [message] in the conversation and returns to it.
  ///
  /// The chat screen renders the highlighted message with a visible marker, so
  /// this is real feedback rather than a claim. It deliberately does **not**
  /// claim to scroll: the message list is a plain `ListView.builder` with no
  /// per-message keys, so there is no way to scroll to an arbitrary index
  /// without guessing bubble heights. Highlighting is what can be done
  /// correctly; a false "jumped" toast is what this replaces.
  void _jumpTo(Message message) {
    ref.read(highlightedMessageProvider.notifier).state = message.id;
    context.pop();
  }

  /// Opens the first URL in a message body with the system browser.
  Future<void> _openLink(Message message) async {
    final RegExpMatch? match = _urlPattern.firstMatch(message.content);
    final String? raw = match?.group(0);
    if (raw == null) {
      iToast(context, context.l10n.noLinkFoundInThat, isError: true);
      return;
    }
    // Chat bodies routinely end a link with sentence punctuation; it is not
    // part of the address and some servers reject it.
    final String trimmed = raw.replaceAll(RegExp(r'[),.;:!?]+$'), '');
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null) {
      iToast(context, context.l10n.thatLinkIsNotValid, isError: true);
      return;
    }
    await _launch(uri);
  }

  Future<void> _launch(Uri uri) async {
    final bool opened =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      iToast(context, context.l10n.noBrowserOnThisDevice,
          isError: true);
    }
  }

  /// Shows one media message full screen.
  ///
  /// Local attachments render from disk; anything that only has a remote URL
  /// renders over the network. A message with neither is not openable, and says
  /// so instead of showing an empty black screen.
  void _openMedia(Message message) {
    final Attachment? attachment = message.attachment;
    final String? local = attachment?.localPath;
    final String? remote = attachment?.remoteUrl;
    if (local == null && remote == null) {
      iToast(context, context.l10n.thisAttachmentIsNotAvailable,
          isError: true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => _SearchMediaViewer(
          localPath: local,
          remoteUrl: remote,
          title: message.type.name,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Message> all =
        ref.watch(messagesProvider(widget.chatId)).orEmpty;
    final Chat? chat =
        ref.watch(chatsProvider).orEmpty.where((Chat c) => c.id == widget.chatId).firstOrNull;

    final String q = _query.text.trim().toLowerCase();

    List<Message> results = all.where((Message m) {
      if (m.isDeleted) return false;
      if (_typeFilter != null && m.type != _typeFilter) return false;
      if (_senderFilter == 'me' && m.direction != MessageDirection.outgoing) {
        return false;
      }
      if (_senderFilter == 'them' &&
          m.direction != MessageDirection.incoming) {
        return false;
      }
      if (q.isEmpty) return _typeFilter != null || _senderFilter != 'all';
      return m.content.toLowerCase().contains(q);
    }).toList()
      ..sort((Message a, Message b) =>
          (b.timestamp).compareTo(a.timestamp));

    final List<Message> mediaResults = results
        .where((Message m) =>
            m.type == MessageType.image ||
            m.type == MessageType.video ||
            m.type == MessageType.document)
        .toList();

    final List<Message> linkResults = results
        .where((Message m) =>
            m.content.contains('http://') || m.content.contains('https://'))
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          cursorColor: context.c.accent,
          style: context.t.bodyLarge,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: context.l10n.searchTitle(chat?.title ?? context.l10n.thisChat),
            hintStyle: context.t.bodyLarge?.copyWith(
              color: context.c.textSecondary,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: <Widget>[
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: context.l10n.clear,
              onPressed: () => setState(_query.clear),
              icon: const Icon(Icons.close_rounded),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              children: <Widget>[
                _FilterChip(
                  label: context.l10n.filterAll,
                  selected: _typeFilter == null,
                  onTap: () => setState(() => _typeFilter = null),
                ),
                const SizedBox(width: AppSpacing.sm),
                for (final ({MessageType type, String label}) entry
                    in <({MessageType type, String label})>[
        (type: MessageType.image, label: context.l10n.photos),
                  (type: MessageType.video, label: context.l10n.videos),
                  (type: MessageType.document, label: context.l10n.docs),
                  (type: MessageType.audio, label: context.l10n.audio),
                  (type: MessageType.voice, label: context.l10n.voice),
                  (type: MessageType.location, label: context.l10n.location),
                  (type: MessageType.contact, label: context.l10n.tabContacts),
                  (type: MessageType.poll, label: context.l10n.polls),
                  (type: MessageType.event, label: context.l10n.events),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _FilterChip(
                      label: entry.label,
                      selected: _typeFilter == entry.type,
                      onTap: () => setState(() => _typeFilter = entry.type),
                    ),
                  ),
                _FilterChip(
                  label: context.l10n.fromMe,
                  selected: _senderFilter == 'me',
                  onTap: () => setState(
                    () => _senderFilter = _senderFilter == 'me' ? 'all' : 'me',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  label: context.l10n.fromThem,
                  selected: _senderFilter == 'them',
                  onTap: () => setState(
                    () => _senderFilter =
                        _senderFilter == 'them' ? 'all' : 'them',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxxl),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: q.isEmpty ? context.l10n.pickAFilter : context.l10n.noMatches,
                message: q.isEmpty
                    ? context.l10n.chooseAMessageTypeOr
                    : '"${_query.text.trim()}" does not appear in this chat.',
              ),
            )
          else ...<Widget>[
            SectionHeader(title: context.l10n.resultsCount(results.length)),
            for (final Message m in results)
              _ResultRow(
                message: m,
                query: q,
                onTap: () => _jumpTo(m),
              ),
          ],

          if (mediaResults.isNotEmpty) ...<Widget>[
            SectionHeader(title: context.l10n.sharedMedia),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                itemCount: mediaResults.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (BuildContext context, int i) {
                  final Message m = mediaResults[i];
                  return _MediaThumb(
                    message: m,
                    onTap: () => _openMedia(m),
                  );
                },
              ),
            ),
          ],

          if (linkResults.isNotEmpty) ...<Widget>[
            SectionHeader(title: context.l10n.links(linkResults.length)),
            for (final Message m in linkResults)
              SettingsTile(
                title: TextUtils.truncate(m.content, 70),
                subtitle: DateFormatter.chatTimestamp(m.timestamp),
                leadingIcon: Icons.link_rounded,
                leadingIconColor: context.c.accent,
                dense: true,
                onTap: () => _openLink(m),
              ),
          ],
        ],
      ),
    );
  }

}

/// Icon for a message type, used as the fallback tile for media that has no
/// local file and no remote URL to render.
IconData _iconForType(MessageType type) {
  switch (type) {
    case MessageType.image:
      return Icons.image_outlined;
    case MessageType.video:
      return Icons.videocam_outlined;
    case MessageType.document:
      return Icons.description_outlined;
    case MessageType.audio:
      return Icons.audiotrack_outlined;
    case MessageType.voice:
      return Icons.mic_none_rounded;
    case MessageType.location:
      return Icons.location_on_outlined;
    case MessageType.contact:
      return Icons.person_outline_rounded;
    case MessageType.poll:
      return Icons.poll_outlined;
    case MessageType.event:
      return Icons.event_outlined;
    case MessageType.sticker:
      return Icons.emoji_emotions_outlined;
    case MessageType.text:
      return Icons.chat_bubble_outline_rounded;
    case MessageType.system:
      return Icons.info_outline_rounded;
    case MessageType.gift:
      return Icons.card_giftcard_rounded;
  }
}

/// One tappable tile in the "Shared media" strip.
///
/// Shows the real thumbnail when one is available — a local file for media this
/// device sent, or the remote URL for media received — and falls back to a type
/// icon only when neither exists. The previous version always drew the icon, so
/// the strip was decorative and did nothing when tapped.
class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.message, required this.onTap});

  final Message message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Attachment? attachment = message.attachment;
    final String? local = attachment?.localPath;
    final String? remote = attachment?.remoteUrl;
    final bool isImage = message.type == MessageType.image;

    Widget content;
    if (isImage && local != null) {
      content = Image.file(
        File(local),
        fit: BoxFit.cover,
        errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
            _fallback(context),
      );
    } else if (isImage && remote != null) {
      content = CachedNetworkImage(
        imageUrl: remote,
        fit: BoxFit.cover,
        placeholder: (BuildContext _, String _) => _fallback(context),
        errorWidget: (BuildContext _, String _, Object _) => _fallback(context),
      );
    } else {
      content = _fallback(context);
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadius.rSm,
        child: SizedBox(
          width: 84,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              content,
              if (message.type == MessageType.video ||
                  message.type == MessageType.document)
                Center(
                  child: Icon(
                    message.type == MessageType.video
                        ? Icons.play_circle_fill_rounded
                        : Icons.open_in_new_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) => Container(
        color: context.c.surfaceAlt,
        alignment: Alignment.center,
        child: Icon(
          _iconForType(message.type),
          color: context.c.textSecondary,
        ),
      );
}

/// Full-screen viewer for a media message opened from search.
class _SearchMediaViewer extends StatelessWidget {
  const _SearchMediaViewer({
    this.localPath,
    this.remoteUrl,
    required this.title,
  });

  final String? localPath;
  final String? remoteUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: localPath != null
              ? Image.file(
                  File(localPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                      Text(
                    context.l10n.thisFileIsNoLonger,
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: remoteUrl ?? '',
                  fit: BoxFit.contain,
                  placeholder: (BuildContext _, String _) =>
                      const Center(child: ILoader(size: 26)),
                  errorWidget: (BuildContext _, String _, Object _) =>
                      Text(
                    context.l10n.couldNotLoadThisAttachment,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? context.c.textOnAccent : context.c.textPrimary,
      ),
      selectedColor: context.c.accent,
      backgroundColor: context.c.surfaceAlt,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.message,
    required this.query,
    required this.onTap,
  });

  final Message message;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String body = message.content.isEmpty
        ? '[${message.type.name}]'
        : message.content;

    return SettingsTile(
      title: TextUtils.truncate(body, 80),
      subtitle: '${message.isOutgoing ? 'You' : 'Them'} · '
          '${DateFormatter.chatTimestamp(message.timestamp)}',
      leading: IAvatar(
        name: message.senderName.isEmpty ? 'User' : message.senderName,
        size: AppSizes.avatarSm,
      ),
      trailing: message.isStarred
          ? Icon(Icons.star_rounded,
              size: AppIconSizes.sm, color: context.c.onWarning)
          : null,
      onTap: onTap,
    );
  }
}
