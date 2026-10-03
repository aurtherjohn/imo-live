import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/chat.dart';
import '../../../../core/models/message_parts.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../../core/utils/l10n.dart';

/// One row in the chat list.
///
/// Handles every visual state: pinned, muted, typing, presence, unread counts,
/// drafts, delivery ticks and group/channel/community variants.
///
/// [onAvatarTap] is what makes the avatar a separate target from the row: the
/// avatar opens the person's profile and the rest of the row opens the chat,
/// matching the WhatsApp/Imo "two zones, one row" behaviour.
class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.onAvatarTap,
    this.onLongPress,
    this.isSelected = false,
  });

  final Chat chat;
  final VoidCallback onTap;

  /// Tapping the avatar opens the contact/profile screen. Falls back to
  /// [onTap] so a caller that does not care about the split still behaves
  /// sensibly.
  final VoidCallback? onAvatarTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final bool hasDraft = chat.draft.trim().isNotEmpty;

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
              // The avatar is its own tap target: profile, not chat.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAvatarTap ?? onTap,
                child: IAvatar(
                  name: chat.title,
                  imagePath: chat.avatarPath,
                  colorSeed: chat.avatarColor,
                  size: AppSizes.avatarMd + 4,
                  isOnline: chat.isOnline,
                  showPresence: !chat.isGroup && !chat.isChannel,
                  isGroup: chat.isGroup,
                  icon: chat.isChannel
                      ? Icons.campaign_rounded
                      : chat.isBroadcast
                          ? Icons.podcasts_rounded
                          : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (chat.isPinned) ...<Widget>[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 13,
                            color: c.textSecondary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            chat.title,
                            style: context.t.bodyLarge?.copyWith(
                              fontWeight:
                                  chat.hasUnread ? FontWeight.w700 : FontWeight.w600,
                              letterSpacing: 0.05,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.isMuted) ...<Widget>[
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
                    _SubtitleRow(chat: chat, hasDraft: hasDraft),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    DateFormatter.chatTimestamp(chat.lastTimestamp),
                    style: context.t.labelSmall?.copyWith(
                      color: chat.hasUnread && !chat.isMuted
                          ? c.accent
                          : c.textSecondary,
                      fontWeight:
                          chat.hasUnread && !chat.isMuted ? FontWeight.w600 : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _TrailingIndicator(chat: chat),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The second line of a tile: draft, typing, or the last message.
class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.chat, required this.hasDraft});

  final Chat chat;
  final bool hasDraft;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    if (chat.isTyping) {
      return Row(
        children: <Widget>[
          const TypingIndicator(dotSize: 4, spacing: 2),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              context.l10n.typing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodySmall?.copyWith(
                color: c.accent,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      );
    }

    if (hasDraft) {
      return Row(
        children: <Widget>[
          Flexible(
            child: Text(
              context.l10n.draft,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyMedium?.copyWith(
                color: c.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              chat.draft,
              style: context.t.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        if (chat.lastMessageIsOutgoing) ...<Widget>[
          _TickIndicator(status: chat.lastMessageStatus),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            chat.lastMessage.isEmpty ? 'No messages yet' : chat.lastMessage,
            style: context.t.bodyMedium?.copyWith(
              color: chat.hasUnread && !chat.isMuted
                  ? c.textPrimary
                  : c.textSecondary,
              fontWeight:
                  chat.hasUnread && !chat.isMuted ? FontWeight.w500 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Delivery tick: clock, single, double, blue double, or error.
class _TickIndicator extends StatelessWidget {
  const _TickIndicator({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final MessageStatus parsed = MessageStatus.values.firstWhere(
      (MessageStatus s) => s.name == status,
      orElse: () => MessageStatus.sent,
    );

    return switch (parsed) {
      MessageStatus.pending => Icon(
          Icons.schedule_rounded,
          size: 14,
          color: c.textSecondary,
        ),
      MessageStatus.sent => Icon(
          Icons.done_rounded,
          size: 15,
          color: c.textSecondary,
        ),
      MessageStatus.delivered => Icon(
          Icons.done_all_rounded,
          size: 15,
          color: c.textSecondary,
        ),
      MessageStatus.read => Icon(
          Icons.done_all_rounded,
          size: 15,
          color: context.c.onInfo,
        ),
      MessageStatus.failed => Icon(
          Icons.error_outline_rounded,
          size: 15,
          color: context.c.onDanger,
        ),
    };
  }
}

/// Trailing column: unread badge, pin/mute glyph, or a placeholder.
class _TrailingIndicator extends StatelessWidget {
  const _TrailingIndicator({required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    if (chat.hasUnread) {
      return UnreadBadge(
        count: chat.unreadCount > 0 ? chat.unreadCount : 1,
        isMuted: chat.isMuted,
      );
    }

    if (chat.isFavorite) {
      return Icon(
        Icons.star_rounded,
        size: 15,
        color: c.textSecondary.withValues(alpha: 0.55),
      );
    }

    return const SizedBox(height: 20);
  }
}

/// Compact tile used inside pickers (forward, add member, broadcast).
class ContactSelectTile extends StatelessWidget {
  const ContactSelectTile({
    super.key,
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onChanged,
    this.imagePath,
    this.colorSeed,
    this.isOnline = false,
    this.trailing,
  });

  final String name;
  final String subtitle;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final String? imagePath;
  final int? colorSeed;
  final bool isOnline;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            IAvatar(
              name: name,
              imagePath: imagePath,
              colorSeed: colorSeed,
              size: AppSizes.avatarSm + 6,
              isOnline: isOnline,
              showPresence: true,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    name,
                    style: context.t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.t.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Checkbox(
                value: selected,
                onChanged: (bool? v) => onChanged(v ?? false),
              ),
          ],
        ),
      ),
    );
  }
}
