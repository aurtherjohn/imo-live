import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/settings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../groups/presentation/widgets/group_picker.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../domain/chat_service.dart';
import '../../../core/utils/l10n.dart';

/// Recipient lists that receive one-to-one copies of a broadcast message.
class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  @override
  Widget build(BuildContext context) {
    final List<BroadcastList> lists = ref.watch(broadcastListsProvider).orEmpty;
    final List<Contact> contacts = ref.watch(contactsProvider).orEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          lists.isEmpty ? context.l10n.broadcastLists : 'Broadcast (${lists.length})',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: context.c.accent,
        foregroundColor: Colors.white,
        onPressed: () => _create(context, contacts),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.l10n.newList),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
        children: <Widget>[
          InfoBanner(
            message:
                context.l10n.aBroadcastSendsAnIndividual2,
          ),
          if (lists.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: AppSpacing.xl),
              child: EmptyState(
                icon: Icons.campaign_outlined,
                title: context.l10n.noBroadcastLists,
                message:
                    context.l10n.createAListOfUp2,
                compact: true,
              ),
            )
          else
            for (final BroadcastList list in lists)
              SettingsTile(
                title: list.name,
                subtitle: context.l10n.recipientsCount(list.recipientIds.length),
                leading: IAvatar(
                  name: list.name,
                  size: AppSizes.avatarMd,
                  icon: Icons.campaign_rounded,
                ),
                trailing: IconButton(
                  tooltip: context.l10n.actions,
                  onPressed: () => _actions(list),
                  icon: const Icon(Icons.more_vert_rounded,
                      size: AppIconSizes.sm),
                ),
                onTap: () => _openList(list, contacts),
              ),
        ],
      ),
    );
  }

  void _actions(BroadcastList list) {
    showActionSheet(
      context,
      title: list.name,
      actions: <({IconData icon, String label, VoidCallback onTap, Color? color})>[
        (
          icon: Icons.edit_outlined,
          label: context.l10n.rename,
          onTap: () async {
            Navigator.pop(context);
            final String? name = await showTextPrompt(
              context,
              title: context.l10n.renameList,
              initialValue: list.name,
              hint: context.l10n.listName,
              confirmLabel: context.l10n.save,
              maxLength: 40,
            );
            if (name == null || name.trim().isEmpty) return;
            await ref
                .read(broadcastListsProvider.notifier)
                .rename(list.id, name.trim());
            if (!mounted) return;
            iToast(context, context.l10n.listRenamed);
          },
          color: null,
        ),
        (
          icon: Icons.person_add_alt_1_rounded,
          label: context.l10n.editRecipients,
          onTap: () {
            Navigator.pop(context);
            _editRecipients(list);
          },
          color: null,
        ),
        (
          icon: Icons.delete_outline_rounded,
          label: context.l10n.deleteList,
          onTap: () async {
            Navigator.pop(context);
            final bool ok = await showConfirmDialog(
              context,
              title: context.l10n.delete2(list.name),
              message:
                  context.l10n.theListIsDeletedExisting2,
              confirmLabel: context.l10n.delete,
              destructive: true,
            );
            if (!ok) return;
            await ref.read(broadcastListsProvider.notifier).remove(list.id);
            if (!mounted) return;
            iToast(context, context.l10n.listDeleted);
          },
          color: context.c.onDanger,
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, List<Contact> contacts) async {
    final String? name = await showTextPrompt(
      context,
      title: context.l10n.newBroadcastList,
      hint: context.l10n.listName,
      confirmLabel: context.l10n.next,
      maxLength: 40,
    );
    if (name == null || name.trim().isEmpty) return;
    if (!context.mounted) return;

    final List<Contact>? picked = await pickContacts(
      context: context,
      ref: ref,
      title: context.l10n.addRecipients,
    );
    if (picked == null || picked.isEmpty) return;

    await ref.read(broadcastListsProvider.notifier).create(
          BroadcastList(
            id: 'broadcast_${DateTime.now().microsecondsSinceEpoch}',
            name: name.trim(),
            recipientIds: picked.map((Contact c) => c.id).toList(),
            createdAt: DateTime.now(),
          ),
        );

    if (!context.mounted) return;
    iToast(context, context.l10n.created(name.trim()));
  }

  Future<void> _editRecipients(BroadcastList list) async {
    final List<Contact>? picked = await pickContacts(
      context: context,
      ref: ref,
      title: context.l10n.editRecipients,
      initiallySelected: list.recipientIds.toSet(),
    );
    if (picked == null) return;
    await ref
        .read(broadcastListsProvider.notifier)
        .updateRecipients(list.id, picked.map((Contact c) => c.id).toList());
    if (!mounted) return;
    iToast(context, context.l10n.recipientsUpdated);
  }

  /// Sends one message to every recipient of [list].
  ///
  /// A broadcast is deliberately *not* a group: each recipient gets a private
  /// 1:1 copy and cannot see who else received it. That is why this loops over
  /// the recipients creating a separate conversation each, rather than posting
  /// into one shared thread — and why a failure for one person does not stop
  /// the rest.
  Future<void> _sendBroadcast(
    BroadcastList list,
    List<Contact> contacts,
  ) async {
    if (list.recipientIds.isEmpty) {
      iToast(context, context.l10n.addAtLeastOneRecipient, isError: true);
      return;
    }

    final String? text = await showTextPrompt(
      context,
      title: context.l10n.broadcastToPeople(list.recipientIds.length),
      hint: context.l10n.message,
      confirmLabel: context.l10n.send,
      maxLines: 4,
      maxLength: 1000,
    );
    if (text == null || text.trim().isEmpty || !mounted) return;

    final ChatService service = ref.read(chatServiceProvider);
    final String body = text.trim();
    int sent = 0;

    for (final String id in list.recipientIds) {
      final Contact? contact =
          contacts.where((Contact x) => x.id == id).firstOrNull;
      if (contact == null) continue;
      try {
        final String chatId = await service.openDirectChat(
          contactId: contact.id,
          name: contact.fullName,
          phone: contact.phone,
          avatarPath: contact.avatarPath ?? '',
          username: contact.username,
          bio: contact.bio,
        );
        if (chatId.isEmpty) continue;
        await service.sendMessage(
          chatId: chatId,
          text: body,
          peerUid: contact.id,
        );
        sent++;
      } on Object catch (error) {
        debugPrint('Broadcast to ${contact.id} failed: $error');
      }
    }

    if (!mounted) return;
    iToast(
      context,
      sent == 0
          ? 'Nothing could be sent — check your connection'
          : 'Broadcast sent to $sent ${sent == 1 ? 'person' : 'people'}',
      isError: sent == 0,
    );
  }

  void _openList(BroadcastList list, List<Contact> contacts) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: sheetContext.c.card,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                list.name,
                style: sheetContext.t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.recipients(list.recipientIds.length),
                style: sheetContext.t.bodySmall?.copyWith(
                  color: sheetContext.c.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.recipientIds.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (BuildContext context, int i) {
                    final String id = list.recipientIds[i];
                    final Contact? c =
                        contacts.where((Contact x) => x.id == id).firstOrNull;
                    return Column(
                      children: <Widget>[
                        IAvatar(
                          name: c?.fullName ?? 'Unknown',
                          imagePath: c?.avatarPath,
                          colorSeed: c?.avatarColor,
                          size: AppSizes.avatarMd,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 60,
                          child: Text(
                            c?.firstName ?? 'Unknown',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: sheetContext.t.labelSmall,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ProminentButton(
                label: context.l10n.sendABroadcast,
                icon: Icons.send_rounded,
                expanded: true,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _sendBroadcast(list, contacts);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
