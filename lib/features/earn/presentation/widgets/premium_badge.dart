import 'package:flutter/material.dart';
import '../../../../app/theme/app_color_scheme.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/l10n.dart';

/// The exclusive badge a premium member carries.
///
/// Kept public and in one place so "this user is premium" looks the same
/// wherever it appears — a profile, a channel, a message header — rather than
/// each screen inventing its own mark.
///
/// Renders nothing when [compact] is false and the width is too tight to fit
/// it: a badge that overflows is worse than a badge that is absent.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.compact = false});

  /// Drops the label and keeps only the mark, for dense rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : AppSpacing.sm,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: AppRadius.rPill,
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.workspace_premium_rounded,
            size: 13,
            color: context.c.onWarning,
          ),
          if (!compact) ...<Widget>[
            SizedBox(width: 4),
            Text(
              context.l10n.premium,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: context.c.onWarning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
