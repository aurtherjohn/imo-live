import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/group.dart';
import '../../../core/services/channel_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'providers.dart';
import '../../../core/utils/l10n.dart';

/// Reviews pending monetization applications.
///
/// Reviewer-only: the gate reads `users/{uid}.isAdmin`, which the client cannot
/// write, so a tampered build cannot promote itself. Approving here is what
/// turns the monetized badge on for a channel — before this screen existed the
/// approve path was unreachable, so `pending` was a dead end.
class MonetizationAdminScreen extends ConsumerWidget {
  const MonetizationAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isAdmin = ref.watch(isAppAdminProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.monetizationReview, showBack: true),
      body: isAdmin
          ? _ReviewList()
          : EmptyState(
              icon: Icons.lock_outline_rounded,
              title: context.l10n.reviewersOnly,
              message: context.l10n.thisScreenIsLimitedTo,
            ),
    );
  }
}

class _ReviewList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Channel>> pending =
        ref.watch(pendingMonetizationProvider);

    return pending.when(
      loading: () => const Center(child: ILoader(size: 26)),
      error: (Object e, StackTrace s) => errorStateFor(context, e),
      data: (List<Channel> channels) {
        if (channels.isEmpty) {
          return EmptyState(
            icon: Icons.verified_outlined,
            title: context.l10n.nothingToReview,
            message:
                context.l10n.channelsAppearHereOnceThey2,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: channels.length,
          separatorBuilder: (BuildContext _, int _) => const IListDivider(),
          itemBuilder: (BuildContext context, int index) {
            final Channel channel = channels[index];
            return ListTile(
              leading: IAvatar(
                name: channel.name,
                imageUrl:
                    (channel.avatarUrl ?? '').isEmpty ? null : channel.avatarUrl,
              ),
              title: Text(channel.name),
              subtitle: Text(
                context.l10n.channelStats(channel.handle.isEmpty ? channel.id : channel.handle, TextUtils.grouped(channel.followerCount), TextUtils.grouped(channel.totalReactions)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: context.l10n.reject,
                    onPressed: () => _decide(
                      context,
                      ref,
                      channel,
                      MonetizationStatus.rejected,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      color: context.c.onDanger,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.approve,
                    onPressed: () => _decide(
                      context,
                      ref,
                      channel,
                      MonetizationStatus.approved,
                    ),
                    icon: Icon(Icons.check_rounded, color: context.c.accent),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    Channel channel,
    MonetizationStatus status,
  ) async {
    final bool approve = status == MonetizationStatus.approved;
    final bool ok = await showConfirmDialog(
      context,
      title: approve ? 'Approve monetization?' : 'Reject this application?',
      message: approve
          ? '${channel.name} gets the monetized badge and can earn from its '
              'audience.'
          : '${channel.name} is told the application was rejected and can '
              're-apply once it grows further.',
      confirmLabel: approve ? context.l10n.approve : context.l10n.reject,
    );
    if (!ok || !context.mounted) return;

    await ref
        .read(channelFirestoreProvider)
        .setMonetizationStatus(channel.id, status);
    if (!context.mounted) return;
    iToast(
      context,
      approve ? context.l10n.channelApproved : context.l10n.applicationRejected,
    );
  }
}
