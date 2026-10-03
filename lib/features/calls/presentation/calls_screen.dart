import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/status.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../../core/utils/l10n.dart';
import '../../../app/app.dart';

/// The Calls tab: log, filters, missed-call badge, quick dial.
class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

enum _CallFilter { all, missed }

class _CallsScreenState extends ConsumerState<CallsScreen> {
  _CallFilter _filter = _CallFilter.all;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CallRecord>> callsAsync = ref.watch(callsProvider);
    final List<CallRecord> all = callsAsync.orEmpty;
    final List<ScheduledCall> scheduled =
        ref.watch(scheduledCallsProvider).orEmpty;
    // Everyone reachable for a call: app contacts plus the device address book.
    final List<Contact> contacts = ref.watch(allContactsProvider);

    final List<CallRecord> visible = _filter == _CallFilter.missed
        ? all.where((CallRecord c) => c.isMissed).toList()
        : all;

    final int missedCount = all.where((CallRecord c) => c.isMissed).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.tabCalls),
        actions: <Widget>[
          if (all.isNotEmpty)
            IconButton(
              tooltip: context.l10n.clearCallLog,
              onPressed: _confirmClear,
              icon: const Icon(Icons.cleaning_services_outlined),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.c.accent,
        foregroundColor: Colors.white,
        onPressed: () => context.push(AppRoutes.selectContact),
        child: const Icon(Icons.add_call),
      ),
      body: callsAsync.isLoading && all.isEmpty
          ? const ChatListSkeleton(rows: 6)
          : CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _FilterBar(
                    value: _filter,
                    missedCount: missedCount,
                    onChanged: (_CallFilter f) => setState(() => _filter = f),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _QuickActions(onKeypad: () => context.push(AppRoutes.keypad)),
                ),
                if (scheduled.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _ScheduledSection(
                      calls: scheduled,
                      onCancel: _cancelScheduled,
                    ),
                  ),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 320,
                      child: EmptyState(
                        icon: _filter == _CallFilter.missed
                            ? Icons.phone_missed_outlined
                            : Icons.call_outlined,
                        title: _filter == _CallFilter.missed
                            ? 'No missed calls'
                            : 'No calls yet',
                        message: _filter == _CallFilter.missed
                            ? 'Missed and declined calls will show up here.'
                            : 'Start a voice or video call from a chat, a '
                                'contact or the list below.',
                        actionLabel: context.l10n.newCall,
                        onAction: () => context.push(AppRoutes.selectContact),
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (BuildContext context, int i) {
                      final CallRecord record = visible[i];
                      return ListStagger(
                        index: i,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _CallRow(
                              record: record,
                              onTap: () => _call(record),
                              onLongPress: () => _rowActions(record),
                              onInfo: () => context.push(
                                '${AppRoutes.contactInfo}/${record.contactId}',
                              ),
                            ),
                            if (i != visible.length - 1)
                              IListDivider(
                                indent: AppSizes.avatarMd +
                                    AppSpacing.lg +
                                    AppSpacing.md,
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                // ------------------------------------------------ device contacts
                if (contacts.isNotEmpty) ...<Widget>[
                  SliverToBoxAdapter(
                    child: SectionHeader(title: context.l10n.tabContacts),
                  ),
                  SliverList.builder(
                    itemCount: contacts.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Contact contact = contacts[i];
                      return _ContactCallRow(
                        contact: contact,
                        onCall: () => _callContact(contact, video: false),
                        onVideo: () => _callContact(contact, video: true),
                        onInfo: () => context.push(
                          '${AppRoutes.contactInfo}/${contact.id}',
                        ),
                      );
                    },
                  ),
                ],

                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xxxl * 2),
                ),
              ],
            ),
    );
  }

  void _callContact(Contact contact, {required bool video}) {
    context.push(
      Uri(
        path: AppRoutes.call,
        queryParameters: <String, String>{
          'id': contact.id,
          'name': contact.fullName,
          'video': video ? '1' : '0',
          'outgoing': '1',
        },
      ).toString(),
    );
  }

  void _call(CallRecord record) {
    context.push(
      Uri(
        path: AppRoutes.call,
        queryParameters: <String, String>{
          'id': record.contactId,
          'name': record.contactName,
          'video': record.kind == CallKind.video ? '1' : '0',
          'outgoing': '1',
        },
      ).toString(),
    );
  }

  void _rowActions(CallRecord record) {
    showActionSheet(
      context,
      title: record.contactName,
      actions: <({IconData icon, String label, VoidCallback onTap, Color? color})>[
        (
          icon: Icons.call_rounded,
          label: context.l10n.voiceCall,
          onTap: () {
            Navigator.pop(context);
            context.push(
              Uri(
                path: AppRoutes.call,
                queryParameters: <String, String>{
                  'id': record.contactId,
                  'name': record.contactName,
                  'outgoing': '1',
                },
              ).toString(),
            );
          },
          color: null,
        ),
        (
          icon: Icons.videocam_outlined,
          label: context.l10n.videoCall,
          onTap: () {
            Navigator.pop(context);
            context.push(
              Uri(
                path: AppRoutes.call,
                queryParameters: <String, String>{
                  'id': record.contactId,
                  'name': record.contactName,
                  'video': '1',
                  'outgoing': '1',
                },
              ).toString(),
            );
          },
          color: null,
        ),
        (
          icon: Icons.event_outlined,
          label: context.l10n.scheduleACall,
          onTap: () {
            Navigator.pop(context);
            context.push(
              Uri(
                path: AppRoutes.callSchedule,
                queryParameters: <String, String>{
                  'id': record.contactId,
                  'name': record.contactName,
                },
              ).toString(),
            );
          },
          color: null,
        ),
        (
          icon: Icons.delete_outline_rounded,
          label: context.l10n.removeFromLog,
          onTap: () async {
            Navigator.pop(context);
            await ref.read(callsProvider.notifier).remove(record.id);
          },
          color: context.c.onDanger,
        ),
      ],
    );
  }

  Future<void> _confirmClear() async {
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.clearCallLog2,
      message: context.l10n.everyCallEntryOnThis2,
      confirmLabel: context.l10n.clearLog,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(callsProvider.notifier).clearHistory();
    if (!mounted) return;
    iToast(context, context.l10n.callLogCleared);
  }

  Future<void> _cancelScheduled(ScheduledCall call) async {
    await ref.read(scheduledCallsProvider.notifier).remove(call.id);
    if (!mounted) return;
    iToast(context, context.l10n.reminderCancelled);
  }
}

// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.value,
    required this.missedCount,
    required this.onChanged,
  });

  final _CallFilter value;
  final int missedCount;
  final ValueChanged<_CallFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        children: <Widget>[
          _Chip(
            label: context.l10n.filterAll,
            selected: value == _CallFilter.all,
            onTap: () => onChanged(_CallFilter.all),
          ),
          const SizedBox(width: AppSpacing.sm),
          _Chip(
            label: missedCount == 0 ? 'Missed' : 'Missed ($missedCount)',
            selected: value == _CallFilter.missed,
            onTap: () => onChanged(_CallFilter.missed),
          ),
          const SizedBox(width: AppSpacing.sm),
          _Chip(
            label: context.l10n.scheduled,
            selected: false,
            onTap: () => context.push(AppRoutes.callSchedule),
          ),
          const SizedBox(width: AppSpacing.sm),
          _Chip(
            label: context.l10n.favourites,
            selected: false,
            onTap: () => context.push(AppRoutes.favorites),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 13,
        color: selected ? context.c.textOnAccent : context.c.textPrimary,
      ),
      selectedColor: context.c.accent,
      backgroundColor: context.c.surfaceAlt,
      side: BorderSide.none,
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onKeypad});

  final VoidCallback onKeypad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          _Tile(
            icon: Icons.dialpad_rounded,
            label: context.l10n.keypad,
            onTap: onKeypad,
          ),
          const SizedBox(width: AppSpacing.md),
          _Tile(
            icon: Icons.phone_callback_outlined,
            label: context.l10n.newCall,
            onTap: () => context.push(AppRoutes.selectContact),
          ),
          const SizedBox(width: AppSpacing.md),
          _Tile(
            icon: Icons.event_available_outlined,
            label: context.l10n.schedule,
            onTap: () => context.push(AppRoutes.callSchedule),
          ),
          const SizedBox(width: AppSpacing.md),
          _Tile(
            icon: Icons.star_border_rounded,
            label: context.l10n.favourites,
            onTap: () => context.push(AppRoutes.favorites),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.c.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: AppIconSizes.md, color: context.c.accent),
              ),
              const SizedBox(height: AppSpacing.sm),
              // "Favourites" wraps to two lines at larger text scales. Without
              // a line limit the Column outgrows its tile and overflows, so the
              // label is capped at two lines and allowed to shrink.
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelSmall?.copyWith(
                  color: context.c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduledSection extends StatelessWidget {
  const _ScheduledSection({required this.calls, required this.onCancel});

  final List<ScheduledCall> calls;
  final ValueChanged<ScheduledCall> onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: context.l10n.scheduledCalls),
        for (final ScheduledCall call in calls)
          SettingsTile(
            title: call.title,
            subtitle: '${call.contactName} · '
                '${DateFormatter.fullTimestamp(call.scheduledAt)}',
            leadingIcon: call.kind == CallKind.video
                ? Icons.videocam_outlined
                : Icons.call_outlined,
            leadingIconColor: context.c.accent,
            trailing: IconButton(
              tooltip: context.l10n.cancel,
              onPressed: () => onCancel(call),
              icon: const Icon(Icons.close_rounded, size: AppIconSizes.sm),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.record,
    required this.onTap,
    required this.onLongPress,
    required this.onInfo,
  });

  final CallRecord record;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final bool missed = record.isMissed;
    final bool incoming = record.direction == CallDirection.incoming;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            IAvatar(
              name: record.contactName,
              imagePath: record.avatarPath,
              colorSeed: record.avatarColor,
              size: AppSizes.avatarMd,
              onTap: onInfo,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.contactName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: missed ? context.c.onDanger : context.c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Icon(
                        missed
                            ? Icons.call_missed_rounded
                            : incoming
                                ? Icons.call_received_rounded
                                : Icons.call_made_rounded,
                        size: 14,
                        color: missed
                            ? context.c.onDanger
                            : context.c.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _subtitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodySmall?.copyWith(
                            color: context.c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: record.kind == CallKind.video ? 'Video call' : 'Voice call',
              onPressed: onTap,
              icon: Icon(
                record.kind == CallKind.video
                    ? Icons.videocam_outlined
                    : Icons.call_outlined,
                color: context.c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final String when = DateFormatter.chatTimestamp(record.timestamp);
    switch (record.outcome) {
      case CallOutcome.answered:
        return record.durationSeconds > 0
            ? '$when · ${record.durationLabel}'
            : when;
      case CallOutcome.missed:
        return '$when · Missed';
      case CallOutcome.declined:
        return '$when · Declined';
      case CallOutcome.cancelled:
        return '$when · Cancelled';
    }
  }
}

/// A row for someone in the contact list who has no call history yet.
///
/// The Calls tab previously showed only past calls, so on a fresh install it
/// was completely empty and gave the user nothing to act on. Every contact
/// reachable on this device is now listed here with one-tap call buttons.
class _ContactCallRow extends StatelessWidget {
  const _ContactCallRow({
    required this.contact,
    required this.onCall,
    required this.onVideo,
    required this.onInfo,
  });

  final Contact contact;
  final VoidCallback onCall;
  final VoidCallback onVideo;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCall,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            IAvatar(
              name: contact.fullName,
              imagePath: contact.avatarPath,
              colorSeed: contact.avatarColor,
              isOnline: contact.isOnline,
              showPresence: contact.isOnline,
              onTap: onInfo,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    contact.fullName,
                    style: context.t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.isOnline ? 'online' : contact.aboutText,
                    style: context.t.bodySmall?.copyWith(
                      color: contact.isOnline
                          ? context.c.online
                          : context.c.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.videoCall,
              onPressed: onVideo,
              icon: Icon(
                Icons.videocam_outlined,
                color: context.c.accent,
              ),
            ),
            IconButton(
              tooltip: context.l10n.voiceCall,
              onPressed: onCall,
              icon: Icon(
                Icons.call_outlined,
                color: context.c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small avatar stack used when a call involves a group. Reserved for the
/// upcoming group-call support; exported so the call screen can reuse it.
class CallParticipantStrip extends StatelessWidget {
  const CallParticipantStrip({super.key, required this.contacts});

  final List<Contact> contacts;

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: contacts.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int i) => IAvatar(
          name: contacts[i].fullName,
          imagePath: contacts[i].avatarPath,
          colorSeed: contacts[i].avatarColor,
          size: 44,
        ),
      ),
    );
  }
}
