import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/group.dart';
import '../../../core/services/media_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../groups/presentation/widgets/group_picker.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Create a community with an announcement group and initial members.
class NewCommunityScreen extends ConsumerStatefulWidget {
  const NewCommunityScreen({super.key});

  @override
  ConsumerState<NewCommunityScreen> createState() => _NewCommunityScreenState();
}

class _NewCommunityScreenState extends ConsumerState<NewCommunityScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  final List<Contact> _members = <Contact>[];
  String? _avatarPath;
  bool _announcementOnly = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canCreate = _name.text.trim().isNotEmpty && !_busy;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.newCommunity),
        actions: <Widget>[
          TextButton(
            onPressed: canCreate ? _create : null,
            child: Text(
              context.l10n.create,
              style: TextStyle(
                color: canCreate ? context.c.accent : context.c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
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
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: <Widget>[
                      IAvatar(
                        name: _name.text.isEmpty ? 'C' : _name.text,
                        imagePath: _avatarPath,
                        size: AppSizes.avatarXl,
                        isGroup: true,
                        icon: Icons.groups_2_rounded,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.l10n.addACommunityPhoto,
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SettingsGroup(
            title: context.l10n.details,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: ITextField(
                  controller: _name,
                  hint: context.l10n.communityName,
                  maxLength: 60,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: ITextField(
                  controller: _description,
                  hint: context.l10n.descriptionOptional,
                  maxLines: 3,
                  maxLength: 200,
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.members2(_members.length),
            footer:
                context.l10n.everyoneYouAddBecomesA2,
            children: <Widget>[
              for (final Contact c in _members)
                SettingsTile(
                  title: c.fullName,
                  subtitle: c.phone,
                  leading: IAvatar(
                    name: c.fullName,
                    imagePath: c.avatarPath,
                    imageUrl: c.avatarUrl,
                    colorSeed: c.avatarColor,
                    size: AppSizes.avatarSm,
                  ),
                  trailing: IconButton(
                    tooltip: context.l10n.remove,
                    onPressed: () => setState(() => _members.remove(c)),
                    icon: const Icon(Icons.close_rounded,
                        size: AppIconSizes.sm),
                  ),
                ),
              SettingsTile(
                title: context.l10n.addMembers,
                subtitle: context.l10n.pickPeopleFromYourContacts,
                leadingIcon: Icons.person_add_alt_1_rounded,
                leadingIconColor: context.c.accent,
                onTap: _addMembers,
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.announcements,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.adminOnlyAnnouncements,
                subtitle: context.l10n.onlyYouAndOtherAdmins,
                value: _announcementOnly,
                onChanged: (bool v) => setState(() => _announcementOnly = v),
              ),
            ],
          ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: InfoBanner(
              message:
                  context.l10n.communitiesLiveOnThisDevice2,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ProminentButton(
              label: _busy ? 'Creating…' : 'Create community',
              icon: Icons.check_rounded,
              expanded: true,
              onPressed: canCreate ? _create : () {},
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final MediaPickResult picked =
        await ref.read(mediaServiceProvider).pickImages();
    if (!mounted) return;
    if (picked.permissionDenied) {
      iToast(context, context.l10n.galleryPermissionIsRequired, isError: true);
      return;
    }
    final String? path = picked.attachments.firstOrNull?.localPath;
    if (path == null) return;
    setState(() => _avatarPath = path);
  }

  Future<void> _addMembers() async {
    final List<Contact>? picked = await pickContacts(
      context: context,
      ref: ref,
      title: context.l10n.addMembers,
      initiallySelected: _members.map((Contact c) => c.id).toSet(),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _members
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _create() async {
    final String name = _name.text.trim();
    if (name.isEmpty) return;

    setState(() => _busy = true);
    final String id = 'community_${DateTime.now().microsecondsSinceEpoch}';

    final Community community = Community(
      id: id,
      name: name,
      description: _description.text.trim(),
      avatarPath: _avatarPath,
      groupIds: const <String>[],
      memberIds: <String>[
        'self',
        ..._members.map((Contact c) => c.id),
      ],
      createdAt: DateTime.now(),
    );

    final Community saved =
        await ref.read(communitiesProvider.notifier).create(community);

    if (!mounted) return;
    setState(() => _busy = false);
    iToast(context, context.l10n.communityCreatedName(name));
    context.pushReplacement('${AppRoutes.community}/${saved.id}');
  }
}
