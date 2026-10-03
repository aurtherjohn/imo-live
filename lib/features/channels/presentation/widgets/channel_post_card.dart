import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/channel_models.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../../core/utils/l10n.dart';

/// One post in a channel feed.
///
/// Followers see the reaction bar; only the owner ([canManage]) sees the delete
/// action, mirroring the rule that only an owner may publish.
class ChannelPostCard extends StatelessWidget {
  const ChannelPostCard({
    super.key,
    required this.post,
    required this.canManage,
    required this.onReact,
    this.onDelete,
    this.onOpenMedia,
  });

  final ChannelPost post;
  final bool canManage;
  final void Function(ChannelReactionKind kind) onReact;
  final VoidCallback? onDelete;

  /// Opens the post's attachment. Images get an in-app viewer; video and file
  /// posts are handed to the system app that can play or open them, so the
  /// channel needs no bundled media player.
  final VoidCallback? onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return ICard(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IAvatar(
                name: post.authorName.isEmpty ? 'Channel' : post.authorName,
                size: AppSizes.avatarMd,
                icon: Icons.campaign_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      post.authorName.isEmpty ? 'Channel' : post.authorName,
                      style: context.t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      post.createdAt == null
                          ? ''
                          : relativeTime(post.createdAt!),
                      style: context.t.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage && onDelete != null)
                IconButton(
                  tooltip: context.l10n.deletePost,
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: AppIconSizes.sm,
                    color: c.textSecondary,
                  ),
                ),
            ],
          ),
          if (post.text.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            SelectableText(
              post.text,
              style: context.t.bodyLarge?.copyWith(height: 1.35),
            ),
          ],
          if (post.isImage) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            GestureDetector(
              onTap: onOpenMedia,
              child: ClipRRect(
                borderRadius: AppRadius.rMd,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: CachedNetworkImage(
                    imageUrl: post.mediaUrl,
                    fit: BoxFit.cover,
                    placeholder: (BuildContext _, String _) =>
                        Container(color: c.surfaceAlt),
                    errorWidget: (BuildContext _, String _, Object _) =>
                        Container(
                      color: c.surfaceAlt,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (post.isVideo) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            GestureDetector(
              onTap: onOpenMedia,
              child: ClipRRect(
                borderRadius: AppRadius.rMd,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: c.surfaceAlt,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.play_circle_fill_rounded,
                          size: 44,
                          color: c.accent,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          context.l10n.tapToPlay,
                          style: context.t.bodySmall?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (post.isFile) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            GestureDetector(
              onTap: onOpenMedia,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: AppRadius.rMd,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.insert_drive_file_rounded,
                      size: 28,
                      color: c.accent,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        post.mediaName.isEmpty ? 'Attachment' : post.mediaName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodyMedium,
                      ),
                    ),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: c.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              for (final ChannelReactionKind kind
                  in ChannelReactionKind.values)
                _ReactionChip(
                  kind: kind,
                  count: post.countOf(kind),
                  selected: post.myReaction == kind,
                  onTap: () => onReact(kind),
                ),
              const Spacer(),
              if (post.viewCount > 0)
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.visibility_outlined,
                      size: 13,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      TextUtils.compactCount(post.viewCount),
                      style: context.t.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.kind,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ChannelReactionKind kind;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.rPill,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? c.accent.withValues(alpha: 0.18)
                  : c.surfaceAlt,
              borderRadius: AppRadius.rPill,
              border: Border.all(
                color: selected ? c.accent : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  channelReactionEmoji(kind),
                  style: const TextStyle(fontSize: 13),
                ),
                if (count > 0) ...<Widget>[
                  const SizedBox(width: 3),
                  Text(
                    '$count',
                    style: context.t.bodySmall?.copyWith(
                      color: selected ? c.accent : c.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
