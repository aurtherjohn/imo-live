import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_color_scheme.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/chat.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/auth_providers.dart';
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
                  context.l10n.chatMarkedAsRead,
                ),
              )
            else
              SettingsTile(
                title: context.l10n.markAsUnread,
                leadingIcon: Icons.mark_chat_unread_outlined,
                onTap: () => run(
                  () => notifier.markUnread(chat.id),
                  context.l10n.chatMarkedAsUnread,
                ),
              ),

            SettingsTile(
              title: chat.isPinned ? context.l10n.unpinChat : context.l10n.pinChat,
              leadingIcon: chat.isPinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded,
              onTap: () => run(
                () => notifier.togglePin(chat.id),
                chat.isPinned
                    ? context.l10n.chatUnpinned
                    : context.l10n.chatPinned,
              ),
            ),

            SettingsTile(
              title: chat.isMuted
                  ? context.l10n.unmuteNotifications
                  : context.l10n.muteNotifications,
              leadingIcon: chat.isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              onTap: () => run(
                () => notifier.toggleMute(chat.id),
                chat.isMuted
                    ? context.l10n.notificationsOn
                    : context.l10n.notificationsMuted,
              ),
            ),

            SettingsTile(
              title: chat.isArchived
                  ? context.l10n.unarchiveChat
                  : context.l10n.archiveChat,
              leadingIcon: chat.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              onTap: () => run(
                () => notifier.toggleArchive(chat.id),
                chat.isArchived
                    ? context.l10n.chatUnarchived
                    : context.l10n.chatArchived,
              ),
            ),

            SettingsTile(
              title: chat.isFavorite
                  ? context.l10n.removeFromFavorites
                  : context.l10n.addToFavorites,
              leadingIcon: chat.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              onTap: () => run(
                () => notifier.toggleFavorite(chat.id),
                chat.isFavorite
                    ? context.l10n.removedFromFavorites
                    : context.l10n.addedToFavorites,
              ),
            ),

            SettingsTile(
              title: context.l10n.disappearingMessages,
              subtitle: chat.disappearingSeconds == 0
                  ? context.l10n.off
                  : _disappearingLabel(context.l10n, chat.disappearingSeconds),
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
                  _openChatInfo(context);
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

  /// Opens the info page for a direct chat.
  ///
  /// This tile used to push `'${AppRoutes.chatInfo}/${chat.id}'`. No route was
  /// ever registered for that path, so tapping it dropped the user straight
  /// onto the router's "That screen doesn't exist." error page — a dead end
  /// `flutter analyze` cannot see and the router test did not cover.
  ///
  /// A direct chat's [Chat.id] is the composite `uidA_uidB`, not a uid, so the
  /// peer has to be resolved from `memberIds`. This mirrors
  /// `ChatScreen._openChatInfo` exactly, so both entry points agree.
  void _openChatInfo(BuildContext context) {
    if (chat.isChannel || chat.isBroadcast) {
      iToast(context, context.l10n.channelsAndBroadcastsHaveNo);
      return;
    }
    final String? peerUid = chat.peerUid(ref.read(currentUidProvider));
    if (peerUid == null) {
      iToast(context, context.l10n.thisChatHasNoLinked, isError: true);
      return;
    }
    context.push('${AppRoutes.contactInfo}/$peerUid');
  }
}

String _disappearingLabel(AppLocalizations l10n, int seconds) {
  if (seconds >= 86400 * 90) return l10n.s90Days;
  if (seconds >= 86400 * 7) return l10n.s7Days;
  if (seconds >= 86400) return l10n.s24Hours;
  if (seconds >= 3600) return l10n.hoursCount(seconds ~/ 3600);
  if (seconds >= 60) return l10n.minutesCount(seconds ~/ 60);
  return l10n.secondsCount(seconds);
}
