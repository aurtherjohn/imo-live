import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_color_scheme.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/message.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../../core/utils/l10n.dart';

/// Every starred message across all chats.
class StarredMessagesScreen extends ConsumerStatefulWidget {
  const StarredMessagesScreen({super.key});

  @override
  ConsumerState<StarredMessagesScreen> createState() =>
      _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends ConsumerState<StarredMessagesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Message>> async = ref.watch(starredMessagesProvider);
    final List<Chat> chats = ref.watch(chatsProvider).orEmpty;
    final List<Message> all = async.orEmpty;

    final String q = _query.trim().toLowerCase();
    final List<Message> visible = q.isEmpty
        ? all
        : all.where((Message m) => m.content.toLowerCase().contains(q)).toList();

    String chatTitle(String chatId) => chats
        .where((Chat c) => c.id == chatId)
        .firstOrNull
        ?.title ?? 'Unknown chat';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.starredMessages),
        actions: <Widget>[
          if (all.isNotEmpty)
            IconButton(
              tooltip: context.l10n.unstarAll,
              onPressed: _unstarAll,
              icon: const Icon(Icons.star_border_rounded),
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
            child: ISearchBar(
              hint: context.l10n.searchStarredMessages,
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: async.isLoading && all.isEmpty
                ? const ChatListSkeleton(rows: 5)
                : visible.isEmpty
                    ? EmptyState(
                        icon: Icons.star_border_rounded,
                        title: q.isEmpty
                            ? context.l10n.noStarredMessages
                            : 'No matches',
                        message: q.isEmpty
                            ? 'Long-press any message and choose Star to keep '
                                'it here for quick access.'
                            : 'No starred message contains "$q".',
                      )
                    : ListView.separated(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.xxxl),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => IListDivider(
                          indent: AppSizes.avatarMd +
                              AppSpacing.lg +
                              AppSpacing.md,
                        ),
                        itemBuilder: (BuildContext context, int i) {
                          final Message m = visible[i];
                          return SettingsTile(
                            title: TextUtils.truncate(
                              m.content.isEmpty
                                  ? '[${m.type.name}]'
                                  : m.content,
                              90,
                            ),
                            subtitle: '${chatTitle(m.chatId)} · '
                                '${DateFormatter.chatTimestamp(m.timestamp)}',
                            leading: IAvatar(
                              name: m.senderName.isEmpty
                                  ? chatTitle(m.chatId)
                                  : m.senderName,
                              size: AppSizes.avatarSm,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.star_rounded,
                                  size: AppIconSizes.sm,
                                  color: context.c.onWarning,
                                ),
                                IconButton(
                                  tooltip: context.l10n.actions,
                                  onPressed: () =>
                                      _actions(m, chatTitle(m.chatId)),
                                  icon: const Icon(Icons.more_vert_rounded,
                                      size: AppIconSizes.sm),
                                ),
                              ],
                            ),
                            onTap: () => context.push(
                              '${AppRoutes.chat}/${m.chatId}',
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _actions(Message m, String title) {
    showActionSheet(
      context,
      title: title,
      actions: <({IconData icon, String label, VoidCallback onTap, Color? color})>[
        (
          icon: Icons.chat_bubble_outline_rounded,
          label: context.l10n.openChat,
          onTap: () {
            Navigator.pop(context);
            context.push('${AppRoutes.chat}/${m.chatId}');
          },
          color: null,
        ),
        (
          icon: Icons.copy_rounded,
          label: context.l10n.copyText,
          onTap: () async {
            Navigator.pop(context);
            final String text = m.content.trim();
            if (text.isEmpty) {
              iToast(context, context.l10n.nothingToCopy, isError: true);
              return;
            }
            await Clipboard.setData(ClipboardData(text: text));
            if (!mounted) return;
            iToast(context, context.l10n.copied2);
          },
          color: null,
        ),
        (
          icon: Icons.star_border_rounded,
          label: context.l10n.removeStar,
          onTap: () async {
            Navigator.pop(context);
            await ref
                .read(messageRepositoryProvider)
                .toggleStar(m.id);
            await ref.read(starredMessagesProvider.notifier).refresh();
            if (!mounted) return;
            iToast(context, context.l10n.starRemoved);
          },
          color: context.c.onDanger,
        ),
      ],
    );
  }

  Future<void> _unstarAll() async {
    final List<Message> all = ref.read(starredMessagesProvider).orEmpty;
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.removeAllStars,
      message:
          context.l10n.starredMessagesUnstarred(all.length),
      confirmLabel: context.l10n.unstarAll,
      destructive: true,
    );
    if (!ok) return;
    await ref
        .read(messageRepositoryProvider)
        .starAll(all.map((Message m) => m.id).toList(), false);
    await ref.read(starredMessagesProvider.notifier).refresh();
    if (!mounted) return;
    iToast(context, context.l10n.allStarsRemoved);
  }
}
