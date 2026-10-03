import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/message.dart';
import '../../../../core/models/message_parts.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/audio_location_service.dart';
import '../../../../core/services/file_service.dart';
import '../../../../core/services/media_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../features/chats/presentation/providers.dart';
import '../../../../features/earn/presentation/providers.dart';
import 'attachment_sheet.dart';
import 'emoji_picker.dart';
import '../../../../core/utils/l10n.dart';

/// The message composer.
///
/// Handles text entry, emoji, attachments, voice-note recording with a live
/// timer and waveform, reply/edit banners, and send-on-enter behaviour driven
/// by the user's chat settings.
class MessageComposer extends ConsumerStatefulWidget {
  const MessageComposer({
    super.key,
    required this.chatId,
    required this.onSend,
    this.replyTo,
    this.editing,
    this.onCancelReply,
    this.onCancelEdit,
    this.enterKeySends = false,
    this.onTyping,
  });

  final String chatId;

  /// Called with the entered text plus any attachment / reply context.
  final void Function(String text, Attachment? attachment, ReplyPreview? replyTo)
      onSend;

  final ReplyPreview? replyTo;
  final Message? editing;
  final VoidCallback? onCancelReply;
  final VoidCallback? onCancelEdit;
  final bool enterKeySends;

  /// Reports whether the user is currently typing, so the screen can publish
  /// the flag to Firestore for the other participant.
  final ValueChanged<bool>? onTyping;

  @override
  ConsumerState<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<String> _recentEmoji = <String>[];

