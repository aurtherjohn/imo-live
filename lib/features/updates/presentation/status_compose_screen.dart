import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/status.dart';
import '../../../core/services/media_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../chats/presentation/providers.dart';
import '../../../core/utils/l10n.dart';

/// Compose a text, photo or video status update.
///
/// Accepts an optional `media` query parameter — the path of a photo the user
/// just captured from the Chats header camera button. When present the screen
/// opens straight into the media preview with that shot attached.
class StatusComposeScreen extends ConsumerStatefulWidget {
  const StatusComposeScreen({super.key, this.initialMediaPath});

  final String? initialMediaPath;

  @override
  ConsumerState<StatusComposeScreen> createState() => _StatusComposeScreenState();
}

class _StatusComposeScreenState extends ConsumerState<StatusComposeScreen> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  int _mode = 0; // 0 = text, 1 = photo/video
  int _backgroundIndex = 0;
  int _durationMs = 5000;
  double _fontSize = 32;

  StatusType _mediaType = StatusType.image;
  String? _mediaPath;
  final TextEditingController _caption = TextEditingController();

  bool _busy = false;

  /// Gradient pairs used as text-status backgrounds.
  static const List<List<int>> _backgrounds = <List<int>>[
    <int>[0xFF1F1F24, 0xFF2A1420],
    <int>[0xFF0F2027, 0xFF2C5364],
    <int>[0xFF3A1C71, 0xFFD76D77],
    <int>[0xFF134E5E, 0xFF71B280],
    <int>[0xFF42275A, 0xFF734B6D],
    <int>[0xFF904E55, 0xFFDD5E89],
    <int>[0xFF232526, 0xFF414345],
    <int>[0xFF0B486B, 0xFFF56217],
  ];

  @override
  void initState() {
    super.initState();
    // A photo handed over from the camera button arrives pre-attached, so the
    // composer opens in media mode rather than making the user pick it again.
    final String? initial = widget.initialMediaPath;
    if (initial != null && initial.isNotEmpty) {
      final String lower = initial.toLowerCase();
      _mode = 1;
      _mediaPath = initial;
      _mediaType = (lower.endsWith('.mp4') ||
              lower.endsWith('.mov') ||
              lower.endsWith('.mkv'))
          ? StatusType.video
          : StatusType.image;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _caption.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Contact? me = ref.watch(selfProfileProvider).valueOrNull;
    final bool hasContent = _mode == 0
        ? _text.text.trim().isNotEmpty
        : _mediaPath != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: context.l10n.close,
          onPressed: () => context.pop(),
        ),
        title: Text(context.l10n.newUpdate),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.textStatus,
            onPressed: () => setState(() {
              _mode = 0;
              _focus.requestFocus();
            }),
            icon: Icon(
              Icons.text_fields_rounded,
              color: _mode == 0 ? context.c.accent : null,
            ),
          ),
          IconButton(
            tooltip: context.l10n.photoOrVideo,
            onPressed: _pickMedia,
            icon: Icon(
              Icons.image_outlined,
              color: _mode == 1 ? context.c.accent : null,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _mode == 0 ? _buildTextEditor() : _buildMediaPreview(),
          ),
          _buildToolbar(me),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: ProminentButton(
                label: _busy ? context.l10n.sharing2 : context.l10n.shareUpdate,
                icon: Icons.send_rounded,
                expanded: true,
                onPressed: hasContent && !_busy ? () => _share(me) : () {},
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ text editor

  Widget _buildTextEditor() {
    final List<int> colors = _backgrounds[_backgroundIndex];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(colors[0]),
              Color(colors[1]),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppRadius.rLg,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              maxLines: null,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: Colors.white,
              style: TextStyle(
                color: Colors.white,
                fontSize: _fontSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: context.l10n.typeAStatus,
                hintStyle: TextStyle(
                  color: Colors.white54,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (_mediaPath == null) {
      return EmptyState(
        icon: Icons.add_photo_alternate_outlined,
        title: context.l10n.addAPhotoOrVideo,
        message: context.l10n.pickMediaFromYourGallery,
        actionLabel: context.l10n.chooseMedia,
      );
    }
    final bool isVideo = _mediaType == StatusType.video;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ClipRRect(
        borderRadius: AppRadius.rLg,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            isVideo
                ? Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(
                          Icons.play_circle_outline_rounded,
                          size: 64,
                          color: Colors.white70,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          context.l10n.videoStatus,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  )
                : Image.file(
                    File(_mediaPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Container(
                      color: context.c.surfaceAlt,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: AppRadius.rMd,
                ),
                child: TextField(
                  controller: _caption,
                  maxLines: 2,
                  minLines: 1,
                  cursorColor: Colors.white,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: context.l10n.addACaption,
                    hintStyle: TextStyle(color: Colors.white60),
                  ),
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.sm,
              top: AppSpacing.sm,
              child: IconButton(
                tooltip: context.l10n.remove,
                onPressed: () => setState(() {
                  _mediaPath = null;
                }),
                icon: const Icon(Icons.cancel, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- toolbar

  Widget _buildToolbar(Contact? me) {
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: context.c.card,
        border: Border(top: BorderSide(color: context.c.divider, width: 0.6)),
      ),
      child: _mode == 0 ? _textToolbar() : _mediaToolbar(me),
    );
  }

  Widget _textToolbar() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      children: <Widget>[
        for (int i = 0; i < _backgrounds.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: GestureDetector(
              onTap: () => setState(() => _backgroundIndex = i),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Color(_backgrounds[i][0]),
                      Color(_backgrounds[i][1]),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _backgroundIndex == i
                        ? context.c.accent
                        : context.c.divider,
                    width: _backgroundIndex == i ? 2.5 : 1,
                  ),
                ),
              ),
            ),
          ),
        Container(width: 1, color: context.c.divider),
        const SizedBox(width: AppSpacing.md),
        _FontSizeStepper(
          value: _fontSize,
          onChanged: (double v) => setState(() => _fontSize = v),
        ),
      ],
    );
  }

  Widget _mediaToolbar(Contact? me) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _DurationPicker(
              value: _durationMs,
              onChanged: (int v) => setState(() => _durationMs = v),
            ),
          ),
          IconButton.filledTonal(
            tooltip: context.l10n.changeMedia,
            onPressed: _pickMedia,
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- behaviour

  Future<void> _pickMedia() async {
    setState(() => _busy = true);
    final MediaPickResult picked = await ref
        .read(mediaServiceProvider)
        .pickImages(fromCamera: false);
    if (!mounted) return;
    setState(() => _busy = false);

    if (picked.permissionDenied) {
      iToast(context, context.l10n.galleryPermissionIsRequired, isError: true);
      return;
    }
    if (picked.hasError || picked.attachments.isEmpty) {
      if (picked.error != null) iToast(context, picked.error!, isError: true);
      return;
    }
    final String? path = picked.attachments.first.localPath;
    if (path == null) return;

    final bool isVideo = path.toLowerCase().endsWith('.mp4') ||
        path.toLowerCase().endsWith('.mov') ||
        path.toLowerCase().endsWith('.mkv');

    setState(() {
      _mode = 1;
      _mediaPath = path;
      _mediaType = isVideo ? StatusType.video : StatusType.image;
    });
  }

  Future<void> _share(Contact? me) async {
    if (_mode == 0 && _text.text.trim().isEmpty) return;
    if (_mode == 1 && _mediaPath == null) return;

    setState(() => _busy = true);

    final String authorId = me?.id ?? 'self';
    final String authorName = me?.fullName ?? 'You';
    final String id = 'status_${DateTime.now().microsecondsSinceEpoch}';

    final Status status = _mode == 0
        ? Status(
            id: id,
            authorId: authorId,
            authorName: authorName,
            type: StatusType.text,
            text: _text.text.trim(),
            backgroundColors: _backgrounds[_backgroundIndex],
            fontSize: _fontSize,
            durationMs: _durationMs,
            createdAt: DateTime.now(),
            isOwn: true,
          )
        : Status(
            id: id,
            authorId: authorId,
            authorName: authorName,
            type: _mediaType,
            text: '',
            mediaPath: _mediaPath,
            caption: _caption.text.trim(),
            durationMs: _durationMs,
            createdAt: DateTime.now(),
            isOwn: true,
          );

    await ref.read(statusesProvider.notifier).add(status);

    // Publish to `status/{statusId}` so the update is visible to the user's
    // contacts on any device. Best-effort: the local copy is already saved.
    final String uid = ref.read(currentUidProvider);
    if (uid.isNotEmpty) {
      unawaited(
        ref.read(firestoreChatServiceProvider).publishStatus(
              statusId: status.id,
              userId: uid,
              caption: status.caption.isEmpty ? status.text : status.caption,
              mediaUrl: status.mediaPath ?? '',
              type: status.type.name,
            ),
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    iToast(context, context.l10n.updateShared);
    context.pop();
  }
}

// ---------------------------------------------------------------------------

class _FontSizeStepper extends StatelessWidget {
  const _FontSizeStepper({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: context.l10n.smallerText,
          onPressed: value <= 18 ? null : () => onChanged(value - 4),
          icon: const Icon(Icons.text_decrease_rounded),
        ),
        Center(
          child: Text(
            context.l10n.aa,
            style: TextStyle(
              fontSize: 14 + (value - 26),
              fontWeight: FontWeight.w600,
              color: context.c.textSecondary,
            ),
          ),
        ),
        IconButton(
          tooltip: context.l10n.largerText,
          onPressed: value >= 56 ? null : () => onChanged(value + 4),
          icon: const Icon(Icons.text_increase_rounded),
        ),
      ],
    );
  }
}

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static List<({int ms, String label})> _options(BuildContext context) =>
      <({int ms, String label})>[
    (ms: 3000, label: context.l10n.seconds3),
    (ms: 5000, label: context.l10n.seconds5),
    (ms: 10000, label: context.l10n.seconds10),
    (ms: 30000, label: context.l10n.seconds30),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(Icons.timer_outlined,
            size: AppIconSizes.sm, color: context.c.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              for (final ({int ms, String label}) option in _options(context))
                ChoiceChip(
                  label: Text(option.label),
                  selected: value == option.ms,
                  onSelected: (_) => onChanged(option.ms),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: value == option.ms
                        ? context.c.textOnAccent
                        : context.c.textPrimary,
                  ),
                  selectedColor: context.c.accent,
                  backgroundColor: context.c.surfaceAlt,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
