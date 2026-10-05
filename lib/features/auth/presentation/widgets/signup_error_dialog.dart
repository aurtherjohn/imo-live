import 'package:flutter/material.dart';

import '../../../../core/utils/l10n.dart';

/// Shows a signup failure.
///
/// ### Why this is a plain dialog now
///
/// It used to attach the last five lines of the in-app log buffer, with a
/// "Copy Logs" action. That was the right trade while the signup failures were
/// being chased — they happen on a phone with no ADB attached, and a screenshot
/// of "Signup failed" is not diagnosable. It is the wrong thing to ship: a
/// published build must not put raw internal log lines in front of a user, and
/// nothing is lost by removing them, because `InAppLogger` mirrors every line
/// to `debugPrint` — which is exactly what a tethered `adb logcat` reads.
Future<void> showSignupError(
  BuildContext context,
  String message,
) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.somethingWentWrong),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.l10n.ok),
        ),
      ],
    ),
  );
}
