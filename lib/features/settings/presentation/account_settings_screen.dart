import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../app/theme/app_color_scheme.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Account information: security, phone number, account actions.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Contact profile = ref.watch(selfProfileProvider).valueOrNull ??
        const Contact(id: 'self', firstName: 'You');
    final int chatCount = ref.watch(chatCountProvider);
    final int contactCount = ref.watch(contactCountProvider);
    final int starCount = ref.watch(starCountProvider);
    final AsyncValue<User?> authState = ref.watch(authStateProvider);
    final User? account = authState.valueOrNull;
    final bool signedIn = account != null;

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.account, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          // Sign in / sign out. The app works without an account, so this is
          // an opt-in card rather than a wall.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: ICard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: signedIn
                          ? AppColors.accent.withValues(alpha: 0.16)
                          : context.c.inputFill,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      signedIn
                          ? Icons.verified_user_rounded
                          : Icons.cloud_off_rounded,
                      size: 20,
                      color: signedIn
                          ? AppColors.accent
                          : context.c.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          signedIn
                              ? (account.email ?? context.l10n.signedIn)
                              : context.l10n.notSignedIn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          signedIn
                              ? context.l10n.yourChatsSyncAcrossYour
                              : context.l10n.signInToSyncChats,
                          style: context.t.bodySmall?.copyWith(
                            color: context.c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (!signedIn) {
                        context.push(AppRoutes.login);
                        return;
                      }
                      final bool ok = await showConfirmDialog(
                        context,
                        title: context.l10n.signOut2,
                        message:
                            context.l10n.yourChatsStayOnThis2,
                        confirmLabel: context.l10n.signOut,
                        destructive: true,
                      );
                      if (!ok) return;
                      await ref.read(authControllerProvider.notifier).signOut();
                    },
                    child: Text(signedIn ? context.l10n.signOut : context.l10n.signIn),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: ICard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: <Widget>[
                  IAvatar(
                    name: profile.fullName,
                    imagePath: profile.avatarPath,
                    colorSeed: profile.avatarColor,
                    size: AppSizes.avatarLg,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          profile.fullName,
                          style: context.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          profile.phone.isEmpty
                              ? AppConstants.unsetPhoneLabel
                              : profile.phone,
                          style: context.t.bodySmall?.copyWith(
                            color: context.c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.editProfile),
                    child: Text(context.l10n.edit),
                  ),
                ],
              ),
            ),
          ),

          SettingsGroup(
            title: context.l10n.security,
            footer:
                context.l10n.twoStepVerificationAndEnd2,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.appLock,
                subtitle: context.l10n.requireADeviceCredentialTo,
                leadingIcon: Icons.fingerprint_rounded,
                value: ref.watch(privacySettingsProvider).valueOrNull?.appLock ??
                    false,
                onChanged: (bool value) async {
                  await ref
                      .read(privacySettingsProvider.notifier)
                      .apply((p) => p.copyWith(appLock: value));
                  if (context.mounted) {
                    iToast(
                      context,
                      value
                          ? context.l10n.appLockEnabled
                          : context.l10n.appLockDisabled,
                    );
                  }
                },
              ),
              SettingsValueRow(
                label: context.l10n.twoStepVerification,
                value: context.l10n.notAvailableYet,
                leadingIcon: Icons.security_rounded,
                onTap: () => showBackendRequiredDialog(
                  context,
                  feature: context.l10n.twoStepVerification,
                  detail:
                      context.l10n.verifyingASecondFactorIs,
                ),
              ),
              SettingsValueRow(
                label: context.l10n.passkeys,
                value: 'Not available yet',
                leadingIcon: Icons.key_rounded,
                onTap: () => showBackendRequiredDialog(
                  context,
                  feature: context.l10n.passkeys,
                  detail:
                      context.l10n.passkeysAreNotImplementedYet,
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.phoneNumber,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.changeNumber,
                value: 'Local only',
                leadingIcon: Icons.phone_iphone_rounded,
                onTap: () async {
                  final String? next = await showTextPrompt(
                    context,
                    title: context.l10n.changeNumber,
                    hint: context.l10n.enterANewPhoneNumber,
                    initialValue: profile.phone,
                    confirmLabel: context.l10n.save,
                  );
                  if (next == null || next.trim().isEmpty) return;
                  await ref
                      .read(selfProfileProvider.notifier)
                      .save(profile.copyWith(phone: next.trim()));
                  if (context.mounted) {
                    iToast(context, context.l10n.numberUpdatedOnThisDevice);
                  }
                },
              ),
              SettingsValueRow(
                label: context.l10n.verifiedNumber,
                value: profile.phone.isEmpty
                    ? AppConstants.unsetPhoneLabel
                    : profile.phone,
                leadingIcon: Icons.verified_outlined,
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.accountActivity,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.tabChats,
                value: '$chatCount',
                leadingIcon: Icons.chat_bubble_outline_rounded,
              ),
              SettingsValueRow(
                label: context.l10n.tabContacts,
                value: '$contactCount',
                leadingIcon: Icons.person_outline_rounded,
              ),
              SettingsValueRow(
                label: context.l10n.starredMessages,
                value: '$starCount',
                leadingIcon: Icons.star_border_rounded,
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.dangerZone,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.clearAllLocalData,
                subtitle:
                    context.l10n.deletesChatsMessagesContactsStatuses2,
                leadingIcon: Icons.delete_forever_rounded,
                leadingIconColor: context.c.onDanger,
                titleColor: context.c.onDanger,
                onTap: () async {
                  final bool confirmed = await showConfirmDialog(
                    context,
                    title: context.l10n.clearAllLocalData2,
                    message:
                        context.l10n.everyChatMessageContactAnd2,
                    confirmLabel: context.l10n.clearEverything,
                    destructive: true,
                  );
                  if (!confirmed) return;

                  await ref.read(chatRepositoryProvider).clear();
                  await ref.read(messageRepositoryProvider).clear();
                  await ref.read(contactRepositoryProvider).clear();
                  await ref.read(groupRepositoryProvider).clear();
                  await ref.read(communityRepositoryProvider).clear();
                  await ref.read(channelRepositoryProvider).clear();
                  await ref.read(statusRepositoryProvider).clear();
                  await ref.read(callRepositoryProvider).clear();

                  await ref.read(chatsProvider.notifier).refresh();
                  await ref.read(contactsProvider.notifier).refresh();
                  await ref.read(groupsProvider.notifier).refresh();
                  await ref.read(communitiesProvider.notifier).refresh();
                  await ref.read(channelsProvider.notifier).refresh();
                  await ref.read(statusesProvider.notifier).refresh();
                  await ref.read(callsProvider.notifier).refresh();
                  await ref.read(starredMessagesProvider.notifier).refresh();

                  if (context.mounted) {
                    iToast(context, context.l10n.allLocalDataCleared);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
