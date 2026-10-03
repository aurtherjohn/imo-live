import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/group.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../../core/utils/l10n.dart';

/// One channel row in the merged chat list.
///
/// ### Why this is not [ChatTile]
///
/// A `Chat` is a conversation with a peer; a `Channel` is a broadcast surface
/// with an owner. They share a row *shape* — avatar, name, preview, time,
/// badge — but not a data model, and the row has to say "this is a channel"
/// at a glance or the merged list becomes confusing. A separate widget keeps
/// that distinction honest instead of threading a fake `Chat` through
/// `ChatTile` and having it render a megaphone badge off a boolean.
///
/// Built to match [ChatTile]'s metrics exactly (same horizontal padding, same
/// avatar size, same title/subtitle weights) so the two kinds of row read as
/// one list rather than two.
class ChannelChatTile extends StatelessWidget {
  const ChannelChatTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final bool unread = channel.hasUnread && !channel.isMuted;

    return Material(
      color: isSelected ? c.accent.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md - 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              IAvatar(
                name: channel.name,
                imagePath: channel.avatarPath,
                imageUrl: channel.avatarUrl,
                colorSeed: channel.avatarColor,
                size: AppSizes.avatarMd + 4,
                isGroup: true,
                // The megaphone is what makes a channel identifiable when the
                // two kinds of row are interleaved.
                icon: Icons.campaign_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            channel.name,
                            style: context.t.bodyLarge?.copyWith(
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              letterSpacing: 0.05,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        // The channel marker, always present. Colour carries
                        // the unread state rather than the icon disappearing,
                        // so the row's identity never changes shape.
                        Icon(
                          Icons.verified_rounded,
                          size: 13,
                          color: unread ? c.accent : c.textSecondary,
                        ),
                        if (channel.isMuted) ...<Widget>[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.notifications_off_rounded,
                            size: 14,
                            color: c.textSecondary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      channel.lastMessage.isEmpty
                          ? context.l10n.noPostsYet
                          : channel.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyMedium?.copyWith(
                        color: c.textSecondary,
                        fontStyle: channel.lastMessage.isEmpty
                            ? FontStyle.italic
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (channel.lastMessageAt != null)
                    Text(
                      DateFormatter.chatTimestamp(channel.lastMessageAt!),
                      style: context.t.labelSmall?.copyWith(
                        color: unread ? c.accent : c.textSecondary,
                        fontWeight: unread ? FontWeight.w600 : null,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (unread)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      // A dot, not a count: the count is not derivable from the
                      // channel document (see [Channel.hasUnread]) and a wrong
                      // number is worse than no number.
                      child: const SizedBox(
                        width: 6,
                        height: 6,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
