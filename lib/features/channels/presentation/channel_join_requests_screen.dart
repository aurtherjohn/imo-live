import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/channel_models.dart';
import '../../../core/services/channel_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import 'providers.dart';
import '../../../core/utils/l10n.dart';

/// Approve or reject pending requests to join a private channel.
///
/// Only reachable from Channel settings, which is owner-only, and the writes
/// are additionally expected to be gated by security rules.
class ChannelJoinRequestsScreen extends ConsumerWidget {
  const ChannelJoinRequestsScreen({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ChannelJoinRequest>> requests =
        ref.watch(channelJoinRequestsProvider(channelId));

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.joinRequests, showBack: true),
      body: requests.when(
        loading: () => const Center(child: ILoader(size: 26)),
        error: (Object e, StackTrace s) => errorStateFor(context, e),
        data: (List<ChannelJoinRequest> list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.how_to_reg_outlined,
              title: context.l10n.noPendingRequests,
              message:
                  context.l10n.shareTheSecretKeyWith2,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: list.length,
            separatorBuilder: (BuildContext _, int _) => const IListDivider(),
            itemBuilder: (BuildContext context, int index) {
              final ChannelJoinRequest request = list[index];
              return ListTile(
                leading: IAvatar(
                  name: request.displayName,
                  imageUrl: request.avatarUrl.isEmpty ? null : request.avatarUrl,
                ),
                title: Text(request.displayName),
                subtitle: Text(
                  request.message.isEmpty
                      ? 'Wants to join this channel'
                      : request.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: context.l10n.reject,
                      onPressed: () async {
                        await ref
                            .read(channelFirestoreProvider)
                            .rejectJoin(channelId, request.uid);
                        if (!context.mounted) return;
                        iToast(context, context.l10n.requestRejected);
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: context.c.onDanger,
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.approve,
                      onPressed: () async {
                        await ref
                            .read(channelFirestoreProvider)
                            .approveJoin(channelId, request.uid);
                        if (!context.mounted) return;
                        iToast(context, context.l10n.canNowJoin(request.displayName));
                      },
                      icon: Icon(
                        Icons.check_rounded,
                        color: context.c.accent,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
