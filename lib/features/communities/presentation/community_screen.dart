import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/group.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../groups/presentation/widgets/group_picker.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// A single community: announcement chat, member groups and members.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key, required this.communityId});

  final String communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(communityByIdProvider(communityId)).when(
          loading: () => const Scaffold(body: Center(child: ILoader(size: 26))),
          error: (Object e, StackTrace s) => Scaffold(
            appBar: AppTopBar(title: context.l10n.community, showBack: true),
            body: errorStateFor(context, e),
          ),
          data: (Community? community) {
            if (community == null) {
              return Scaffold(
                appBar: AppTopBar(title: context.l10n.community, showBack: true),
                body: EmptyState(
                  icon: Icons.groups_2_outlined,
                  title: context.l10n.communityNotFound,
                  message: context.l10n.itWasDeletedFromThis,
                ),
              );
            }
            return _Body(community: community);
          },
        );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Group> allGroups = ref.watch(groupsProvider).orEmpty;
    final List<Group> groups = allGroups
        .where((Group g) => community.groupIds.contains(g.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.community),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.edit,
            onPressed: () => _rename(context, ref),
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
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
                  name: community.name,
                  imagePath: community.avatarPath,
                  colorSeed: community.avatarColor,
                  size: AppSizes.avatarXl,
                  isGroup: true,
                  icon: Icons.groups_2_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  community.name,
                  style: context.t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${groups.length} ${groups.length == 1 ? 'group' : 'groups'} · '
                  '${TextUtils.members(community.memberIds.length)}',
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          if (community.description.isNotEmpty)
            SettingsGroup(
              title: context.l10n.about,
              children: <Widget>[
                SettingsTile(
                  title: community.description,
                  subtitle: context.l10n.tapToEdit,
                  leadingIcon: Icons.notes_rounded,
                  onTap: () => _editDescription(context, ref),
                ),
              ],
            ),

          SettingsGroup(
            title: context.l10n.announcements,
            footer:
                context.l10n.everyoneInTheCommunityReceives2,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.openAnnouncementChat,
                subtitle: community.announcementChatId == null
                    ? 'Not created yet'
                    : 'Broadcast to all members',
                leadingIcon: Icons.campaign_outlined,
                leadingIconColor: context.c.accent,
                onTap: () {
                  if (community.announcementChatId == null) {
                    iToast(context, context.l10n.announcementChatIsNotReady);
                    return;
                  }
                  context.push(
                    '${AppRoutes.chat}/${community.announcementChatId}',
                  );
                },
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.groupsInThisCommunity,
            children: <Widget>[
              for (final Group g in groups)
                SettingsTile(
                  title: g.name,
                  subtitle: TextUtils.members(g.memberCount),
                  leading: IAvatar(
                    name: g.name,
                    imagePath: g.avatarPath,
                    colorSeed: g.avatarColor,
                    size: AppSizes.avatarSm,
                    isGroup: true,
                    icon: Icons.groups_rounded,
                  ),
                  onTap: () => context.push('${AppRoutes.groupInfo}/${g.id}'),
                ),
              SettingsTile(
                title: context.l10n.createAGroupHere,
                subtitle: context.l10n.newGroupThatIsAutomatically,
                leadingIcon: Icons.add_rounded,
                leadingIconColor: context.c.accent,
                onTap: () => context.push(
                  '${AppRoutes.newGroup}?community=${community.id}',
                ),
              ),
              SettingsTile(
                title: context.l10n.addExistingGroups,
                subtitle: context.l10n.linkGroupsYouAlreadyCreated,
                leadingIcon: Icons.link_rounded,
                onTap: () => _addGroups(context, ref, allGroups),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.members,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.invitePeople,
                subtitle: context.l10n.addContactsToThisCommunity,
                leadingIcon: Icons.person_add_alt_1_rounded,
                leadingIconColor: context.c.accent,
                onTap: () => _invite(context, ref),
              ),
              SettingsTile(
                title: context.l10n.copyInviteLink,
                subtitle: 'imo://community/${community.id}',
                leadingIcon: Icons.link_rounded,
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: 'imo://community/${community.id}'),
                  );
                  if (!context.mounted) return;
                  iToast(context, context.l10n.inviteLinkCopied);
                },
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.dangerZone,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.deleteCommunity,
                subtitle: context.l10n.removeTheCommunityAndIts,
                leadingIcon: Icons.delete_forever_rounded,
                leadingIconColor: context.c.onDanger,
                titleColor: context.c.onDanger,
                onTap: () => _delete(context, ref),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final String? name = await showTextPrompt(
      context,
      title: context.l10n.communityName,
      initialValue: community.name,
      hint: context.l10n.communityName,
      confirmLabel: context.l10n.save,
      maxLength: 60,
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(communitiesProvider.notifier).persist(
          community.copyWith(name: name.trim()),
        );
    if (!context.mounted) return;
    iToast(context, context.l10n.communityRenamed);
  }

  Future<void> _editDescription(BuildContext context, WidgetRef ref) async {
    final String? text = await showTextPrompt(
      context,
      title: context.l10n.communityDescription,
      initialValue: community.description,
      hint: context.l10n.whatIsThisCommunityAbout,
      confirmLabel: context.l10n.save,
      maxLength: 200,
      maxLines: 3,
    );
    if (text == null) return;
    await ref.read(communitiesProvider.notifier).persist(
          community.copyWith(description: text.trim()),
        );
    if (!context.mounted) return;
    iToast(context, context.l10n.descriptionUpdated);
  }

  Future<void> _addGroups(
    BuildContext context,
    WidgetRef ref,
    List<Group> allGroups,
  ) async {
    final List<Group> candidates = allGroups
        .where((Group g) => !community.groupIds.contains(g.id))
        .toList();

    if (candidates.isEmpty) {
      iToast(context, context.l10n.everyGroupIsAlreadyIn);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => Container(
        height: MediaQuery.sizeOf(sheetContext).height * 0.6,
        decoration: BoxDecoration(
          color: sheetContext.c.card,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: <Widget>[
                  Text(
                    context.l10n.addGroups,
                    style: sheetContext.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(context.l10n.done),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: candidates.length,
                itemBuilder: (BuildContext context, int i) {
                  final Group g = candidates[i];
                  return SettingsTile(
                    title: g.name,
                    subtitle: TextUtils.members(g.memberCount),
                    leading: IAvatar(
                      name: g.name,
                      size: AppSizes.avatarSm,
                      isGroup: true,
                      icon: Icons.groups_rounded,
                    ),
                    trailing: const Icon(Icons.add_circle_outline_rounded),
                    onTap: () async {
                      await ref.read(communitiesProvider.notifier).persist(
                            community.copyWith(
                              groupIds: <String>[...community.groupIds, g.id],
                            ),
                          );
                      if (!sheetContext.mounted) return;
                      Navigator.pop(sheetContext);
                      iToast(context, context.l10n.added(g.name));
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

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final List<String> memberIds = community.memberIds;
    final List<Contact>? picked = await pickContacts(
      context: context,
      ref: ref,
      title: context.l10n.inviteTo(community.name),
      initiallySelected: memberIds.toSet(),
    );
    if (picked == null) return;
    await ref.read(communitiesProvider.notifier).persist(
          community.copyWith(
            memberIds: picked.map((Contact c) => c.id).toList(),
          ),
        );
    if (!context.mounted) return;
    iToast(context, context.l10n.membersCount(picked.length));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.delete3(community.name),
      message:
          context.l10n.theCommunityIsRemovedFrom2,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(communitiesProvider.notifier).delete(community.id);
    if (!context.mounted) return;
    iToast(context, context.l10n.communityDeleted);
    context.pop();
  }
}
