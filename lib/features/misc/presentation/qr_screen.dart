import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/file_service.dart';
import '../../../core/widgets/brand_assets.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Renders any payload as a QR code with a copy action.
///
/// Used for the user's own contact QR, group invites and channel invites — the
/// callers all pass `title` and `payload` through the route query.
class QrScreen extends StatelessWidget {
  const QrScreen({
    super.key,
    required this.title,
    required this.payload,
    this.subtitle,
  });

  final String title;
  final String payload;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(title),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.copyCode,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              if (!context.mounted) return;
              iToast(context, context.l10n.copied2);
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.rLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // `logoPlate` rather than the transparent mark: this card is
                  // opaque white, and the plate is the same white, so the
                  // artwork drops in with no compositing edge. A transparent
                  // asset would also work here but would have to be trusted not
                  // to carry a fringe against a pure-white surround.
                  const BrandMark(
                    asset: BrandAssets.logoPlate,
                    size: 72,
                    semanticLabel: AppConstants.appName,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 232,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0B0B0D),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0B0B0D),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: <Widget>[
                  Text(
                    subtitle ?? 'Scan this code to add or join',
                    textAlign: TextAlign.center,
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: context.c.surfaceAlt,
                      borderRadius: AppRadius.rMd,
                    ),
                    child: SelectableText(
                      payload,
                      textAlign: TextAlign.center,
                      style: context.t.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: InfoBanner(
              message:
                  context.l10n.theCodeCarriesAnImo2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ProminentButton(
              label: context.l10n.shareCode,
              icon: Icons.share_outlined,
              expanded: true,
              // Shares the payload, not the image: the payload is what the
              // other person's app can act on, and it needs no storage
              // permission to hand to the platform share sheet.
              onPressed: () =>
                  const ShareService().shareText(payload, subject: title),
            ),
          ),
        ],
      ),
    );
  }
}
