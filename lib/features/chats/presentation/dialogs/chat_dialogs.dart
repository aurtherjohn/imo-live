import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/message.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../../core/utils/l10n.dart';

/// Shows delivery details for one message.
Future<void> showMessageInfoSheet(BuildContext context, Message message) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: sheetContext.c.divider,
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
                child: Text(context.l10n.messageInfo, style: sheetContext.t.titleMedium),
              ),
            ),
            _InfoRow(
              icon: Icons.schedule_rounded,
              label: context.l10n.sent,
              value: DateFormatter.fullTimestamp(message.timestamp),
            ),
            if (message.deliveredAt != null)
              _InfoRow(
                icon: Icons.done_all_rounded,
                label: context.l10n.delivered,
                value: DateFormatter.fullTimestamp(message.deliveredAt!),
              ),
            if (message.readAt != null)
              _InfoRow(
                icon: Icons.done_all_rounded,
                label: context.l10n.read,
                value: DateFormatter.fullTimestamp(message.readAt!),
              ),
            _InfoRow(
              icon: Icons.shield_outlined,
              label: context.l10n.status,
              value: message.localOnly
                  ? 'Queued on this device'
                  : 'Synced to your account',
            ),
            if (message.localOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: AppRadius.rMd,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: context.c.onWarning,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          context.l10n.thisMessageIsQueuedOn2,
                          style: sheetContext.t.bodySmall?.copyWith(height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: AppIconSizes.sm, color: context.c.textSecondary),
          SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 70,
            child: Text(label, style: context.t.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: context.t.bodyMedium?.copyWith(
                color: context.c.textSecondary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ poll

/// Result of the poll composer.
class PollDraft {
  const PollDraft({
    required this.question,
    required this.options,
    this.allowMultiple = false,
    this.correctIndex,
  });

  final String question;
  final List<String> options;
  final bool allowMultiple;

  /// Index into [options] of the right answer, or null for a plain poll.
  final int? correctIndex;

  bool get isQuiz => correctIndex != null;
}

/// Builds a poll — or, with [asQuiz], a graded quiz. Returns null when cancelled.
Future<PollDraft?> showPollComposer(
  BuildContext context, {
  bool asQuiz = false,
}) {
  return showModalBottomSheet<PollDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _PollComposer(asQuiz: asQuiz),
    ),
  );
}

class _PollComposer extends StatefulWidget {
  const _PollComposer({this.asQuiz = false});

  final bool asQuiz;

  @override
  State<_PollComposer> createState() => _PollComposerState();
}

class _PollComposerState extends State<_PollComposer> {
  final TextEditingController _question = TextEditingController();
  final List<TextEditingController> _options = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;
  late final bool _isQuiz = widget.asQuiz;

  /// Index of the option marked as correct — only meaningful in quiz mode.
  int? _correctIndex;

  @override
  void dispose() {
    _question.dispose();
    for (final TextEditingController c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      _question.text.trim().isNotEmpty &&
      _options.where((TextEditingController c) => c.text.trim().isNotEmpty).length >=
          2 &&
      // A quiz without a marked answer would grade every response wrong.
      (!_isQuiz || (_correctIndex != null && _optionAt(_correctIndex!) != null));

  /// The controller for [index], or null when that slot was removed/emptied.
  TextEditingController? _optionAt(int index) =>
      index >= 0 && index < _options.length ? _options[index] : null;

  /// Clears [index] when its text is emptied, so a stale "correct" mark cannot
  /// survive on a row the user has just blanked out.
  void _onOptionChanged(int index) {
    if (_correctIndex == index &&
        (_optionAt(index)?.text.trim().isEmpty ?? true)) {
      _correctIndex = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(height: AppSpacing.md),
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
                AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    _isQuiz ? Icons.quiz_rounded : Icons.poll_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _isQuiz ? 'Create quiz' : 'Create poll',
                    style: context.t.titleMedium,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  ITextField(
                    controller: _question,
                    hint: _isQuiz ? 'Quiz question' : 'Ask a question',
                    maxLines: 2,
                    minLines: 1,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...List<Widget>.generate(_options.length, (int index) {
                    final bool marked = _isQuiz && _correctIndex == index;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: <Widget>[
                          if (_isQuiz)
                            IconButton(
                              tooltip: marked
                                  ? 'Correct answer'
                                  : 'Mark as correct answer',
                              onPressed: () => setState(
                                () => _correctIndex = marked ? null : index,
                              ),
                              icon: Icon(
                                marked
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 22,
                                color: marked
                                    ? context.c.onSuccess
                                    : context.c.textSecondary,
                              ),
                            ),
                          Expanded(
                            child: ITextField(
                              controller: _options[index],
                              hint: context.l10n.option(index + 1),
                              onChanged: (_) => _onOptionChanged(index),
                            ),
                          ),
                          if (_options.length > 2)
                            IconButton(
                              tooltip: context.l10n.remove,
                              onPressed: () {
                                setState(() {
                                  _options.removeAt(index).dispose();
                                  // Removing a row shifts every later index, so
                                  // a mark beyond the removal point must slide
                                  // down with it — and must not dangle.
                                  if (_correctIndex != null) {
                                    if (_correctIndex == index) {
                                      _correctIndex = null;
                                    } else if (_correctIndex! > index) {
                                      _correctIndex = _correctIndex! - 1;
                                    }
                                  }
                                });
                              },
                              icon: Icon(
                                Icons.remove_circle_outline_rounded,
                                size: 20,
                                color: context.c.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (_options.length < 12)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () => _options.add(TextEditingController()),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(context.l10n.addOption),
                      ),
                    ),
                  if (!_isQuiz)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _allowMultiple,
                      onChanged: (bool value) =>
                          setState(() => _allowMultiple = value),
                      title: Text(
                        context.l10n.allowMultipleAnswers,
                        style: context.t.bodyLarge,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _canSubmit
                          ? () {
                              // Re-derive the correct index against the list we
                              // actually submit: blank rows are dropped, which
                              // renumbers everything after them.
                              final List<String> options = _options
                                  .map((TextEditingController c) => c.text.trim())
                                  .toList();
                              int? correct;
                              if (_isQuiz && _correctIndex != null) {
                                int seen = 0;
                                for (int i = 0; i < options.length; i++) {
                                  if (options[i].isEmpty) continue;
                                  if (i == _correctIndex) {
                                    correct = seen;
                                    break;
                                  }
                                  seen++;
                                }
                              }
                              Navigator.pop(
                                context,
                                PollDraft(
                                  question: _question.text.trim(),
                                  options: options
                                      .where((String s) => s.isNotEmpty)
                                      .toList(),
                                  allowMultiple: _isQuiz ? false : _allowMultiple,
                                  correctIndex: correct,
                                ),
                              );
                            }
                          : null,
                      child: Text(_isQuiz ? 'Create quiz' : 'Create poll'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- event

/// Result of the event composer.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.start,
    this.end,
    this.location = '',
    this.description = '',
  });

  final String title;
  final DateTime start;
  final DateTime? end;
  final String location;
  final String description;
}

/// Builds an event. Returns null when cancelled.
Future<EventDraft?> showEventComposer(BuildContext context) {
  return showModalBottomSheet<EventDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: const _EventComposer(),
    ),
  );
}

class _EventComposer extends StatefulWidget {
  const _EventComposer();

  @override
  State<_EventComposer> createState() => _EventComposerState();
}

class _EventComposerState extends State<_EventComposer> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _description = TextEditingController();

  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime? _end;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final DateTime base = isStart ? _start : (_end ?? _start);
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    final DateTime combined =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = combined;
        if (_end != null && _end!.isBefore(_start)) _end = null;
      } else {
        _end = combined;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(height: AppSpacing.md),
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
                AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.event_rounded, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Text(context.l10n.createEvent, style: context.t.titleMedium),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  ITextField(
                    controller: _title,
                    hint: context.l10n.eventName,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _PickerRow(
                    icon: Icons.schedule_rounded,
                    label: context.l10n.starts,
                    value: DateFormatter.fullTimestamp(_start),
                    onTap: () => _pickDate(isStart: true),
                  ),
                  _PickerRow(
                    icon: Icons.schedule_outlined,
                    label: context.l10n.ends,
                    value: _end == null
                        ? 'Not set'
                        : DateFormatter.fullTimestamp(_end!),
                    onTap: () => _pickDate(isStart: false),
                  ),
                  SizedBox(height: AppSpacing.md),
                  ITextField(
                    controller: _location,
                    hint: context.l10n.locationOptional,
                    prefixIcon: Icon(
                      Icons.place_outlined,
                      size: AppIconSizes.sm,
                      color: context.c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ITextField(
                    controller: _description,
                    hint: context.l10n.descriptionOptional,
                    maxLines: 3,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _title.text.trim().isEmpty
                          ? null
                          : () => Navigator.pop(
                                context,
                                EventDraft(
                                  title: _title.text.trim(),
                                  start: _start,
                                  end: _end,
                                  location: _location.text.trim(),
                                  description: _description.text.trim(),
                                ),
                              ),
                      child: Text(context.l10n.createEvent),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.rMd,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(icon, size: AppIconSizes.md, color: context.c.accent),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 60,
              child: Text(label, style: context.t.bodyMedium),
            ),
            Expanded(
              child: Text(
                value,
                style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.c.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- contact pick

/// Picks one contact from [contacts]. Returns null when dismissed.
Future<Contact?> showContactPicker(
  BuildContext context, {
  required List<Contact> contacts,
}) {
  return showModalBottomSheet<Contact>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) => FractionallySizedBox(
      heightFactor: 0.7,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: sheetContext.c.divider,
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
              child: Text(context.l10n.shareAContact, style: sheetContext.t.titleMedium),
            ),
          ),
          Expanded(
            child: contacts.isEmpty
                ? EmptyState(
                    icon: Icons.person_off_outlined,
                    title: context.l10n.noContacts,
                    message: context.l10n.addAContactFirstTo,
                    compact: true,
                  )
                : ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Contact contact = contacts[index];
                      return ListTile(
                        leading: IAvatar(
                          name: contact.fullName,
                          imagePath: contact.avatarPath,
                          imageUrl: contact.avatarUrl,
                          colorSeed: contact.avatarColor,
                          size: AppSizes.avatarSm + 6,
                        ),
                        title: Text(
                          contact.fullName,
                          style: sheetContext.t.bodyLarge,
                        ),
                        subtitle: Text(
                          contact.phone,
                          style: sheetContext.t.bodySmall,
                        ),
                        onTap: () => Navigator.pop(sheetContext, contact),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

// -------------------------------------------------------------- emoji pick

/// Picks a single sticker / big emoji.
Future<String?> showStickerPicker(BuildContext context) {
  const List<String> stickers = <String>[
    '😀', '😂', '🥰', '😎', '🤔', '😴', '🥳', '😭', '😱', '🤯',
    '❤️', '🔥', '✨', '🎉', '🙏', '👍', '💯', '🙌', '💪', '🌸',
    '🐶', '🐱', '🦊', '🐼', '🍕', '🎂', '⚽', '🎮', '🌈', '☀️',
  ];
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: sheetContext.c.divider,
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
              child: Text(context.l10n.stickers, style: sheetContext.t.titleMedium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
              ),
              itemCount: stickers.length,
              itemBuilder: (BuildContext context, int index) {
                return InkWell(
                  onTap: () => Navigator.pop(sheetContext, stickers[index]),
                  borderRadius: AppRadius.rMd,
                  child: Center(
                    child: Text(
                      stickers[index],
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    ),
  );
}

/// Confirms before a bulk destructive action, returning the chosen scope.
Future<bool> confirmClearMessages(BuildContext context) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(context.l10n.clearThisChat),
      content: Text(
        context.l10n.allMessagesInThisConversation2,
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
            context.l10n.clear,
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
