import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/group.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import 'widgets/group_picker.dart';
import '../../../core/utils/l10n.dart';

/// Full group management: members, roles, permissions and destructive actions.
class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  @override
  Widget build(BuildContext context) {
    final AsyncValue<Group?> groupAsync =
        ref.watch(groupByIdProvider(widget.groupId));

    return groupAsync.when(
      loading: () => const Scaffold(body: Center(child: ILoader(size: 26))),
      error: (Object e, StackTrace s) => Scaffold(
        appBar: AppTopBar(title: context.l10n.groupInfo, showBack: true),
        body: errorStateFor(context, e),
      ),
      data: (Group? group) {
        if (group == null) {
          return Scaffold(
            appBar: AppTopBar(title: context.l10n.groupInfo, showBack: true),
            body: EmptyState(
              icon: Icons.group_off_outlined,
              title: context.l10n.groupNotFound,
              message: context.l10n.thisGroupWasDeletedOr,
            ),
          );
        }
        return _buildBody(context, group);
      },
    );
  }

  Widget _buildBody(BuildContext context, Group group) {
    final List<Contact> contacts = ref.watch(contactsProvider).orEmpty;    final Chat? chat = ref
        .watch(chatsProvider)
        .orEmpty
        .where((Chat c) => c.id == 'chat_${group.id}' || c.id == group.id)
        .firstOrNull;

    Contact? contactFor(String id) {
      if (id == 'self') {
        return ref.watch(selfProfileProvider).valueOrNull;
      }
      return contacts.where((Contact c) => c.id == id).firstOrNull;
    }

    final bool canManage = group.members.any(
      (GroupMember m) => m.contactId == 'self' && m.isAdmin,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.groupInfo),
        actions: <Widget>[
          if (canManage)
            IconButton(
              onPressed: () => _editGroup(group),
              icon: const Icon(Icons.edit_outlined),
              tooltip: context.l10n.editGroup,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Column(
              children: <Widget>[
                IAvatar(
                  name: group.name,
                  imagePath: group.avatarPath,
                  colorSeed: group.avatarColor,
                  size: AppSizes.avatarXxl,
                  isGroup: true,
                  icon: Icons.groups_rounded,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  group.name,
                  style: context.t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.group2(TextUtils.members(group.memberCount)),
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary,
                  ),
                ),
                if (group.createdAt != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.created2(DateFormatter.relative(group.createdAt!)),
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          Padding(
            padding: AppSpacing.pageH,
            child: Row(
              children: <Widget>[
                _Action(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: context.l10n.message,
                  onTap: chat == null
                      ? null
                      : () => context.push('${AppRoutes.chat}/${chat.id}'),
                ),
                _Action(
                  icon: Icons.call_outlined,
                  label: context.l10n.call,
                  onTap: () => context.push(
                    '${AppRoutes.call}?id=${group.id}'
                    '&name=${Uri.encodeComponent(group.name)}',
                  ),
                ),
                _Action(
                  icon: Icons.videocam_outlined,
                  label: context.l10n.video,
                  onTap: () => context.push(
                    '${AppRoutes.call}?id=${group.id}'
                    '&name=${Uri.encodeComponent(group.name)}'
                    '&video=true',
                  ),
                ),
                _Action(
                  icon: Icons.link_rounded,
                  label: context.l10n.invite,
                  onTap: () => _showInvite(group),
                ),
              ],
            ),
          ),

          if (group.description.isNotEmpty)
            SettingsGroup(
              title: context.l10n.description,
              children: <Widget>[
                SettingsTile(
                  title: group.description,
                  subtitle: context.l10n.tapToEdit,
                  leadingIcon: Icons.notes_rounded,
                  onTap: canManage ? () => _editDescription(group) : null,
                ),
              ],
            ),

          SettingsGroup(
            title: context.l10n.members3(group.memberCount),
            footer: canManage
                ? 'Admins can add or remove members and change group settings.'
                : 'Only admins can change group settings.',
            children: <Widget>[
              // Index-based rather than `member != group.members.last`, which
              // relied on object identity and mis-drew the divider whenever two
              // members compared equal.
              for (int i = 0; i < group.members.length; i++) ...<Widget>[
                Builder(
                  builder: (BuildContext context) {
                    final GroupMember member = group.members[i];
                    final bool isSelf = member.contactId == 'self';
                    final Contact? contact = contactFor(member.contactId);
                    final String name = isSelf
                        ? 'You'
                        : contact?.fullName ?? 'Unknown member';
                    return SettingsTile(
                      title: name,
                      subtitle: member.isAdmin
                          ? 'Admin'
                          : contact?.aboutText ?? 'Member',
                      leading: IAvatar(
                        name: name,
                        imagePath: contact?.avatarPath,
                        colorSeed: contact?.avatarColor,
                        size: AppSizes.avatarSm,
                        isOnline: contact?.isOnline ?? false,
                        showPresence: !isSelf,
                      ),
                      trailing: member.isAdmin
                          ? IPill(
                              label: context.l10n.admin,
                              color: context.c.accent,
                              filled: true,
                            )
                          : null,
                      onTap: isSelf || contact == null
                          ? null
                          : () => _memberActions(group, contact, member),
                    );
                  },
                ),
                if (i < group.members.length - 1)
                  IListDivider(
                    indent: AppSizes.avatarSm + AppSpacing.lg + AppSpacing.md,
                  ),
              ],
              if (canManage)
                SettingsTile(
                  title: context.l10n.addMembers,
                  subtitle: context.l10n.inviteMorePeopleTo(group.name),
                  leadingIcon: Icons.person_add_alt_1_rounded,
                  leadingIconColor: context.c.accent,
                  onTap: () => _addMembers(group),
                ),
              if (group.members.any((GroupMember m) => m.contactId == 'self'))
                SettingsTile(
                  title: context.l10n.exitGroup,
                  subtitle: context.l10n.leave(group.name),
                  leadingIcon: Icons.logout_rounded,
                  leadingIconColor: context.c.onDanger,
                  titleColor: context.c.onDanger,
                  onTap: () => _exitGroup(group, chat),
                ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.groupSettings,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.muteNotifications,
                subtitle: context.l10n.silenceAlertsForThisGroup,
                value: chat?.isMuted ?? false,
                enabled: chat != null,
                onChanged: chat == null
                    ? null
                    : (bool v) async {
                        await ref
                            .read(chatsProvider.notifier)
                            .toggleMute(chat.id);
                        if (context.mounted) {
                          iToast(context, v ? 'Muted' : 'Unmuted');
                        }
                      },
              ),
              SettingsValueRow(
                label: context.l10n.disappearingMessages,
                value: chat == null
                    ? 'No chat'
                    : group.disappearingSeconds == 0 &&
                            chat.disappearingSeconds == 0
                        ? 'Off'
                        : DateFormatter.longDuration(
                            Duration(
                              seconds: chat.disappearingSeconds != 0
                                  ? chat.disappearingSeconds
                                  : group.disappearingSeconds,
                            ),
                          ),
                leadingIcon: Icons.timer_outlined,
                onTap: () => context.push(AppRoutes.chatSettings),
              ),
              SettingsValueRow(
                label: context.l10n.starredMessages,
                value: '${ref.watch(starCountProvider)}',
                leadingIcon: Icons.star_border_rounded,
                onTap: () => context.push(AppRoutes.starred),
              ),
              SettingsValueRow(
                label: context.l10n.mediaLinksAndDocs,
                value: '${chat == null ? 0 : 1} chat',
                leadingIcon: Icons.photo_library_outlined,
                onTap: () => showInfoDialog(
                  context,
                  title: context.l10n.sharedMedia,
                  message:
                      context.l10n.openTheConversationAndTap2,
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.adminPermissions,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.sendMessages,
                subtitle: context.l10n.allowMembersToSendMessages,
                value: group.permissions.sendMessages,
                onChanged: canManage
                    ? (bool v) => ref
                        .read(groupsProvider.notifier)
                        .updatePermissions(
                          group.id,
                          group.permissions.copyWith(sendMessages: v),
                        )
                    : null,
              ),
              SettingsSwitchRow(
                title: context.l10n.editGroupInfo,
                subtitle: context.l10n.allowMembersToChangeThe,
                value: group.permissions.editGroupInfo,
                onChanged: canManage
                    ? (bool v) => ref
                        .read(groupsProvider.notifier)
                        .updatePermissions(
                          group.id,
                          group.permissions.copyWith(editGroupInfo: v),
                        )
                    : null,
              ),
              SettingsSwitchRow(
                title: context.l10n.addMembers,
                subtitle: context.l10n.allowMembersToAddOther,
                value: group.permissions.addMembers,
                onChanged: canManage
                    ? (bool v) => ref
                        .read(groupsProvider.notifier)
                        .updatePermissions(
                          group.id,
                          group.permissions.copyWith(addMembers: v),
                        )
                    : null,
              ),
              SettingsSwitchRow(
                title: context.l10n.inviteViaLink,
                subtitle: context.l10n.anyoneWithTheInviteLink,
                value: group.permissions.inviteViaLink,
                onChanged: canManage
                    ? (bool v) => ref
                        .read(groupsProvider.notifier)
                        .updatePermissions(
                          group.id,
                          group.permissions.copyWith(inviteViaLink: v),
                        )
                    : null,
              ),
              SettingsSwitchRow(
                title: context.l10n.approveNewMembers,
                subtitle: context.l10n.adminsMustApproveEveryoneWho,
                value: group.permissions.approvalRequired,
                onChanged: canManage
                    ? (bool v) => ref
                        .read(groupsProvider.notifier)
                        .updatePermissions(
                          group.id,
                          group.permissions.copyWith(approvalRequired: v),
                        )
                    : null,
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.inviteLink,
            footer:
                context.l10n.theInviteCodeIsGenerated2,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.copyInviteLink,
                subtitle: 'imo://group/${group.inviteCode}',
                leadingIcon: Icons.link_rounded,
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: 'imo://group/${group.inviteCode}'),
                  );
                  if (context.mounted) {
                    iToast(context, context.l10n.inviteLinkCopied);
                  }
                },
              ),
              SettingsTile(
                title: context.l10n.resetInviteLink,
                subtitle: context.l10n.invalidateTheCurrentCodeAnd,
                leadingIcon: Icons.refresh_rounded,
                onTap: () => showInfoDialog(
                  context,
                  title: context.l10n.resetInviteLink,
                  message:
                      context.l10n.invalidatingAnInviteLinkIs2,
                ),
              ),
            ],
          ),

          if (canManage)
            SettingsGroup(
              title: context.l10n.dangerZone,
              children: <Widget>[
                SettingsTile(
                  title: context.l10n.clearMessages,
                  subtitle: context.l10n.deleteEveryMessageInThis,
                  leadingIcon: Icons.cleaning_services_outlined,
                  leadingIconColor: context.c.onWarning,
                  onTap: () async {
                    final bool ok = await showConfirmDialog(
                      context,
                      title: context.l10n.clearAllMessages,
                      message:
                          context.l10n.everyMessageInIsPermanently(group.name),
                      confirmLabel: context.l10n.clearMessages,
                      destructive: true,
                    );
                    if (!ok || chat == null) return;
                    await ref.read(chatsProvider.notifier).clearChat(chat.id);
                    if (context.mounted) {
                      iToast(context, context.l10n.groupMessagesCleared);
                    }
                  },
                ),
                SettingsTile(
                  title: context.l10n.deleteGroup,
                  subtitle: context.l10n.removeTheGroupAndIts,
                  leadingIcon: Icons.delete_forever_rounded,
                  leadingIconColor: context.c.onDanger,
                  titleColor: context.c.onDanger,
                  onTap: () => _deleteGroup(group, chat),
                ),
              ],
            ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Future<void> _editGroup(Group group) async {
    final String? name = await showTextPrompt(
      context,
      title: context.l10n.groupName,
      initialValue: group.name,
      hint: context.l10n.groupName,
      confirmLabel: context.l10n.save,
      maxLength: 60,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    await ref.read(groupsProvider.notifier).save(
          group.copyWith(name: name.trim()),
        );
    await _syncChatTitle(group, name.trim());
    if (mounted) iToast(context, context.l10n.groupNameUpdated);
  }

  Future<void> _editDescription(Group group) async {
    final String? description = await showTextPrompt(
      context,
      title: context.l10n.groupDescription,
      initialValue: group.description,
      hint: context.l10n.whatIsThisGroupAbout,
      confirmLabel: context.l10n.save,
      maxLength: 200,
      maxLines: 3,
    );
    if (description == null || !mounted) return;
    await ref.read(groupsProvider.notifier).save(
          group.copyWith(description: description.trim()),
        );
    if (mounted) iToast(context, context.l10n.descriptionUpdated);
  }

  Future<void> _syncChatTitle(Group group, String title) async {
    final List<Chat> chats = ref.read(chatsProvider).orEmpty;
    final Chat? chat = chats
        .where((Chat c) => c.id == 'chat_${group.id}' || c.id == group.id)
        .firstOrNull;
    if (chat == null) return;
    await ref
        .read(chatsProvider.notifier)
        .save(chat.copyWith(title: title));
  }

  /// Opens the contact picker and adds everyone chosen to [group].
  ///
  /// Shared by the "Add members" tile and the overflow sheet's "Add members
  /// directly" entry — the latter used to just toast "Use \"Add members\"
  /// below", which is a hint rather than an action.
  Future<void> _addMembers(Group group) async {
    final List<Contact>? picked = await pickContacts(
      context: context,
      ref: ref,
      title: context.l10n.addMembers,
      initiallySelected:
          group.members.map((GroupMember m) => m.contactId).toSet(),
    );
    if (picked == null || !mounted) return;
    await ref.read(groupsProvider.notifier).addMembers(
          group.id,
          picked.map((Contact c) => c.id).toList(),
        );
    if (!mounted) return;
    iToast(
      context,
      context.l10n.membersAdded(picked.length),
    );
  }

  void _showInvite(Group group) {
    showActionSheet(
      context,
      title: context.l10n.inviteTo2(group.name),
      actions: <({IconData icon, String label, VoidCallback onTap, Color? color})>[
        (
          icon: Icons.link_rounded,
          label: context.l10n.copyInviteLink,
          onTap: () async {
            Navigator.pop(context);
            await Clipboard.setData(
              ClipboardData(text: 'imo://group/${group.inviteCode}'),
            );
            if (mounted) iToast(context, context.l10n.inviteLinkCopied);
          },
          color: null,
        ),
        (
          icon: Icons.qr_code_rounded,
          label: context.l10n.showQRCode,
          onTap: () {
            Navigator.pop(context);
            context.push(
              '${AppRoutes.qr}?title=${Uri.encodeComponent(group.name)}'
              '&payload=${Uri.encodeComponent('imo://group/${group.inviteCode}')}',
            );
          },
          color: null,
        ),
        (
          icon: Icons.person_add_alt_1_rounded,
          label: context.l10n.addMembersDirectly,
          onTap: () {
            Navigator.pop(context);
            _addMembers(group);
          },
          color: null,
        ),
      ],
    );
  }

  void _memberActions(Group group, Contact contact, GroupMember member) {
    showActionSheet(
      context,
      title: contact.fullName,
      actions: <({IconData icon, String label, VoidCallback onTap, Color? color})>[
        (
          icon: Icons.chat_bubble_outline_rounded,
          label: context.l10n.message2(contact.firstName),
          onTap: () {
            Navigator.pop(context);
            context.push('${AppRoutes.contactInfo}/${contact.id}');
          },
          color: null,
        ),
        (
          icon: member.isAdmin
              ? Icons.remove_moderator_outlined
              : Icons.admin_panel_settings_outlined,
          label: member.isAdmin ? 'Dismiss as admin' : 'Make group admin',
          onTap: () async {
            Navigator.pop(context);
            await ref.read(groupsProvider.notifier).setRole(
                  group.id,
                  contact.id,
                  member.isAdmin ? GroupRole.member : GroupRole.admin,
                );
            if (mounted) {
              iToast(
                context,
                member.isAdmin
                    ? '${contact.firstName} is no longer an admin'
                    : '${contact.firstName} is now an admin',
              );
            }
          },
          color: null,
        ),
        (
          icon: Icons.person_remove_outlined,
          label: context.l10n.removeFromGroup,
          onTap: () async {
            Navigator.pop(context);
            final bool ok = await showConfirmDialog(
              context,
              title: context.l10n.remove2(contact.fullName),
              message:
                  context.l10n.isRemovedFromGroupsAre(contact.firstName, group.name),
              confirmLabel: context.l10n.remove,
              destructive: true,
            );
            if (!ok || !mounted) return;
            await ref
                .read(groupsProvider.notifier)
                .removeMember(group.id, contact.id);
            if (mounted) {
              iToast(context, context.l10n.removed(contact.firstName));
            }
          },
          color: context.c.onDanger,
        ),
      ],
    );
  }

  Future<void> _exitGroup(Group group, Chat? chat) async {
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.exit(group.name),
      message:
          context.l10n.youLeaveTheGroupYour2,
      confirmLabel: context.l10n.exitGroup,
      destructive: true,
    );
    if (!ok || !mounted) return;

    final List<Chat> chats = ref.read(chatsProvider).orEmpty;
    final Chat? target = chat ??
        chats
            .where((Chat c) => c.id == 'chat_${group.id}' || c.id == group.id)
            .firstOrNull;

    if (target != null) {
      await ref.read(chatsProvider.notifier).deleteChat(target.id);
    }
    await ref.read(groupsProvider.notifier).delete(group.id);

    if (!mounted) return;
    iToast(context, context.l10n.youLeft(group.name));
    if (context.canPop()) context.pop();
  }

  Future<void> _deleteGroup(Group group, Chat? chat) async {
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.delete5(group.name),
      message:
          context.l10n.theGroupItsMembersAnd2,
      confirmLabel: context.l10n.deleteGroup,
      destructive: true,
    );
    if (!ok || !mounted) return;

    final List<Chat> chats = ref.read(chatsProvider).orEmpty;
    final Chat? target = chat ??
        chats
            .where((Chat c) => c.id == 'chat_${group.id}' || c.id == group.id)
            .firstOrNull;
    if (target != null) {
      await ref.read(chatsProvider.notifier).deleteChat(target.id);
    }
    await ref.read(groupsProvider.notifier).delete(group.id);

    if (!mounted) return;
    iToast(context, context.l10n.groupDeleted);
    if (context.canPop()) context.pop();
  }
}

/// One of the circular quick actions at the top of a group page.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rMd,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.c.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: AppIconSizes.md,
                    color: context.c.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  style: context.t.labelSmall?.copyWith(
                    color: context.c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
