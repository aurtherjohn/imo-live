import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/settings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Manage blocked contacts.
class BlockedContactsScreen extends ConsumerWidget {
  const BlockedContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Contact> blocked =
        ref.watch(blockedContactsProvider).valueOrNull ?? <Contact>[];
    final List<Contact> all = ref.watch(contactsProvider).orEmpty;
    final PrivacySettings privacy = ref.watch(privacySettingsProvider)
        .valueOrNull ?? const PrivacySettings();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.blockedContacts),
        actions: <Widget>[
          IconButton(
            onPressed: all.isEmpty
                ? null
                : () => _pickToBlock(context, ref, all, blocked),
            icon: const Icon(Icons.add_rounded),
            tooltip: context.l10n.blockAContact,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          InfoBanner(
            icon: Icons.block_rounded,
            message:
                context.l10n.blockingHidesAContactS,
          ),

          if (blocked.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.block_rounded,
                title: context.l10n.noBlockedContacts,
                message:
                    context.l10n.blockedContactsCannotMessageOr2,
              ),
            )
          else
            SettingsGroup(
              title: context.l10n.blocked(blocked.length),
              footer:
                  context.l10n.unblockingRestoresTheContactTo2,
              children: blocked
                  .map(
                    (Contact contact) => SettingsTile(
                      title: contact.fullName,
                      subtitle: contact.phone.isEmpty
                          ? contact.aboutText
                          : contact.phone,
                      leading: IAvatar(
                        name: contact.fullName,
                        imagePath: contact.avatarPath,
                        colorSeed: contact.avatarColor,
                        size: AppSizes.avatarSm,
                      ),
                      onTap: () => context.push(
                        '${AppRoutes.contactInfo}/${contact.id}',
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final bool ok = await showConfirmDialog(
                            context,
                            title: context.l10n.unblock2(contact.fullName),
                            message:
                                context.l10n.thisContactWillBeAble2,
                            confirmLabel: context.l10n.unblock,
                          );
                          if (!ok) return;
                          await ref
                              .read(contactsProvider.notifier)
                              .toggleBlocked(contact.id);
                          if (context.mounted) {
                            iToast(context, context.l10n.unblocked(contact.fullName));
                          }
                        },
                        child: Text(context.l10n.unblock),
                      ),
                    ),
                  )
                  .toList(),
            ),

          SettingsGroup(
            title: context.l10n.unknownSenders,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.blockUnknownSenders,
                subtitle: privacy.blockUnknownSenders
                    ? context.l10n.messagesFromAnyoneNotIn
                    : context.l10n.anyoneWhoFindsYouCan,
                leadingIcon: Icons.report_gmailerrorred_outlined,
                value: privacy.blockUnknownSenders,
                onChanged: (bool v) async {
                  await ref.read(privacySettingsProvider.notifier).apply(
                        (PrivacySettings s) =>
                            s.copyWith(blockUnknownSenders: v),
                      );
                  if (!context.mounted) return;
                  iToast(
                    context,
                    v
                        ? context.l10n.messagesFromUnknownSendersWill
                        : context.l10n.anyoneCanMessageYouAgain,
                  );
                },
              ),
              SettingsTile(
                title: context.l10n.blockedCallers,
                subtitle: context.l10n.blockedContactsAreAlsoPrevented,
                leadingIcon: Icons.phone_disabled_outlined,
                onTap: () => context.push(AppRoutes.privacy),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Future<void> _pickToBlock(
    BuildContext context,
    WidgetRef ref,
    List<Contact> all,
    List<Contact> blocked,
  ) async {
    final Set<String> blockedIds = blocked.map((Contact c) => c.id).toSet();
    final List<Contact> candidates =
        all.where((Contact c) => !blockedIds.contains(c.id)).toList()
          ..sort(
            (Contact a, Contact b) => a.sortedKey.compareTo(b.sortedKey),
          );

    if (candidates.isEmpty) {
      iToast(context, context.l10n.everyContactIsAlreadyBlocked);
      return;
    }

    final Contact? chosen = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        final AppColorScheme c = ctx.c;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.md),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: AppRadius.rXl,
              border: Border.all(color: c.divider, width: 0.8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: 36,
                  height: 4,
                  decoration:
                      BoxDecoration(color: c.divider, borderRadius: AppRadius.rPill),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          context.l10n.blockAContact,
                          style: ctx.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Contact contact = candidates[index];
                      return InkWell(
                        onTap: () => Navigator.of(ctx).pop(contact),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
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
                                child: Text(
                                  contact.fullName,
                                  style: ctx.t.bodyLarge,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        );
      },
    );

    if (chosen == null || !context.mounted) return;
    await ref.read(contactsProvider.notifier).toggleBlocked(chosen.id);
    if (context.mounted) iToast(context, context.l10n.blocked2(chosen.fullName));
  }
}
