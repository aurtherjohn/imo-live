import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/group.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../../core/utils/l10n.dart';
import '../../../app/app.dart';

/// Communities tab: your communities plus the channels you follow.
class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(_tab == 0 ? context.l10n.tabCommunities : context.l10n.channels),
        actions: <Widget>[
          IconButton(
            tooltip: _tab == 0 ? context.l10n.newCommunity : context.l10n.newChannel,
            onPressed: () => context.push(
              _tab == 0 ? AppRoutes.newCommunity : AppRoutes.newChannel,
            ),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _SegmentedTab(
                    label: context.l10n.tabCommunities,
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _SegmentedTab(
                    label: context.l10n.channels,
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _tab == 0 ? const _CommunitiesList() : const _ChannelsList(),
          ),
        ],
      ),
    );
  }
}

class _SegmentedTab extends StatelessWidget {
  const _SegmentedTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.rMd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? context.c.accent.withValues(alpha: 0.14)
              : context.c.surfaceAlt,
          borderRadius: AppRadius.rMd,
          border: Border.all(
            color: selected ? context.c.accent : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: context.t.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? context.c.accent : context.c.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CommunitiesList extends ConsumerWidget {
  const _CommunitiesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Community>> async = ref.watch(communitiesProvider);
    final List<Community> list = async.orEmpty;

    if (async.isLoading && list.isEmpty) {
      return const ChatListSkeleton(rows: 5);
    }

    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.groups_2_outlined,
        title: context.l10n.noCommunitiesYet,
        message:
            context.l10n.aCommunityGroupsRelatedChats2,
        actionLabel: context.l10n.newCommunity,
        onAction: () => context.push(AppRoutes.newCommunity),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      itemCount: list.length,
      separatorBuilder: (_, _) => IListDivider(
        indent: AppSizes.avatarMd + AppSpacing.lg + AppSpacing.md,
      ),
      itemBuilder: (BuildContext context, int i) {
        final Community community = list[i];
        final List<Group> groups =
            ref.watch(groupsProvider).orEmpty
                .where((Group g) => community.groupIds.contains(g.id))
                .toList();

        return ListStagger(
          index: i,
          child: SettingsTile(
            title: community.name,
            subtitle: community.description.isEmpty
                ? '${groups.length} ${groups.length == 1 ? 'group' : 'groups'} · '
                    '${TextUtils.members(community.memberIds.length)}'
                : community.description,
            leading: IAvatar(
              name: community.name,
              imagePath: community.avatarPath,
              colorSeed: community.avatarColor,
              size: AppSizes.avatarMd,
              isGroup: true,
              icon: Icons.groups_2_rounded,
            ),
            trailing: IconButton(
              tooltip: context.l10n.communityActions,
              onPressed: () => _actions(context, ref, community),
              icon: const Icon(Icons.more_vert_rounded, size: AppIconSizes.sm),
            ),
            onTap: () => context.push('${AppRoutes.community}/${community.id}'),
          ),
        );
      },
    );
  }

  void _actions(BuildContext context, WidgetRef ref, Community community) {
    showActionSheet(
      context,
      title: community.name,
      actions: <({IconData icon, String label, VoidCallback onTap, Color? color})>[
        (
          icon: Icons.info_outline_rounded,
          label: context.l10n.openCommunity,
          onTap: () {
            Navigator.pop(context);
            context.push('${AppRoutes.community}/${community.id}');
          },
          color: null,
        ),
        (
          icon: Icons.delete_outline_rounded,
          label: context.l10n.deleteCommunity,
          onTap: () async {
            Navigator.pop(context);
            final bool ok = await showConfirmDialog(
              context,
              title: context.l10n.delete3(community.name),
              message:
                  context.l10n.theCommunityAndItsAnnouncement2,
              confirmLabel: context.l10n.delete,
              destructive: true,
            );
            if (!ok) return;
            await ref.read(communitiesProvider.notifier).delete(community.id);
          },
          color: context.c.onDanger,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ChannelsList extends ConsumerWidget {
  const _ChannelsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Channel>> async = ref.watch(channelsProvider);
    final List<Channel> list = async.orEmpty;

    if (async.isLoading && list.isEmpty) {
      return const ChatListSkeleton(rows: 5);
    }

    final List<Channel> following =
        list.where((Channel c) => c.isFollowing).toList();
    final List<Channel> discover =
        list.where((Channel c) => !c.isFollowing).toList();

    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.podcasts_outlined,
        title: context.l10n.noChannelsYet,
        message:
            context.l10n.channelsBroadcastOneWayTo2,
        actionLabel: context.l10n.newChannel,
        onAction: () => context.push(AppRoutes.newChannel),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: <Widget>[
        if (following.isNotEmpty) ...<Widget>[
          SectionHeader(title: context.l10n.following),
          for (final Channel c in following)
            _ChannelRow(
              channel: c,
              // The conversation view, not the management feed: tapping a
              // channel here should read like opening a chat, which is what the
              // merged chat list does too. `/channel/:id` stays reachable from
              // the header's info action.
              onTap: () => context.push('${AppRoutes.channelChat}/${c.id}'),
            ),
        ],
        if (discover.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: following.isEmpty
                ? context.l10n.allChannels
                : context.l10n.discover,
          ),
          for (final Channel c in discover)
            _ChannelRow(
              channel: c,
              onTap: () => context.push('${AppRoutes.channelChat}/${c.id}'),
            ),
        ],
      ],
    );
  }
}

class _ChannelRow extends ConsumerWidget {
  const _ChannelRow({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsTile(
      title: channel.name,
      subtitle: channel.description.isEmpty
          ? '${channel.category} · '
              '${TextUtils.members(channel.followerCount)}'
          : channel.description,
      leading: IAvatar(
        name: channel.name,
        imagePath: channel.avatarPath,
        colorSeed: channel.avatarColor,
        size: AppSizes.avatarMd,
        icon: Icons.podcasts_rounded,
        badgeCount: channel.unreadCount == 0 ? null : channel.unreadCount,
      ),
      trailing: channel.isFollowing
          ? IconButton(
              tooltip: channel.isMuted ? context.l10n.unmute : context.l10n.mute,
              onPressed: () =>
                  ref.read(channelsProvider.notifier).toggleMute(channel.id),
              icon: Icon(
                channel.isMuted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_none_rounded,
                color: channel.isMuted ? channel.isMuted ? context.c.onWarning : null : null,
              ),
            )
          : TextButton(
              onPressed: () =>
                  ref.read(channelsProvider.notifier).toggleFollow(channel.id),
              child: Text(context.l10n.follow),
            ),
      onTap: onTap,
    );
  }
}
