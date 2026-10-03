import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/message.dart';
import '../../../../core/models/message_parts.dart';
import 'emoji_data.dart';
import '../../../../core/utils/l10n.dart';

/// Actions offered when a message is long-pressed.
enum MessageAction {
  reply,
  copy,
  forward,
  star,
  pin,
  edit,
  info,
  deleteForMe,
  deleteForEveryone,
  select,
  save,
  share,
}

/// The reaction bar shown above the action sheet.
///
/// Returns either a reaction emoji (String), a [MessageAction], or null.
///
/// [canDeleteForEveryone] is the caller's answer to
/// `message.canDeleteForEveryone` — the author's own message, not already
/// deleted, and inside [Message.deleteForEveryoneWindow]. Passing it in keeps
/// this widget free of clock reads; the repository re-checks the same rule
/// before writing, so hiding the row is a courtesy and not the enforcement.
Future<Object?> showMessageActionSheet(
  BuildContext context, {
  required Message message,
  required bool isGroup,
  required bool canDeleteForEveryone,
}) {
  return showModalBottomSheet<Object>(
    context: context,
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) {
      final AppColorScheme c = sheetContext.c;

      void pick(Object value) => Navigator.pop(sheetContext, value);

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: AppRadius.rPill,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // -------------------------------------------------- reactions
              if (!message.isDeleted)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: quickReactions.map((String emoji) {
                      final bool mine = message.reactions
                          .any((r) => r.emoji == emoji && r.senderId == 'self');
                      return InkWell(
                        onTap: () => pick(emoji),
                        borderRadius: AppRadius.rPill,
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: mine
                                ? c.accent.withValues(alpha: 0.18)
                                : Colors.transparent,
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              if (!message.isDeleted) const Divider(height: 20),

              // --------------------------------------------------- actions
              if (!message.isDeleted)
                _ActionRow(
                  icon: Icons.reply_rounded,
                  label: context.l10n.reply,
                  onTap: () => pick(MessageAction.reply),
                ),
              if (!message.isDeleted && message.type == MessageType.text)
                _ActionRow(
                  icon: Icons.copy_rounded,
                  label: context.l10n.copy,
                  onTap: () => pick(MessageAction.copy),
                ),
              if (!message.isDeleted)
                _ActionRow(
                  icon: Icons.forward_rounded,
                  label: context.l10n.forward,
                  onTap: () => pick(MessageAction.forward),
                ),
              if (!message.isDeleted)
                _ActionRow(
                  icon: message.isStarred
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  label: message.isStarred ? 'Unstar' : 'Star',
                  onTap: () => pick(MessageAction.star),
                ),
              if (!message.isDeleted)
                _ActionRow(
                  icon: message.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  label: message.isPinned ? 'Unpin' : 'Pin',
                  onTap: () => pick(MessageAction.pin),
                ),
              if (message.isOutgoing &&
                  !message.isDeleted &&
                  message.type == MessageType.text)
                _ActionRow(
                  icon: Icons.edit_rounded,
                  label: context.l10n.edit,
                  onTap: () => pick(MessageAction.edit),
                ),
              if (!message.isDeleted)
                _ActionRow(
                  icon: Icons.checklist_rounded,
                  label: context.l10n.select,
                  onTap: () => pick(MessageAction.select),
                ),
              _ActionRow(
                icon: Icons.info_outline_rounded,
                label: context.l10n.messageInfo,
                onTap: () => pick(MessageAction.info),
              ),

              const Divider(height: 20),

              _ActionRow(
                icon: Icons.delete_outline_rounded,
                label: context.l10n.deleteForMe,
                color: context.c.onDanger,
                onTap: () => pick(MessageAction.deleteForMe),
              ),
              if (message.isOutgoing && canDeleteForEveryone && !message.isDeleted)
                _ActionRow(
                  icon: Icons.delete_forever_rounded,
                  label: context.l10n.deleteForEveryone,
                  color: context.c.onDanger,
                  onTap: () => pick(MessageAction.deleteForEveryone),
                ),

              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      );
    },
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: AppIconSizes.md, color: color ?? context.c.textPrimary),
            const SizedBox(width: AppSpacing.lg),
            Text(
              label,
              style: context.t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation used before "delete for everyone".
///
/// The wording matters twice over. It used to claim the delete needed "a server
/// connection" long after `MessageRepository.deleteForEveryone` was implemented,
/// so the dialog was discouraging a feature that already worked. It now states
/// the real, local-first behaviour, the real limitation, **and** the one-hour
/// window — a user who is about to lose the option needs to know why it is
/// there now and will be gone later.
Future<bool> confirmDeleteForEveryone(BuildContext context) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(context.l10n.deleteForEveryone2),
      content: Text(
        context.l10n.theMessageIsRemovedFrom2,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            context.l10n.cancel,
            style: TextStyle(color: context.c.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            context.l10n.delete,
            style: TextStyle(
              color: context.c.onDanger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
