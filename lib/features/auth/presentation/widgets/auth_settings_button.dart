import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/l10n.dart';
import '../../../chats/presentation/providers.dart';
import '../../../settings/presentation/language_screen.dart';

/// The settings gear in the top-right corner of every auth screen.
///
/// ### Why a gear on the login screen at all
///
/// The language picker lives under Settings, and Settings is behind the auth
/// gate — a signed-out user cannot reach it. That made the app's language
/// effectively unchangeable until after an account existed, which is the wrong
/// order for a user who cannot read English well enough to finish signing up.
/// This button is the way in: it is the only settings surface reachable without
/// a session.
///
/// ### Why the sheet only offers Language
///
/// Everything else under Settings (account, privacy, chats, storage) reads or
/// writes under the signed-in uid, so it is meaningless — or broken — before
/// there is a session. Language is the one genuinely device-scoped preference,
/// so it is the only tile here rather than a menu of dead entries.
///
/// The picker itself is not reimplemented: the tile pushes the existing
/// [LanguageScreen], which already owns the language list, the persistence and
/// the "coming soon" fallback. A second copy of that list is a second thing
/// that can drift.
class AuthSettingsButton extends ConsumerWidget {
  const AuthSettingsButton({super.key, this.color = Colors.white70});

  /// Icon tint. The auth screens are always on the dark backdrop, so the
  /// default is legible everywhere they appear.
  final Color color;

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => _AuthSettingsSheet(
        onLanguage: () {
          // Close the sheet first so the pushed route is not sitting under it,
          // then push with the *screen's* context — the sheet's context is
          // already being torn down by the pop above.
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => const LanguageScreen(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: context.l10n.settings,
      onPressed: () => _openSheet(context),
      icon: const Icon(Icons.settings_rounded),
      color: color,
    );
  }
}

/// The bottom sheet behind [AuthSettingsButton].
class _AuthSettingsSheet extends ConsumerWidget {
  const _AuthSettingsSheet({required this.onLanguage});

  final VoidCallback onLanguage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `valueOrNull` rather than `requireValue`: the notifier reads local
    // storage, and on the very first frame that read may not have resolved.
    // The label is cosmetic, so a one-frame 'English' is better than a spinner.
    final String code = ref.watch(languageProvider).valueOrNull ?? 'en';
    final String label =
        code == 'bn' ? context.l10n.bengali : context.l10n.english;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: AppRadius.rXl,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.sm),
            // Grab handle — signals the sheet is dismissible by drag.
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: AppRadius.rPill,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(
                Icons.translate_rounded,
                color: AppColors.accentLight,
              ),
              title: Text(
                context.l10n.language,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              onTap: onLanguage,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
