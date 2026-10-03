import 'package:flutter/material.dart';

import '../../app/theme/app_color_scheme.dart';
import '../../app/theme/app_tokens.dart';
import '../services/media_service.dart';
import '../utils/l10n.dart';

/// Which source the user chose in [showCameraSourceSheet].
enum CameraSource { camera, gallery }

/// Asks whether to shoot a new photo/video or pick an existing one.
///
/// Returns null when dismissed. The caller is responsible for actually running
/// the picker through [MediaService] — this sheet only collects the intent, so
/// the same flow can be reused from the Chats header, a status update and the
/// profile editor.
Future<CameraSource?> showCameraSourceSheet(
  BuildContext context, {
  bool allowVideo = true,
}) {
  return showModalBottomSheet<CameraSource>(
    context: context,
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: sheetContext.c.divider,
              borderRadius: AppRadius.rPill,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(context.l10n.camera, style: sheetContext.t.titleMedium),
            ),
          ),
          _SourceTile(
            icon: Icons.photo_camera_rounded,
            title: context.l10n.takeAPhoto,
            subtitle: context.l10n.opensTheDeviceCamera,
            onTap: () => Navigator.pop(sheetContext, CameraSource.camera),
          ),
          if (allowVideo)
            _SourceTile(
              icon: Icons.photo_library_rounded,
              title: context.l10n.chooseFromGallery,
              subtitle: context.l10n.pickAnExistingPhotoOr,
              onTap: () => Navigator.pop(sheetContext, CameraSource.gallery),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: context.c.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: AppIconSizes.md, color: context.c.accent),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: context.t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains a failed capture and offers a shortcut into system settings.
///
/// Every camera path in the app funnels its errors here so that a refused
/// permission is never a silent no-op — the specific complaint that started
/// this work was "tapping the camera icon does nothing".
void showMediaErrorSnack(
  BuildContext context,
  MediaPickResult result, {
  VoidCallback? onOpenSettings,
}) {
  final String? message = result.error;
  if (message == null) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: result.permissionDenied && onOpenSettings != null
            ? SnackBarAction(label: context.l10n.settings, onPressed: onOpenSettings)
            : null,
      ),
    );
}
