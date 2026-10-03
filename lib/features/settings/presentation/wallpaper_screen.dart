import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/settings.dart';
import '../../../core/services/media_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'widgets/wallpaper_preview.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Wallpaper picker with a live chat preview.
class WallpaperScreen extends ConsumerWidget {
  const WallpaperScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Wallpaper current = ref.watch(wallpaperProvider).valueOrNull ??
        defaultWallpaper;
    final List<Wallpaper> options = ref.watch(wallpaperChoicesProvider);

    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.chatWallpaper,
        showBack: true,
        actions: <Widget>[
          TopBarAction(
            icon: Icons.image_outlined,
            tooltip: context.l10n.chooseFromGallery,
            onPressed: () => _pickFromGallery(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          SectionHeader(title: context.l10n.preview),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: WallpaperChatPreview(wallpaper: current),
          ),

          SettingsGroup(
            title: context.l10n.current,
            children: <Widget>[
              SettingsValueRow(
                label: current.name,
                value: switch (current.kind) {
                  WallpaperKind.defaultPattern => 'Default pattern',
                  WallpaperKind.solid => 'Solid colour',
                  WallpaperKind.gradient => 'Gradient',
                  WallpaperKind.pattern => 'Pattern',
                  WallpaperKind.image => 'Custom image',
                },
                leadingIcon: Icons.wallpaper_rounded,
                onTap: () async {
                  await ref.read(wallpaperProvider.notifier).select(defaultWallpaper);
                  if (context.mounted) iToast(context, context.l10n.defaultRestored);
                },
              ),
            ],
          ),

          SectionHeader(title: context.l10n.chooseAWallpaper),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: options.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (BuildContext context, int index) {
                final Wallpaper w = options[index];
                final bool selected = w.id == current.id;
                return GestureDetector(
                  onTap: () async {
                    await ref.read(wallpaperProvider.notifier).select(w);
                    if (context.mounted) {
                      iToast(context, context.l10n.wallpaperSetTo(w.name));
                    }
                  },
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: AnimatedContainer(
                          duration: AppDurations.fast,
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.rMd,
                            border: Border.all(
                              color: selected
                                  ? context.c.accent
                                  : context.c.divider,
                              width: selected ? 2.5 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: AppRadius.rMd,
                            child: WallpaperSwatch(wallpaper: w),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs + 2),
                      Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.t.labelSmall?.copyWith(
                          color: selected
                              ? context.c.accent
                              : context.c.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          SettingsGroup(
            title: context.l10n.custom,
            footer:
                context.l10n.pickedImagesAreCopiedInto,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.chooseFromGallery,
                subtitle: context.l10n.useAPhotoFromYour,
                leadingIcon: Icons.photo_library_outlined,
                onTap: () => _pickFromGallery(context, ref),
              ),
              SettingsTile(
                title: context.l10n.takeAPhoto,
                subtitle: context.l10n.captureANewWallpaperWith,
                leadingIcon: Icons.photo_camera_outlined,
                onTap: () => _capture(context, ref),
              ),
              if (current.kind == WallpaperKind.image)
                SettingsTile(
                  title: context.l10n.removeCustomWallpaper,
                  subtitle: context.l10n.deleteTheFileAndReturn,
                  leadingIcon: Icons.delete_outline_rounded,
                  leadingIconColor: context.c.onDanger,
                  titleColor: context.c.onDanger,
                  onTap: () async {
                    final bool ok = await showConfirmDialog(
                      context,
                      title: context.l10n.removeWallpaper,
                      message:
                          context.l10n.theCopiedImageFileIs2,
                      confirmLabel: context.l10n.remove,
                      destructive: true,
                    );
                    if (!ok) return;
                    if (current.imagePath != null) {
                      await ref
                          .read(fileStorageProvider)
                          .deleteFile(current.imagePath);
                    }
                    await ref
                        .read(wallpaperProvider.notifier)
                        .select(defaultWallpaper);
                    if (context.mounted) iToast(context, context.l10n.wallpaperRemoved);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromGallery(BuildContext context, WidgetRef ref) async {
    final MediaPickResult result =
        await ref.read(mediaServiceProvider).pickImages();
    if (!context.mounted) return;
    if (result.isEmpty) {
      if (result.error != null) {
        iToast(context, result.error!, isError: true);
      }
      return;
    }
    final String? picked = result.attachments.first.localPath;
    if (picked == null) {
      iToast(context, context.l10n.couldNotReadTheSelected, isError: true);
      return;
    }
    await _applyImage(context, ref, picked);
  }

  Future<void> _capture(BuildContext context, WidgetRef ref) async {
    final MediaPickResult result =
        await ref.read(mediaServiceProvider).capturePhoto();
    if (!context.mounted) return;
    if (result.isEmpty) {
      if (result.error != null) {
        iToast(context, result.error!, isError: true);
      }
      return;
    }
    final String? picked = result.attachments.first.localPath;
    if (picked == null) {
      iToast(context, context.l10n.couldNotReadTheSelected, isError: true);
      return;
    }
    await _applyImage(context, ref, picked);
  }

  Future<void> _applyImage(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    final String stored = await ref.read(mediaRepositoryProvider).upload(path);
    if (!context.mounted) return;
    await ref.read(wallpaperProvider.notifier).select(
          Wallpaper(
            id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
            name: 'My photo',
            kind: WallpaperKind.image,
            imagePath: stored,
            isDark: true,
          ),
        );
    if (context.mounted) iToast(context, context.l10n.wallpaperApplied);
  }
}
