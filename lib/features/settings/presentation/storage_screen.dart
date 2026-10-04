import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../local/storage/file_storage_service.dart';
import '../../chats/presentation/providers.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Storage & data usage breakdown with per-category cleanup actions.
class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  /// Built per call: the folder labels change with the UI language, so this
  /// cannot be a `static const` map.
  static Map<String, ({String label, IconData icon})> _folderMeta(
          BuildContext context) =>
      <String, ({String label, IconData icon})>{
    AppConstants.dirImages: (label: context.l10n.images, icon: Icons.image_outlined),
    AppConstants.dirVideos: (label: context.l10n.videos, icon: Icons.videocam_outlined),
    AppConstants.dirAudio: (label: context.l10n.audio, icon: Icons.audiotrack_outlined),
    AppConstants.dirDocuments: (label: context.l10n.documents, icon: Icons.description_outlined),
    AppConstants.dirVoiceNotes: (label: context.l10n.voiceMessages, icon: Icons.mic_none_rounded),
    AppConstants.dirProfile: (label: context.l10n.profilePhotos, icon: Icons.person_outline_rounded),
    AppConstants.dirWallpapers: (label: context.l10n.wallpapers, icon: Icons.wallpaper_rounded),
    AppConstants.dirStatus: (label: context.l10n.statusMedia, icon: Icons.donut_large_rounded),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Map<String, int>> usageAsync =
        ref.watch(storageUsageProvider);

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.storageAndData, showBack: true),
      body: usageAsync.when(
        loading: () => const Center(child: ILoader(size: 26)),
        error: (Object error, StackTrace stack) => ErrorState(
          message: context.l10n.couldNotReadLocalStorage(error),
          onRetry: () => ref.invalidate(storageUsageProvider),
        ),
        data: (Map<String, int> usage) {
          final int total = usage.values.fold<int>(0, (int a, int b) => a + b);
          final List<MapEntry<String, int>> rows = usage.entries
              .where((MapEntry<String, int> e) => e.value > 0)
              .toList()
            ..sort(
              (MapEntry<String, int> a, MapEntry<String, int> b) =>
                  b.value.compareTo(a.value),
            );

          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: ICard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: context.c.accent.withValues(alpha: 0.14),
                              borderRadius: AppRadius.rMd,
                            ),
                            child: Icon(
                              Icons.storage_rounded,
                              color: context.c.accent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  formatBytes(total),
                                  style: context.t.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  context.l10n.mediaStoredOnThisDevice,
                                  style: context.t.bodySmall?.copyWith(
                                    color: context.c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (total > 0) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        ClipRRect(
                          borderRadius: AppRadius.rPill,
                          child: SizedBox(
                            height: 8,
                            child: Row(
                              children: rows
                                  .map(
                                    (MapEntry<String, int> e) => Expanded(
                                      flex: ((e.value / total) * 1000)
                                          .round()
                                          .clamp(1, 1000),
                                      child: Container(
                                        color: _colorFor(
                                          context,
                                          e.key,
                                          rows.indexOf(e),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.sm,
                          children: rows
                              .map(
                                (MapEntry<String, int> e) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: _colorFor(
                                          context,
                                          e.key,
                                          rows.indexOf(e),
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs + 2),
                                    Text(
                                      _folderMeta(context)[e.key]?.label ?? e.key,
                                      style: context.t.bodySmall?.copyWith(
                                        color: context.c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (rows.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xxl),
                  child: EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: context.l10n.nothingStoredYet,
                    message:
                        context.l10n.photosVideosVoiceNotesAnd2,
                  ),
                )
              else
                SettingsGroup(
                  title: context.l10n.breakdown,
                  children: rows
                      .map(
                        (MapEntry<String, int> e) => SettingsTile(
                          title: _folderMeta(context)[e.key]?.label ?? e.key,
                          subtitle:
                              '${formatBytes(e.value)} · ${_percent(e.value, total)}',
                          leadingIcon: _folderMeta(context)[e.key]?.icon,
                          leadingIconColor: _colorFor(
                            context,
                            e.key,
                            rows.indexOf(e),
                          ),
                          onTap: () => _clearFolder(context, ref, e.key),
                        ),
                      )
                      .toList(),
                ),

              SettingsGroup(
                title: context.l10n.messageData,
                children: <Widget>[
                  SettingsValueRow(
                    label: context.l10n.tabChats,
                    value: '${ref.watch(chatCountProvider)}',
                    leadingIcon: Icons.chat_bubble_outline_rounded,
                  ),
                  SettingsValueRow(
                    label: context.l10n.starredMessages,
                    value: '${ref.watch(starCountProvider)}',
                    leadingIcon: Icons.star_border_rounded,
                  ),
                  SettingsTile(
                    title: context.l10n.purgeExpiredMessages,
                    subtitle:
                        context.l10n.removesMessagesWhoseDisappearingTimer2,
                    leadingIcon: Icons.auto_delete_outlined,
                    onTap: () async {
                      final int removed =
                          await ref.read(messageRepositoryProvider).purgeExpired();
                      await ref.read(starredMessagesProvider.notifier).refresh();
                      if (context.mounted) {
                        iToast(
                          context,
                          removed == 0
                              ? context.l10n.noExpiredMessagesFound
                              : 'Removed $removed expired message${removed == 1 ? '' : 's'}',
                        );
                      }
                    },
                  ),
                  SettingsTile(
                    title: context.l10n.deleteAllMediaFiles,
                    subtitle: context.l10n.removesEveryFileKeptIn,
                    leadingIcon: Icons.delete_sweep_outlined,
                    leadingIconColor: context.c.onDanger,
                    titleColor: context.c.onDanger,
                    onTap: () => _clearAll(context, ref),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  static String _percent(int part, int total) {
    if (total == 0) return '0%';
    return '${((part / total) * 100).toStringAsFixed(1)}%';
  }

  static Color _colorFor(BuildContext context, String folder, int index) {
    const List<Color> ramp = <Color>[
      Color(0xFFFF2D55),
      Color(0xFF7B61FF),
      Color(0xFF3BA9FF),
      Color(0xFF25D366),
      Color(0xFFFFB020),
      Color(0xFFFF6B4A),
      Color(0xFF14B8A6),
      Color(0xFFD946EF),
    ];
    return ramp[index % ramp.length];
  }

  Future<void> _clearFolder(
    BuildContext context,
    WidgetRef ref,
    String folder,
  ) async {
    final FileStorageService storage = ref.read(fileStorageProvider);
    final int size = await storage.folderSize(folder);
    if (size == 0) return;
    if (!context.mounted) return;

    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(context.l10n.clear2(_folderMeta(context)[folder]?.label ?? folder)),
            content: Text(
              context.l10n.thisPermanentlyDeletesOfLocal(formatBytes(size)),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  context.l10n.cancel,
                  style: TextStyle(color: ctx.c.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  context.l10n.delete,
                  style: TextStyle(
                    color: context.c.onDanger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;
    await storage.clearFolder(folder);
    ref.invalidate(storageUsageProvider);
    if (context.mounted) {
      iToast(context, context.l10n.cleared(_folderMeta(context)[folder]?.label ?? folder));
    }
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final FileStorageService storage = ref.read(fileStorageProvider);
    final int total = await storage.totalSize();
    if (total == 0) {
      if (context.mounted) iToast(context, context.l10n.noMediaFilesToDelete);
      return;
    }
    if (!context.mounted) return;

    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(context.l10n.deleteAllMedia),
            content: Text(
              context.l10n.removesOfImagesVideosAudio(formatBytes(total)),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  context.l10n.cancel,
                  style: TextStyle(color: ctx.c.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  context.l10n.deleteEverything,
                  style: TextStyle(
                    color: context.c.onDanger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;
    for (final String folder in storage.managedFolders) {
      await storage.clearFolder(folder);
    }
    ref.invalidate(storageUsageProvider);
    if (context.mounted) iToast(context, context.l10n.allMediaFilesDeleted);
  }
}
