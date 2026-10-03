import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/channel_models.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/group.dart';
import '../../../core/services/channel_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../earn/presentation/providers.dart';
import '../../earn/presentation/widgets/gift_sheet.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import 'widgets/channel_media.dart';
import 'channel_analytics_screen.dart';
import 'channel_join_requests_screen.dart';
import 'channel_settings_screen.dart';
import 'providers.dart';
import 'widgets/channel_post_card.dart';
import '../../../core/utils/l10n.dart';

/// A single channel: header, post feed, follow state and owner controls.
///
/// The channel document is read live from Firestore, so an edit made on another
/// device appears here without a refresh. When Firebase is unavailable the
/// local Hive mirror is used instead, which is what keeps a channel created
/// offline openable.
class ChannelScreen extends ConsumerWidget {
  const ChannelScreen({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Channel?> remote =
        ref.watch(channelDocProvider(channelId));
    final Channel? local =
        ref.watch(channelByIdProvider(channelId)).valueOrNull;
    final Channel? channel = remote.valueOrNull ?? local;

    if (channel == null) {
      if (remote.isLoading && local == null) {
        return const Scaffold(body: Center(child: ILoader(size: 26)));
      }
      return Scaffold(
        appBar: AppTopBar(title: context.l10n.channel, showBack: true),
        body: EmptyState(
          icon: Icons.podcasts_outlined,
          title: context.l10n.channelNotFound,
          message:
              context.l10n.itIsNotOnThis2,
        ),
      );
    }

    return _Body(channel: channel);
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.channel});

  final Channel channel;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final Set<String> _countedViews = <String>{};

  String get _uid => ref.read(channelViewerUidProvider);

  /// The creator of a legacy local-only channel has an empty ownerId; on this
  /// device that user *is* the owner, so treat it as owner rather than locking
  /// them out of their own channel.
  bool get _isOwner =>
      widget.channel.ownerId.isEmpty || widget.channel.ownerId == _uid;

