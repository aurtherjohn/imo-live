import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Help centre: FAQ, troubleshooting, contact, legal.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  /// The FAQ cannot be a `static const` list: its text is user-visible, so it
  /// has to be read through `context.l10n`, which needs a `BuildContext` and a
  /// non-const initialiser. Same refactor as the six label lists in Settings.
  static List<({String question, String answer})> _faq(BuildContext context) =>
      <({String question, String answer})>[
    (
      question: context.l10n.doesImoLIVEHaveEnd,
      answer:
          context.l10n.noAndThisAppDeliberately,
    ),
    (
      question: context.l10n.doINeedAnAccount,
      answer:
          context.l10n.anAccountYesSignIn,
    ),
    (
      question: context.l10n.whereAreMyPhotosAnd,
      answer:
          context.l10n.aCopyStaysInThe,
    ),
    (
      question: context.l10n.willMyMessagesDisappear,
      answer:
          context.l10n.onlyIfYouTurnOn,
    ),
    (
      question: context.l10n.howDoIMoveMy,
      answer:
          context.l10n.signInWithTheSame,
    ),
    (
      question: context.l10n.whyCanTILink,
      answer:
          context.l10n.companionPairingNeedsASession,
    ),
    (
      question: context.l10n.canIUseImoLIVE,
      answer:
          context.l10n.yesEnglishAndShipWith,
    ),
    (
      question: context.l10n.howDoIReportA,
      answer:
          context.l10n.useContactUsBelowReports,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppTopBar(title: context.l10n.help, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          SectionHeader(title: context.l10n.frequentlyAsked),
          ..._faq(context).map(
            (({String answer, String question}) item) => Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: ICard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  title: Text(
                    item.question,
                    style: context.t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.textPrimary,
                    ),
                  ),
                  iconColor: context.c.accent,
                  collapsedIconColor: context.c.textSecondary,
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: <Widget>[
                    Text(
                      item.answer,
                      style: context.t.bodyMedium?.copyWith(
                        color: context.c.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SettingsGroup(
            title: context.l10n.contactUs,
            footer:
                context.l10n.theseActionsHandOffTo2,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.emailSupport,
                subtitle: 'support@imolive.app',
                leadingIcon: Icons.mail_outline_rounded,
                onTap: () => _open(
                  context,
                  Uri(
                    scheme: 'mailto',
                    path: 'support@imolive.app',
                    query: 'subject=Imo LIVE ${AppConstants.appVersion} feedback',
                  ),
                ),
              ),
              SettingsTile(
                title: context.l10n.openTheWebsite,
                subtitle: 'imolive.app',
                leadingIcon: Icons.language_rounded,
                onTap: () => _open(context, Uri.parse('https://imolive.app')),
              ),
              SettingsTile(
                title: context.l10n.diagnostics,
                subtitle: context.l10n.locallyStoredCountsAndStorage,
                leadingIcon: Icons.bug_report_outlined,
                onTap: () => showInfoDialog(
                  context,
                  title: context.l10n.diagnostics,
                  message:
                      context.l10n.appVersionNChatsNContactsNStarred(AppConstants.appVersion, ref.read(chatCountProvider), ref.read(contactCountProvider), ref.read(starCountProvider), ref.read(totalStorageProvider)),
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.legal,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.termsOfService,
                leadingIcon: Icons.description_outlined,
                onTap: () => showInfoDialog(
                  context,
                  title: context.l10n.termsOfService,
                  message:
                      context.l10n.imoLIVEIsALocal,
                ),
              ),
              SettingsTile(
                title: context.l10n.privacyPolicy,
                leadingIcon: Icons.privacy_tip_outlined,
                onTap: () => showInfoDialog(
                  context,
                  title: context.l10n.privacyPolicy,
                  message:
                      context.l10n.imoLIVECollectsNoAnalytics,
                ),
              ),
              SettingsTile(
                title: context.l10n.licences,
                leadingIcon: Icons.article_outlined,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: AppConstants.appVersion,
                  applicationLegalese: 'Built with Flutter.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        iToast(context, context.l10n.noAppCanHandleThat, isError: true);
      }
    } on Object {
      if (context.mounted) {
        iToast(context, context.l10n.noAppCanHandleThat, isError: true);
      }
    }
  }
}
