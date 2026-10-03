import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/gift.dart';
import '../../../../core/models/message.dart';
import '../../../../core/models/message_parts.dart';
import '../../../../core/services/voice_player.dart';
import '../../../../core/utils/formatters.dart';
import 'message_bubble_parts.dart';
import '../../../../core/utils/l10n.dart';

/// Resolves the renderable image for an [attachment].
///
/// The local file wins: it is instant, works offline, and is the only source
/// that exists for media this device sent. The R2 URL is the fallback, and it
/// is what makes media **received from another device** render at all — before
/// this the receive path had no attachment and every incoming photo showed
/// "Photo unavailable".
///
/// Returns null when neither source is usable, so the caller can show its own
/// unavailable state instead of a broken-image box.
ImageProvider? mediaImageProvider(Attachment? attachment) {
  if (attachment == null) return null;
  final String? path = attachment.localPath;
  if (path != null && path.isNotEmpty && File(path).existsSync()) {
    return FileImage(File(path));
  }
  final String? url = attachment.remoteUrl;
  if (url != null && url.isNotEmpty) {
    return CachedNetworkImageProvider(url);
  }
  return null;
}

/// True when [attachment] resolves to something renderable.
bool hasRenderableMedia(Attachment? attachment) =>
    mediaImageProvider(attachment) != null;

/// Renders a message bubble for any [MessageType].
///
/// Everything is real: images load from the local file, voice/audio notes carry
/// a working scrubber, polls accept votes, events accept RSVPs and location
/// cards open the platform map. [onInteraction] receives a typed payload so the
/// parent screen owns the persistence.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.showSenderName,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.onPollVote,
    this.onRsvp,
    this.onOpenMedia,
    this.onOpenLocation,
    this.onOpenContact,
    this.onOpenDocument,
    this.onSave,
    this.isHighlighted = false,
    this.isSelected = false,
  });

  final Message message;
  final bool showSenderName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final ValueChanged<String>? onPollVote;
  final ValueChanged<RsvpStatus>? onRsvp;
  final VoidCallback? onOpenMedia;
  final VoidCallback? onOpenLocation;
  final VoidCallback? onOpenContact;
  final VoidCallback? onOpenDocument;

  /// Saves this message's attachment to the device.
  ///
  /// A visible affordance on the bubble itself, not only in the long-press
  /// menu: saving a photo is one of the most common things a person does with
  /// one, and burying it behind a long-press is how a feature goes unfound.
  final VoidCallback? onSave;
  final bool isHighlighted;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return BubbleShell(
        isOutgoing: message.isOutgoing,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DeletedMessageBody(isOutgoing: message.isOutgoing),
            BubbleFooter(message: message, compact: true),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BubbleShell(
          isOutgoing: message.isOutgoing,
          padding: _paddingFor(message.type),
          border: isHighlighted
              ? Border.all(color: context.c.accent, width: 1.4)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MessageMeta(
                message: message,
                showSenderName: showSenderName,
                senderColor: _senderColor(message.senderName),
              ),
              if (message.replyTo != null)
                QuotedMessage(
                  reply: message.replyTo!,
                  isOutgoing: message.isOutgoing,
                ),
              _Body(
                message: message,
                onPollVote: onPollVote,
                onRsvp: onRsvp,
                onOpenMedia: onOpenMedia,
                onOpenLocation: onOpenLocation,
                onOpenContact: onOpenContact,
                onOpenDocument: onOpenDocument,
                onSave: onSave,
              ),
              if (!_isMediaOnly(message.type))
                BubbleFooter(message: message),
            ],
          ),
        ),
        if (message.reactions.isNotEmpty)
          ReactionChips(reactions: message.reactions),
      ],
    );
  }

  static EdgeInsets _paddingFor(MessageType type) => switch (type) {
        MessageType.image || MessageType.video => const EdgeInsets.all(4),
        MessageType.sticker => const EdgeInsets.all(AppSpacing.sm),
        _ => const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 1,
          ),
      };

  /// Media bubbles overlay their footer, so no separate row is emitted.
  static bool _isMediaOnly(MessageType type) =>
      type == MessageType.image ||
      type == MessageType.video ||
      type == MessageType.sticker;

  static Color _senderColor(String name) {
    const List<Color> palette = <Color>[
      Color(0xFFE0577B),
      Color(0xFF7B61FF),
      Color(0xFF2BB3A3),
      Color(0xFFE08A3C),
      Color(0xFF4A8FE7),
      Color(0xFFB45FCB),
      Color(0xFF3FA45B),
      Color(0xFFD65C5C),
    ];
    if (name.isEmpty) return palette.first;
    int hash = 0;
    for (final int unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}

/// Routes to the concrete body for the message type.
class _Body extends StatelessWidget {
  const _Body({
    required this.message,
    this.onPollVote,
    this.onRsvp,
    this.onOpenMedia,
    this.onOpenLocation,
    this.onOpenContact,
    this.onOpenDocument,
    this.onSave,
  });

  final Message message;
  final ValueChanged<String>? onPollVote;
  final ValueChanged<RsvpStatus>? onRsvp;
  final VoidCallback? onOpenMedia;
  final VoidCallback? onOpenLocation;
  final VoidCallback? onOpenContact;
  final VoidCallback? onOpenDocument;
  final VoidCallback? onSave;

  /// Message types whose attachment has bytes worth keeping on the device.
  static bool _isSavable(MessageType type) =>
      type == MessageType.image ||
      type == MessageType.video ||
      type == MessageType.document ||
      type == MessageType.voice ||
      type == MessageType.audio;

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (message.type) {
      MessageType.text => TextBody(message: message),
      MessageType.image => ImageBody(
          message: message,
          onTap: onOpenMedia,
        ),
      MessageType.video => VideoBody(
          message: message,
          onTap: onOpenMedia,
        ),
      MessageType.voice => VoiceBody(message: message),
      MessageType.audio => AudioBody(message: message),
      MessageType.document => DocumentBody(
          message: message,
          onTap: onOpenDocument,
        ),
      MessageType.location => LocationBody(
          message: message,
          onTap: onOpenLocation,
        ),
      MessageType.contact => ContactBody(
          message: message,
          onTap: onOpenContact,
        ),
      MessageType.poll => PollBody(
          message: message,
          onVote: onPollVote,
        ),
      MessageType.event => EventBody(
          message: message,
          onRsvp: onRsvp,
        ),
      MessageType.sticker => StickerBody(message: message),
      MessageType.system => SystemBody(message: message),
      MessageType.gift => GiftBody(message: message),
    };

    final VoidCallback? save = onSave;
    if (save == null || !_isSavable(message.type)) return body;

    // A full-bleed image or video has its whole surface as the target, so the
    // save button sits in the bottom-right corner over the media. A document or
    // a voice note has text and a play control in those places, so it goes to
    // the top-right instead.
    final bool fullBleed = message.type == MessageType.image ||
        message.type == MessageType.video;
    return Stack(
      children: <Widget>[
        body,
        Positioned(
          top: fullBleed ? null : 2,
          bottom: fullBleed ? 6 : null,
          right: 6,
          child: _SaveOverlayButton(onTap: save),
        ),
      ],
    );
  }
}

