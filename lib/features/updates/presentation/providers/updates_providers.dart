import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/status.dart';
import '../../../chats/presentation/providers.dart';

/// Convenience providers for the Updates and Calls tabs, kept separate so the
/// shell does not need to know about either feature's internals.

/// Number of unviewed statuses across everyone except the local user.
final Provider<int> unreadStatusCountProvider = Provider<int>((Ref ref) {
  final List<Status> all = ref.watch(statusesProvider).valueOrNull ?? <Status>[];
  final Set<String> unseenAuthors = <String>{};
  for (final Status status in all) {
    if (status.isOwn) continue;
    if (!status.isViewed) unseenAuthors.add(status.authorId);
  }
  return unseenAuthors.length;
});

/// Statuses split into the sections the Updates tab renders.
class StatusSections {
  const StatusSections({
    required this.mine,
    required this.recent,
    required this.viewed,
    required this.muted,
  });

  final List<Status> mine;
  final List<Status> recent;
  final List<Status> viewed;
  final List<Status> muted;

  bool get isEmpty =>
      mine.isEmpty && recent.isEmpty && viewed.isEmpty && muted.isEmpty;
}

/// Groups statuses by author, then classifies each author group.
final Provider<StatusSections> statusSectionsProvider =
    Provider<StatusSections>((Ref ref) {
  final Map<String, List<Status>> groups = ref.watch(statusGroupsProvider);

  final List<Status> mine = <Status>[];
  final List<Status> recent = <Status>[];
  final List<Status> viewed = <Status>[];
  final List<Status> muted = <Status>[];

  for (final MapEntry<String, List<Status>> entry in groups.entries) {
    final List<Status> list = entry.value;
    if (list.isEmpty) continue;
    final Status latest = list.last;
    if (latest.isOwn) {
      mine.addAll(list);
    } else if (latest.isMuted) {
      muted.addAll(list);
    } else if (list.any((Status s) => !s.isViewed)) {
      recent.addAll(list);
    } else {
      viewed.addAll(list);
    }
  }

  // Newest author first within each section.
  int byTime(Status a, Status b) =>
      (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
  recent.sort(byTime);
  viewed.sort(byTime);
  muted.sort(byTime);
  mine.sort(byTime);

  return StatusSections(
    mine: mine,
    recent: recent,
    viewed: viewed,
    muted: muted,
  );
});

/// Number of missed calls for the Calls tab badge.
final Provider<int> missedCallCountProvider = Provider<int>((Ref ref) {
  final List<CallRecord> calls = ref.watch(callsProvider).valueOrNull ?? <CallRecord>[];
  return calls.where((CallRecord c) => c.isMissed).length;
});

