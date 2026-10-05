import 'package:flutter/foundation.dart';

/// A prefixed, timestamped facade over `debugPrint` for the auth and delete
/// paths.
///
/// Why it exists: the signup failures that prompted it happen on a real phone
/// with no ADB attached, where `debugPrint` output is the only evidence
/// available and an unstructured log is hard to read. Every line is stamped and
/// carries a severity marker, so `adb logcat | grep '\[+\]'` is a filter that
/// actually works — and the same markers are what a Crashlytics non-fatal
/// breadcrumb would be built from.
///
/// ### It no longer buffers anything
///
/// It used to keep a 1000-line ring buffer in memory and expose `getLogs()` for
/// the developer log screen. Both were removed on 2026-10-06, together with that
/// screen and the "Copy Logs" action in the signup-failure dialog. What is left
/// is the part that has value in a shipped build: the formatted line, echoed to
/// the platform log.
///
/// Nothing here is persisted and nothing sensitive is ever passed to it — the
/// phone flow's PIN goes straight to the auth SDK and is never logged.
class InAppLogger {
  InAppLogger._();

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
    // Echo to the platform log — the only sink there is now.
    debugPrint(line);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
