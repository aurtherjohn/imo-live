import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_color_scheme.dart';
import '../../../core/models/chat.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/utils/l10n.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../channels/presentation/providers.dart';
import '../../chats/presentation/providers.dart';
import 'widgets/settings_widgets.dart';

/// The root settings screen.
///
/// Every row navigates to a real, functional screen — nothing here is a
/// decorative placeholder.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Contact> self = ref.watch(selfProfileProvider);
    final Contact profile =
        self.valueOrNull ?? const Contact(id: 'self', firstName: 'You');
    final List<Chat> chats = ref.watch(chatsProvider).orEmpty;
    final int occupied = ref.watch(chatCountProvider);
    final int starred = ref.watch(starCountProvider);
    final int archived = ref.watch(archivedChatsProvider).length;

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.settings, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          ProfileSummaryCard(
            name: profile.fullName.isEmpty ? 'You' : profile.fullName,
            about: profile.aboutText,
            imagePath: profile.avatarPath,
            colorSeed: profile.avatarColor,
            onTap: () => context.push(AppRoutes.profile),
            onQrTap: () => context.push(
              '${AppRoutes.qr}?title=${Uri.encodeComponent(profile.fullName)}'
              '&payload=${Uri.encodeComponent('imo://user/${profile.id}')}',
            ),
          ),
          const InfoBanner(),

          // ------------------------------------------------------------ account
          SettingsGroup(
            title: context.l10n.account,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.account,
                value: _accountValue(ref, profile),
                leadingIcon: Icons.vpn_key_outlined,
                onTap: () => context.push(AppRoutes.account),
              ),
              SettingsValueRow(
                label: context.l10n.privacy,
                value: 'Lock, last seen, blocked',
                leadingIcon: Icons.lock_outline_rounded,
                onTap: () => context.push(AppRoutes.privacy),
              ),
              SettingsValueRow(
                label: context.l10n.linkedDevices,
                value: 'Manage',
                leadingIcon: Icons.devices_rounded,
                onTap: () => context.push(AppRoutes.linkedDevices),
              ),
              SettingsValueRow(
                label: context.l10n.favourites,
                value: '${ref.watch(favoritesProvider).valueOrNull?.length ?? 0} contacts',
                leadingIcon: Icons.favorite_border_rounded,
                onTap: () => context.push(AppRoutes.favorites),
              ),
              SettingsValueRow(
                label: context.l10n.blockedContacts,
                value: '${ref.watch(blockedContactsProvider).valueOrNull?.length ?? 0}',
                leadingIcon: Icons.block_rounded,
                onTap: () => context.push(AppRoutes.blocked),
              ),
            ],
          ),

          // -------------------------------------------------------------- chats
          SettingsGroup(
            title: context.l10n.chats,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.chatSettings,
                value: 'Theme, enter key, auto-download',
                leadingIcon: Icons.chat_bubble_outline_rounded,
                onTap: () => context.push(AppRoutes.chatSettings),
              ),
              SettingsValueRow(
                label: context.l10n.wallpaper,
                value: ref.watch(wallpaperProvider).valueOrNull?.name ?? 'Default',
                leadingIcon: Icons.wallpaper_rounded,
                onTap: () => context.push(AppRoutes.wallpaper),
              ),
              SettingsValueRow(
                label: context.l10n.lists,
                value: '${chats.length} chats, $occupied indexed',
                leadingIcon: Icons.list_alt_rounded,
                onTap: () => context.push(AppRoutes.lists),
              ),
              SettingsValueRow(
                label: context.l10n.starredMessages,
                value: '$starred',
                leadingIcon: Icons.star_border_rounded,
                onTap: () => context.push(AppRoutes.starred),
              ),
              SettingsValueRow(
                label: context.l10n.archivedChats,
                value: '$archived',
                leadingIcon: Icons.archive_outlined,
                onTap: () => context.push(AppRoutes.archived),
              ),
              SettingsValueRow(
                label: context.l10n.broadcastLists,
                value: '${ref.watch(broadcastListsProvider).orEmpty.length}',
                leadingIcon: Icons.campaign_outlined,
                onTap: () => context.push(AppRoutes.broadcast),
              ),
            ],
          ),

          // ------------------------------------------------------ notifications
          SettingsGroup(
            title: context.l10n.notificationsStorage,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.notifications,
                value: ref.watch(notificationSettingsProvider).valueOrNull
                            ?.messageNotifications ==
                        true
                    ? 'On'
                    : 'Off',
                leadingIcon: Icons.notifications_none_rounded,
                onTap: () => context.push(AppRoutes.notifications),
              ),
              SettingsValueRow(
                label: context.l10n.storageAndData,
                value: ref.watch(totalStorageProvider) == 0
                    ? 'No media yet'
                    : '${ref.watch(starCountProvider)} starred',
                leadingIcon: Icons.storage_rounded,
                onTap: () => context.push(AppRoutes.storage),
              ),
            ],
          ),

          // --------------------------------------------------------- appearance
          SettingsGroup(
            title: context.l10n.appExperience,
            footer: context.l10n.theSwitchMatchesTheSystem2,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.darkMode,
                subtitle: switch (ref.watch(themeModeProvider)) {
                  ThemeMode.dark => 'On · dark theme',
                  ThemeMode.light => 'Off · light theme',
                  ThemeMode.system =>
                    'Following system · ${MediaQuery.platformBrightnessOf(context) == Brightness.dark ? 'dark' : 'light'}',
                },
                leadingIcon: ref.watch(themeModeProvider) == ThemeMode.dark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                value: ref.watch(themeModeProvider) == ThemeMode.dark ||
                    (ref.watch(themeModeProvider) == ThemeMode.system &&
                        MediaQuery.platformBrightnessOf(context) ==
                            Brightness.dark),
                onChanged: (bool dark) =>
                    ref.read(appearanceProvider.notifier).setDark(dark),
              ),
              SettingsValueRow(
                label: context.l10n.themeMode,
                value: switch (ref.watch(themeModeProvider)) {
                  ThemeMode.dark => 'Dark',
                  ThemeMode.light => 'Light',
                  ThemeMode.system => 'System',
                },
                leadingIcon: Icons.contrast_rounded,
                onTap: () => context.push(AppRoutes.appearance),
              ),
              SettingsValueRow(
                label: context.l10n.appearance,
                value: 'Accent, text size, chat theme, icon',
                leadingIcon: Icons.palette_outlined,
                onTap: () => context.push(AppRoutes.appearance),
              ),
              SettingsValueRow(
                label: context.l10n.language,
                value: ref.watch(languageProvider).valueOrNull == 'bn'
                    ? 'বাংলা'
                    : 'English',
                leadingIcon: Icons.translate_rounded,
                onTap: () => context.push(AppRoutes.language),
              ),
            ],
          ),

          // --------------------------------------------------------- support
          SettingsGroup(
            title: context.l10n.support,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.help,
                value: 'FAQ, contact us, terms',
                leadingIcon: Icons.help_outline_rounded,
                onTap: () => context.push(AppRoutes.help),
              ),
              SettingsValueRow(
                label: context.l10n.subscriptions,
                value: 'Channels & communities',
                leadingIcon: Icons.workspace_premium_outlined,
                onTap: () => context.push(AppRoutes.subscriptions),
              ),
              SettingsValueRow(
                label: context.l10n.about,
                value: '${AppConstants.appName} ${AppConstants.appVersion}',
                leadingIcon: Icons.info_outline_rounded,
                onTap: () => context.push(AppRoutes.about),
              ),
            ],
          ),

          // -------------------------------------------------------- reviewer
          // Hidden unless `users/{uid}.isAdmin` is set, which the client cannot
          // write — so the entry cannot be self-granted by a tampered build.
          if (ref.watch(isAppAdminProvider).valueOrNull ?? false)
            SettingsGroup(
              title: context.l10n.reviewer,
              children: <Widget>[
                SettingsValueRow(
                  label: context.l10n.monetizationReview,
                  value: 'Approve or reject channel applications',
                  leadingIcon: Icons.fact_check_outlined,
                  onTap: () => context.push(AppRoutes.monetizationAdmin),
                ),
              ],
            ),

          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Column(
              children: <Widget>[
                Text(
                  context.l10n.fromImoLIVE,
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppConstants.appTagline,
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// What the Account row shows.
  ///
  /// The signed-in address wins when there is one: prompting someone who signed
  /// in with an email to "Add phone number" reads as though they have no account
  /// at all.
  String _accountValue(WidgetRef ref, Contact profile) {
    final String email = ref.watch(authStateProvider).valueOrNull?.email ?? '';
    if (email.isNotEmpty) return email;
    return profile.phone.isEmpty
        ? AppConstants.unsetPhoneLabel
        : profile.phone;
  }
}

/// Small helper used by list screens to render a contact row consistently.
class ContactRowTile extends StatelessWidget {
  const ContactRowTile({
    super.key,
    required this.name,
    required this.about,
    this.imagePath,
    this.colorSeed,
    this.onTap,
    this.trailing,
    this.isOnline = false,
    this.showPresence = false,
  });

  final String name;
  final String about;
  final String? imagePath;
  final int? colorSeed;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool isOnline;
  final bool showPresence;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            IAvatar(
              name: name,
              imagePath: imagePath,
              colorSeed: colorSeed,
              isOnline: isOnline,
              showPresence: showPresence,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: context.t.bodyLarge?.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    about,
                    style: context.t.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
