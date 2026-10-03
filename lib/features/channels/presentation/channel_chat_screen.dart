import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/channel_models.dart';
import '../../../core/models/group.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../earn/presentation/providers.dart';
import '../../../core/utils/l10n.dart';
import '../../../core/services/channel_service.dart';
import 'providers.dart';
import 'widgets/channel_media.dart';
import 'widgets/channel_post_card.dart';

/// A channel, presented as a conversation.
///
/// ### Why this screen exists
///
/// A channel used to be a read-only feed with a separate "Post" composer, which
/// made it a different *kind* of thing from every other row in the chat list.
/// The directive asks for the WhatsApp/Telegram model: a channel is a
/// conversation you happen to be unable to speak in. So this reuses the chat
/// screen's shape — header, message list, composer — and the only difference is
/// who may send.
///
/// ### Admin and visitor are the same screen
///
/// Not two screens with a shared base: the *only* differences are whether the
/// composer is shown and whether destructive actions appear on long-press.
/// Splitting them would duplicate the header, the list, the reactions and the
/// media handling, and those would drift.
class ChannelChatScreen extends ConsumerStatefulWidget {
  const ChannelChatScreen({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<ChannelChatScreen> createState() => _ChannelChatScreenState();
}

class _ChannelChatScreenState extends ConsumerState<ChannelChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  /// Guards the read-marker write so a rebuild does not spam Firestore.
  bool _markedRead = false;

  @override
  void initState() {
    super.initState();
    // Opening the channel is what marks it read, so this belongs to the
    // screen's lifetime rather than to a build. Deferred to after the first
    // frame because it touches a provider, which must not happen mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final String uid =
          ref.read(authStateProvider).valueOrNull?.uid ?? '';
      _markReadIfNeeded(widget.channelId, uid);
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Channel?> channelAsync =
        ref.watch(channelDocProvider(widget.channelId));

    return channelAsync.when(
      loading: () => const Scaffold(
        body: Center(child: ILoader()),
      ),
      error: (Object error, StackTrace _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              context.l10n.couldNotLoadThisChannel,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium,
            ),
          ),
        ),
      ),
      data: (Channel? channel) {
        if (channel == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(
                context.l10n.channelNotFound,
                style: context.t.bodyMedium,
              ),
            ),
          );
        }
        return _Body(
          channel: channel,
          composer: _composer,
          scroll: _scroll,
          sending: _sending,
          onSend: _send,
          onSendMedia: _sendMedia,
        );
      },
    );
  }

  /// Marks the channel read once per visit.
  void _markReadIfNeeded(String channelId, String uid) {
    if (_markedRead || uid.isEmpty) return;
    _markedRead = true;
    // Fire-and-forget: a failed read-marker leaves a badge on, which is
    // cosmetic and self-corrects on the next visit.
    unawaited(ref.read(channelFirestoreProvider).markChannelRead(channelId, uid));
  }

  /// Publishes a text post.
  ///
  /// Writes to the same `channels/{id}/posts` collection the feed always used,
  /// so an existing follower's history is untouched; what changed is only that
  /// the *entry point* is a chat composer rather than a feed form.
  Future<void> _send() async {
    final String text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    final String uid = ref.read(currentUidProvider);
    final Channel? channel =
        ref.read(channelDocProvider(widget.channelId)).valueOrNull;
    if (channel == null || uid.isEmpty) return;

    setState(() => _sending = true);
    final String? id =
        await ref.read(channelFirestoreProvider).addPost(
              channelId: widget.channelId,
              authorId: uid,
              authorName: channel.name,
              text: text,
            );
    if (!mounted) return;
    setState(() => _sending = false);

    if (id == null) {
      iToast(context, context.l10n.couldNotPublishThePost, isError: true);
      return;
    }
    _composer.clear();
    // The channel post interstitial placement, unchanged from the feed flow.
    unawaited(
      ref.read(adServiceProvider).noteAndMaybeShow(AdTrigger.channelPost),
    );
    _scrollToTop();
  }

  /// Publishes a post carrying media.
  Future<void> _sendMedia({
    required String url,
    required String type,
    String name = '',
  }) async {
    final Channel? channel =
        ref.read(channelDocProvider(widget.channelId)).valueOrNull;
    final String uid = ref.read(currentUidProvider);
    if (channel == null || uid.isEmpty) return;

    final String? id =
        await ref.read(channelFirestoreProvider).addPost(
              channelId: widget.channelId,
              authorId: uid,
              authorName: channel.name,
              text: '',
              mediaUrl: url,
              mediaType: type,
              mediaName: name,
            );
    if (!mounted) return;
    if (id == null) {
      iToast(context, context.l10n.couldNotPublishThePost, isError: true);
      return;
    }
    unawaited(
      ref.read(adServiceProvider).noteAndMaybeShow(AdTrigger.channelPost),
    );
    _scrollToTop();
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

/// The loaded channel: header, posts, and the composer (admins only).
class _Body extends ConsumerWidget {
  const _Body({
    required this.channel,
    required this.composer,
    required this.scroll,
    required this.sending,
    required this.onSend,
    required this.onSendMedia,
  });

  final Channel channel;
  final TextEditingController composer;
  final ScrollController scroll;
  final bool sending;
  final Future<void> Function() onSend;
  final Future<void> Function({
    required String url,
    required String type,
    String name,
  }) onSendMedia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColorScheme c = context.c;
    final String uid = ref.watch(currentUidProvider);
    final bool isOwner = uid.isNotEmpty && channel.ownerId == uid;
    final AsyncValue<List<ChannelPost>> posts =
        ref.watch(channelPostsProvider(channel.id));

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: <Widget>[
          _ChannelHeader(channel: channel, isOwner: isOwner),
          Expanded(
            child: posts.when(
              loading: () => const Center(child: ILoader()),
              error: (Object error, StackTrace _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    context.l10n.couldNotLoadPosts,
                    textAlign: TextAlign.center,
                    style: context.t.bodyMedium
                        ?.copyWith(color: c.textSecondary),
                  ),
                ),
              ),
              data: (List<ChannelPost> list) {
                if (list.isEmpty) {
                  return _EmptyChannel(isOwner: isOwner);
                }
                return RefreshIndicator(
                  color: c.accent,
                  backgroundColor: c.card,
                  onRefresh: () async =>
                      ref.invalidate(channelPostsProvider(channel.id)),
                  child: ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.lg,
                    ),
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int i) {
                      final ChannelPost post = list[i];
                      return ChannelPostCard(
                        key: ValueKey<String>(post.id),
                        post: post,
                        canManage: isOwner,
                        onReact: (ChannelReactionKind kind) async {
                          await ref
                              .read(channelFirestoreProvider)
                              .reactToPost(
                                channelId: channel.id,
                                postId: post.id,
                                uid: uid,
                                kind: kind,
                              );
                        },
                        onDelete: () => _confirmDelete(context, ref, post),
                        onOpenMedia: () => openChannelPostMedia(context, post),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (isOwner)
            _ChannelComposer(
              channelId: channel.id,
              controller: composer,
              sending: sending,
              onSend: onSend,
              onSendMedia: onSendMedia,
            )
          else
            _VisitorNotice(),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ChannelPost post,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.deleteThisPost),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(channelFirestoreProvider)
        .deletePost(channel.id, post.id);
  }

}

/// The channel header: avatar, name, follower count, admin badge.
class _ChannelHeader extends ConsumerWidget {
  const _ChannelHeader({required this.channel, required this.isOwner});

  final Channel channel;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColorScheme c = context.c;

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(
          bottom: BorderSide(color: c.divider.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: c.textPrimary,
                tooltip: context.l10n.back,
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/chats');
                  }
                },
              ),
              IAvatar(
                name: channel.name,
                imagePath: channel.avatarPath,
                imageUrl: channel.avatarUrl,
                colorSeed: channel.avatarColor,
                size: AppSizes.avatarSm + 4,
                isGroup: true,
                icon: Icons.campaign_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isOwner) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          _AdminBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Subscriber count, which is what a channel header shows
                      // instead of "online"/"typing".
                      context.l10n.nSubscribers(channel.followerCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall
                          ?.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline_rounded),
                color: c.textSecondary,
                tooltip: context.l10n.channelInfo,
                onPressed: () =>
                    context.push('/channel/${channel.id}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Admin" chip next to an owner's channel name.
class _AdminBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        context.l10n.admin,
        style: context.t.labelSmall?.copyWith(
          color: c.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The notice a non-admin sees where the composer would be.
class _VisitorNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.card,
        border: Border(
          top: BorderSide(color: c.divider.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 15,
                color: c.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  context.l10n.onlyAdminsCanSendMessages,
                  textAlign: TextAlign.center,
                  style: context.t.bodySmall
                      ?.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The composer an owner posts from.
class _ChannelComposer extends StatefulWidget {
  const _ChannelComposer({
    required this.channelId,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onSendMedia,
  });

  final String channelId;
  final TextEditingController controller;
  final bool sending;
  final Future<void> Function() onSend;
  final Future<void> Function({
    required String url,
    required String type,
    String name,
  }) onSendMedia;

  @override
  State<_ChannelComposer> createState() => _ChannelComposerState();
}

class _ChannelComposerState extends State<_ChannelComposer> {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final bool canSend = widget.controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(
          top: BorderSide(color: c.divider.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  style: context.t.bodyMedium,
                  decoration: InputDecoration(
                    hintText: context.l10n.writeAPost,
                    isDense: true,
                    filled: true,
                    fillColor: c.bg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SendButton(
                enabled: canSend && !widget.sending,
                sending: widget.sending,
                onTap: widget.onSend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round send control, matching the chat composer's.
class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final Future<void> Function() onTap;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  Future<void> _handle() async {
    if (!widget.enabled) return;
    // The pop runs alongside the send, not after it: waiting for Firestore
    // would make the button feel unresponsive.
    unawaited(_pop.forward().then((_) => _pop.reverse()));
    await widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Color fill =
        widget.enabled ? c.accent : c.accent.withValues(alpha: 0.35);

    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 1.15).animate(
        CurvedAnimation(parent: _pop, curve: Curves.easeOut),
      ),
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.enabled ? _handle : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: widget.sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.send_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}

/// What a channel with no posts shows.
class _EmptyChannel extends StatelessWidget {
  const _EmptyChannel({required this.isOwner});

  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.campaign_outlined,
              size: 56,
              color: c.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isOwner
                  ? context.l10n.noPostsYet
                  : context.l10n.noPostsYet,
              style: context.t.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isOwner
                  ? context.l10n.writeYourFirstPost
                  : context.l10n.nothingHasBeenPostedYet,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
