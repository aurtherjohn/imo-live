import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/gift.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../chats/presentation/providers.dart';
import '../providers.dart';
import '../../../../core/utils/l10n.dart';

/// What was sent, once a gift has been paid for.
///
/// Carries the [gift] as well as the result so the caller can post the matching
/// message without having to guess which catalogue entry was chosen — the sheet
/// is the only place that selection exists.
@immutable
class GiftReceipt {
  const GiftReceipt({required this.gift, required this.result});

  final Gift gift;
  final GiftResult result;
}

/// Opens the gift picker for [toUid].
///
/// Returns a [GiftReceipt] when a gift was sent, or null when the sheet was
/// dismissed. A *failed* send also returns a receipt, with `result.success`
/// false, so the caller can tell "they gave up" apart from "the payment was
/// refused" without the sheet having to throw.
///
/// ### Why it is a sheet and not a screen
///
/// Sending a gift is a detour from a conversation, not a destination. A sheet
/// keeps the chat visible behind it, so the user never loses their place — and
/// it can be dismissed with a swipe, which is the right weight for "actually,
/// never mind".
Future<GiftReceipt?> showGiftSheet(
  BuildContext context, {
  required String toUid,
  required String toName,
  String chatId = '',
  String channelId = '',
}) {
  return showModalBottomSheet<GiftReceipt>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _GiftSheet(
      toUid: toUid,
      toName: toName,
      chatId: chatId,
      channelId: channelId,
    ),
  );
}

class _GiftSheet extends ConsumerStatefulWidget {
  const _GiftSheet({
    required this.toUid,
    required this.toName,
    required this.chatId,
    required this.channelId,
  });

  final String toUid;
  final String toName;
  final String chatId;
  final String channelId;

  @override
  ConsumerState<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends ConsumerState<_GiftSheet> {
  /// The gift the user has highlighted, defaulting to the cheapest so the Send
  /// button is live from the moment the sheet opens.
  Gift _selected = Gift.catalogue.first;

  bool _sending = false;

  Future<void> _send() async {
    final String uid = ref.read(currentUidProvider);
    final String myName =
        ref.read(selfProfileProvider).valueOrNull?.fullName ?? '';

    setState(() => _sending = true);
    try {
      final GiftResult result = await ref.read(pointsServiceProvider).sendGift(
            fromUid: uid,
            fromName: myName,
            toUid: widget.toUid,
            toName: widget.toName,
            gift: _selected,
            chatId: widget.chatId,
            channelId: widget.channelId,
          );

      if (!mounted) return;
      if (result.success) {
        // Hand the receipt back so the caller can post the gift message; the
        // sheet's job is the payment, not the conversation.
        Navigator.of(context).pop(
          GiftReceipt(gift: _selected, result: result),
        );
      } else {
        iToast(context, result.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final PointsAccount account =
        ref.watch(pointsAccountProvider).valueOrNull ?? PointsAccount.empty;
    final bool affordable = account.points >= _selected.points;
    final bool isSelf = ref.watch(currentUidProvider) == widget.toUid;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xxl),
        ),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: AppRadius.rPill,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.toName.trim().isEmpty
                        ? 'Send a gift'
                        : 'Send a gift to ${widget.toName}',
                    style: context.t.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.14),
                    borderRadius: AppRadius.rPill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.stars_rounded,
                          size: 14, color: c.accent),
                      const SizedBox(width: 4),
                      Text(
                        TextUtils.grouped(account.points),
                        style: context.t.labelLarge?.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (isSelf)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  "You can't send a gift to yourself.",
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.onWarning,
                  ),
                ),
              ),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: <Widget>[
                for (final Gift gift in Gift.catalogue)
                  _GiftTile(
                    gift: gift,
                    selected: gift.id == _selected.id,
                    affordable: account.points >= gift.points,
                    onTap: () => setState(() => _selected = gift),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    affordable
                        ? '${_selected.emoji} ${_selected.name} · '
                            '${TextUtils.grouped(_selected.points)} points'
                        : 'You need '
                            '${TextUtils.grouped(_selected.points - account.points)}'
                            ' more points for a ${_selected.name}',
                    style: context.t.bodySmall?.copyWith(
                      color: affordable ? c.textSecondary : context.c.onWarning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ProminentButton(
              label: _sending ? 'Sending…' : context.l10n.sendGift,
              icon: _sending ? null : Icons.send_rounded,
              expanded: true,
              onPressed: (_sending || isSelf || !affordable) ? null : _send,
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One gift in the picker grid.
class _GiftTile extends StatelessWidget {
  const _GiftTile({
    required this.gift,
    required this.selected,
    required this.affordable,
    required this.onTap,
  });

  final Gift gift;
  final bool selected;

  /// Unaffordable gifts stay tappable so their cost can be read, but are shown
  /// dimmed — disabling them would hide what the catalogue contains.
  final bool affordable;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Opacity(
      opacity: affordable ? 1 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rMd,
        child: Container(
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? c.accent.withValues(alpha: 0.14)
                : c.card,
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: selected ? c.accent : c.divider,
              width: selected ? 1.6 : 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(gift.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                gift.name,
                style: context.t.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                TextUtils.compactCount(gift.points),
                style: context.t.labelSmall?.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
