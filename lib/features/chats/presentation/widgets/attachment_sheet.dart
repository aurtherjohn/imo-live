import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/l10n.dart';

/// The attachment kinds offered by the composer.
enum AttachmentKind {
  gallery,
  camera,
  video,
  audio,
  document,
  location,
  contact,
  poll,
  quiz,
  event,
  sticker,
  wallpaper,
  voiceNote,
}

extension AttachmentKindX on AttachmentKind {
  String get label => switch (this) {
        AttachmentKind.gallery => 'Gallery',
        AttachmentKind.camera => 'Camera',
        AttachmentKind.video => 'Video',
        AttachmentKind.audio => 'Audio',
        AttachmentKind.document => 'Document',
        AttachmentKind.location => 'Location',
        AttachmentKind.contact => 'Contact',
        AttachmentKind.poll => 'Poll',
        AttachmentKind.quiz => 'Quiz',
        AttachmentKind.event => 'Event',
        AttachmentKind.sticker => 'Sticker',
        AttachmentKind.wallpaper => 'Wallpaper',
        AttachmentKind.voiceNote => 'Voice note',
      };

  IconData get icon => switch (this) {
        AttachmentKind.gallery => Icons.photo_library_rounded,
        AttachmentKind.camera => Icons.camera_alt_rounded,
        AttachmentKind.video => Icons.videocam_rounded,
        AttachmentKind.audio => Icons.library_music_rounded,
        AttachmentKind.document => Icons.insert_drive_file_rounded,
        AttachmentKind.location => Icons.location_on_rounded,
        AttachmentKind.contact => Icons.person_rounded,
        AttachmentKind.poll => Icons.poll_rounded,
        AttachmentKind.quiz => Icons.quiz_rounded,
        AttachmentKind.event => Icons.event_rounded,
        AttachmentKind.sticker => Icons.emoji_emotions_rounded,
        AttachmentKind.wallpaper => Icons.wallpaper_rounded,
        AttachmentKind.voiceNote => Icons.mic_rounded,
      };

  Color get color => switch (this) {
        AttachmentKind.gallery => const Color(0xFFB45FCB),
        AttachmentKind.camera => const Color(0xFF4A8FE7),
        AttachmentKind.video => const Color(0xFFE0577B),
        AttachmentKind.audio => const Color(0xFFE08A3C),
        AttachmentKind.document => const Color(0xFF6C7BD1),
        AttachmentKind.location => const Color(0xFF2BA769),
        AttachmentKind.contact => const Color(0xFF2BB3A3),
        AttachmentKind.poll => const Color(0xFF3FA45B),
        AttachmentKind.quiz => const Color(0xFF8B5CF6),
        AttachmentKind.event => const Color(0xFFD65C5C),
        AttachmentKind.sticker => const Color(0xFFFFB020),
        AttachmentKind.wallpaper => const Color(0xFF7B61FF),
        AttachmentKind.voiceNote => AppColors.accent,
      };
}

/// Bottom sheet presenting every attachment option.
///
/// Laid out in a grid so each item is a comfortable tap target. Returns the
/// chosen [AttachmentKind], or null when dismissed.
Future<AttachmentKind?> showAttachmentSheet(BuildContext context) {
  return showModalBottomSheet<AttachmentKind>(
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
              color: context.c.divider,
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
              child: Text(context.l10n.share, style: context.t.titleMedium),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.86,
            ),
            itemCount: AttachmentKind.values.length,
            itemBuilder: (BuildContext context, int index) {
              final AttachmentKind kind = AttachmentKind.values[index];
              return _AttachmentOption(
                kind: kind,
                onTap: () => Navigator.pop(sheetContext, kind),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    ),
  );
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({required this.kind, required this.onTap});

  final AttachmentKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.rLg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: kind.color.withValues(alpha: 0.16),
              borderRadius: AppRadius.rLg,
            ),
            child: Icon(kind.icon, size: AppIconSizes.lg, color: kind.color),
          ),
          const SizedBox(height: AppSpacing.sm - 2),
          Text(
            kind.label,
            style: context.t.labelSmall?.copyWith(fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
