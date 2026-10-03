import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/l10n.dart';

/// A confirmation dialog used before destructive actions.
///
/// Returns `true` when the user confirms, `false` (or null) otherwise.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            cancelLabel,
            style: TextStyle(color: context.c.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmLabel,
            style: TextStyle(
              color: destructive ? destructive ? context.c.onDanger : context.c.accent : context.c.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// A single-line text prompt dialog.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String? initialValue,
  String hint = '',
  String confirmLabel = 'Save',
  int maxLength = 120,
  int maxLines = 1,
}) async {
  final TextEditingController controller =
      TextEditingController(text: initialValue ?? '');
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint, counterText: ''),
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.l10n.cancel,
            style: TextStyle(color: context.c.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(
            confirmLabel,
            style: TextStyle(
              color: context.c.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// A dialog that asks the user to pick one of several labelled options.
Future<T?> showOptionDialog<T>(
  BuildContext context, {
  required String title,
  required List<({String label, T value, String? subtitle})> options,
  String? message,
}) {
  return showDialog<T>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (message != null) ...<Widget>[
            Text(message),
            const SizedBox(height: AppSpacing.md),
          ],
          ...options.map(
            (({String label, T value, String? subtitle}) option) => InkWell(
              onTap: () => Navigator.pop(context, option.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      option.label,
                      style: context.t.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (option.subtitle != null)
                      Text(option.subtitle!, style: context.t.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.l10n.cancel,
            style: TextStyle(color: context.c.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// A simple informational dialog.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String closeLabel = 'Got it',
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            closeLabel,
            style: TextStyle(
              color: context.c.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Placeholder dialog for features that genuinely need a backend.
///
/// Deliberately explicit: the app never pretends a server-side feature works.
Future<void> showBackendRequiredDialog(
  BuildContext context, {
  required String feature,
  String? detail,
}) {
  return showInfoDialog(
    context,
    title: context.l10n.featureNotAvailableYet(feature),
    message: detail ??
        'This part of Imo LIVE is not built yet. The interface and local '
            'behaviour are complete and the integration point is already wired '
            'up, so enabling it is additive — no screen has to change.',
  );
}

/// Bottom sheet with a title and a list of rows.
Future<void> showActionSheet(
  BuildContext context, {
  required String title,
  required List<({IconData icon, String label, VoidCallback onTap, Color? color})>
      actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.c.divider,
              borderRadius: AppRadius.rPill,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: context.t.titleMedium),
            ),
          ),
          ...actions.map(
            (({IconData icon, String label, VoidCallback onTap, Color? color})
                    action) =>
                ListTile(
              leading: Icon(action.icon, size: AppIconSizes.md, color: action.color),
              title: Text(
                action.label,
                style: context.t.bodyLarge?.copyWith(color: action.color),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                action.onTap();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}
