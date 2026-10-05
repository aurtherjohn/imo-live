import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/services/in_app_logger.dart';

/// Shows a signup failure with the last few log lines attached.
///
/// Why a dialog and not the inline `_error` text these screens already have:
/// the inline text says what went wrong, and on a phone with no ADB that is the
/// *only* thing the user can tell you. A screenshot of "Signup failed" is not
/// diagnosable; a screenshot with the auth code and the last five log lines is.
///
/// The logs are shown to the user on purpose. They are their own device's
/// output, they contain no password material (the PIN goes straight to the auth
/// SDK and is never logged), and the alternative is asking them to find a
/// developer screen while already stuck.
Future<void> showSignupError(
  BuildContext context,
  String message,
) async {
  final AppColorScheme c = context.c;
  // Last five, oldest-first within the slice, so they read as a sequence.
  final List<LogEntry> entries = InAppLogger.getLogs();
  final List<String> recent = entries
      .skip(entries.length > 5 ? entries.length - 5 : 0)
      .map((LogEntry e) => e.line)
      .toList(growable: false);

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Signup Failed'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                message,
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Recent logs:',
                style: Theme.of(dialogContext).textTheme.labelLarge?.copyWith(
                      color: c.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: AppRadius.rSm,
                ),
                child: SelectableText(
                  recent.isEmpty ? '(no logs captured)' : recent.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              final List<LogEntry> all = InAppLogger.getLogs();
              await Clipboard.setData(
                ClipboardData(
                  text: all.isEmpty
                      ? message
                      : all.map((LogEntry e) => e.line).join('\n'),
                ),
              );
            },
            child: const Text('Copy Logs'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