  bool _showEmoji = false;
  bool _isRecording = false;
  bool _hasText = false;
  Duration _recordedDuration = Duration.zero;
  StreamSubscription<Duration>? _elapsedSub;
  String? _recordingError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    if (widget.editing != null) {
      _controller.text = widget.editing!.content;
      _focusNode.requestFocus();
    }
  }

  @override
  void didUpdateWidget(MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing?.id != oldWidget.editing?.id && widget.editing != null) {
      _controller.text = widget.editing!.content;
      _focusNode.requestFocus();
    }
    if (widget.editing == null && oldWidget.editing != null) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _elapsedSub?.cancel();
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    final bool has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    // Only report a *transition* to typing; the screen owns the debounce that
    // clears it, so a long sentence does not fire a write per keystroke.
    if (has) widget.onTyping?.call(true);
  }

  void _send() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text, null, widget.replyTo);
    _controller.clear();
    setState(() => _hasText = false);
    widget.onTyping?.call(false);
  }

  // ------------------------------------------------------------ recording

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _recordedDuration = Duration.zero;
      _recordingError = null;
    });
    HapticFeedback.mediumImpact();

    final AudioRecorderService recorder = ref.read(audioRecorderProvider);
    final ({bool ok, String? error}) result = await recorder.start();
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _isRecording = false;
        _recordingError = result.error ?? 'Recording is unavailable.';
      });
      if (result.error != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(result.error!)));
      }
      return;
    }

    _elapsedSub?.cancel();
    _elapsedSub = recorder.elapsedStream.listen((Duration value) {
      if (mounted) setState(() => _recordedDuration = value);
    });
  }

  Future<void> _finishRecording({required bool keep}) async {
    final AudioRecorderService recorder = ref.read(audioRecorderProvider);
    _elapsedSub?.cancel();
    _elapsedSub = null;

    if (keep) {
      final VoiceRecordingResult result = await recorder.stopAndKeep();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (result.isSuccess) {
        widget.onSend(
          '',
          result.attachment,
          widget.replyTo,
        );
        HapticFeedback.lightImpact();
        // A finished recording is a completed, deliberate action, so it is a
        // defensible interstitial placement. Fired and forgotten — the send
        // must never wait on an ad load. Paced by [AdService] like every other
        // trigger.
        unawaited(
          ref.read(adServiceProvider).noteAndMaybeShow(AdTrigger.voiceMessage),
        );
      } else if (result.error != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(result.error!)));
      }
    } else {
      await recorder.cancel();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordedDuration = Duration.zero;
      });
    }
  }

  // ----------------------------------------------------------- attachment

  Future<void> _openAttachments() async {
    final AttachmentKind? kind = await showAttachmentSheet(context);
    if (kind == null || !mounted) return;

    switch (kind) {
      case AttachmentKind.gallery:
        final MediaPickResult result =
            await ref.read(mediaServiceProvider).pickImages(multiple: true);
        _deliverMedia(result);
      case AttachmentKind.camera:
        final MediaPickResult result =
            await ref.read(mediaServiceProvider).capturePhoto();
        _deliverMedia(result);
      case AttachmentKind.video:
        final MediaPickResult result =
            await ref.read(mediaServiceProvider).pickVideo();
        await _deliverVideo(result);
      case AttachmentKind.audio:
        final FilePickResult result =
            await ref.read(fileServiceProvider).pickAudio();
        _deliverFiles(result);
      case AttachmentKind.document:
        final List<Attachment> files =
            await ref.read(fileServiceProvider).pickDocuments();
        _deliverFiles(FilePickResult(attachments: files));
      case AttachmentKind.location:
        await _shareLocation();
      case AttachmentKind.voiceNote:
        await _startRecording();
      case AttachmentKind.contact:
        await _shareContact();
      case AttachmentKind.poll:
      case AttachmentKind.quiz:
      case AttachmentKind.event:
      case AttachmentKind.sticker:
      case AttachmentKind.wallpaper:
        if (!mounted) return;
        widget.onSend('__open_${kind.name}__', null, null);
    }
  }

  void _deliverMedia(MediaPickResult result) {
    if (!mounted) return;
    if (result.hasError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(result.error!),
            action: result.permissionDenied
                ? SnackBarAction(
                    label: context.l10n.settings,
                    onPressed: () =>
                        ref.read(permissionServiceProvider).openSettings(),
                  )
                : null,
          ),
        );
      return;
    }
    for (final Attachment attachment in result.attachments) {
      widget.onSend('', attachment, widget.replyTo);
    }
  }

  /// Videos get a poster frame before they are sent.
  ///
  /// `Attachment.thumbnailPath` was read by the bubble and written by nothing,
  /// so every video in every chat rendered the same grey placeholder. The
  /// poster is generated on the *sending* device, where the bytes already exist,
  /// which also means the receiver never pays to decode one.
  ///
  /// A failure here is not a failure to send: the attachment goes on unchanged
  /// and the bubble falls back to its placeholder.
  Future<void> _deliverVideo(MediaPickResult result) async {
    if (!mounted) return;
    if (result.hasError || result.attachments.isEmpty) {
      _deliverMedia(result);
      return;
    }

    final List<Attachment> enriched = <Attachment>[];
    for (final Attachment attachment in result.attachments) {
      final String? path = attachment.localPath;
      if (path == null || path.isEmpty) {
        enriched.add(attachment);
        continue;
      }
      final String? poster = await ref
          .read(videoThumbnailerProvider)
          .generate(context, path);
      enriched.add(
        poster == null ? attachment : attachment.copyWith(thumbnailPath: poster),
      );
    }

    if (!mounted) return;
    _deliverMedia(MediaPickResult(attachments: enriched));
  }

  void _deliverFiles(FilePickResult result) {
    if (!mounted) return;
    // A refusal must be explained. Returning silently here (the old behaviour)
    // meant that denying the audio permission looked like a broken button.
    if (result.error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(result.error!),
            action: result.permissionDenied
                ? SnackBarAction(
                    label: context.l10n.settings,
                    onPressed: () =>
                        ref.read(permissionServiceProvider).openSettings(),
                  )
                : null,
          ),
        );
      return;
    }
    for (final Attachment attachment in result.attachments) {
      widget.onSend('', attachment, widget.replyTo);
    }
  }

  Future<void> _shareLocation() async {
    final ({PlaceLocation? location, String? error}) result =
        await ref.read(locationServiceProvider).currentLocation();
    if (!mounted) return;
    if (result.location == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(result.error ?? 'Location unavailable.')),
        );
      return;
    }
    widget.onSend('', result.location!.toAttachment(), widget.replyTo);
  }

  Future<void> _shareContact() async {
    if (!mounted) return;
    widget.onSend('__pick_contact__', null, null);
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.divider, width: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.replyTo != null)
            _ReplyBanner(reply: widget.replyTo!, onCancel: widget.onCancelReply),
          if (widget.editing != null) _EditBanner(onCancel: widget.onCancelEdit),
          if (_recordingError != null) _ErrorBanner(message: _recordingError!),

          if (_isRecording)
            _RecordingBar(
              duration: _recordedDuration,
              onCancel: () => _finishRecording(keep: false),
              onSend: () => _finishRecording(keep: true),
            )
          else
            _InputRow(
              controller: _controller,
              focusNode: _focusNode,
              hasText: _hasText,
              showEmoji: _showEmoji,
              onToggleEmoji: () {
                setState(() => _showEmoji = !_showEmoji);
                if (_showEmoji) {
                  _focusNode.unfocus();
                } else {
                  _focusNode.requestFocus();
                }
              },
              onAttach: _openAttachments,
              onSend: _send,
              onStartRecording: _startRecording,
              enterKeySends: widget.enterKeySends,
              hint: widget.editing != null
                  ? 'Edit message'
                  : 'Message',
            ),

          if (_showEmoji && !_isRecording)
            EmojiPicker(
              recent: _recentEmoji,
              onBackspace: () {
                final String text = _controller.text;
                if (text.isEmpty) return;
                _controller.text =
                    text.substring(0, text.characters.length - 1);
                _controller.selection = TextSelection.collapsed(
                  offset: _controller.text.length,
                );
              },
              onSelected: (String emoji) {
                final TextSelection selection = _controller.selection;
                final int start = selection.start < 0
                    ? _controller.text.length
                    : selection.start;
                final int end = selection.end < 0
                    ? _controller.text.length
                    : selection.end;
                _controller.text = _controller.text.replaceRange(
                  start,
                  end,
                  emoji,
                );
                _controller.selection = TextSelection.collapsed(
                  offset: start + emoji.length,
                );
                setState(() {
                  _recentEmoji
                    ..remove(emoji)
                    ..insert(0, emoji);
                  if (_recentEmoji.length > 24) _recentEmoji.removeLast();
                });
              },
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ rows

class _InputRow extends StatefulWidget {
  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.showEmoji,
    required this.onToggleEmoji,
    required this.onAttach,
    required this.onSend,
    required this.onStartRecording,
    required this.enterKeySends,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final bool showEmoji;
  final VoidCallback onToggleEmoji;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onStartRecording;
  final bool enterKeySends;
  final String hint;

  @override
  State<_InputRow> createState() => _InputRowState();
}

class _InputRowState extends State<_InputRow> {
  bool _longPressActive = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          // Emoji toggle
          _CircleButton(
            icon: widget.showEmoji
                ? Icons.keyboard_alt_outlined
                : Icons.emoji_emotions_outlined,
            onTap: widget.onToggleEmoji,
            tooltip: context.l10n.emoji,
          ),

          const SizedBox(width: AppSpacing.xs),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 132),
              decoration: BoxDecoration(
                color: c.inputFill,
                borderRadius: AppRadius.rPill,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: c.accent,
                      style: context.t.bodyLarge,
                      textInputAction: widget.enterKeySends
                          ? TextInputAction.send
                          : TextInputAction.newline,
                      onSubmitted: (_) {
                        if (widget.enterKeySends) widget.onSend();
                      },
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md + 1,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      right: AppSpacing.xs,
                      bottom: AppSpacing.xs,
                    ),
                    child: _CircleButton(
                      icon: Icons.attach_file_rounded,
                      onTap: widget.onAttach,
                      tooltip: context.l10n.attach,
                      size: 34,
                      iconSize: 19,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.xs),

          // Send or mic
          if (widget.hasText)
            _SendButton(onPressed: widget.onSend)
          else
            GestureDetector(
              onLongPressStart: (_) {
                _longPressActive = true;
                widget.onStartRecording();
              },
              onLongPressEnd: (_) {
                // The recording bar takes over, so nothing else is needed.
                _longPressActive = false;
              },
              child: _CircleButton(
                icon: _longPressActive
                    ? Icons.mic_rounded
                    : Icons.mic_none_rounded,
                onTap: widget.onStartRecording,
                tooltip: context.l10n.holdToRecordAVoice,
                size: 42,
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
    this.iconSize = AppIconSizes.md,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rPill,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: context.c.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Semantics(
      button: true,
      label: context.l10n.sendMessage,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.rPill,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: c.accent,
            shape: BoxShape.circle,
            boxShadow: AppShadows.soft,
          ),
          child: const Icon(
            Icons.send_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- banners

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.reply, this.onCancel});

  final ReplyPreview reply;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: c.divider, width: 0.6),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(width: 3, height: 34, color: c.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  reply.senderName,
                  style: context.t.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.accent,
                  ),
                ),
                Text(
                  reply.preview,
                  style: context.t.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: context.l10n.cancelReply,
              color: c.textSecondary,
              splashRadius: 18,
            ),
        ],
      ),
    );
  }
}

