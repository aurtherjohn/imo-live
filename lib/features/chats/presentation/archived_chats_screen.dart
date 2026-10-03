import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../../core/utils/l10n.dart';

/// Chats the user archived, with restore and bulk actions.
class ArchivedChatsScreen extends ConsumerWidget {
  const ArchivedChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Chat> archived = ref
        .watch(chatsProvider)
        .orEmpty
        .where((Chat c) => c.isArchived)
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          archived.isEmpty ? 'Archived' : 'Archived (${archived.length})',
        ),
        actions: <Widget>[
          if (archived.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: context.l10n.archiveActions,
              onSelected: (String value) async {
                if (value == 'read') {
                  for (final Chat c in archived) {
                    await ref.read(chatsProvider.notifier).markRead(c.id);
                  }
                } else if (value == 'restore') {
                  for (final Chat c in archived) {
                    await ref.read(chatsProvider.notifier).toggleArchive(c.id);
                  }
                  if (!context.mounted) return;
                  iToast(context, context.l10n.allChatsRestored);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'read',
                  child: Text(context.l10n.markAllAsRead),
                ),
                PopupMenuItem<String>(
                  value: 'restore',
                  child: Text(context.l10n.unarchiveAll),
                ),
              ],
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: archived.isEmpty
          ? EmptyState(
              icon: Icons.archive_outlined,
              title: context.l10n.nothingArchived,
              message:
                  context.l10n.archivedChatsAreHiddenFrom2,
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
              itemCount: archived.length,
              separatorBuilder: (_, _) => IListDivider(
                indent: AppSizes.avatarMd + AppSpacing.lg + AppSpacing.md,
              ),
              itemBuilder: (BuildContext context, int i) {
                final Chat chat = archived[i];
                return SettingsTile(
                  title: chat.title,
                  subtitle: chat.lastMessage.isEmpty ? 'No messages' : chat.lastMessage,
                  leading: IAvatar(
                    name: chat.title,
                    imagePath: chat.avatarPath,
                    colorSeed: chat.avatarColor,
                    size: AppSizes.avatarMd,
                    isGroup: chat.isGroup,
                    badgeCount:
                        chat.unreadCount == 0 ? null : chat.unreadCount,
                  ),
                  trailing: IconButton(
                    tooltip: context.l10n.unarchive,
                    onPressed: () async {
                      await ref
                          .read(chatsProvider.notifier)
                          .toggleArchive(chat.id);
                      if (!context.mounted) return;
                      iToast(context, context.l10n.restored(chat.title));
                    },
                    icon: const Icon(Icons.unarchive_outlined,
                        size: AppIconSizes.sm),
                  ),
                  onTap: () => context.push('${AppRoutes.chat}/${chat.id}'),
                );
              },
            ),
    );
  }
}
