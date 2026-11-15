import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// A named grouping of chats — the equivalent of chat folders.
class ListsScreen extends ConsumerWidget {
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Chat> chats = ref.watch(chatsProvider).orEmpty;
    final ChatFilter filter = ref.watch(chatFilterProvider);

    final Map<ChatFilter, List<Chat>> buckets = <ChatFilter, List<Chat>>{
      ChatFilter.all: chats.where((Chat c) => !c.isArchived).toList(),
      ChatFilter.unread: chats.where((Chat c) => c.hasUnread).toList(),
      ChatFilter.favorites: chats.where((Chat c) => c.isFavorite).toList(),
      ChatFilter.groups:
          chats.where((Chat c) => c.isGroup).toList(),
      ChatFilter.work: chats.where((Chat c) => c.isWork).toList(),
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.lists),
        actions: <Widget>[
          IconButton(
            onPressed: () => _createList(context, ref),
            icon: const Icon(Icons.add_rounded),
            tooltip: context.l10n.newList,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          SettingsGroup(
            title: context.l10n.builtInLists,
            footer:
                context.l10n.aListIsASaved2,
            children: buckets.entries
                .map(
                  (MapEntry<ChatFilter, List<Chat>> entry) => SettingsTile(
                    title: entry.key.label,
                    subtitle: entry.value.isEmpty
                        ? context.l10n.noChats
                        : '${entry.value.length} chat${entry.value.length == 1 ? '' : 's'}',
                    leading: _FilterDot(
                      color: _colorFor(context, entry.key),
                    ),
                    trailing: filter == entry.key
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: AppIconSizes.md,
                            color: context.c.accent,
                          )
                        : null,
                    onTap: () {
                      ref.read(chatFilterProvider.notifier).select(entry.key);
                      context.go(AppRoutes.chats);
                    },
                  ),
                )
                .toList(),
          ),

          SettingsGroup(
            title: context.l10n.customLists,
            footer:
                context.l10n.theWorkListIsA2,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.filterWork,
                subtitle:
                    context.l10n.chatsFlaggedAsWork(buckets[ChatFilter.work]!.length),
                leadingIcon: Icons.work_outline_rounded,
                trailing: TextButton(
                  onPressed: () => _manageWork(context, ref, chats),
                  child: Text(context.l10n.manage),
                ),
                onTap: () {
                  ref.read(chatFilterProvider.notifier).select(ChatFilter.work);
                  context.go(AppRoutes.chats);
                },
              ),
              SettingsTile(
                title: context.l10n.newList,
                subtitle: context.l10n.pickAFilterAndApply,
                leadingIcon: Icons.add_circle_outline_rounded,
                onTap: () => _createList(context, ref),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.reset,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.showAllChats,
                subtitle: context.l10n.clearTheActiveFilter,
                leadingIcon: Icons.restart_alt_rounded,
                onTap: () {
                  ref.read(chatFilterProvider.notifier).select(ChatFilter.all);
                  if (context.mounted) iToast(context, context.l10n.showingAllChats);
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  static Color _colorFor(BuildContext context, ChatFilter filter) =>
      switch (filter) {
        ChatFilter.all => context.c.accent,
        ChatFilter.unread => context.c.onInfo,
        ChatFilter.favorites => context.c.onWarning,
        ChatFilter.groups => context.c.onSuccess,
        ChatFilter.work => context.c.onDanger,
      };

  /// Lets the user choose which chats belong to the Work list.
  ///
  /// The flag lives on the chat itself rather than in a separate list document,
  /// which is why this is the only place it is written — and why the Work
  /// filter on the Chats tab reads exactly this set.
  ///
  /// Each toggle re-reads the chat from the provider before saving: the sheet
  /// holds a snapshot from when it opened, and saving that snapshot back would
  /// undo anything that changed while it was up (a new message, a mute).
  Future<void> _manageWork(
    BuildContext context,
    WidgetRef ref,
    List<Chat> chats,
  ) async {
    final List<Chat> candidates = chats
        .where((Chat c) => !c.isArchived)
        .toList()
      ..sort(
        (Chat a, Chat b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );

    if (candidates.isEmpty) {
      iToast(context, context.l10n.noChatsToOrganiseYet);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (BuildContext context, ScrollController controller) =>
            Column(
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.c.divider,
                borderRadius: AppRadius.rPill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.l10n.chatsInWork, style: context.t.titleMedium),
              ),
            ),
            const IListDivider(),
            Expanded(
              // Watches the provider so a toggle repaints the row without the
              // sheet having to keep its own copy of the list in sync.
              child: Consumer(
                builder: (BuildContext context, WidgetRef sheetRef, _) {
                  final List<Chat> live =
                      sheetRef.watch(chatsProvider).orEmpty;
                  final List<Chat> rows = live
                      .where((Chat c) => !c.isArchived)
                      .toList()
                    ..sort(
                      (Chat a, Chat b) => a.title
                          .toLowerCase()
                          .compareTo(b.title.toLowerCase()),
                    );

                  return ListView.builder(
                    controller: controller,
                    itemCount: rows.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Chat chat = rows[index];
                      return CheckboxListTile(
                        value: chat.isWork,
                        title: Text(
                          chat.title.isEmpty ? context.l10n.untitledChat : chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: chat.isGroup
                            ? Text(context.l10n.group)
                            : Text(context.l10n.directChat),
                        onChanged: (bool? value) => sheetRef
                            .read(chatsProvider.notifier)
                            .save(chat.copyWith(isWork: value ?? false)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createList(BuildContext context, WidgetRef ref) async {
    final String? name = await showTextPrompt(
      context,
      title: context.l10n.newList,
      hint: context.l10n.listName,
      confirmLabel: context.l10n.create,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final ChatFilter? target = await showOptionDialog<ChatFilter>(
      context,
      title: context.l10n.whatShouldListContain(name),
      message: context.l10n.pickTheChatsThisList,
      options: <({String label, ChatFilter value, String? subtitle})>[
        (
          label: context.l10n.unreadChats,
          value: ChatFilter.unread,
          subtitle: context.l10n.anythingWithABadge,
        ),
        (label: context.l10n.favourites, value: ChatFilter.favorites, subtitle: context.l10n.chatsYouStarred),
        (label: context.l10n.groupsCommunities, value: ChatFilter.groups, subtitle: null),
        (label: context.l10n.everyone, value: ChatFilter.all, subtitle: context.l10n.noFiltering),
      ],
    );
    if (target == null || !context.mounted) return;
    ref.read(chatFilterProvider.notifier).select(target);
    iToast(context, context.l10n.listCreatedAndApplied(name));
  }
}

/// A small coloured dot used as a list icon.
class _FilterDot extends StatelessWidget {
  const _FilterDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: AppRadius.rSm,
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
