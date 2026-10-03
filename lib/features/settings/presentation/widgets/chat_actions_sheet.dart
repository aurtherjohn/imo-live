import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_color_scheme.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/chat.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../chats/presentation/providers.dart';
import '../../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../../contacts/presentation/dialogs/disappearing_messages_sheet.dart';
import '../../../../core/utils/l10n.dart';

/// Long-press action sheet for a chat in the list.
///
/// Every entry performs a real local mutation — nothing is a dead button.
Future<void> showChatActionsSheet(
  BuildContext context,
  WidgetRef ref,
  Chat chat,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return _ChatActionsSheet(chat: chat, ref: ref);
    },
  );
}

class _ChatActionsSheet extends StatelessWidget {
  const _ChatActionsSheet({required this.chat, required this.ref});

  final Chat chat;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final ChatsNotifier notifier = ref.read(chatsProvider.notifier);

    void close() => Navigator.pop(context);

    void run(VoidCallback action, String toast) {
      close();
      action();
      iToast(context, toast);
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.c.divider,
                borderRadius: AppRadius.rPill,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: <Widget>[
                  IAvatar(
                    name: chat.title,
                    imagePath: chat.avatarPath,
                    colorSeed: chat.avatarColor,
                    size: AppSizes.avatarMd,
                    isGroup: chat.isGroup,
                    isOnline: chat.isOnline,
                    showPresence: !chat.isGroup,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          chat.title,
                          style: context.t.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          chat.lastMessage,
                          style: context.t.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),

            if (chat.hasUnread)
              SettingsTile(
                title: context.l10n.markAsRead,
                leadingIcon: Icons.mark_chat_read_outlined,
                onTap: () => run(
                  () => notifier.markRead(chat.id),
                  'Marked as read',
                ),
              )
            else
              SettingsTile(
                title: context.l10n.markAsUnread,
                leadingIcon: Icons.mark_chat_unread_outlined,
                onTap: () => run(
                  () => notifier.markUnread(chat.id),
                  'Marked as unread',
                ),
              ),

            SettingsTile(
              title: chat.isPinned ? 'Unpin chat' : 'Pin chat',
              leadingIcon: chat.isPinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded,
              onTap: () => run(
                () => notifier.togglePin(chat.id),
                chat.isPinned ? 'Chat unpinned' : 'Chat pinned',
              ),
            ),

            SettingsTile(
              title: chat.isMuted ? 'Unmute notifications' : 'Mute notifications',
              leadingIcon: chat.isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              onTap: () => run(
                () => notifier.toggleMute(chat.id),
                chat.isMuted ? 'Notifications on' : 'Notifications muted',
              ),
            ),

            SettingsTile(
              title: chat.isArchived ? 'Unarchive chat' : 'Archive chat',
              leadingIcon: chat.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              onTap: () => run(
                () => notifier.toggleArchive(chat.id),
                chat.isArchived ? 'Chat unarchived' : 'Chat archived',
              ),
            ),

            SettingsTile(
              title: chat.isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              leadingIcon: chat.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              onTap: () => run(
                () => notifier.toggleFavorite(chat.id),
                chat.isFavorite
                    ? 'Removed from favorites'
                    : 'Added to favorites',
              ),
            ),

            SettingsTile(
              title: context.l10n.disappearingMessages,
              subtitle: chat.disappearingSeconds == 0
                  ? 'Off'
                  : _disappearingLabel(chat.disappearingSeconds),
              leadingIcon: Icons.timer_outlined,
              onTap: () {
                close();
                showDisappearingMessagesSheet(context, ref, chat);
              },
            ),

            if (chat.isGroup || chat.isCommunity)
              SettingsTile(
                title: context.l10n.groupInfo,
                leadingIcon: Icons.info_outline_rounded,
                onTap: () {
                  close();
                  context.push('${AppRoutes.groupInfo}/${chat.id}');
                },
              )
            else
              SettingsTile(
                title: context.l10n.chatInfo,
                leadingIcon: Icons.info_outline_rounded,
                onTap: () {
                  close();
                  context.push('${AppRoutes.chatInfo}/${chat.id}');
                },
              ),

            SettingsTile(
              title: context.l10n.clearChat,
              leadingIcon: Icons.cleaning_services_outlined,
              onTap: () async {
                close();
                final bool confirmed = await showConfirmDialog(
                  context,
                  title: context.l10n.clearChat2,
                  message:
                      context.l10n.allMessagesInThisChat2,
                  confirmLabel: context.l10n.clear,
                  destructive: true,
                );
                if (!confirmed) return;
                await notifier.clearChat(chat.id);
                if (context.mounted) iToast(context, context.l10n.chatCleared);
              },
            ),

            SettingsTile(
              title: context.l10n.deleteChat,
              leadingIcon: Icons.delete_outline_rounded,
              titleColor: context.c.onDanger,
              leadingIconColor: context.c.onDanger,
              onTap: () async {
                close();
                final bool confirmed = await showConfirmDialog(
                  context,
                  title: context.l10n.deleteChat2,
                  message:
                      context.l10n.thisConversationAndAllIts2,
                  confirmLabel: context.l10n.delete,
                  destructive: true,
                );
                if (!confirmed) return;
                await notifier.deleteChat(chat.id);
                if (context.mounted) iToast(context, context.l10n.chatDeleted);
              },
              showDivider: false,
            ),

            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

String _disappearingLabel(int seconds) {
  if (seconds >= 86400 * 90) return '90 days';
  if (seconds >= 86400 * 7) return '7 days';
  if (seconds >= 86400) return '24 hours';
  if (seconds >= 3600) return '${seconds ~/ 3600} hours';
  if (seconds >= 60) return '${seconds ~/ 60} minutes';
  return '$seconds seconds';
}
