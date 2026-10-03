import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/gift.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/auth_providers.dart';
import 'providers.dart';
import '../../../core/utils/l10n.dart';

/// In-app notifications, which today means gift receipts.
///
/// ### Why these are in Firestore rather than only a local push
///
/// A gift is sent by somebody else and may arrive while this device is offline
/// or the app is closed. A local notification would simply never be scheduled;
/// a document survives until the recipient opens the app, and the badge can be
/// computed from it. The local push is a nudge on top, not the record.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Marking read on open rather than per row: the user has seen the list, and
    // asking them to clear a badge row by row is busywork.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pointsServiceProvider).markNotificationsRead(
            ref.read(currentUidProvider),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AppNotification>> notifications =
        ref.watch(appNotificationsProvider);

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.notifications, showBack: true),
      body: notifications.when(
        loading: () => const Center(child: ILoader()),
        error: (Object error, StackTrace stack) => ErrorState(
          title: context.l10n.couldNotLoadNotifications,
          message: context.l10n.checkYourConnectionAndTry,
        ),
        data: (List<AppNotification> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_none_rounded,
              title: context.l10n.noNotificationsYet,
              message: context.l10n.giftsYouReceiveWillShow,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: items.length,
            separatorBuilder: (BuildContext context, int index) =>
                const IListDivider(indent: AppSpacing.lg),
            itemBuilder: (BuildContext context, int index) =>
                _NotificationRow(entry: items[index]),
          );
        },
      ),
    );
  }
}

/// One notification row. Tapping a gift opens the chat or channel it came from.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.entry});

  final AppNotification entry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final bool unread = !entry.read;

    return InkWell(
      onTap: () {
        // The gift carries where it was sent; without one there is nowhere to
        // go, so the row is inert rather than opening an arbitrary screen.
        if (entry.chatId.isNotEmpty) {
          context.push('${AppRoutes.chat}/${entry.chatId}');
        } else if (entry.channelId.isNotEmpty) {
          // A channel notification is about a post, so it opens the post's
          // conversation, not the channel's management feed.
          context.push('${AppRoutes.channelChat}/${entry.channelId}');
        }
      },
      child: Container(
        color: unread ? c.accent.withValues(alpha: 0.06) : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Text(
                entry.icon,
                style: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.title,
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (entry.body.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(entry.body, style: context.t.bodySmall),
                  ],
                  if (entry.createdAt != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      DateFormatter.relative(entry.createdAt!),
                      style: context.t.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, left: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
