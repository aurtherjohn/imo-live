import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/group.dart';
import '../../../core/models/message.dart';
import '../../../core/models/message_parts.dart';
import '../../../core/services/media_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import 'widgets/group_picker.dart';
import '../../../core/utils/l10n.dart';

/// Create a group: name it, pick a photo, and choose members.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String? _photoPath;
  List<Contact> _members = <Contact>[];
  final Set<String> _adminIds = <String>{};
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canCreate => _name.text.trim().isNotEmpty && _members.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.newGroup),
        actions: <Widget>[
          TextButton(
            onPressed: _canCreate && !_creating ? _create : null,
            child: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    context.l10n.create,
                    style: TextStyle(
                      color: _canCreate
                          ? context.c.accent
                          : context.c.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Column(
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      IAvatar(
                        name: _name.text.trim().isEmpty
                            ? 'New group'
                            : _name.text.trim(),
                        imagePath: _photoPath,
                        size: AppSizes.avatarXl,
                        isGroup: true,
                        icon: Icons.groups_rounded,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: context.c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _photoPath == null ? 'Add group photo' : 'Change photo',
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          Padding(
            padding: AppSpacing.pageH,
            child: Text(
              context.l10n.groupNAME,
              style: context.t.labelMedium?.copyWith(
                color: context.c.textSecondary,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: ITextField(
              controller: _name,
              hint: context.l10n.eGWeekendRiders,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              context.l10n.description2,
              style: context.t.labelMedium?.copyWith(
                color: context.c.textSecondary,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: ITextField(
              controller: _description,
              hint: context.l10n.whatIsThisGroupAbout,
              maxLines: 3,
              maxLength: 200,
            ),
          ),

          SectionHeader(title: context.l10n.members),

          Padding(
            padding: AppSpacing.pageH,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _members.isEmpty
                        ? 'Add at least one member'
                        : '${_members.length} selected'
                            '${_adminIds.isEmpty ? '' : ' · ${_adminIds.length} admin'}',
                    style: context.t.bodySmall?.copyWith(
                      color: _members.isEmpty
                          ? context.c.textSecondary
                          : context.c.accent,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => pickContacts(
                    context: context,
                    ref: ref,
                    initiallySelected: _members.map((Contact c) => c.id).toSet(),
                  ).then((List<Contact>? picked) {
                    if (picked == null || !mounted) return;
                    setState(() {
                      _members = picked;
                      _adminIds.removeWhere(
                        (String id) =>
                            !picked.any((Contact c) => c.id == id),
                      );
                    });
                  }),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(_members.isEmpty ? 'Add members' : 'Change'),
                ),
              ],
            ),
          ),

          if (_members.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: AppSpacing.lg),
              child: EmptyState(
                icon: Icons.group_add_rounded,
                title: context.l10n.noMembersYet,
                message:
                    context.l10n.aGroupNeedsAtLeast2,
                compact: true,
              ),
            )
          else
            Padding(
              padding: AppSpacing.pageH,
              child: Container(
                decoration: BoxDecoration(
                  color: context.c.card,
                  borderRadius: AppRadius.rLg,
                  border: Border.all(
                    color: context.c.divider.withValues(alpha: 0.7),
                    width: 0.8,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < _members.length; i++) ...<Widget>[
                      _MemberRow(
                        contact: _members[i],
                        isAdmin: _adminIds.contains(_members[i].id),
                        onToggleAdmin: () => setState(() {
                          final String id = _members[i].id;
                          if (!_adminIds.remove(id)) _adminIds.add(id);
                        }),
                        onRemove: () => setState(() {
                          _adminIds.remove(_members[i].id);
                          _members = List<Contact>.from(_members)
                            ..removeAt(i);
                        }),
                      ),
                      if (i != _members.length - 1)
                        IListDivider(indent: AppSizes.avatarMd + AppSpacing.lg + AppSpacing.md),
                    ],
                  ],
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.xl),

          Padding(
            padding: AppSpacing.pageH,
            child: ICard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.shield_outlined,
                        size: AppIconSizes.md,
                        color: context.c.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          context.l10n.youWillBeTheGroup,
                          style: context.t.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l10n.adminsCanAddOrRemove2,
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: AppSpacing.pageH,
            child: ProminentButton(
              label: _members.isEmpty
                  ? 'Add members to continue'
                  : 'Create group',
              icon: Icons.check_rounded,
              expanded: true,
              onPressed: _canCreate && !_creating ? _create : () {},
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final MediaPickResult result =
        await ref.read(mediaServiceProvider).pickImages();
    if (!mounted) return;
    if (result.isEmpty) {
      if (result.error != null) iToast(context, result.error!, isError: true);
      return;
    }
    final String? path = result.attachments.first.localPath;
    if (path == null) {
      iToast(context, context.l10n.couldNotReadTheSelected, isError: true);
      return;
    }
    final String stored = await ref.read(mediaRepositoryProvider).upload(path);
    if (mounted) setState(() => _photoPath = stored);
  }

  Future<void> _create() async {
    setState(() => _creating = true);

    final String groupId = 'g_${DateTime.now().microsecondsSinceEpoch}';
    final String chatId = 'chat_$groupId';
    final String myName =
        ref.read(selfProfileProvider).valueOrNull?.fullName ?? 'You';
    final DateTime now = DateTime.now();

    final List<GroupMember> members = <GroupMember>[
      GroupMember(
        contactId: 'self',
        role: GroupRole.admin,
        joinedAt: now,
      ),
      ..._members.map(
        (Contact c) => GroupMember(
          contactId: c.id,
          role: _adminIds.contains(c.id) ? GroupRole.admin : GroupRole.member,
          joinedAt: now,
        ),
      ),
    ];

    final Group group = Group(
      id: groupId,
      name: _name.text.trim(),
      description: _description.text.trim(),
      avatarPath: _photoPath,
      members: members,
      createdAt: now,
      inviteCode: _inviteCode(groupId),
    );

    // Every `context.l10n` read is hoisted above the first `await`: reading one
    // after an async gap is flagged by `use_build_context_synchronously`, and
    // these three are all consumed by writes that happen later still.
    final String createdMessage =
        context.l10n.createdTheGroup(myName, _name.text.trim());
    final String createdPreview = context.l10n.youCreatedTheGroup;
    final String systemSender = context.l10n.system;

    await ref.read(groupsProvider.notifier).save(group);

    final Chat chat = Chat(
      id: chatId,
      title: group.name,
      lastMessage: createdPreview,
      lastTimestamp: now,
      avatarPath: group.avatarPath,
      isGroup: true,
      memberIds: members.map((GroupMember m) => m.contactId).toList(),
      memberCount: members.length,
      description: group.description,
    );
    await ref.read(chatsProvider.notifier).create(chat);

    await ref.read(messageRepositoryProvider).save(
          Message(
            id: 'sys_${DateTime.now().microsecondsSinceEpoch}',
            chatId: chatId,
            senderId: 'system',
            senderName: systemSender,
            content: createdMessage,
            timestamp: now,
            direction: MessageDirection.incoming,
            type: MessageType.system,
            status: MessageStatus.read,
          ),
        );

    if (!mounted) return;
    setState(() => _creating = false);
    iToast(context, context.l10n.groupCreated);
    context.pushReplacement('${AppRoutes.chat}/$chatId');
  }

  static String _inviteCode(String seed) {
    final int hash = seed.codeUnits.fold<int>(17, (int a, int b) => a * 31 + b);
    final String chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final StringBuffer buffer = StringBuffer();
    int value = hash.abs();
    for (int i = 0; i < 8; i++) {
      buffer.write(chars[value % chars.length]);
      value = (value ~/ chars.length) + 7;
    }
    return buffer.toString();
  }
}

/// A member row with admin toggle and remove.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.contact,
    required this.isAdmin,
    required this.onToggleAdmin,
    required this.onRemove,
  });

  final Contact contact;
  final bool isAdmin;
  final VoidCallback onToggleAdmin;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: <Widget>[
          IAvatar(
            name: contact.fullName,
            imagePath: contact.avatarPath,
            colorSeed: contact.avatarColor,
            size: AppSizes.avatarSm,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    contact.fullName,
                    style: context.t.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isAdmin) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  IPill(
                    label: context.l10n.admin,
                    color: context.c.accent,
                    filled: true,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onToggleAdmin,
            icon: Icon(
              isAdmin
                  ? Icons.admin_panel_settings_rounded
                  : Icons.admin_panel_settings_outlined,
              size: AppIconSizes.sm,
              color: isAdmin ? context.c.accent : context.c.textSecondary,
            ),
            tooltip: isAdmin ? 'Remove as admin' : 'Make admin',
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(
              Icons.close_rounded,
              size: AppIconSizes.sm,
              color: context.c.textSecondary,
            ),
            tooltip: context.l10n.remove,
          ),
        ],
      ),
    );
  }
}
