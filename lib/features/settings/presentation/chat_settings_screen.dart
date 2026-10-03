import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Chat behaviour preferences: typography, media, backup, wallpapers.
class ChatSettingsScreen extends ConsumerWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ChatSettings s =
        ref.watch(chatSettingsProvider).valueOrNull ?? const ChatSettings();
    final Wallpaper wallpaper =
        ref.watch(wallpaperProvider).valueOrNull ??
            const Wallpaper(id: 'default', name: 'Default', kind: WallpaperKind.defaultPattern);

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.tabChats, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          SettingsGroup(
            title: context.l10n.display,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.wallpaper,
                value: wallpaper.name,
                leadingIcon: Icons.wallpaper_rounded,
                onTap: () => context.push(AppRoutes.wallpaper),
              ),
              SettingsValueRow(
                label: context.l10n.fontSize,
                value: '${(s.fontSize * 100).round()}%',
                leadingIcon: Icons.format_size_rounded,
                onTap: () async {
                  final double? size = await showChoiceSheet<double>(
                    context: context,
                    title: context.l10n.fontSize,
                    selected: s.fontSize,
                    options: <({double value, String label, String? subtitle})>[
                      (value: 0.85, label: context.l10n.small, subtitle: '85%'),
                      (value: 1.0, label: context.l10n.defaultLabel, subtitle: '100%'),
                      (value: 1.15, label: context.l10n.large, subtitle: '115%'),
                      (value: 1.3, label: context.l10n.extraLarge, subtitle: '130%'),
                    ],
                  );
                  if (size == null) return;
                  await ref
                      .read(chatSettingsProvider.notifier)
                      .apply((ChatSettings v) => v.copyWith(fontSize: size));
                },
              ),
              SettingsSwitchRow(
                title: context.l10n.enterKeySendsMessage,
                subtitle: context.l10n.pressEnterToSendInstead,
                value: s.enterKeySends,
                onChanged: (bool v) => ref
                    .read(chatSettingsProvider.notifier)
                    .apply((ChatSettings c) => c.copyWith(enterKeySends: v)),
              ),
              SettingsSwitchRow(
                title: context.l10n.mediaVisibility,
                subtitle: context.l10n.showNewlyDownloadedMediaIn,
                value: s.mediaVisibility,
                onChanged: (bool v) => ref
                    .read(chatSettingsProvider.notifier)
                    .apply((ChatSettings c) => c.copyWith(mediaVisibility: v)),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.chatHistory,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.keepChatsArchived,
                subtitle:
                    context.l10n.newMessagesStayInThe2,
                value: s.keepArchived,
                onChanged: (bool v) => ref
                    .read(chatSettingsProvider.notifier)
                    .apply((ChatSettings c) => c.copyWith(keepArchived: v)),
              ),
              SettingsSwitchRow(
                title: context.l10n.chatBackup,
                subtitle: s.backupEnabled
                    ? 'A local snapshot is written on every ${s.backupFrequency} run'
                    : 'Keep a local snapshot of your chats on this device',
                value: s.backupEnabled,
                onChanged: (bool v) => ref
                    .read(chatSettingsProvider.notifier)
                    .apply((ChatSettings c) => c.copyWith(backupEnabled: v)),
              ),
              if (s.backupEnabled)
                SettingsValueRow(
                  label: context.l10n.backUpOver,
                  value: s.backupFrequency == 'daily'
                      ? 'Daily'
                      : s.backupFrequency == 'weekly'
                          ? 'Weekly'
                          : 'Monthly',
                  leadingIcon: Icons.schedule_rounded,
                  onTap: () async {
                    final String? freq = await showChoiceSheet<String>(
                      context: context,
                      title: context.l10n.backUpOver,
                      selected: s.backupFrequency,
                      options: <({String value, String label, String? subtitle})>[
                        (value: 'daily', label: context.l10n.daily, subtitle: null),
                        (value: 'weekly', label: context.l10n.weekly, subtitle: null),
                        (value: 'monthly', label: context.l10n.monthly, subtitle: null),
                      ],
                    );
                    if (freq == null) return;
                    await ref.read(chatSettingsProvider.notifier).apply(
                          (ChatSettings c) => c.copyWith(backupFrequency: freq),
                        );
                  },
                ),
              SettingsValueRow(
                label: context.l10n.archivedChats,
                value: '${ref.watch(archivedChatsProvider).length}',
                leadingIcon: Icons.archive_outlined,
                onTap: () => context.push(AppRoutes.archived),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.autoDownload,
            footer: context.l10n.appliesToMediaYouReceive,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.photos,
                value: s.autoDownloadPhotos,
                onChanged: (bool v) => ref
                    .read(chatSettingsProvider.notifier)
                    .apply((ChatSettings c) => c.copyWith(autoDownloadPhotos: v)),
              ),
              SettingsSwitchRow(
                title: context.l10n.audio,
                value: s.autoDownloadAudio,
                onChanged: (bool v) => ref
                    .read(chatSettingsProvider.notifier)
                    .apply((ChatSettings c) => c.copyWith(autoDownloadAudio: v)),
              ),
              SettingsSwitchRow(
                title: context.l10n.video,
                value: s.autoDownloadVideos,
                onChanged: (bool v) => ref
                    .read(chatSettingsProvider.notifier)
                    .apply((ChatSettings c) => c.copyWith(autoDownloadVideos: v)),
              ),
              SettingsSwitchRow(
                title: context.l10n.documents,
                value: s.autoDownloadDocuments,
                onChanged: (bool v) => ref
                    .read(chatSettingsProvider.notifier)
                    .apply(
                      (ChatSettings c) => c.copyWith(autoDownloadDocuments: v),
                    ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.housekeeping,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.resetChatSettings,
                subtitle: context.l10n.restoreEveryChatPreferenceTo,
                leadingIcon: Icons.restart_alt_rounded,
                onTap: () async {
                  final bool ok = await showConfirmDialog(
                    context,
                    title: context.l10n.resetChatSettings2,
                    message:
                        context.l10n.chatPreferencesReturnToTheir2,
                    confirmLabel: context.l10n.reset,
                  );
                  if (!ok) return;
                  await ref
                      .read(chatSettingsProvider.notifier)
                      .apply((ChatSettings _) => const ChatSettings());
                  if (context.mounted) {
                    iToast(context, context.l10n.chatSettingsReset);
                  }
                },
              ),
              SettingsSwitchRow(
                title: context.l10n.syncContactsOnSave,
                subtitle:
                    context.l10n.offerToAddANumber2,
                value: ref.watch(syncContactsOnSaveProvider).valueOrNull ?? false,
                onChanged: (bool v) => ref
                    .read(syncContactsOnSaveProvider.notifier)
                    .select(v),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
