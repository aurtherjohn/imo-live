import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/message.dart';
import '../../../../core/models/message_parts.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n.dart';

/// Delivery state icon shown inside outgoing bubbles.
class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({super.key, required this.status, this.size = 15});

  final MessageStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return switch (status) {
      MessageStatus.pending => Icon(
          Icons.schedule_rounded,
          size: size,
          color: c.textSecondary,
        ),
      MessageStatus.sent => Icon(
          Icons.done_rounded,
          size: size,
          color: c.textSecondary,
        ),
      MessageStatus.delivered => Icon(
          Icons.done_all_rounded,
          size: size,
          color: c.textSecondary,
        ),
      MessageStatus.read => Icon(
          Icons.done_all_rounded,
          size: size,
          color: context.c.onInfo,
        ),
      MessageStatus.failed => Icon(
          Icons.error_rounded,
          size: size,
          color: context.c.onDanger,
        ),
    };
  }
}

/// Rounded chat bubble with an asymmetric tail-facing corner.
class BubbleShell extends StatelessWidget {
  const BubbleShell({
    super.key,
    required this.child,
    required this.isOutgoing,
    this.color,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm + 1,
    ),
    this.width,
    this.border,
  });

  final Widget child;
  final bool isOutgoing;
  final Color? color;
  final EdgeInsets padding;
  final double? width;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    const double r = AppRadius.lg;
    const double tight = 6;

    final BorderRadius radius = BorderRadius.only(
      topLeft: const Radius.circular(r),
      topRight: const Radius.circular(r),
      bottomLeft: Radius.circular(isOutgoing ? r : tight),
      bottomRight: Radius.circular(isOutgoing ? tight : r),
    );

    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (isOutgoing ? c.bubbleOut : c.bubbleIn),
        borderRadius: radius,
        border: border,
      ),
      child: child,
    );
  }
}

/// A row of reaction chips attached under a bubble.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.reactions,
    this.alignEnd = true,
  });

  final List<MessageReaction> reactions;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final Map<String, List<MessageReaction>> grouped =
        <String, List<MessageReaction>>{};
    for (final MessageReaction r in reactions) {
      grouped.putIfAbsent(r.emoji, () => <MessageReaction>[]).add(r);
    }
    final List<MapEntry<String, List<MessageReaction>>> entries =
        grouped.entries.toList();

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisAlignment:
            alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: context.c.elevated,
              borderRadius: AppRadius.rPill,
              border: Border.all(color: context.c.divider, width: 0.6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: entries.map((MapEntry<String, List<MessageReaction>> e) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(e.key, style: const TextStyle(fontSize: 12)),
                      if (e.value.length > 1) ...<Widget>[
                        const SizedBox(width: 2),
                        Text(
                          '${e.value.length}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: context.c.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The quote block shown inside a reply bubble.
class QuotedMessage extends StatelessWidget {
  const QuotedMessage({
    super.key,
    required this.reply,
    required this.isOutgoing,
    this.onTap,
    this.maxLines = 2,
  });

  final ReplyPreview reply;
  final bool isOutgoing;
  final VoidCallback? onTap;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Color bar = isOutgoing ? c.accent : context.c.onInfo;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: c.isDark ? 0.22 : 0.05),
          borderRadius: AppRadius.rSm,
          border: Border(left: BorderSide(color: bar, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              reply.senderName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: bar,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              reply.preview,
              style: context.t.bodySmall?.copyWith(
                color: c.textSecondary,
                height: 1.25,
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small text row above bubble content: "Forwarded", sender name in groups.
class MessageMeta extends StatelessWidget {
  const MessageMeta({
    super.key,
    required this.message,
    required this.showSenderName,
    this.senderColor,
  });

  final Message message;
  final bool showSenderName;
  final Color? senderColor;

  @override
  Widget build(BuildContext context) {
    if (!showSenderName && !message.isForwarded) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showSenderName)
            Text(
              message.senderName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: senderColor ?? _nameColor(message.senderName),
              ),
            ),
          if (message.isForwarded)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.forward_rounded,
                  size: 12,
                  color: context.c.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  context.l10n.forwarded,
                  style: context.t.labelSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _nameColor(String name) {
    const List<Color> palette = <Color>[
      Color(0xFFE0577B),
      Color(0xFF7B61FF),
      Color(0xFF2BB3A3),
      Color(0xFFE08A3C),
      Color(0xFF4A8FE7),
      Color(0xFFB45FCB),
      Color(0xFF3FA45B),
      Color(0xFFD65C5C),
    ];
    if (name.isEmpty) return palette.first;
    int hash = 0;
    for (final int unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}

/// The time + status footer inside a bubble, right-aligned.
class BubbleFooter extends StatelessWidget {
  const BubbleFooter({
    super.key,
    required this.message,
    this.compact = false,
  });

  final Message message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Padding(
      padding: EdgeInsets.only(top: compact ? 2 : 3, left: AppSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (message.isStarred) ...<Widget>[
            Icon(Icons.star_rounded, size: 12, color: c.textSecondary),
            const SizedBox(width: 3),
          ],
          if (message.isEdited) ...<Widget>[
            Text(
              context.l10n.edited,
              style: context.t.labelSmall?.copyWith(fontSize: 11),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            DateFormatter.time(message.timestamp),
            style: TextStyle(
              fontSize: 11,
              color: c.textSecondary,
              height: 1.1,
            ),
          ),
          if (message.isOutgoing) ...<Widget>[
            const SizedBox(width: 4),
            MessageStatusIcon(status: message.status, size: 14),
          ],
        ],
      ),
    );
  }
}

/// The "this message was deleted" placeholder bubble body.
class DeletedMessageBody extends StatelessWidget {
  const DeletedMessageBody({super.key, required this.isOutgoing});

  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.block_rounded,
          size: 14,
          color: c.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          context.l10n.messageDeleted,
          style: context.t.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Day separator rendered between message groups.
class DaySeparator extends StatelessWidget {
  const DaySeparator({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: context.c.elevated.withValues(alpha: 0.9),
            borderRadius: AppRadius.rPill,
          ),
          child: Text(
            DateFormatter.daySeparator(date),
            style: context.t.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small centred system notice (e.g. date-based info inside a chat).
class SystemNotice extends StatelessWidget {
  const SystemNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.c.elevated.withValues(alpha: 0.85),
            borderRadius: AppRadius.rSm,
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: context.t.labelSmall?.copyWith(height: 1.35),
          ),
        ),
      ),
    );
  }
}

/// Animates a bubble in when it is first sent or received.
class BubbleEntrance extends StatelessWidget {
  const BubbleEntrance({
    super.key,
    required this.child,
    required this.isOutgoing,
  });

  final Widget child;
  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.normal,
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? c) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset((1 - value) * (isOutgoing ? 16 : -16), 0),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}