  @override
  Widget build(BuildContext context) {
    final Channel channel = widget.channel;
    final AppColorScheme c = context.c;
    final AsyncValue<List<ChannelPost>> posts =
        ref.watch(channelPostsProvider(channel.id));
    final Map<String, ChannelReactionKind> myReactions =
        ref.watch(myChannelReactionsProvider).valueOrNull ??
            <String, ChannelReactionKind>{};

    // One impression per post per session — this is the "reach" series the
    // analytics dashboard plots. Scheduled after the frame so a build never
    // awaits a network write, and guarded by [_countedViews] so a rebuild
    // cannot inflate the count.
    if (posts.hasValue) {
      for (final ChannelPost post in posts.requireValue) {
        if (_countedViews.add(post.id)) {
          WidgetsBinding.instance.addPostFrameCallback((Duration _) {
            ref
                .read(channelFirestoreProvider)
                .recordPostView(channel.id, post.id);
          });
        }
      }
    }

    // A private channel is readable by its owner and its approved followers.
    final bool membership =
        ref.watch(channelMembershipProvider(channel.id)).valueOrNull ?? false;
    final bool locked = channel.isPrivate && !_isOwner && !membership;

    // A premium channel is open to any premium member — there is no key and no
    // approval step, so the only question is whether the viewer has premium.
    final bool premiumLocked =
        channel.isPremiumOnly && !_isOwner && !ref.watch(isPremiumProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(channel.name),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.channelActions,
            onPressed: () => _actions(context),
            icon: const Icon(Icons.more_vert_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        color: c.accent,
        backgroundColor: c.surface,
        onRefresh: () async => ref.invalidate(channelPostsProvider(channel.id)),
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
          children: <Widget>[
            _Header(channel: channel, isOwner: _isOwner),
            if (locked)
              _LockedPanel(channel: channel)
            else if (premiumLocked)
              const _PremiumPanel()
            else
              _Feed(
                posts: posts,
                myReactions: myReactions,
                isOwner: _isOwner,
                onReact: _react,
                onDelete: _delete,
                onOpenMedia: _openPostMedia,
              ),
            _MonetizationPanel(
              channel: channel,
              isOwner: _isOwner,
              // Summed from the posts already loaded for the feed rather than a
              // separate counter on the channel document — the per-post
              // `viewCount` is the number the analytics screen already shows,
              // and two sources for one figure is how they drift apart.
              totalViews: posts.valueOrNull?.fold<int>(
                    0,
                    (int sum, ChannelPost p) => sum + p.viewCount,
                  ) ??
                  0,
            ),
            _OwnerTools(channel: channel, isOwner: _isOwner),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- actions

  Future<void> _react(ChannelPost post, ChannelReactionKind kind) async {
    await ref.read(channelFirestoreProvider).reactToPost(
          channelId: widget.channel.id,
          postId: post.id,
          uid: _uid,
          kind: kind,
        );
  }

  Future<void> _delete(ChannelPost post) async {
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.deleteThisPost,
      message: context.l10n.itDisappearsForEveryFollower,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!ok) return;
    await ref
        .read(channelFirestoreProvider)
        .deletePost(widget.channel.id, post.id);
    if (!mounted) return;
    iToast(context, context.l10n.postDeleted);
  }

  /// Opens a post's attachment.
  ///
  /// Images get an in-app pinch-zoom viewer, which needs no extra dependency.
  /// Video and file posts are handed to whichever installed app can play or
  /// open them: bundling a video player to satisfy a feature that only has to
  /// *work* would add roughly 10 MB of native code to every APK, and the
  /// system player already handles every format the uploader might send.
  /// Opens the post's media.
  ///
  /// Delegates to the shared opener so the feed and the conversation view
  /// cannot drift apart on how a video or document is handed off.
  Future<void> _openPostMedia(ChannelPost post) async {
    await openChannelPostMedia(context, post);
  }

  Future<void> _toggleFollow() async {
    final Channel channel = widget.channel;
    final bool following = !channel.isFollowing;
    await ref.read(channelFirestoreProvider).setFollowing(
          channelId: channel.id,
          uid: _uid,
          following: following,
        );
    // Mirror locally so the follow state survives without a round-trip.
    await ref
        .read(channelsProvider.notifier)
        .persist(channel.copyWith(isFollowing: following));
    if (!mounted) return;
    iToast(
      context,
      following ? 'Following ${channel.name}' : 'Unfollowed ${channel.name}',
    );
  }

  Future<void> _requestJoin() async {
    final Contact me = ref.read(selfProfileProvider).valueOrNull ??
        const Contact(id: 'self', firstName: 'You');
    await ref.read(channelFirestoreProvider).requestJoin(
          channelId: widget.channel.id,
          uid: _uid,
          name: me.fullName,
          username: '',
          message: '',
        );
    if (!mounted) return;
    iToast(context, context.l10n.requestSentTheOwnerWill);
  }

  /// Sends a points gift to the channel's owner.
  ///
  /// Followers cannot post into a channel — only the owner can — so a gift is
  /// delivered as a notification to the owner rather than as a post. That is
  /// also why the amount is not shown in the feed: a channel has one author, and
  /// a gift from a reader would look like a post by them.
  Future<void> _sendGift() async {
    final GiftReceipt? receipt = await showGiftSheet(
      context,
      toUid: widget.channel.ownerId,
      toName: widget.channel.name,
      channelId: widget.channel.id,
    );
    if (receipt == null || !receipt.result.success || !mounted) return;
    iToast(context, receipt.result.message);
  }

  void _actions(BuildContext context) {
    showActionSheet(
      context,
      title: widget.channel.name,
      actions: <({IconData icon, String label, VoidCallback onTap, Color? color})>[
        // Posting lives in the conversation view now. This screen is the
        // management feed — analytics, settings, the feed itself — and the
        // composer moved to `ChannelChatScreen` so there is one place to post
        // from rather than two that drift.
        if (_isOwner)
          (
            icon: Icons.edit_rounded,
            label: context.l10n.postToYourChannel,
            onTap: () {
              Navigator.pop(context);
              context.push('${AppRoutes.channelChat}/${widget.channel.id}');
            },
            color: null,
          ),
        (
          icon: Icons.insights_rounded,
          label: context.l10n.analytics,
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) =>
                    ChannelAnalyticsScreen(channelId: widget.channel.id),
              ),
            );
          },
          color: null,
        ),
        // A follower's way to support the channel. Hidden on your own channel,
        // where there is nobody to send to.
        if (widget.channel.ownerId.isNotEmpty &&
            widget.channel.ownerId != _uid)
          (
            icon: Icons.card_giftcard_rounded,
            label: context.l10n.sendGiftToOwner,
            onTap: () {
              Navigator.pop(context);
              unawaited(_sendGift());
            },
            color: null,
          ),
        if (_isOwner)
          (
            icon: Icons.settings_outlined,
            label: context.l10n.channelSettings,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) =>
                      ChannelSettingsScreen(channel: widget.channel),
                ),
              );
            },
            color: null,
          ),
        (
          icon: Icons.link_rounded,
          label: context.l10n.copyInviteLink,
          onTap: () async {
            Navigator.pop(context);
            await Clipboard.setData(
              ClipboardData(text: 'imo://channel/${widget.channel.inviteCode}'),
            );
            if (!context.mounted) return;
            iToast(context, context.l10n.inviteLinkCopied);
          },
          color: null,
        ),
        (
          icon: Icons.qr_code_rounded,
          label: context.l10n.showQRCode,
          onTap: () {
            Navigator.pop(context);
            final String payload =
                'imo://channel/${widget.channel.inviteCode}';
            context.push(
              '${AppRoutes.qr}?title=${Uri.encodeComponent(widget.channel.name)}'
              '&payload=${Uri.encodeComponent(payload)}',
            );
          },
          color: null,
        ),
      ],
    );
  }
}

