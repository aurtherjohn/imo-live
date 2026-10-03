import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/contact.dart';
import '../../../core/utils/l10n.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'widgets/settings_widgets.dart';

/// Language selection. English and বাংলা ship with full translations.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  /// Built per call because the labels change with the UI language. `native` is
  /// the endonym and deliberately stays as-is, so "বাংলা" reads the same in
  /// every locale.
  static List<({String code, String label, String native, bool available})>
      _languages(BuildContext context) =>
          <({String code, String label, String native, bool available})>[
    (code: 'en', label: context.l10n.english, native: 'English', available: true),
    (code: 'bn', label: context.l10n.bengali, native: 'বাংলা', available: true),
    (code: 'hi', label: context.l10n.hindi, native: 'हिन्दी', available: false),
    (code: 'ar', label: context.l10n.arabic, native: 'العربية', available: false),
    (code: 'es', label: context.l10n.spanish, native: 'Español', available: false),
    (code: 'fr', label: context.l10n.french, native: 'Français', available: false),
    (code: 'pt', label: context.l10n.portuguese, native: 'Português', available: false),
    (code: 'ru', label: context.l10n.russian, native: 'Русский', available: false),
    (code: 'id', label: context.l10n.indonesian, native: 'Bahasa Indonesia', available: false),
    (code: 'tr', label: context.l10n.turkish, native: 'Türkçe', available: false),
    (code: 'zh', label: context.l10n.chinese, native: '中文', available: false),
    (code: 'ja', label: context.l10n.japanese, native: '日本語', available: false),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String current = ref.watch(languageProvider).valueOrNull ?? 'en';
    final Contact? profile = ref.watch(selfProfileProvider).valueOrNull;

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.appLanguage, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          SettingsGroup(
            title: context.l10n.appDisplayLanguage,
            footer:
                context.l10n.translationsAreBundledWithThe2,
            children: _languages(context)
                .where((({bool available, String code, String label, String native}) l) =>
                    l.available)
                .map(
                  (({bool available, String code, String label, String native}) l) =>
                      SettingsTile(
                    title: l.label,
                    subtitle: l.native == l.label ? null : l.native,
                    trailing: current == l.code
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: AppIconSizes.md,
                            color: context.c.accent,
                          )
                        : null,
                    onTap: () async {
                      await ref.read(languageProvider.notifier).select(l.code);
                      if (context.mounted) {
                        iToast(context, context.l10n.languageSetTo(l.native));
                      }
                    },
                  ),
                )
                .toList(),
          ),
          SettingsGroup(
            title: context.l10n.comingSoon,
            children: _languages(context)
                .where((({bool available, String code, String label, String native}) l) =>
                    !l.available)
                .map(
                  (({bool available, String code, String label, String native}) l) =>
                      SettingsTile(
                    title: l.label,
                    subtitle: l.native,
                    titleColor: context.c.textSecondary,
                    onTap: () async {
                      final bool ok = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext ctx) => AlertDialog(
                              title: Text(context.l10n.isComingSoon(l.native)),
                              content: Text(
                                context.l10n.stringsHaveNotBeenTranslated(l.label),
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
                                  child: Text(context.l10n.switchAnyway),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                      if (!ok) return;
                      await ref.read(languageProvider.notifier).select(l.code);
                      if (context.mounted) {
                        iToast(
                          context,
                          context.l10n.selectedFallingBackToEnglish(l.native),
                        );
                      }
                    },
                  ),
                )
                .toList(),
          ),
          SettingsGroup(
            title: context.l10n.region,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.country,
                // Read the profile once (see `profile` above). Calling
                // `valueOrNull` repeatedly is unsafe: it can be non-null on the
                // first read and null on the next (still loading, or storage
                // unavailable), which made the force-unwrap crash the screen.
                value: (profile?.countryCode ?? '').isEmpty
                    ? 'Not set'
                    : profile!.countryCode,
                leadingIcon: Icons.public_rounded,
                onTap: () async {
                  final String? picked = await showChoiceSheet<String>(
                    context: context,
                    title: context.l10n.country,
                    selected: profile?.countryCode ?? '',
                    options: <({String value, String label, String? subtitle})>[
                      (value: 'BD', label: context.l10n.bangladesh, subtitle: context.l10n.dialCode880),
                      (value: 'IN', label: context.l10n.india, subtitle: context.l10n.dialCode91),
                      (value: 'US', label: context.l10n.unitedStates, subtitle: context.l10n.dialCode1),
                      (value: 'GB', label: context.l10n.unitedKingdom, subtitle: context.l10n.dialCode44),
                      (value: 'PK', label: context.l10n.pakistan, subtitle: context.l10n.dialCode92),
                      (value: 'AE', label: context.l10n.unitedArabEmirates, subtitle: context.l10n.dialCode971),
                      (value: 'SA', label: context.l10n.saudiArabia, subtitle: context.l10n.dialCode966),
                      (value: 'ID', label: context.l10n.indonesia, subtitle: context.l10n.dialCode62),
                    ],
                  );
                  // A dismissed sheet returns null — keep the stored value.
                  if (picked == null || !context.mounted) return;
                  final Contact current = profile ??
                      const Contact(id: 'self', firstName: '');
                  await ref
                      .read(selfProfileProvider.notifier)
                      .save(current.copyWith(countryCode: picked));
                  if (context.mounted) {
                    iToast(context, context.l10n.countrySetTo(picked));
                  }
                },
              ),
              SettingsValueRow(
                label: context.l10n.timeFormat,
                value: MediaQuery.of(context).alwaysUse24HourFormat
                    ? '24-hour'
                    : '12-hour',
                leadingIcon: Icons.schedule_rounded,
                onTap: () => showInfoDialog(
                  context,
                  title: context.l10n.timeFormat,
                  message:
                      context.l10n.imoLIVEFollowsYourDevice2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
