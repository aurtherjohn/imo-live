import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/brand_assets.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// About screen with app identity, build details and legal entry points.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.about, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Column(
              children: <Widget>[
                // The same mark the launcher shows, drawn from the same asset
                // the rest of the app uses. It used to be a gradient rounded
                // tile with a generic chat-bubble glyph painted on top — a
                // second, unrelated logo that matched nothing else in the app.
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: c.accent.withValues(alpha: 0.30),
                        blurRadius: 46,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: BrandMark(
                    size: 96,
                    semanticLabel: AppConstants.appName,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  AppConstants.appName,
                  style: context.t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.version2(AppConstants.appVersion),
                  style: context.t.bodyMedium?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppConstants.appTagline,
                  style: context.t.bodySmall?.copyWith(
                    color: c.textSecondary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          InfoBanner(
            icon: Icons.cloud_done_rounded,
            message:
                context.l10n.imoLIVESyncsThroughFirebase2,
          ),

          SettingsGroup(
            title: context.l10n.build,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.appName2,
                value: AppConstants.appName,
                leadingIcon: Icons.badge_outlined,
              ),
              SettingsValueRow(
                label: context.l10n.version,
                value: AppConstants.appVersion,
                leadingIcon: Icons.tag_rounded,
              ),
              SettingsValueRow(
                label: context.l10n.architecture,
                value: 'Flutter · Material 3 · Riverpod',
                leadingIcon: Icons.architecture_rounded,
                onTap: () => _showArchitecture(context),
              ),
              SettingsValueRow(
                label: context.l10n.mode,
                value: 'Offline-first with Firebase sync',
                leadingIcon: Icons.cloud_sync_outlined,
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.capabilities,
            footer:
                context.l10n.theseAreTheBoundariesOf2,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.connected,
                subtitle:
                    context.l10n.emailGoogleAndFacebookSign2,
                leadingIcon: Icons.cloud_done_outlined,
                leadingIconColor: context.c.onSuccess,
              ),
              SettingsTile(
                title: context.l10n.worksOffline,
                subtitle:
                    context.l10n.chatsMessagesMediaVoiceNotes2,
                leadingIcon: Icons.check_circle_outline_rounded,
                leadingIconColor: context.c.onSuccess,
              ),
              SettingsTile(
                title: context.l10n.needsConfiguration,
                subtitle:
                    context.l10n.cloudflareR2CredentialsTheFacebook2,
                leadingIcon: Icons.build_outlined,
                leadingIconColor: context.c.onWarning,
                onTap: () => _showBackendRoadmap(context),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.whereToNext,
            children: <Widget>[
              SettingsTile(
                title: context.l10n.helpFAQ,
                leadingIcon: Icons.help_outline_rounded,
                onTap: () => context.push(AppRoutes.help),
              ),
              SettingsTile(
                title: context.l10n.licences,
                leadingIcon: Icons.article_outlined,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: AppConstants.appVersion,
                  applicationLegalese:
                      'Built with Flutter. Imo LIVE is an original application '
                      'and is not affiliated with WhatsApp or Meta.',
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: Text(
              context.l10n.madeWithFlutter,
              style: context.t.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  void _showArchitecture(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(context.l10n.architecture),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                context.l10n.imoLIVEFollowsAClean,
                style: ctx.t.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.coreModelsServicesWidgetsConstants,
                style: ctx.t.bodySmall?.copyWith(
                  height: 1.6,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.everyScreenDependsOnAn2,
                style: ctx.t.bodyMedium?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  void _showBackendRoadmap(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(context.l10n.whatStillNeedsConfiguring),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                context.l10n.everythingBelowAlreadyHasIts2,
                style: ctx.t.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.liveNowSignInEmail,
                style: ctx.t.bodySmall?.copyWith(height: 1.8),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }
}
