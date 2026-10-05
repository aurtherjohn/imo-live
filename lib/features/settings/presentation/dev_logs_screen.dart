import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/services/in_app_logger.dart';
import '../../../core/widgets/common_widgets.dart';

/// Renders the [InAppLogger] ring buffer on the device.
///
/// This screen exists for exactly one situation: a bug that happens on a real
/// phone with no ADB attached. Everything else in the app's diagnostics
/// (`CrashLogger`) only records what *throws*; a signup that silently returns
/// the user to the login screen throws nothing, so there was no evidence to
/// work from. This is that evidence.
///
/// Deliberately plain — monospace, newest first, no filtering. It is a debugging
/// tool, and the fastest thing to read is the raw text in the order it
/// happened (reversed, because the useful part is always at the end).
class DevLogsScreen extends StatefulWidget {
  const DevLogsScreen({super.key});

  @override
  State<DevLogsScreen> createState() => _DevLogsScreenState();
}

class _DevLogsScreenState extends State<DevLogsScreen> {
  /// Drives the rebuild. Polling rather than a `ValueNotifier` on the logger:
  /// [InAppLogger] is a static utility with no lifecycle, and a periodic
  /// subscription that the screen owns is the whole cost of not giving it one.
  /// 2 s is fast enough to watch a signup happen and slow enough to be free.
  StreamSubscription<void>? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream<void>.periodic(const Duration(seconds: 2)).listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _copyAll() async {
    final List<LogEntry> entries = InAppLogger.getLogs();
    final String text = entries.isEmpty
        ? '(no logs)'
        : entries.map((LogEntry e) => e.line).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast(
      entries.isEmpty
          ? 'Nothing to copy.'
          : 'Copied ${entries.length} lines.',
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    // Newest first: the line that explains the failure is the one written last.
    final List<LogEntry> logs = InAppLogger.getLogs().reversed.toList(
          growable: false,
        );

    return Scaffold(
      appBar: AppTopBar(
        title: 'Developer Logs',
        subtitle: logs.isEmpty ? 'empty' : '${logs.length} lines',
        showBack: true,
        actions: <Widget>[
          IconButton(
            onPressed: _copyAll,
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            onPressed: () {
              InAppLogger.clear();
              setState(() {});
              _toast('Logs cleared.');
            },
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.article_outlined,
                    size: AppIconSizes.xxl,
                    color: c.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No logs yet',
                    style: context.t.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Logs appear here as the app runs.',
                    style: context.t.bodySmall?.copyWith(
                      color: c.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xxxl,
              ),
              itemCount: logs.length,
              itemBuilder: (BuildContext context, int index) {
                final LogEntry entry = logs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: SelectableText(
                    entry.line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                      // Colour by severity so the eye lands on `!!` first, and a
                      // successful signup is visibly different from a failed one.
                      color: _colorFor(entry.line, c),
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// Cheap severity read off the marker the logger wrote. The marker is a fixed
  /// prefix, so a `startsWith` on the text after the timestamp is exact rather
  /// than a guess.
  Color _colorFor(String line, AppColorScheme c) {
    if (line.contains(' !! ')) return c.onDanger;
    if (line.contains(' [+] ')) return c.onSuccess;
    if (line.contains(' [!] ')) return c.onWarning;
    if (line.contains(' [i] ')) return c.onInfo;
    return c.textSecondary;
  }
}
