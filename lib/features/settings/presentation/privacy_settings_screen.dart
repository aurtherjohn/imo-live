import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Privacy controls. Everything here persists locally and takes effect
/// immediately in the UI.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  static List<({String value, String label, String? subtitle})> _visibilityOptions(
          BuildContext context) =>
      <({String value, String label, String? subtitle})>[
    (value: 'everyone', label: context.l10n.everyone, subtitle: context.l10n.anyImoLiveUser),
    (value: 'contacts', label: context.l10n.myContacts, subtitle: context.l10n.peopleYouSaved),
    (value: 'nobody', label: context.l10n.nobody, subtitle: context.l10n.hideCompletely),
  ];

  Future<void> _pickVisibility(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String current,
    required PrivacySettings Function(PrivacySettings, String) apply,
  }) async {
    final String? chosen = await showChoiceSheet<String>(
      context: context,
      title: title,
      options: _visibilityOptions(context),
      selected: current,
    );
    if (chosen == null) return;
    await ref.read(privacySettingsProvider.notifier).apply(
          (PrivacySettings p) => apply(p, chosen),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PrivacySettings p =
        ref.watch(privacySettingsProvider).valueOrNull ??
            const PrivacySettings();
    final int blocked = ref.watch(blockedContactsProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.privacy, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          InfoBanner(
            icon: Icons.lock_outline_rounded,
            message:
                context.l10n.theseSwitchesControlWhatImo2,
          ),

          SettingsGroup(
            title: context.l10n.whoCanSeeMyPersonal,
            footer:
                context.l10n.changingLastSeenAlsoAffects2,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.lastSeenAndOnline,
                value: _labelFor(p.lastSeenVisibility),
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: context.l10n.lastSeenAndOnline,
                  current: p.lastSeenVisibility,
                  apply: (PrivacySettings s, String v) =>
                      s.copyWith(lastSeenVisibility: v),
                ),
              ),
              SettingsValueRow(
                label: context.l10n.profilePhoto,
                value: _labelFor(p.profilePhotoVisibility),
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: context.l10n.profilePhoto,
                  current: p.profilePhotoVisibility,
                  apply: (PrivacySettings s, String v) =>
                      s.copyWith(profilePhotoVisibility: v),
                ),
              ),
              SettingsValueRow(
                label: context.l10n.about,
                value: _labelFor(p.aboutVisibility),
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: context.l10n.about,
                  current: p.aboutVisibility,
                  apply: (PrivacySettings s, String v) =>
                      s.copyWith(aboutVisibility: v),
                ),
              ),
              SettingsValueRow(
                label: context.l10n.status,
                value: _labelFor(p.statusVisibility),
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: context.l10n.status,
                  current: p.statusVisibility,
                  apply: (PrivacySettings s, String v) =>
                      s.copyWith(statusVisibility: v),
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.messaging,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.readReceipts,
                subtitle:
                    context.l10n.sendDeliveryAndReadTicks2,
                value: p.readReceipts,
                onChanged: (bool v) => ref
                    .read(privacySettingsProvider.notifier)
                    .apply((PrivacySettings s) => s.copyWith(readReceipts: v)),
              ),
              SettingsValueRow(
                label: context.l10n.whoCanAddMeTo,
                value: _labelFor(p.groupsVisibility),
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: context.l10n.whoCanAddMeTo,
                  current: p.groupsVisibility,
                  apply: (PrivacySettings s, String v) =>
                      s.copyWith(groupsVisibility: v),
                ),
              ),
              SettingsValueRow(
                label: context.l10n.defaultMessageTimer,
                value: p.defaultDisappearingSeconds == 0
                    ? 'Off'
                    : DateFormatter.longDuration(
                        Duration(seconds: p.defaultDisappearingSeconds),
                      ),
                onTap: () async {
                  final int? seconds = await showChoiceSheet<int>(
                    context: context,
                    title: context.l10n.defaultMessageTimer,
                    selected: p.defaultDisappearingSeconds,
                    options: <({int value, String label, String? subtitle})>[
                      (value: 0, label: context.l10n.off, subtitle: context.l10n.keepMessagesForever),
                      (value: 86400, label: context.l10n.s24Hours, subtitle: null),
                      (value: 604800, label: context.l10n.s7Days, subtitle: null),
                      (value: 7776000, label: context.l10n.s90Days, subtitle: null),
                    ],
                  );
                  if (seconds == null) return;
                  await ref.read(privacySettingsProvider.notifier).apply(
                        (PrivacySettings s) =>
                            s.copyWith(defaultDisappearingSeconds: seconds),
                      );
                },
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.tabCalls,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.whoCanCallMe,
                value: _labelFor(p.callsVisibility),
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: context.l10n.whoCanCallMe,
                  current: p.callsVisibility,
                  apply: (PrivacySettings s, String v) =>
                      s.copyWith(callsVisibility: v),
                ),
              ),
              SettingsSwitchRow(
                title: context.l10n.silenceUnknownCallers,
                subtitle: context.l10n.muteCallNotificationsFromPeople,
                value: p.callsVisibility == 'contacts',
                onChanged: (bool v) => ref
                    .read(privacySettingsProvider.notifier)
                    .apply((PrivacySettings s) => s.copyWith(
                          callsVisibility: v ? 'contacts' : 'everyone',
                        )),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.appSecurity,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.appLock,
                subtitle: context.l10n.requireADeviceCredentialBefore,
                value: p.appLock,
                onChanged: (bool v) async {
                  await ref
                      .read(privacySettingsProvider.notifier)
                      .apply((PrivacySettings s) => s.copyWith(appLock: v));
                  if (context.mounted && v) {
                    showInfoDialog(
                      context,
                      title: context.l10n.appLockEnabled,
                      message:
                          context.l10n.imoLIVEWillAskFor2,
                    );
                  }
                },
              ),
              SettingsSwitchRow(
                title: context.l10n.liveLocation,
                subtitle:
                    context.l10n.allowSharingYourCurrentLocation2,
                value: p.liveLocation,
                onChanged: (bool v) => ref
                    .read(privacySettingsProvider.notifier)
                    .apply((PrivacySettings s) => s.copyWith(liveLocation: v)),
              ),
              SettingsValueRow(
                label: context.l10n.blockedContacts,
                value: '$blocked',
                onTap: () => context.push(AppRoutes.blocked),
              ),
              SettingsValueRow(
                label: context.l10n.advancedPrivacySettings,
                value: context.l10n.details,
                onTap: () => showInfoDialog(
                  context,
                  title: context.l10n.advancedPrivacy,
                  message:
                      context.l10n.imoLIVEDoesNotClaim2,
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.storage,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.resetPrivacySettings,
                subtitle: context.l10n.restoreEveryPrivacyOptionTo,
                leadingIcon: Icons.restart_alt_rounded,
                onTap: () async {
                  final bool ok = await showConfirmDialog(
                    context,
                    title: context.l10n.resetPrivacySettings2,
                    message:
                        context.l10n.allPrivacyOptionsReturnTo2,
                    confirmLabel: context.l10n.reset,
                  );
                  if (!ok) return;
                  await ref.read(privacySettingsProvider.notifier).apply(
                        (PrivacySettings _) => const PrivacySettings(),
                      );
                  if (context.mounted) {
                    iToast(context, context.l10n.privacySettingsReset);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              context.l10n.onDevicePrivacyModelSyncs,
              style: context.t.bodySmall?.copyWith(
                color: context.c.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

String _labelFor(String visibility) => switch (visibility) {
      'everyone' => 'Everyone',
      'contacts' => 'My contacts',
      'nobody' => 'Nobody',
      _ => visibility,
    };

/// Re-exported so the appearance/chat screens can share the same accent list.
AppColorScheme accentPreview(BuildContext context) => context.c;
