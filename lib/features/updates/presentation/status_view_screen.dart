import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/models/status.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../../core/utils/l10n.dart';

/// Full-screen status viewer with auto-advancing progress bars.
class StatusViewScreen extends ConsumerStatefulWidget {
  const StatusViewScreen({
    super.key,
    required this.statusIds,
    this.isMine = false,
  });

  /// Ordered ids of the statuses to play.
  final List<String> statusIds;

  /// True when the viewer was opened from "My status".
  final bool isMine;

  @override
  ConsumerState<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends ConsumerState<StatusViewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  int _index = 0;
  bool _paused = false;
  final Set<String> _marked = <String>{};

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this);
    _progress.addStatusListener(_onProgressStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_paused) _next();
  }

  /// Resolve the current playlist from the live provider so deletions apply.
  List<Status> _playlist() {
    final List<Status> all = ref.read(statusesProvider).orEmpty;
    final List<Status> ordered = <Status>[];
    for (final String id in widget.statusIds) {
      final Status? match =
          all.where((Status s) => s.id == id).firstOrNull;
      if (match != null) ordered.add(match);
    }
    return ordered;
  }

  void _play() {
    final List<Status> list = _playlist();
    if (list.isEmpty) {
      _exit();
      return;
    }
    _index = _index.clamp(0, list.length - 1);
    final Status current = list[_index];

    if (!_marked.contains(current.id)) {
      _marked.add(current.id);
      if (!current.isOwn) {
        unawaited(
          ref
              .read(statusesProvider.notifier)
              .markViewed(current.id, 'self'),
        );
      }
    }

    _progress
      ..duration = Duration(
        milliseconds: current.durationMs <= 0 ? 5000 : current.durationMs,
      )
      ..value = 0;
    if (!_paused) _progress.forward();
  }

  void _next() {
    final List<Status> list = _playlist();
    if (_index >= list.length - 1) {
      _exit();
      return;
    }
    setState(() => _index++);
    _play();
  }

  void _previous() {
    if (_progress.value > 0.25 && _index >= 0) {
      _progress
        ..value = 0
        ..forward();
      return;
    }
    if (_index == 0) {
      _play();
      return;
    }
    setState(() => _index--);
    _play();
  }

  void _exit() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/updates');
    }
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _progress.stop();
      } else {
        _progress
          ..value = 0
          ..forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the underlying statuses change (e.g. deletion).
    ref.watch(statusesProvider);
    final List<Status> list = _playlist();

    if (list.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final int safeIndex = _index.clamp(0, list.length - 1);
    final Status current = list[safeIndex];
    final bool isText =
        current.type == StatusType.text && current.mediaPath == null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (TapUpDetails details) {
          final double w = MediaQuery.sizeOf(context).width;
          if (details.globalPosition.dx < w * 0.35) {
            _previous();
          } else {
            _next();
          }
        },
        onLongPressStart: (_) => _togglePause(),
        onLongPressEnd: (_) {
          if (_paused) _togglePause();
        },
        onVerticalDragEnd: (DragEndDetails d) {
          final double v = d.primaryVelocity ?? 0;
          if (v > 250) _exit();
          if (v < -250) _openReplySheet(current);
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _buildBackground(current, isText),
            if (!isText && current.mediaPath != null)
              _buildMedia(current),
            SafeArea(
              child: Column(
                children: <Widget>[
                  _ProgressBars(
                    count: list.length,
                    index: safeIndex,
                    progress: _progress,
                  ),
                  _buildHeader(current),
                  Expanded(
                    child: Align(
                      alignment: isText
                          ? Alignment.center
                          : Alignment.bottomCenter,
                      child: _buildOverlayText(current, isText),
                    ),
                  ),
                  _buildFooter(current),
                ],
              ),
            ),
            if (_paused)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: AppRadius.rLg,
                  ),
                  child: const Icon(
                    Icons.pause_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(Status status, bool isText) {
    if (!isText) return const SizedBox.shrink();
    final List<int> colors = status.backgroundColors.isEmpty
        ? const <int>[0xFF1F1F24, 0xFF2A1420]
        : status.backgroundColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color(colors.first),
            Color(colors.length > 1 ? colors[1] : colors.first),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildMedia(Status status) {
    final String path = status.mediaPath!;
    final bool isVideo = status.type == StatusType.video;
    if (isVideo) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.play_circle_outline_rounded,
              size: 72,
              color: Colors.white70,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.videoPlaybackNeedsAVideo(path),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.broken_image_outlined, size: 56, color: Colors.white38),
            SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.thisMediaFileIsNo,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayText(Status status, bool isText) {
    if (isText) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Text(
          status.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(status.textColor),
            fontSize: status.fontSize,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      );
    }
    if (status.caption.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: AppRadius.rMd,
      ),
      child: Text(
        status.caption,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
    );
  }

  Widget _buildHeader(Status status) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          IAvatar(
            name: status.authorName,
            size: AppSizes.avatarSm,
            ringColor: Colors.white24,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  status.isOwn ? 'You' : status.authorName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  status.createdAt == null
                      ? status.timeAgo
                      : DateFormatter.time(status.createdAt!),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          if (status.isOwn)
            IconButton(
              tooltip: context.l10n.deleteUpdate2,
              onPressed: () => _deleteStatus(status),
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white),
            ),
          IconButton(
            tooltip: context.l10n.close,
            onPressed: _exit,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(Status status) {
    if (!status.isOwn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                onTap: () => _openReplySheet(status),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.rPill,
                    border: Border.all(color: Colors.white38),
                  ),
                  child: Text(
                    context.l10n.reply2,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            IconButton.filled(
              tooltip: context.l10n.react,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _openReplySheet(status),
              icon: const Icon(Icons.favorite_border_rounded),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.visibility_outlined,
              size: AppIconSizes.sm, color: Colors.white70),
          const SizedBox(width: AppSpacing.sm),
          // Both labels must be able to shrink: on a narrow screen or at a
          // large text scale "Expires in 23 hours" runs out of room and the
          // Row overflows.
          Flexible(
            child: Text(
              status.viewerIds.isEmpty
                  ? 'No views yet'
                  : '${status.viewerIds.length} view'
                      '${status.viewerIds.length == 1 ? '' : 's'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              context.l10n.expiresIn(DateFormatter.remaining(status.remaining)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteStatus(Status status) {
    unawaited(
      showConfirmDialog(
        context,
        title: context.l10n.deleteUpdate,
        message: context.l10n.thisUpdateIsRemovedFor,
        confirmLabel: context.l10n.delete,
        destructive: true,
      ).then((bool ok) async {
        if (!ok) return;
        await ref.read(statusesProvider.notifier).remove(status.id);
        if (!mounted) return;
        final List<Status> list = _playlist();
        if (list.isEmpty) {
          _exit();
        } else {
          setState(() => _index = 0);
          _play();
        }
      }),
    );
  }

  void _openReplySheet(Status status) {
    if (status.isOwn) return;
    _paused = true;
    _progress.stop();
    final TextEditingController controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    for (final String emoji in const <String>[
                      '❤️',
                      '😂',
                      '😮',
                      '😢',
                      '🙏',
                      '👍',
                    ])
                      Expanded(
                        child: InkWell(
                          borderRadius: AppRadius.rPill,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _sentReply(emoji);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                            child: Text(
                              emoji,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          hintText: context.l10n.sendAMessage,
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.send,
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _sentReply(controller.text);
                      },
                      icon: const Icon(Icons.send_rounded,
                          color: Color(0xFFFF2D55)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      controller.dispose();
      if (!mounted) return;
      _paused = false;
      _progress
        ..value = 0
        ..forward();
    });
  }

  void _sentReply(String text) {
    if (text.trim().isEmpty) return;
    iToast(
      context,
      context.l10n.statusRepliesNeedAChat,
    );
  }
}

// ---------------------------------------------------------------------------

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({
    required this.count,
    required this.index,
    required this.progress,
  });

  final int count;
  final int index;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < count; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedBuilder(
                  animation: progress,
                  builder: (BuildContext context, Widget? child) {
                    final double value = i < index
                        ? 1
                        : i == index
                            ? progress.value
                            : 0;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps the system UI available while a status is playing.
class StatusSystemUi extends StatefulWidget {
  const StatusSystemUi({super.key, required this.child});

  final Widget child;

  @override
  State<StatusSystemUi> createState() => _StatusSystemUiState();
}

class _StatusSystemUiState extends State<StatusSystemUi> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
