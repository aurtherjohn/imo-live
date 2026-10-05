import 'package:flutter/foundation.dart';

/// An in-memory ring buffer of log lines that the user can read on the device.
///
/// Why this exists: the signup failures that prompted it happen on a real phone
/// with no ADB attached. `debugPrint` goes nowhere the user can see, and
/// `CrashLogger` only keeps what throws. A signup that *silently* walks the user
/// back to the login screen throws nothing at all — so there was no evidence to
/// work from, only a symptom.
///
/// This keeps the last [maxLines] lines in memory, stamped with the wall clock,
/// mirroring everything to `debugPrint` so a tethered run is still readable.
/// The developer-logs screen renders it and offers Copy All.
///
/// Deliberately **not** persisted: it is diagnostic scaffolding, and a phone
/// account's derived address and a uid are the only sensitive things in it. If
/// it ever needs to survive a restart, write it to a file the way
/// `CrashLogger` does — do not put it in Hive or Firestore.
class InAppLogger {
  InAppLogger._();

  /// Ring-buffer ceiling. The buffer is trimmed from the front, so the oldest
  /// lines fall off first and the newest survive — which is what a "what just
  /// happened" screen needs.
  static const int maxLines = 1000;

  static final List<LogEntry> _logs = <LogEntry>[];

  /// Lines recorded so far, newest last.
  static List<LogEntry> getLogs() => List<LogEntry>.unmodifiable(_logs);

  /// How many lines are held. Cheap enough to poll for a "N lines" subtitle.
  static int get count => _logs.length;

  static void clear() {
    _logs.clear();
    debugPrint('[log] cleared');
  }

  static void log(String message) => _append('   ', message);

  static void info(String message) => _append('[i]', message);

  static void success(String message) => _append('[+]', message);

  static void warn(String message) => _append('[!]', message);

  /// Records a failure. The stack trace is truncated to the first few frames —
  /// enough to locate the throw site, not enough to bury the message.
  static void error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final StringBuffer buffer = StringBuffer(message);
    if (error != null) buffer.write(' :: $error');
    if (stackTrace != null) {
      final List<String> frames = stackTrace
          .toString()
          .split('\n')
          .where((String line) => line.trim().isNotEmpty)
          .take(5)
          .toList(growable: false);
      if (frames.isNotEmpty) {
        buffer
          ..write('\n')
          ..write(frames.join('\n'));
      }
    }
    _append('!! ', buffer.toString());
  }

  static void _append(String marker, String message) {
    final DateTime now = DateTime.now();
    final String line =
        '[${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}] '
        '$marker $message';
    _logs.add(LogEntry(timestamp: now, line: line));
    if (_logs.length > maxLines) {
      _logs.removeRange(0, _logs.length - maxLines);
    }
    // Echo to the platform log so a tethered device shows the same thing.
    debugPrint(line);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// One buffered line. The timestamp is kept separately from the formatted
/// string so the viewer can style the time without re-parsing text.
class LogEntry {
  const LogEntry({required this.timestamp, required this.line});

  final DateTime timestamp;
  final String line;

  @override
  String toString() => line;
}