class _EditBanner extends StatelessWidget {
  const _EditBanner({this.onCancel});

  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: c.accent.withValues(alpha: 0.10),
      child: Row(
        children: <Widget>[
          Icon(Icons.edit_rounded, size: 16, color: c.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.l10n.editingMessage,
              style: context.t.bodySmall?.copyWith(
                color: c.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onCancel != null)
            InkWell(
              onTap: onCancel,
              child: Icon(Icons.close_rounded, size: 17, color: c.accent),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.danger.withValues(alpha: 0.12),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: context.c.onDanger,
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.t.bodySmall?.copyWith(color: context.c.onDanger),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.duration,
    required this.onCancel,
    required this.onSend,
  });

  final Duration duration;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          InkWell(
            onTap: onCancel,
            borderRadius: AppRadius.rPill,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: c.inputFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: context.c.onDanger,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const _RecordingDot(),
          const SizedBox(width: AppSpacing.sm),
          Text(
            DateFormatter.duration(duration),
            style: context.t.bodyLarge?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: _LiveWaveform()),
          const SizedBox(width: AppSpacing.md),
          InkWell(
            onTap: onSend,
            borderRadius: AppRadius.rPill,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: context.c.onDanger,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _LiveWaveform extends StatefulWidget {
  const _LiveWaveform();

  @override
  State<_LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<_LiveWaveform> {
  final List<double> _levels = List<double>.filled(28, 0.15);

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return SizedBox(
      height: 26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List<Widget>.generate(_levels.length, (int index) {
          final double level = _levels[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.2),
            child: AnimatedContainer(
              duration: AppDurations.fast,
              width: 2.6,
              height: 4 + level * 20,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.4 + level * 0.6),
                borderRadius: AppRadius.rPill,
              ),
            ),
          );
        }),
      ),
    );
  }
}
