import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../earn/presentation/providers.dart';
import '../../earn/presentation/widgets/premium_badge.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Your own profile — the same layout as a contact page, with edit actions.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Contact me = ref.watch(selfProfileProvider).valueOrNull ??
        const Contact(id: 'self', firstName: 'You');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.profile),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.push(
              '${AppRoutes.qr}?title=${Uri.encodeComponent(me.fullName)}'
              '&payload=${Uri.encodeComponent('imo://user/${me.id}')}',
            ),
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: context.l10n.myQRCode,
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
                GestureDetector(
                  onTap: () => context.push(AppRoutes.editProfile),
                  child: Stack(
                    children: <Widget>[
                      IAvatar(
                        name: me.fullName,
                        imagePath: me.avatarPath,
                        imageUrl: me.avatarUrl,
                        colorSeed: me.avatarColor,
                        size: AppSizes.avatarXxl,
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: context.c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        me.fullName,
                        style: context.t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ref.watch(isPremiumProvider)) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      const PremiumBadge(),
                    ],
                  ],
                ),
                if (me.username.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '@${me.username}',
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.accent,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                  child: Text(
                    me.aboutText,
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.textSecondary,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          Padding(
            padding: AppSpacing.pageH,
            child: ProminentButton(
              label: context.l10n.editProfile,
              icon: Icons.edit_outlined,
              expanded: true,
              onPressed: () => context.push(AppRoutes.editProfile),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          SettingsGroup(
            title: context.l10n.myDetails,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.name,
                value: me.fullName,
                leadingIcon: Icons.person_outline_rounded,
                onTap: () => context.push(AppRoutes.editProfile),
              ),
              SettingsValueRow(
                label: context.l10n.about,
                value: me.aboutText,
                leadingIcon: Icons.info_outline_rounded,
                onTap: () => context.push(AppRoutes.editProfile),
              ),
              SettingsValueRow(
                label: context.l10n.username,
                value: me.username.isEmpty ? 'Not set' : '@${me.username}',
                leadingIcon: Icons.alternate_email_rounded,
                onTap: () => context.push(AppRoutes.editProfile),
              ),
              SettingsValueRow(
                label: context.l10n.phone,
                value: me.phone.isEmpty
                    ? AppConstants.unsetPhoneLabel
                    : me.phone,
                leadingIcon: Icons.phone_outlined,
                onTap: () => context.push(AppRoutes.account),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.myActivity,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.tabChats,
                value: '${ref.watch(chatCountProvider)}',
                leadingIcon: Icons.chat_bubble_outline_rounded,
                onTap: () => context.go(AppRoutes.chats),
              ),
              SettingsValueRow(
                label: context.l10n.tabContacts,
                value: '${ref.watch(contactCountProvider)}',
                leadingIcon: Icons.people_outline_rounded,
                onTap: () => context.push(AppRoutes.selectContact),
              ),
              SettingsValueRow(
                label: context.l10n.starredMessages,
                value: '${ref.watch(starCountProvider)}',
                leadingIcon: Icons.star_border_rounded,
                onTap: () => context.push(AppRoutes.starred),
              ),
              SettingsValueRow(
                label: context.l10n.linkedDevices,
                value: '${ref.watch(linkedDevicesProvider).orEmpty.length}',
                leadingIcon: Icons.devices_rounded,
                onTap: () => context.push(AppRoutes.linkedDevices),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.account,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.privacy,
                leadingIcon: Icons.lock_outline_rounded,
                value: context.l10n.manage,
                onTap: () => context.push(AppRoutes.privacy),
              ),
              SettingsValueRow(
                label: context.l10n.favourites,
                value:
                    '${ref.watch(favoritesProvider).valueOrNull?.length ?? 0}',
                leadingIcon: Icons.favorite_border_rounded,
                onTap: () => context.push(AppRoutes.favorites),
              ),
              SettingsValueRow(
                label: context.l10n.storageAndData,
                leadingIcon: Icons.storage_rounded,
                value: ref.watch(totalStorageProvider) == 0
                    ? 'No media'
                    : 'In use',
                onTap: () => context.push(AppRoutes.storage),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.sharing,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.shareMyQRCode,
                subtitle: context.l10n.letSomeoneScanToAdd,
                leadingIcon: Icons.qr_code_rounded,
                onTap: () => context.push(
                  '${AppRoutes.qr}?title=${Uri.encodeComponent(me.fullName)}'
                  '&payload=${Uri.encodeComponent('imo://user/${me.id}')}',
                ),
              ),
              SettingsTile(
                title: context.l10n.shareMyContactCard,
                subtitle: context.l10n.sendYourNameAndNumber,
                leadingIcon: Icons.contact_page_outlined,
                onTap: () {
                  final String handle =
                      me.username.isNotEmpty ? '\n@${me.username}' : '';
                  final String number =
                      me.phone.isNotEmpty ? '\n${me.phone}' : '';
                  ref.read(shareServiceProvider).shareText(
                        '${me.fullName}$handle$number',
                        subject: me.fullName,
                      );
                },
              ),
              SettingsTile(
                title: context.l10n.lastSeen,
                subtitle:
                    context.l10n.thisDeviceShowsYouAs(me.isOnline ? context.l10n.online : context.l10n.offline),
                leadingIcon: Icons.schedule_rounded,
                onTap: () => context.push(AppRoutes.privacy),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