/// Cover, avatar, name, handle and the follow button.
class _Header extends ConsumerWidget {
  const _Header({required this.channel, required this.isOwner});

  final Channel channel;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColorScheme c = context.c;
    final String? cover = channel.coverUrl;

    return Column(
      children: <Widget>[
        if (cover != null && cover.isNotEmpty)
          SizedBox(
            height: 132,
            width: double.infinity,
            child: Image.network(
              cover,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                  Container(color: c.surfaceAlt),
            ),
          ),
        Transform.translate(
          offset: Offset(0, cover == null || cover.isEmpty ? 0 : -34),
          child: Column(
            children: <Widget>[
              IAvatar(
                name: channel.name,
                imagePath: channel.avatarPath,
                imageUrl: channel.avatarUrl,
                colorSeed: channel.avatarColor,
                size: AppSizes.avatarXl,
                icon: Icons.podcasts_rounded,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                channel.name,
                textAlign: TextAlign.center,
                style: context.t.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (channel.handle.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  channel.handle,
                  style: context.t.bodyMedium?.copyWith(color: c.accent),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (!channel.isPublic)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 13,
                        color: c.textSecondary,
                      ),
                    ),
                  Text(
                    context.l10n.followers2(channel.category, TextUtils.compactCount(channel.followerCount)),
                    style: context.t.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  if (channel.isMonetized) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    IPill(
                      label: context.l10n.monetized,
                      icon: Icons.verified_rounded,
                      color: c.accent,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                child: ProminentButton(
                  label: channel.isFollowing ? context.l10n.following : 'Follow channel',
                  icon: channel.isFollowing
                      ? Icons.check_rounded
                      : Icons.add_rounded,
                  expanded: true,
                  onPressed: () => context
                      .findAncestorStateOfType<_BodyState>()
                      ?._toggleFollow(),
                ),
              ),
              if (channel.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                  child: Text(
                    channel.description,
                    textAlign: TextAlign.center,
                    style: context.t.bodyMedium?.copyWith(
                      color: c.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The preview shown when a private channel has not granted access.
class _LockedPanel extends ConsumerWidget {
  const _LockedPanel({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColorScheme c = context.c;
    final _BodyState? state = context.findAncestorStateOfType<_BodyState>();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ICard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, size: 34, color: c.textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.thisChannelIsPrivate,
              style: context.t.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l10n.postsAreOnlyVisibleTo2,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            ProminentButton(
              label: context.l10n.requestToJoin,
              icon: Icons.how_to_reg_rounded,
              expanded: true,
              onPressed: () => state?._requestJoin(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown to a non-premium viewer on a premium channel.
///
/// Unlike [_LockedPanel] there is nothing to request — the answer is to buy
/// premium, so the call to action goes to the Earn screen where that is done.
class _PremiumPanel extends StatelessWidget {
  const _PremiumPanel();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ICard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.workspace_premium_rounded,
              size: 34,
              color: context.c.onWarning,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.premiumChannel,
              style: context.t.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l10n.thisChannelIsReservedFor2,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            ProminentButton(
              label: context.l10n.getPremium,
              icon: Icons.stars_rounded,
              expanded: true,
              onPressed: () => context.push(AppRoutes.earn),
            ),
          ],
        ),
      ),
    );
  }
}

/// The post feed, with an empty state that explains who can post.
class _Feed extends StatelessWidget {
  const _Feed({
    required this.posts,
    required this.myReactions,
    required this.isOwner,
    required this.onReact,
    required this.onDelete,
    required this.onOpenMedia,
  });

  final AsyncValue<List<ChannelPost>> posts;
  final Map<String, ChannelReactionKind> myReactions;
  final bool isOwner;

  final void Function(ChannelPost post, ChannelReactionKind kind) onReact;
  final void Function(ChannelPost post) onDelete;
  final void Function(ChannelPost post) onOpenMedia;

  @override
  Widget build(BuildContext context) {
    return posts.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Center(child: ILoader(size: 24)),
      ),
      error: (Object e, StackTrace s) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: errorStateFor(context, e),
      ),
      data: (List<ChannelPost> list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: EmptyState(
              icon: Icons.campaign_outlined,
              title: context.l10n.noPostsYet,
              message: isOwner
                  ? 'Publish your first post above — followers will see it '
                      'instantly.'
                  : 'The owner has not posted anything yet.',
            ),
          );
        }

        final List<Widget> children = <Widget>[];
        for (int i = 0; i < list.length; i++) {
          final ChannelPost post = list[i];
          children.add(
            ChannelPostCard(
              key: ValueKey<String>(post.id),
              post: post.myReaction == null && myReactions.containsKey(post.id)
                  ? post.copyWith(myReaction: myReactions[post.id])
                  : post,
              canManage: isOwner,
              onReact: (ChannelReactionKind kind) => onReact(post, kind),
              onDelete: () => onDelete(post),
              onOpenMedia: () => onOpenMedia(post),
            ),
          );
        }
        return Column(children: children);
      },
    );
  }
}

/// The channel's monetization status, requirements and estimated earnings.
///
/// Shown to everyone who can read the channel; the Apply control only appears
/// for the owner. Read-only for followers on purpose — the numbers describe the
/// channel, and a follower has no action to take on them.
///
/// ### Everything here is labelled an estimate, and it has to be
///
/// The app cannot know what an ad network will pay. A single confident figure
/// would be a promise the app is not in a position to keep, so the panel shows
/// a *range* and says so. The requirement thresholds, by contrast, are real:
/// they are the same constants the eligibility check uses
/// ([Channel.monetizationFollowerThreshold] and
/// [Channel.monetizationReactionThreshold]), so the progress bars cannot
/// disagree with the Apply button.
class _MonetizationPanel extends ConsumerWidget {
  const _MonetizationPanel({
    required this.channel,
    required this.isOwner,
    required this.totalViews,
  });

  final Channel channel;
  final bool isOwner;
  final int totalViews;

  /// The per-1,000-views range this app quotes. Order-of-magnitude figures for
  /// interstitial/banner inventory, not a quote.
  static const double rpmLow = 0.50;
  static const double rpmHigh = 2.00;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColorScheme c = context.c;
    final MonetizationStatus status = channel.monetizationStatus;
    final bool monetized = status == MonetizationStatus.approved;
    final int followers = channel.followerCount;
    final int reactions = channel.totalReactions;

    final double followerProgress =
        (followers / Channel.monetizationFollowerThreshold).clamp(0.0, 1.0);
    final double reactionProgress =
        (reactions / Channel.monetizationReactionThreshold).clamp(0.0, 1.0);

    final double earningsLow = (totalViews / 1000) * rpmLow;
    final double earningsHigh = (totalViews / 1000) * rpmHigh;
    final double costPerViewLow = totalViews == 0 ? 0 : earningsLow / totalViews;
    final double costPerViewHigh =
        totalViews == 0 ? 0 : earningsHigh / totalViews;

    return SettingsGroup(
      title: context.l10n.monetization,
      footer: monetized
          ? 'Estimates only. Actual revenue is settled by the ad network, not '
              'by this app, and depends on where each view came from.'
          : 'Meet both requirements, then apply. Applications are reviewed by a '
              'person — nothing is approved automatically.',
      children: <Widget>[
        SettingsValueRow(
          label: context.l10n.status,
          value: switch (status) {
            MonetizationStatus.approved => 'Enabled',
            MonetizationStatus.pending => 'Pending review',
            MonetizationStatus.rejected => 'Not approved',
            MonetizationStatus.none => channel.isEligibleForMonetization
                ? 'Eligible — not applied'
                : 'Not eligible yet',
          },
          leadingIcon:
              monetized ? Icons.verified_rounded : Icons.timelapse_rounded,
        ),
        SettingsValueRow(
          label: context.l10n.requirement,
          value: '${Channel.monetizationFollowerThreshold}+ subscribers and '
              '${Channel.monetizationReactionThreshold} reactions in 60 days',
          leadingIcon: Icons.rule_rounded,
        ),
        SettingsValueRow(
          label: context.l10n.subscribers,
          value: TextUtils.grouped(followers),
          leadingIcon: Icons.people_alt_outlined,
        ),
        _ProgressRow(
          label: context.l10n.subscriberProgress,
          value: followers,
          target: Channel.monetizationFollowerThreshold,
          progress: followerProgress,
        ),
        SettingsValueRow(
          label: context.l10n.reactions,
          value: TextUtils.grouped(reactions),
          leadingIcon: Icons.favorite_outline_rounded,
        ),
        _ProgressRow(
          label: context.l10n.reactionProgress,
          value: reactions,
          target: Channel.monetizationReactionThreshold,
          progress: reactionProgress,
        ),
        SettingsValueRow(
          label: context.l10n.estimatedRPM,
          value: '\$${rpmLow.toStringAsFixed(2)} – '
              '\$${rpmHigh.toStringAsFixed(2)} per 1,000 views',
          leadingIcon: Icons.trending_up_rounded,
        ),
        SettingsValueRow(
          label: context.l10n.views,
          value: TextUtils.grouped(totalViews),
          leadingIcon: Icons.visibility_outlined,
        ),
        SettingsValueRow(
          label: context.l10n.estimatedRevenue,
          value: '\$${earningsLow.toStringAsFixed(2)} – '
              '\$${earningsHigh.toStringAsFixed(2)}',
          leadingIcon: Icons.attach_money_rounded,
        ),
        SettingsValueRow(
          label: context.l10n.estimatedCostPerView,
          value: '\$${costPerViewHigh.toStringAsFixed(4)} – '
              '\$${costPerViewLow.toStringAsFixed(4)}',
          leadingIcon: Icons.calculate_outlined,
        ),
        if (isOwner && channel.isEligibleForMonetization)
          SettingsTile(
            title: context.l10n.applyForMonetization,
            subtitle: context.l10n.sendThisChannelForReview,
            leadingIcon: Icons.campaign_rounded,
            titleColor: c.accent,
            onTap: () async {
              final bool ok = await showConfirmDialog(
                context,
                title: context.l10n.applyForMonetization2,
                message: context.l10n.yourChannelMeetsTheRequirements2,
                confirmLabel: context.l10n.apply,
              );
              if (!ok) return;
              await ref.read(channelFirestoreProvider).applyForMonetization(
                    channel.id,
                    followersAtApply: followers,
                    reactionsAtApply: reactions,
                  );
              if (!context.mounted) return;
              iToast(context, context.l10n.applicationSentForReview);
            },
          ),
      ],
    );
  }
}

/// A labelled progress bar for one monetization requirement.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.target,
    required this.progress,
  });

  final String label;
  final int value;
  final int target;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(label, style: context.t.bodyMedium),
              ),
              Text(
                '${TextUtils.grouped(value)} / ${TextUtils.grouped(target)}',
                style: context.t.labelSmall?.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.rPill,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: c.divider,
              valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Owner-only shortcuts, shown at the foot of the channel.
class _OwnerTools extends ConsumerWidget {
  const _OwnerTools({required this.channel, required this.isOwner});

  final Channel channel;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isOwner) return const SizedBox.shrink();
    final int pending =
        ref.watch(channelJoinRequestsProvider(channel.id)).valueOrNull?.length ??
            0;

    return SettingsGroup(
      title: context.l10n.ownerTools,
      children: <Widget>[
        SettingsTile(
          title: context.l10n.analytics,
          subtitle: context.l10n.followerGrowthReachAndReactions,
          leadingIcon: Icons.insights_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) =>
                  ChannelAnalyticsScreen(channelId: channel.id),
            ),
          ),
        ),
        SettingsTile(
          title: context.l10n.channelSettings,
          subtitle: context.l10n.nameUsernameDescriptionAvatarAnd,
          leadingIcon: Icons.settings_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => ChannelSettingsScreen(channel: channel),
            ),
          ),
        ),
        if (!channel.isPublic)
          SettingsTile(
            title: context.l10n.joinRequests,
            subtitle: pending == 0
                ? 'Nobody is waiting'
                : '$pending waiting for a decision',
            leadingIcon: Icons.how_to_reg_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) =>
                    ChannelJoinRequestsScreen(channelId: channel.id),
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-screen pinch-zoom viewer for a channel image post.
///
/// Deliberately minimal: a black backdrop, the image, and a close button. The
/// only interactive behaviour a follower needs is zoom and pan, and
/// [InteractiveViewer] provides both with no extra dependency.