/// The small translucent "save to device" control drawn over a media bubble.
class _SaveOverlayButton extends StatelessWidget {
  const _SaveOverlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: context.l10n.saveToDevice,
          child: Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.download_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- text

class TextBody extends StatelessWidget {
  const TextBody({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    if (message.content.isEmpty) return const SizedBox.shrink();
    return SelectableText(
      message.content,
      style: context.t.bodyLarge?.copyWith(height: 1.32, letterSpacing: 0.1),
    );
  }
}

// ---------------------------------------------------------------- image

class ImageBody extends StatelessWidget {
  const ImageBody({super.key, required this.message, this.onTap});

  final Message message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Attachment? attachment = message.attachment;
    final ImageProvider? image = mediaImageProvider(attachment);
    final double width = MediaQuery.of(context).size.width *
        AppSizes.maxBubbleWidthFactor;
    final double height = width * 0.72;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.md),
          topRight: Radius.circular(AppRadius.md),
          bottomLeft: Radius.circular(AppRadius.md),
          bottomRight: Radius.circular(2),
        ),
        child: Stack(
          children: <Widget>[
            SizedBox(
              width: width,
              height: height,
              child: image == null
                  ? _MissingMedia(
                      icon: Icons.image_rounded,
                      label: context.l10n.photoUnavailable,
                    )
                  : Image(
                      image: image,
                      fit: BoxFit.cover,
                      errorBuilder: (
                        BuildContext context,
                        Object error,
                        StackTrace? stack,
                      ) =>
                          _MissingMedia(
                        icon: Icons.broken_image_rounded,
                        label: context.l10n.photoUnavailable,
                      ),
                    ),
            ),
            if (message.content.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xxl,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Colors.transparent, Color(0xB3000000)],
                    ),
                  ),
                  child: Text(
                    message.content,
                    style: context.t.bodyMedium?.copyWith(
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            Positioned(
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: _MediaFooter(message: message),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- video

class VideoBody extends StatelessWidget {
  const VideoBody({super.key, required this.message, this.onTap});

  final Message message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Attachment? attachment = message.attachment;
    final double width =
        MediaQuery.of(context).size.width * AppSizes.maxBubbleWidthFactor;
    final double height = width * 0.62;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.md),
          topRight: Radius.circular(AppRadius.md),
          bottomLeft: Radius.circular(AppRadius.md),
          bottomRight: Radius.circular(2),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Container(
                color: const Color(0xFF101014),
                child: attachment?.thumbnailPath != null &&
                        File(attachment!.thumbnailPath!).existsSync()
                    ? Image.file(File(attachment.thumbnailPath!),
                        fit: BoxFit.cover)
                    : const Center(
                        child: Icon(
                          Icons.movie_creation_outlined,
                          size: 40,
                          color: Colors.white24,
                        ),
                      ),
              ),
              const Center(child: _PlayBadge()),
              if (attachment?.durationMs != null)
                Positioned(
                  left: AppSpacing.sm,
                  top: AppSpacing.sm,
                  child: _Chip(label: attachment!.readableDuration),
                ),
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: _MediaFooter(message: message),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white70, width: 1.6),
      ),
      child: const Icon(Icons.play_arrow_rounded, size: 30, color: Colors.white),
    );
  }
}

