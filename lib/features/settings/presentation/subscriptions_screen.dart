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
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Channels and communities the user follows, in one place.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Channel> channels = ref.watch(channelsProvider).orEmpty;
    final List<Channel> followed =
        channels.where((Channel c) => c.isFollowing).toList();
    final List<Channel> muted =
        channels.where((Channel c) => c.isFollowing && c.isMuted).toList();
    final List<Community> communities = ref.watch(communitiesProvider).orEmpty;

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.subscriptions, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: ICard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: <Widget>[
                  _Stat(
                    label: context.l10n.channels,
                    value: '${followed.length}',
                    color: context.c.accent,
                  ),
                  _Stat(
                    label: context.l10n.muted,
                    value: '${muted.length}',
                    color: context.c.onWarning,
                  ),
                  _Stat(
                    label: context.l10n.tabCommunities,
                    value: '${communities.length}',
                    color: context.c.onInfo,
                  ),
                ],
              ),
            ),
          ),

          if (followed.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: AppSpacing.xl),
              child: EmptyState(
                icon: Icons.campaign_outlined,
                title: context.l10n.noChannelSubscriptions,
                message:
                    context.l10n.followAChannelFromThe2,
              ),
            )
          else
            SettingsGroup(
              title: context.l10n.followedChannels,
              footer:
                  context.l10n.mutingAChannelKeepsIt2,
              children: followed
                  .map(
                    (Channel channel) => SettingsTile(
                      title: channel.name,
                      subtitle:
                          context.l10n.followers3(TextUtils.members(channel.followerCount), channel.category),
                      leading: IAvatar(
                        name: channel.name,
                        imagePath: channel.avatarPath,
                        colorSeed: channel.avatarColor,
                        size: AppSizes.avatarSm,
                        icon: Icons.campaign_rounded,
                      ),
                      trailing: IconButton(
                        onPressed: () async {
                          await ref
                              .read(channelsProvider.notifier)
                              .toggleMute(channel.id);
                          if (context.mounted) {
                            iToast(
                              context,
                              channel.isMuted
                                  ? '${channel.name} unmuted'
                                  : '${channel.name} muted',
                            );
                          }
                        },
                        icon: Icon(
                          channel.isMuted
                              ? Icons.notifications_off_outlined
                              : Icons.notifications_active_outlined,
                          size: AppIconSizes.sm,
                          color: channel.isMuted
                              ? context.c.onWarning
                              : context.c.textSecondary,
                        ),
                        tooltip: channel.isMuted
                            ? context.l10n.unmute
                            : context.l10n.mute,
                      ),
                      onTap: () => context.push(
                        '${AppRoutes.channelChat}/${channel.id}',
                      ),
                    ),
                  )
                  .toList(),
            ),

          SettingsGroup(
            title: context.l10n.tabCommunities,
            children: communities.isEmpty
                ? <Widget>[
                    SettingsTile(
                      title: context.l10n.noCommunitiesYet,
                      subtitle: context.l10n.createOrJoinOneFrom,
                      leadingIcon: Icons.groups_outlined,
                      onTap: () => context.go(AppRoutes.communities),
                    ),
                  ]
                : communities
                    .map(
                      (Community community) => SettingsTile(
                        title: community.name,
                        subtitle:
                            context.l10n.groupsMembers(community.groupIds.length, community.memberIds.length),
                        leading: IAvatar(
                          name: community.name,
                          imagePath: community.avatarPath,
                          colorSeed: community.avatarColor,
                          size: AppSizes.avatarSm,
                          icon: Icons.groups_rounded,
                        ),
                        onTap: () => context.push(
                          '${AppRoutes.community}/${community.id}',
                        ),
                      ),
                    )
                    .toList(),
          ),

          SettingsGroup(
            title: context.l10n.discover,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.findChannels,
                subtitle: context.l10n.browsePublicChannelsByCategory,
                leadingIcon: Icons.explore_outlined,
                onTap: () => context.go(AppRoutes.updates),
              ),
              SettingsTile(
                title: context.l10n.newChannel,
                subtitle: context.l10n.createAChannelOfYour,
                leadingIcon: Icons.add_circle_outline_rounded,
                onTap: () => context.push(AppRoutes.newChannel),
              ),
              SettingsTile(
                title: context.l10n.newCommunity,
                subtitle: context.l10n.startACommunityWithAnnouncement,
                leadingIcon: Icons.add_business_outlined,
                onTap: () => context.push(AppRoutes.newCommunity),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.notificationDefaults,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.channelNotifications,
                value: ref.watch(notificationSettingsProvider).valueOrNull
                            ?.statusNotifications ==
                        true
                    ? 'On'
                    : 'Off',
                leadingIcon: Icons.notifications_none_rounded,
                onTap: () => context.push(AppRoutes.notifications),
              ),
              SettingsValueRow(
                label: context.l10n.lastRefreshed,
                value: followed.isEmpty
                    ? 'Never'
                    : DateFormatter.relative(
                        followed
                            .map((Channel c) => c.lastUpdateAt ?? DateTime(2000))
                            .reduce((DateTime a, DateTime b) =>
                                a.isAfter(b) ? a : b),
                      ),
                leadingIcon: Icons.refresh_rounded,
                onTap: () async {
                  await ref.read(channelsProvider.notifier).refresh();
                  await ref.read(communitiesProvider.notifier).refresh();
                  if (context.mounted) iToast(context, context.l10n.subscriptionsRefreshed);
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                value,
                style: context.t.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            style: context.t.bodySmall?.copyWith(
              color: context.c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
