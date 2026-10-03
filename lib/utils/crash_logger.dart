import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Lightweight crash recorder — **temporary debugging aid**.
///
/// It exists so a crash on a real device can be diagnosed without `adb
/// logcat`. Errors that escape the guarded zone, the Flutter framework or the
/// platform dispatcher are appended to a plain-text file in the app's documents
/// directory, which [getCrashLogs] reads back.
///
/// Two rules make it safe to call from anywhere:
/// - **It never throws.** Every filesystem call is guarded; if logging itself
///   fails it degrades to a `debugPrint` and nothing else happens.
/// - **It never blocks.** Writes are fire-and-forget and bounded by a timeout,
///   so a hung platform channel cannot stall the caller or the first frame.
class CrashLogger {
  CrashLogger._();

  static const String _fileName = 'crash_logs.txt';

  /// Caps the file so a crash loop cannot grow it without bound. Once the file
  /// passes this many bytes the oldest half is dropped.
  static const int _maxBytes = 128 * 1024;

  /// Upper bound on any single platform/IO call. `path_provider` can hang in
  /// tests and on misconfigured devices; logging must not wait forever.
  static const Duration _ioTimeout = Duration(seconds: 3);

  /// Runs [body] inside a zone whose uncaught errors are recorded.
  ///
  /// Drop-in replacement for a bare `runZonedGuarded` call in `main()`.
  static void runGuarded(void Function() body) {
    runZonedGuarded<void>(
      body,
      (Object error, StackTrace stack) {
        unawaited(record(error, stack, source: 'zone'));
      },
    );
  }

  /// Appends one entry. Never throws — a failure to persist is swallowed after
  /// being echoed to `debugPrint`.
  static Future<void> record(
    Object error,
    StackTrace? stack, {
    String source = 'unknown',
    String? context,
  }) async {
    debugPrint('🧨 CrashLogger[$source]: $error');

    try {
      final File? file = await _logFile();
      if (file == null) return;
      await file.writeAsString(
        _format(error, stack, source, context),
        mode: FileMode.append,
        flush: true,
      );
      await _trimIfNeeded(file);
    } on Object catch (writeError) {
      debugPrint('CrashLogger: could not persist entry: $writeError');
    }
  }

  /// Reads everything recorded so far. Returns an empty string when there is
  /// nothing to read (including when storage is unavailable).
  static Future<String> getCrashLogs() async {
    try {
      final File? file = await _logFile();
      if (file == null || !await file.exists()) return '';
      return await file.readAsString();
    } on Object catch (error) {
      debugPrint('CrashLogger: could not read logs: $error');
      return '';
    }
  }

  /// Absolute path of the log file, or `null` when storage is unavailable.
  /// Handy for a "share log" button in the temporary viewer.
  static Future<String?> getCrashLogPath() async {
    try {
      final File? file = await _logFile();
      return file?.path;
    } on Object {
      return null;
    }
  }

  /// Deletes the log. Returns `true` when the file is gone afterwards.
  static Future<bool> clearCrashLogs() async {
    try {
      final File? file = await _logFile();
      if (file == null || !await file.exists()) return true;
      await file.delete();
      return true;
    } on Object catch (error) {
      debugPrint('CrashLogger: could not clear logs: $error');
      return false;
    }
  }

  // -------------------------------------------------------------- internals

  static Future<File?> _logFile() async {
    final Directory? directory = await _documentsDirectory();
    if (directory == null) return null;
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<Directory?> _documentsDirectory() async {
    try {
      return await getApplicationDocumentsDirectory().timeout(_ioTimeout);
    } on Object catch (error) {
      debugPrint('CrashLogger: documents directory unavailable: $error');
      return null;
    }
  }

  static String _format(
    Object error,
    StackTrace? stack,
    String source,
    String? context,
  ) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('===== ${DateTime.now().toIso8601String()} [$source] =====');
    if (context != null && context.isNotEmpty) {
      buffer.writeln('at: $context');
    }
    buffer.writeln(error.toString());
    if (stack != null) {
      buffer.writeln(stack.toString());
    }
    buffer.writeln();
    return buffer.toString();
  }

  static Future<void> _trimIfNeeded(File file) async {
    try {
      if (await file.length() <= _maxBytes) return;
      final String content = await file.readAsString();
      final int half = content.length ~/ 2;
      // Cut on an entry boundary so a stack trace is never split mid-frame.
      final int cut = content.indexOf('\n=====', half);
      final String kept =
          cut == -1 ? content.substring(half) : content.substring(cut);
      await file.writeAsString('(older entries trimmed)\n$kept', flush: true);
    } on Object catch (error) {
      debugPrint('CrashLogger: trim failed: $error');
    }
  }
}
