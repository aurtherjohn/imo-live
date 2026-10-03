import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/chat.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../chats/presentation/providers.dart';
import '../../../../core/utils/l10n.dart';

/// Disappearing-messages picker, shared by Chat Info and Settings.
Future<void> showDisappearingMessagesSheet(
  BuildContext context,
  WidgetRef ref,
  Chat chat,
) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) {
      final List<({String label, int value})> options =
          <({String label, int value})>[
        (label: sheetContext.l10n.off, value: 0),
        (label: sheetContext.l10n.s24Hours, value: 86400),
        (label: sheetContext.l10n.s7Days, value: 604800),
        (label: sheetContext.l10n.s90Days, value: 7776000),
      ];

      return SafeArea(
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
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.disappearingMessages,
                    style: context.t.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.newMessagesInThisChat2,
                    style: context.t.bodySmall,
                  ),
                ],
              ),
            ),
            RadioGroup<int>(
              groupValue: chat.disappearingSeconds,
              onChanged: (int? value) async {
                Navigator.pop(sheetContext);
                final Chat? current =
                    await ref.read(chatRepositoryProvider).findById(chat.id);
                if (current == null) return;
                await ref
                    .read(chatsProvider.notifier)
                    .save(current.copyWith(disappearingSeconds: value ?? 0));
                if (context.mounted) {
                  iToast(
                    context,
                    value == 0
                        ? 'Disappearing messages turned off'
                        : 'Messages will disappear after the selected time',
                  );
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: options
                    .map(
                      (({String label, int value}) option) => RadioListTile<int>(
                        value: option.value,
                        title: Text(option.label, style: context.t.bodyLarge),
                        activeColor: context.c.accent,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      );
    },
  );
}
