import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/status.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../groups/presentation/widgets/group_picker.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Lists scheduled call reminders and creates new ones.
class ScheduleCallScreen extends ConsumerStatefulWidget {
  const ScheduleCallScreen({super.key, this.preselectedId, this.preselectedName});

  final String? preselectedId;
  final String? preselectedName;

  @override
  ConsumerState<ScheduleCallScreen> createState() => _ScheduleCallScreenState();
}

class _ScheduleCallScreenState extends ConsumerState<ScheduleCallScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  String? _contactId;
  String? _contactName;
  CallKind _kind = CallKind.voice;
  DateTime _date = DateTime.now().add(const Duration(hours: 1));
  int _remindBefore = 10;

  @override
  void initState() {
    super.initState();
    _contactId = widget.preselectedId;
    _contactName = widget.preselectedName;
    _title.text = widget.preselectedName == null
        ? 'Call'
        : 'Call with ${widget.preselectedName}';
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<ScheduledCall> upcoming = ref.watch(scheduledCallsProvider).orEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.scheduleACall),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          InfoBanner(
            message:
                context.l10n.remindersFireFromTheLocal2,
          ),

          SettingsGroup(
            title: context.l10n.who,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.contact,
                value: _contactName ?? 'Choose a contact',
                leadingIcon: Icons.person_outline_rounded,
                onTap: _pickContact,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: ITextField(
                  controller: _title,
                  hint: context.l10n.title,
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.when,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.date,
                value: DateFormatter.fullTimestamp(_date).split(' at ').first,
                leadingIcon: Icons.calendar_today_outlined,
                onTap: _pickDate,
              ),
              SettingsValueRow(
                label: context.l10n.time,
                value: TimeOfDay.fromDateTime(_date).format(context),
                leadingIcon: Icons.schedule_outlined,
                onTap: _pickTime,
              ),
              SettingsValueRow(
                label: context.l10n.remindMe,
                value: _remindLabel(_remindBefore),
                leadingIcon: Icons.notifications_active_outlined,
                onTap: _pickReminder,
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.type,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _KindCard(
                        icon: Icons.call_rounded,
                        label: context.l10n.voiceCall,
                        selected: _kind == CallKind.voice,
                        onTap: () => setState(() => _kind = CallKind.voice),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _KindCard(
                        icon: Icons.videocam_rounded,
                        label: context.l10n.videoCall,
                        selected: _kind == CallKind.video,
                        onTap: () => setState(() => _kind = CallKind.video),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.notes,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ITextField(
                  controller: _notes,
                  hint: context.l10n.anythingToRemember,
                  maxLines: 3,
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ProminentButton(
              label: context.l10n.saveReminder,
              icon: Icons.alarm_add_rounded,
              expanded: true,
              onPressed: _contactId == null ? () {} : _save,
            ),
          ),

          if (upcoming.isNotEmpty) ...<Widget>[
            SectionHeader(title: context.l10n.upcoming),
            for (final ScheduledCall call in upcoming)
              SettingsTile(
                title: call.title,
                subtitle: '${call.contactName} · '
                    '${DateFormatter.fullTimestamp(call.scheduledAt)}',
                leading: IAvatar(
                  name: call.contactName,
                  size: AppSizes.avatarSm,
                ),
                trailing: IconButton(
                  tooltip: context.l10n.cancel,
                  onPressed: () async {
                    await ref
                        .read(scheduledCallsProvider.notifier)
                        .remove(call.id);
                    if (!context.mounted) return;
                    iToast(context, context.l10n.reminderCancelled);
                  },
                  icon: const Icon(Icons.close_rounded, size: AppIconSizes.sm),
                ),
                onTap: () => _editExisting(call),
              ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  String _remindLabel(int minutes) {
    if (minutes == 0) return 'At the scheduled time';
    if (minutes < 60) return '$minutes minutes before';
    if (minutes == 60) return '1 hour before';
    return '${minutes ~/ 60} hours before';
  }

  Future<void> _pickContact() async {
    final List<Contact> contacts = ref.read(contactsProvider).orEmpty;
    if (contacts.isEmpty) {
      iToast(context, context.l10n.addAContactFirst, isError: true);
      return;
    }
    final List<Contact>? pickedList = await pickContacts(
      context: context,
      ref: ref,
      title: context.l10n.scheduleWith,
      searchHint: 'Search contacts',
    );
    final Contact? picked = pickedList?.firstOrNull;

    // The picker is an async gap — the screen can be popped while it is open.
    if (!mounted || picked == null) return;
    setState(() {
      _contactId = picked.id;
      _contactName = picked.fullName;
      if (_title.text.isEmpty || _title.text.startsWith('Call')) {
        _title.text = 'Call with ${picked.fullName}';
      }
    });
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickReminder() async {
    final int? value = await showChoiceSheet<int>(
      context: context,
      title: context.l10n.remindMe,
      selected: _remindBefore,
      options: <({int value, String label, String? subtitle})>[
        (value: 0, label: context.l10n.atTheScheduledTime, subtitle: null),
        (value: 5, label: context.l10n.s5MinutesBefore, subtitle: null),
        (value: 10, label: context.l10n.s10MinutesBefore, subtitle: null),
        (value: 30, label: context.l10n.s30MinutesBefore, subtitle: null),
        (value: 60, label: context.l10n.s1HourBefore, subtitle: null),
      ],
    );
    if (!mounted || value == null) return;
    setState(() => _remindBefore = value);
  }

  Future<void> _editExisting(ScheduledCall call) async {
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.removeReminder,
      message: context.l10n.onIsDeleted(call.title, DateFormatter.fullTimestamp(call.scheduledAt)),
      confirmLabel: context.l10n.remove,
      destructive: true,
    );
    if (!ok) return;
    if (!mounted) return;
    await ref.read(scheduledCallsProvider.notifier).remove(call.id);
    if (!mounted) return;
    iToast(context, context.l10n.reminderRemoved);
  }

  Future<void> _save() async {
    if (_contactId == null) return;
    if (_date.isBefore(DateTime.now())) {
      iToast(context, context.l10n.pickATimeInThe, isError: true);
      return;
    }

    await ref.read(scheduledCallsProvider.notifier).add(
          ScheduledCall(
            id: 'sched_${DateTime.now().microsecondsSinceEpoch}',
            contactId: _contactId!,
            contactName: _contactName ?? 'Unknown',
            title: _title.text.trim().isEmpty ? context.l10n.call : _title.text.trim(),
            scheduledAt: _date,
            remindMinutesBefore: _remindBefore,
            kind: _kind,
            notes: _notes.text.trim(),
          ),
        );

    if (!mounted) return;
    iToast(context, context.l10n.reminderSaved);
    if (context.canPop()) context.pop();
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.rMd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected
              ? context.c.accent.withValues(alpha: 0.14)
              : context.c.surfaceAlt,
          borderRadius: AppRadius.rMd,
          border: Border.all(
            color: selected ? context.c.accent : context.c.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              icon,
              color: selected ? context.c.accent : context.c.textSecondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: context.t.bodySmall?.copyWith(
                color: selected ? context.c.accent : context.c.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
