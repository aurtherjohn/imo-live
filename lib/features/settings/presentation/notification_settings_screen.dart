import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/models/settings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Notification preferences plus a live test notification.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  static const List<String> _tones = <String>[
    'Default',
    'Chime',
    'Bubble',
    'Ping',
    'Note',
    'Silent',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NotificationSettings s =
        ref.watch(notificationSettingsProvider).valueOrNull ??
            const NotificationSettings();

    Future<void> apply(
      NotificationSettings Function(NotificationSettings) change,
    ) =>
        ref.read(notificationSettingsProvider.notifier).apply(change);

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.notifications, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          InfoBanner(
            icon: Icons.notifications_none_rounded,
            message:
                context.l10n.notificationsAreDeliveredLocallyBy2,
          ),

          SettingsGroup(
            title: context.l10n.messageNotifications,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.showNotifications,
                subtitle: context.l10n.masterSwitchForEveryMessage,
                value: s.messageNotifications,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) =>
                      n.copyWith(messageNotifications: v),
                ),
              ),
              SettingsSwitchRow(
                title: context.l10n.groupNotifications,
                enabled: s.messageNotifications,
                value: s.groupNotifications,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(groupNotifications: v),
                ),
              ),
              SettingsSwitchRow(
                title: context.l10n.showPreview,
                subtitle: context.l10n.includeMessageTextInThe,
                enabled: s.messageNotifications,
                value: s.showPreview,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(showPreview: v),
                ),
              ),
              SettingsSwitchRow(
                title: context.l10n.reactions,
                subtitle: context.l10n.notifyWhenSomeoneReactsTo,
                enabled: s.messageNotifications,
                value: s.reactionsEnabled,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(reactionsEnabled: v),
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.callsStatus,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.callNotifications,
                value: s.callNotifications,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(callNotifications: v),
                ),
              ),
              SettingsSwitchRow(
                title: context.l10n.statusNotifications,
                value: s.statusNotifications,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(statusNotifications: v),
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.soundVibration,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.sound,
                value: s.soundEnabled,
                onChanged: (bool v) =>
                    apply((NotificationSettings n) => n.copyWith(soundEnabled: v)),
              ),
              if (s.soundEnabled)
                SettingsValueRow(
                  label: context.l10n.notificationTone,
                  value: s.soundTone,
                  leadingIcon: Icons.music_note_rounded,
                  onTap: () async {
                    final String? tone = await showChoiceSheet<String>(
                      context: context,
                      title: context.l10n.notificationTone,
                      selected: s.soundTone,
                      options: _tones
                          .map(
                            (String t) => (
                              value: t,
                              label: t,
                              subtitle: null,
                            ),
                          )
                          .toList(),
                    );
                    if (tone == null) return;
                    await apply(
                      (NotificationSettings n) => n.copyWith(soundTone: tone),
                    );
                  },
                ),
              SettingsSwitchRow(
                title: context.l10n.vibrate,
                value: s.vibrationEnabled,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(vibrationEnabled: v),
                ),
              ),
              SettingsSwitchRow(
                title: context.l10n.popup,
                subtitle: context.l10n.showABannerWhileYou,
                value: s.popupEnabled,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(popupEnabled: v),
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.inApp,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.inAppSounds,
                value: s.inAppSounds,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(inAppSounds: v),
                ),
              ),
              SettingsSwitchRow(
                title: context.l10n.inAppVibration,
                value: s.inAppVibrate,
                onChanged: (bool v) => apply(
                  (NotificationSettings n) => n.copyWith(inAppVibrate: v),
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.tryItOut,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.sendATestNotification,
                subtitle: context.l10n.postsALocalNotificationThrough,
                leadingIcon: Icons.notifications_active_outlined,
                onTap: () async {
                  await ref
                      .read(notificationServiceProvider)
                      .showMessage(
                        chatId: 'test',
                        title: context.l10n.appName,
                        body: s.showPreview
                            ? 'This is how your message alerts will look.'
                            : 'You have a new message.',
                      );
                  if (context.mounted) {
                    iToast(context, context.l10n.testNotificationPosted);
                  }
                },
              ),
              SettingsTile(
                title: context.l10n.resetNotificationSettings,
                subtitle: context.l10n.restoreEveryNotificationOptionTo,
                leadingIcon: Icons.restart_alt_rounded,
                onTap: () async {
                  await apply(
                    (NotificationSettings _) => const NotificationSettings(),
                  );
                  if (context.mounted) {
                    iToast(context, context.l10n.notificationSettingsReset);
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