// ---------------------------------------------------------------- voice

/// Voice note bubble with a real player.
///
/// Tap the button to play or pause. The waveform fill tracks the actual
/// playback position rather than a decorative constant, and the elapsed time
/// replaces the timestamp while the note is playing. A note with neither a
/// local file nor a remote URL renders as unplayable instead of pretending to
/// work — the previous implementation drew a play icon that was not even
/// tappable.
class VoiceBody extends ConsumerStatefulWidget {
  const VoiceBody({super.key, required this.message});

  final Message message;

  @override
  ConsumerState<VoiceBody> createState() => _VoiceBodyState();
}

class _VoiceBodyState extends ConsumerState<VoiceBody> {
  bool _unavailable = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Attachment? attachment = widget.message.attachment;
    final int durationMs = attachment?.durationMs ?? 0;
    final VoicePlayerService player = ref.watch(voicePlayerProvider);

    final String? local = attachment?.localPath;
    final String? remote = attachment?.remoteUrl;
    final bool hasLocalFile = local != null &&
        local.isNotEmpty &&
        !local.startsWith('http') &&
        File(local).existsSync();
    final bool playable = hasLocalFile || (remote != null && remote.isNotEmpty);
    final bool unavailable = !playable || _unavailable;

    return StreamBuilder<VoicePlayback>(
      stream: player.stream,
      initialData: player.state,
      builder: (BuildContext context, AsyncSnapshot<VoicePlayback> snapshot) {
        final VoicePlayback playback = snapshot.data ?? const VoicePlayback();
        final bool active = playback.messageId == widget.message.id;
        final bool playing = active && playback.playing;
        final bool loading = active && playback.loading;
        final bool started = active && playback.position > Duration.zero;
        final Duration shown =
            started ? playback.position : Duration(milliseconds: durationMs);
        final double progress = active ? playback.progress : 0;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 228),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(
                onTap: unavailable ? null : _toggle,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: unavailable ? c.surfaceAlt : c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: loading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          unavailable
                              ? Icons.mic_off_rounded
                              : playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                          size: 21,
                          color: Colors.white,
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _Waveform(seed: widget.message.id, progress: progress),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        if (widget.message.isForwarded)
                          Icon(
                            Icons.forward_rounded,
                            size: 11,
                            color: c.textSecondary,
                          ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            started
                                ? _clock(shown)
                                : DateFormatter.time(widget.message.timestamp),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _DurationLabel(
                          ms: active && playback.duration > Duration.zero
                              ? playback.duration.inMilliseconds
                              : durationMs,
                        ),
                        if (widget.message.isOutgoing) ...<Widget>[
                          const SizedBox(width: 4),
                          MessageStatusIcon(
                            status: widget.message.status,
                            size: 13,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggle() async {
    final Attachment? attachment = widget.message.attachment;
    final bool ok = await ref.read(voicePlayerProvider).toggle(
          messageId: widget.message.id,
          localPath: attachment?.localPath,
          remoteUrl: attachment?.remoteUrl,
          durationMs: attachment?.durationMs,
        );
    if (!mounted) return;
    if (!ok) setState(() => _unavailable = true);
  }

  static String _clock(Duration d) {
    final int total = d.inSeconds;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

class _DurationLabel extends StatelessWidget {
  const _DurationLabel({required this.ms});

  final int ms;

  @override
  Widget build(BuildContext context) {
    final int totalSeconds = ms ~/ 1000;
    return Text(
      '${totalSeconds ~/ 60}:${(totalSeconds % 60).toString().padLeft(2, '0')}',
      style: TextStyle(fontSize: 11, color: context.c.textSecondary),
    );
  }
}

/// Deterministic pseudo-waveform so every voice note looks distinct and stable,
/// with the played portion filled to the real playback position.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.seed, this.progress = 0});

  final String seed;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    int hash = 0;
    for (final int unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return SizedBox(
      height: 22,
      child: CustomPaint(
        painter: _WavePainter(
          seed: hash,
          progress: progress,
          color: c.accent.withValues(alpha: 0.85),
          base: c.textSecondary.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.seed,
    required this.progress,
    required this.color,
    required this.base,
  });

  final int seed;
  final double progress;
  final Color color;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    const int bars = 32;
    final double barWidth = size.width / (bars * 1.7);
    final double gap = barWidth * 0.7;
    final Paint paint = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i < bars; i++) {
      final double t = ((seed >> (i % 20)) & 0x7) / 7.0;
      final double h = 4 + t * (size.height - 6);
      final double x = (barWidth + gap) * i;
      paint.strokeWidth = barWidth;
      // Bars behind the play head are filled; the rest keep the idle colour.
      paint.color = (i + 1) / bars <= progress ? color : base;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color;
}

// ---------------------------------------------------------------- audio

/// Music/audio attachment bubble.
class AudioBody extends StatelessWidget {
  const AudioBody({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Attachment? attachment = message.attachment;

    return SizedBox(
      width: 236,
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.16),
              borderRadius: AppRadius.rMd,
            ),
            child: Icon(Icons.music_note_rounded, size: 22, color: c.accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  attachment?.fileName?.replaceAll(RegExp(r'\.[^.]+$'), '') ??
                      'Audio file',
                  style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  attachment?.readableDuration ?? '--:--',
                  style: context.t.labelSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: AppRadius.rPill,
                  child: LinearProgressIndicator(
                    value: 0.38,
                    minHeight: 3,
                    backgroundColor: c.divider,
                    color: c.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.play_circle_fill_rounded, size: 32, color: c.accent),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- document

class DocumentBody extends StatelessWidget {
  const DocumentBody({super.key, required this.message, this.onTap});

  final Message message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Attachment? attachment = message.attachment;

    return SizedBox(
      width: 246,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rSm,
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 46,
              decoration: BoxDecoration(
                color: _docColor(attachment),
                borderRadius: AppRadius.rSm,
              ),
              child: Center(
                child: Text(
                  attachment?.fileExtension.isEmpty ?? true
                      ? 'FILE'
                      : attachment!.fileExtension,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    attachment?.fileName ?? 'Document',
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${attachment?.readableSize ?? '—'} · ${attachment?.fileExtension.toLowerCase() ?? ''}',
                    style: context.t.labelSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppRadius.rPill,
                          child: LinearProgressIndicator(
                            value: 1,
                            minHeight: 2.5,
                            backgroundColor: c.divider,
                            color: c.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.download_done_rounded,
                        size: 15,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _docColor(Attachment? attachment) {
    final String ext = attachment?.fileExtension.toLowerCase() ?? '';
    return switch (ext) {
      'pdf' => const Color(0xFFD9503F),
      'doc' || 'docx' => const Color(0xFF2B579A),
      'xls' || 'xlsx' || 'csv' => const Color(0xFF1F7244),
      'ppt' || 'pptx' => const Color(0xFFD24726),
      'zip' || 'rar' || '7z' => const Color(0xFF8E6B2E),
      'txt' => const Color(0xFF5A6472),
      _ => const Color(0xFF6C7BD1),
    };
  }
}

// ------------------------------------------------------------- location

class LocationBody extends StatelessWidget {
  const LocationBody({super.key, required this.message, this.onTap});

  final Message message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Attachment? attachment = message.attachment;
    final double? lat = attachment?.latitude;
    final double? lon = attachment?.longitude;

    return SizedBox(
      width: 244,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: AppRadius.rMd,
              child: SizedBox(
                height: 118,
                width: double.infinity,
                child: _MapPreview(latitude: lat, longitude: lon),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Icon(
                  Icons.location_on_rounded,
                  size: 17,
                  color: context.c.accent,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    attachment?.fileName?.isNotEmpty ?? false
                        ? attachment!.fileName!
                        : 'Shared location',
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              lat == null || lon == null
                  ? 'Coordinates unavailable'
                  : '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
              style: context.t.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Offline coordinate preview card.
///
/// A real map tile provider is the marked integration point (see
/// [MapProviderConfig]); until one is configured this renders a deterministic,
/// dependency-free grid so the layout is final and the data is honest.
class _MapPreview extends StatelessWidget {
  const _MapPreview({this.latitude, this.longitude});

  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final bool hasCoords = latitude != null && longitude != null;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(
          painter: _GridPainter(
            base: c.surfaceAlt,
            line: c.divider,
            seed: hasCoords
                ? ((latitude! * 1000).round() ^ (longitude! * 1000).round())
                : 0,
            accent: c.accent,
          ),
        ),
        if (hasCoords)
          Center(
            child: Icon(
              Icons.location_pin,
              size: 34,
              color: c.accent,
              shadows: const <Shadow>[
                Shadow(color: Color(0x66000000), blurRadius: 6),
              ],
            ),
          ),
        if (!hasCoords)
          Center(
            child: Text(
              context.l10n.locationPreview,
              style: context.t.labelSmall,
            ),
          ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.base,
    required this.line,
    required this.seed,
    required this.accent,
  });

  final Color base;
  final Color line;
  final int seed;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = base,
    );

    final Paint road = Paint()
      ..color = line
      ..strokeWidth = 1;
    const double step = 22;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }

    // A couple of deterministic "blocks" so the preview reads as a map.
    final Paint block = Paint()..color = accent.withValues(alpha: 0.16);
    for (int i = 0; i < 5; i++) {
      final double x = ((seed >> (i * 3)) & 0xF) / 15 * (size.width - 46);
      final double y = ((seed >> (i * 2 + 1)) & 0xF) / 15 * (size.height - 30);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 40, 24),
          const Radius.circular(4),
        ),
        block,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.base != base;
}

// -------------------------------------------------------------- contact

class ContactBody extends StatelessWidget {
  const ContactBody({super.key, required this.message, this.onTap});

  final Message message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Attachment? attachment = message.attachment;
    final String name = attachment?.contactName ?? message.content;

    return SizedBox(
      width: 232,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rSm,
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_rounded,
                size: 22,
                color: c.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    name.isEmpty ? 'Contact' : name,
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attachment?.contactPhone ?? 'Phone number',
                    style: context.t.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ----------------------------------------------------------------- poll

class PollBody extends StatelessWidget {
  const PollBody({super.key, required this.message, this.onVote});

  final Message message;
  final ValueChanged<String>? onVote;

  @override
  Widget build(BuildContext context) {
    final Poll? poll = message.poll;
    if (poll == null) return const SizedBox.shrink();

    final bool isQuiz = poll.isQuiz;
    // Quiz results stay hidden until you answer, so the correct row cannot be
    // read off the bars without committing to a choice.
    final bool revealed = !isQuiz || poll.totalVotes > 0;
    final bool answeredWrong = isQuiz &&
        poll.totalVotes > 0 &&
        poll.correctOptionId != null &&
        !(poll.correctOption?.voterIds.isNotEmpty ?? false);

    return SizedBox(
      width: 262,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isQuiz ? Icons.quiz_rounded : Icons.poll_rounded,
                size: 16,
                color: context.c.accent,
              ),
              const SizedBox(width: 6),
              Text(
                isQuiz ? 'QUIZ' : 'POLL',
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              if (isQuiz && revealed) ...<Widget>[
                const Spacer(),
                Icon(
                  answeredWrong
                      ? Icons.cancel_rounded
                      : Icons.verified_rounded,
                  size: 16,
                  color: answeredWrong ? answeredWrong ? context.c.onDanger : context.c.onSuccess : answeredWrong ? context.c.onDanger : context.c.onSuccess,
                ),
                const SizedBox(width: 4),
                Text(
                  answeredWrong ? 'Try again' : 'Correct',
                  style: context.t.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: answeredWrong ? answeredWrong ? context.c.onDanger : context.c.onSuccess : answeredWrong ? context.c.onDanger : context.c.onSuccess,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            poll.question,
            style: context.t.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          ...poll.options.map(
            (PollOption option) => _PollOptionRow(
              option: option,
              totalVotes: revealed ? poll.totalVotes : 0,
              // Before answering a quiz, show the options bare — grading is
              // what the tap reveals.
              grade: !revealed
                  ? null
                  : isQuiz
                      ? (option.id == poll.correctOptionId)
                      : null,
              onTap: message.isOutgoing || onVote == null
                  ? null
                  : () => onVote!(option.id),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isQuiz
                ? (poll.totalVotes == 0
                    ? 'Tap an answer to see the result'
                    : '${poll.totalVotes} ${poll.totalVotes == 1 ? 'answer' : 'answers'} · '
                        'correct answer marked in green')
                : '${poll.totalVotes} ${poll.totalVotes == 1 ? 'vote' : 'votes'}'
                    '${poll.allowMultiple ? ' · multiple answers' : ''}',
            style: context.t.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.option,
    required this.totalVotes,
    this.onTap,
    this.grade,
  });

  final PollOption option;
  final int totalVotes;
  final VoidCallback? onTap;

  /// `true`/`false` once a quiz has been answered; null for plain polls.
  final bool? grade;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final double fraction =
        totalVotes == 0 ? 0 : option.votes / totalVotes;
    final bool voted = option.voterIds.isNotEmpty;

    final Color barColor = switch (grade) {
      true => AppColors.success.withValues(alpha: 0.28),
      false => c.accent.withValues(alpha: 0.24),
      null => c.accent.withValues(alpha: 0.24),
    };
    final Color markColor = switch (grade) {
      true => context.c.onSuccess,
      false => c.accent,
      null => (voted ? c.accent : c.textSecondary),
    };
    final IconData markIcon = switch (grade) {
      true => Icons.check_circle_rounded,
      false => voted
          ? Icons.cancel_rounded
          : Icons.radio_button_off_rounded,
      null => voted
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_off_rounded,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rSm,
        child: ClipRRect(
          borderRadius: AppRadius.rSm,
          child: Stack(
            children: <Widget>[
              Container(
                height: 38,
                color: c.surfaceAlt,
              ),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(
                  height: 38,
                  color: barColor,
                ),
              ),
              SizedBox(
                height: 38,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        markIcon,
                        size: 16,
                        color: markColor,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          option.text,
                          style: context.t.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${option.votes}',
                        style: context.t.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- event

class EventBody extends StatelessWidget {
  const EventBody({super.key, required this.message, this.onRsvp});

  final Message message;
  final ValueChanged<RsvpStatus>? onRsvp;

  @override
  Widget build(BuildContext context) {
    final EventInfo? event = message.event;
    if (event == null) return const SizedBox.shrink();

    final AppColorScheme c = context.c;
    final int going =
        event.rsvps.values.where((RsvpStatus s) => s == RsvpStatus.going).length;
    final int maybe =
        event.rsvps.values.where((RsvpStatus s) => s == RsvpStatus.maybe).length;

    return SizedBox(
      width: 266,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.event_rounded, size: 16, color: c.accent),
              const SizedBox(width: 6),
              Text(
                context.l10n.event2,
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            event.title,
            style: context.t.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _EventRow(
            icon: Icons.schedule_rounded,
            label: _formatRange(event.start, event.end),
          ),
          if (event.location.isNotEmpty)
            _EventRow(icon: Icons.place_outlined, label: event.location),
          if (event.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              event.description,
              style: context.t.bodySmall?.copyWith(height: 1.3),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (onRsvp != null)
            Row(
              children: <Widget>[
                Expanded(
                  child: _RsvpChip(
                    label: context.l10n.going,
                    count: going,
                    isActive: event.rsvps.values.contains(RsvpStatus.going),
                    onTap: () => onRsvp!(RsvpStatus.going),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _RsvpChip(
                    label: context.l10n.maybe,
                    count: maybe,
                    isActive: event.rsvps.values.contains(RsvpStatus.maybe),
                    onTap: () => onRsvp!(RsvpStatus.maybe),
                  ),
                ),
              ],
            ),
          if (going + maybe > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.pollGoingMaybe(going, maybe),
              style: context.t.labelSmall,
            ),
          ],
        ],
      ),
    );
  }

  static String _formatRange(DateTime start, DateTime? end) {
    final String date = DateFormatter.fullTimestamp(start);
    if (end == null) return date;
    return '$date – ${DateFormatter.time(end)}';
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 15, color: context.c.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: context.t.bodySmall?.copyWith(height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _RsvpChip extends StatelessWidget {
  const _RsvpChip({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.rPill,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isActive ? c.accent : c.surfaceAlt,
          borderRadius: AppRadius.rPill,
        ),
        child: Center(
          child: Text(
            count > 0 ? '$label · $count' : label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : c.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- sticker

class StickerBody extends StatelessWidget {
  const StickerBody({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? image = mediaImageProvider(message.attachment);
    if (image != null) {
      return Image(
        image: image,
        width: 120,
        height: 120,
        fit: BoxFit.contain,
      );
    }
    return Container(
      width: 120,
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.c.surfaceAlt,
        borderRadius: AppRadius.rMd,
      ),
      child: Text(
        message.content.isEmpty ? '🙂' : message.content,
        style: const TextStyle(fontSize: 46),
      ),
    );
  }
}

// --------------------------------------------------------------- system

class SystemBody extends StatelessWidget {
  const SystemBody({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message.content,
      style: context.t.bodySmall?.copyWith(
        fontStyle: FontStyle.italic,
        height: 1.3,
      ),
    );
  }
}

// ---------------------------------------------------------------- gift

/// A gift the sender paid for with points.
///
/// Renders the gift's emoji at display size with its name and cost, rather than
/// as a line of text — a gift is the most expensive thing a user can send, and a
/// plain bubble would make it indistinguishable from a message that merely says
/// "🌹 Rose".
///
/// Falls back to the raw body when the content does not decode, which is what
/// keeps an older conversation readable if the encoding ever changes.
class GiftBody extends StatelessWidget {
  const GiftBody({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final ({String emoji, String name, int points})? gift =
        Gift.decodeMessageBody(message.content);

    if (gift == null) {
      return Text(message.content, style: context.t.bodyMedium);
    }

    final AppColorScheme c = context.c;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(gift.emoji, style: const TextStyle(fontSize: 34)),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              gift.name,
              style: context.t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.stars_rounded, size: 12, color: c.accent),
                const SizedBox(width: 3),
                Text(
                  context.l10n.points(TextUtils.grouped(gift.points)),
                  style: context.t.labelSmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- helpers

/// Small translucent label used over media.
class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: AppRadius.rSm,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Instagram-style caption + time overlay for media bubbles.
class _MediaFooter extends StatelessWidget {
  const _MediaFooter({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: AppRadius.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (message.isStarred) ...<Widget>[
            const Icon(Icons.star_rounded, size: 11, color: Colors.white70),
            const SizedBox(width: 3),
          ],
          Text(
            DateFormatter.time(message.timestamp),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (message.isOutgoing) ...<Widget>[
            const SizedBox(width: 4),
            MessageStatusIcon(status: message.status, size: 13),
          ],
        ],
      ),
    );
  }
}

/// Placeholder for media that could not be loaded from disk.
class _MissingMedia extends StatelessWidget {
  const _MissingMedia({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Container(
      color: c.surfaceAlt,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 32, color: c.textSecondary),
          const SizedBox(height: AppSpacing.sm),
          Text(label, style: context.t.labelSmall),
        ],
      ),
    );
  }
}
