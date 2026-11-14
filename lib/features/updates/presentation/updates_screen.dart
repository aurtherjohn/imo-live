import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/status.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../../core/utils/l10n.dart';
import '../../../app/app.dart';

/// The Updates tab: my status, recent updates from contacts, and muted ones.
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Status>> statusesAsync = ref.watch(statusesProvider);
    final List<Status> all = statusesAsync.orEmpty;
    final Contact? me = ref.watch(selfProfileProvider).valueOrNull;

    final List<Status> mine = all
        .where((Status s) => s.isOwn)
        .toList()
      ..sort(_newestFirst);
    final List<Status> others = all
        .where((Status s) => !s.isOwn && !s.isExpired && !s.isMuted)
        .toList()
      ..sort(_newestFirst);
    final List<Status> muted = all
        .where((Status s) => !s.isOwn && !s.isExpired && s.isMuted)
        .toList()
      ..sort(_newestFirst);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.tabUpdates),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.statusPrivacy,
            onPressed: () => context.push(AppRoutes.privacy),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.c.accent,
        foregroundColor: Colors.white,
        onPressed: () => context.push(AppRoutes.statusCompose),
        child: const Icon(Icons.edit_outlined),
      ),
      body: statusesAsync.isLoading && all.isEmpty
          ? const ChatListSkeleton(rows: 6)
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
              children: <Widget>[
                const SizedBox(height: AppSpacing.sm),

                // ---------------------------------------------------- my status
                SectionHeader(title: context.l10n.myStatus),
                _MyStatusRow(
                  name: me?.fullName ?? 'My status',
                  avatarPath: me?.avatarPath,
                  colorSeed: me?.avatarColor,
                  statuses: mine,
                  onTap: mine.isEmpty
                      ? () => context.push(AppRoutes.statusCompose)
                      : () => _openViewer(context, ref, mine, isMine: true),
                  onAdd: () => context.push(AppRoutes.statusCompose),
                ),

                // ------------------------------------------------- others
                if (others.isNotEmpty) ...<Widget>[
                  SectionHeader(title: context.l10n.recentUpdates),
                  for (final (int i, Status status) in others.indexed)
                    ListStagger(
                      index: i,
                      child: _StatusRow(
                        status: status,
                        onTap: () => _openViewer(
                          context,
                          ref,
                          others.where((Status s) => s.authorId == status.authorId).toList(),
                        ),
                      ),
                    ),
                ],

                // ------------------------------------------------- muted
                if (muted.isNotEmpty) ...<Widget>[
                  SectionHeader(title: context.l10n.mutedUpdates),
                  for (final (int i, Status status) in muted.indexed)
                    ListStagger(
                      index: i,
                      child: _StatusRow(
                        status: status,
                        muted: true,
                        onTap: () => _openViewer(
                          context,
                          ref,
                          muted.where((Status s) => s.authorId == status.authorId).toList(),
                        ),
                      ),
                    ),
                ],

                if (all.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xxxl),
                    child: EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: context.l10n.noUpdates,
                      message:
                          context.l10n.shareATextPhotoOr2,
                    ),
                  ),

                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text(
                    context.l10n.updatesAreStoredOnThis2,
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
    );
  }

  static int _newestFirst(Status a, Status b) =>
      (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));

  void _openViewer(
    BuildContext context,
    WidgetRef ref,
    List<Status> list, {
    bool isMine = false,
  }) {
    final List<Status> ordered = List<Status>.from(list)..sort(_newestFirst);
    context.push(
      Uri(
        path: AppRoutes.statusView,
        queryParameters: <String, String>{
          'ids': ordered.map((Status s) => s.id).join(','),
          if (isMine) 'mine': '1',
        },
      ).toString(),
    );
  }
}

// ---------------------------------------------------------------------------

class _MyStatusRow extends StatelessWidget {
  const _MyStatusRow({
    required this.name,
    required this.statuses,
    required this.onTap,
    required this.onAdd,
    this.avatarPath,
    this.colorSeed,
  });

  final String name;
  final List<Status> statuses;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final String? avatarPath;
  final int? colorSeed;

  @override
  Widget build(BuildContext context) {
    final bool has = statuses.isNotEmpty;
    return SettingsTile(
      title: context.l10n.myStatus,
      subtitle: has
          ? '${statuses.length} update${statuses.length == 1 ? '' : 's'} · '
              '${statuses.first.timeAgo}'
          : context.l10n.tapToAddAStatus,
      leading: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          IAvatar(
            name: name,
            imagePath: avatarPath,
            colorSeed: colorSeed,
            size: AppSizes.avatarMd,
            ringColor: has ? context.c.accent : null,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: context.c.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.add, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.onTap,
    this.muted = false,
  });

  final Status status;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final String label = status.type == StatusType.text
        ? status.text
        : status.caption.isNotEmpty
            ? status.caption
            : status.type == StatusType.image
                ? context.l10n.photo
                : context.l10n.video;

    return SettingsTile(
      title: status.authorName,
      subtitle: '${status.timeAgo}${muted ? ' · muted' : ''}'
          '${label.isEmpty ? '' : ' · $label'}',
      leading: IAvatar(
        name: status.authorName,
        size: AppSizes.avatarMd,
        ringColor: status.isViewed ? null : context.c.accent,
      ),
      titleColor: muted ? context.c.textSecondary : null,
      trailing: muted
          ? Icon(Icons.volume_off_rounded,
              size: AppIconSizes.sm, color: context.c.textSecondary)
          : null,
      onTap: onTap,
    );
  }
}
