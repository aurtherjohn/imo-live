import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/gift.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../chats/presentation/providers.dart';
import '../../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../../earn/presentation/providers.dart';

/// The slide-in drawer from the Chats header.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Contact? me = ref.watch(selfProfileProvider).valueOrNull;
    final int archived = ref.watch(archivedChatsProvider).length;
    final int starred = ref.watch(starCountProvider);
    final int unread = ref.watch(totalUnreadProvider);
    final PointsAccount? points = ref.watch(pointsAccountProvider).valueOrNull;
    final int unreadNotes = ref.watch(unreadNotificationCountProvider);

    void close() => Navigator.pop(context);

    void go(String route) {
      close();
      context.push(route);
    }

    return Drawer(
      backgroundColor: context.c.surface,
      width: MediaQuery.of(context).size.width * 0.82,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(AppRadius.xxl),
          bottomRight: Radius.circular(AppRadius.xxl),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // -------------------------------------------------------- profile
            InkWell(
              onTap: () => go(AppRoutes.profile),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: <Widget>[
                    IAvatar(
                      name: me?.fullName ?? 'You',
                      imagePath: me?.avatarPath,
                      size: AppSizes.avatarLg,
                      isOnline: true,
                      showPresence: true,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            me?.fullName ?? 'You',
                            style: context.t.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            me?.username.isNotEmpty == true
                                ? '@${me!.username}'
                                : (me?.phone ?? ''),
                            style: context.t.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.qr_code_rounded,
                      size: AppIconSizes.md,
                      color: context.c.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // ------------------------------------------------------- shortcuts
            _DrawerRow(
              icon: Icons.group_add_outlined,
              label: context.l10n.newGroup,
              onTap: () => go(AppRoutes.newGroup),
            ),
            _DrawerRow(
              icon: Icons.campaign_outlined,
              label: context.l10n.newChannel,
              onTap: () => go(AppRoutes.newChannel),
            ),
            _DrawerRow(
              icon: Icons.groups_outlined,
              label: context.l10n.newCommunity,
              onTap: () => go(AppRoutes.newCommunity),
            ),
            _DrawerRow(
              icon: Icons.person_add_alt_rounded,
              label: context.l10n.newContact,
              onTap: () => go(AppRoutes.newContact),
            ),
            const Divider(height: 1),
            _DrawerRow(
              icon: Icons.stars_rounded,
              label: context.l10n.earnPoints,
              onTap: () => go(AppRoutes.earn),
              trailing: points == null ? null : TextUtils.grouped(points.points),
            ),
            _DrawerRow(
              icon: Icons.notifications_none_rounded,
              label: context.l10n.notifications,
              onTap: () => go(AppRoutes.notificationsCenter),
              trailing: unreadNotes == 0 ? null : '$unreadNotes',
            ),
            _DrawerRow(
              icon: Icons.contacts_outlined,
              label: context.l10n.tabContacts,
              onTap: () {
                close();
                context.go(AppRoutes.contacts);
              },
            ),
            _DrawerRow(
              icon: Icons.star_border_rounded,
              label: context.l10n.starredMessages,
              onTap: () => go(AppRoutes.starred),
              trailing: starred == 0 ? null : '$starred',
            ),
            _DrawerRow(
              icon: Icons.archive_outlined,
              label: context.l10n.archivedChats,
              onTap: () => go(AppRoutes.archived),
              trailing: archived == 0 ? null : '$archived',
            ),
            _DrawerRow(
              icon: Icons.mark_chat_unread_outlined,
              label: context.l10n.unreadChats,
              trailing: unread == 0 ? null : '$unread',
              onTap: () {
                close();
                ref.read(chatFilterProvider.notifier).select(ChatFilter.unread);
                context.go(AppRoutes.chats);
              },
            ),
            _DrawerRow(
              icon: Icons.podcasts_rounded,
              label: context.l10n.broadcastLists,
              onTap: () => go(AppRoutes.broadcast),
            ),
            _DrawerRow(
              icon: Icons.devices_rounded,
              label: context.l10n.linkedDevices,
              onTap: () => go(AppRoutes.linkedDevices),
            ),
            const Divider(height: 1),
            _DrawerRow(
              icon: Icons.done_all_rounded,
              label: context.l10n.readAll,
              onTap: () {
                close();
                ref.read(chatsProvider.notifier).markAllRead();
                iToast(context, context.l10n.allChatsMarkedAsRead);
              },
            ),
            _DrawerRow(
              icon: Icons.settings_outlined,
              label: context.l10n.settings,
              onTap: () => go(AppRoutes.settings),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                '${AppConstants.appName} ${AppConstants.appVersion}',
                style: context.t.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: AppIconSizes.md, color: context.c.textSecondary),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                label,
                style: context.t.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: context.c.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadius.rPill,
                ),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.c.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Convenience helper: confirm-and-run a destructive action with a toast.
Future<void> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Future<void> Function() action,
  required String successMessage,
}) async {
  final bool ok = await showConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: true,
  );
  if (!ok) return;
  await action();
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(successMessage)));
  }
}
