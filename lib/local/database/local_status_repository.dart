import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/status.dart';
import '../../../features/chats/domain/repositories.dart';
import 'local_database.dart';

/// Hive-backed implementation of [StatusRepository].
class LocalStatusRepository implements StatusRepository {
  LocalStatusRepository({LocalDatabase? db}) : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final StreamController<List<Status>> _controller =
      StreamController<List<Status>>.broadcast();
  static const String _key = 'all_statuses';

  List<Status> _cache = <Status>[];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _cache = _db.readList<Status>(AppConstants.boxStatuses, _key, Status.fromJson);
    _loaded = true;
  }

  Future<void> _persist() async {
    await _db.writeList<Status>(
      AppConstants.boxStatuses,
      _key,
      _cache,
      (s) => s.toJson(),
    );
    if (!_controller.isClosed) _controller.add(List<Status>.unmodifiable(_cache));
  }

  @override
  Future<List<Status>> getAll() async {
    await _ensureLoaded();
    final List<Status> copy = _cache.where((s) => !s.isExpired).toList();
    copy.sort((a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return copy;
  }

  @override
  Stream<List<Status>> watchAll() async* {
    await _ensureLoaded();
    yield await getAll();
    yield* _controller.stream.asyncMap((_) => getAll());
  }

  @override
  Future<Status> save(Status status) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((s) => s.id == status.id);
    if (index == -1) {
      _cache.add(status);
    } else {
      _cache[index] = status;
    }
    await _persist();
    return status;
  }

  @override
  Future<void> delete(String id) async {
    await _ensureLoaded();
    _cache.removeWhere((s) => s.id == id);
    await _persist();
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    _cache = <Status>[];
    await _persist();
  }

  @override
  Future<void> markViewed(String id, String viewerId) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((s) => s.id == id);
    if (index == -1) return;
    final List<String> viewers = List<String>.from(_cache[index].viewerIds);
    if (!viewers.contains(viewerId)) {
      viewers.add(viewerId);
      _cache[index] = _cache[index].copyWith(viewerIds: viewers);
      await _persist();
    }
  }

  @override
  Future<int> purgeExpired() async {
    await _ensureLoaded();
    final int before = _cache.length;
    _cache = _cache.where((s) => !s.isExpired).toList();
    if (_cache.length != before) await _persist();
    return before - _cache.length;
  }

  @override
  Future<List<Status>> getMyUpdates() async {
    final List<Status> all = await getAll();
    return all.where((s) => s.isOwn).toList();
  }

  @override
  Future<List<Status>> search(String query) async {
    final List<Status> all = await getAll();
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((s) =>
            s.authorName.toLowerCase().contains(q) ||
            s.text.toLowerCase().contains(q) ||
            s.caption.toLowerCase().contains(q))
        .toList();
  }

  /// Closes the change-notification stream.
  ///
  /// Wired to `ref.onDispose` in the owning provider, so the controller is
  /// released when the [ProviderContainer] is torn down instead of leaking.
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

// ------------------------------------------------------------------- calls

/// Hive-backed implementation of [CallRepository].
class LocalCallRepository implements CallRepository {
  LocalCallRepository({LocalDatabase? db}) : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final StreamController<List<CallRecord>> _controller =
      StreamController<List<CallRecord>>.broadcast();

  static const String _key = 'all_calls';
  static const String _scheduledKey = 'scheduled_calls';

  List<CallRecord> _cache = <CallRecord>[];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _cache = _db.readList<CallRecord>(
      AppConstants.boxCalls,
      _key,
      CallRecord.fromJson,
    );
    _cache.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _loaded = true;
  }

  Future<void> _persist() async {
    await _db.writeList<CallRecord>(
      AppConstants.boxCalls,
      _key,
      _cache,
      (c) => c.toJson(),
    );
    if (!_controller.isClosed) _controller.add(List<CallRecord>.unmodifiable(_cache));
  }

  @override
  Future<List<CallRecord>> getAll() async {
    await _ensureLoaded();
    final List<CallRecord> copy = List<CallRecord>.from(_cache);
    copy.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return copy;
  }

  @override
  Stream<List<CallRecord>> watchAll() async* {
    await _ensureLoaded();
    yield await getAll();
    yield* _controller.stream.asyncMap((_) => getAll());
  }

  @override
  Future<CallRecord> save(CallRecord record) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == record.id);
    if (index == -1) {
      _cache.add(record);
    } else {
      _cache[index] = record;
    }
    await _persist();
    return record;
  }

  @override
  Future<void> delete(String id) async {
    await _ensureLoaded();
    _cache.removeWhere((c) => c.id == id);
    await _persist();
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    _cache = <CallRecord>[];
    await _persist();
  }

  @override
  Future<void> clearHistory() => clear();

  @override
  Future<List<ScheduledCall>> getScheduled() async => _db.readList<ScheduledCall>(
        AppConstants.boxCalls,
        _scheduledKey,
        ScheduledCall.fromJson,
      )
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  @override
  Future<ScheduledCall> saveScheduled(ScheduledCall call) async {
    final List<ScheduledCall> list = await getScheduled();
    final int index = list.indexWhere((c) => c.id == call.id);
    if (index == -1) {
      list.add(call);
    } else {
      list[index] = call;
    }
    await _db.writeList<ScheduledCall>(
      AppConstants.boxCalls,
      _scheduledKey,
      list,
      (c) => c.toJson(),
    );
    return call;
  }

  @override
  Future<void> deleteScheduled(String id) async {
    final List<ScheduledCall> list = await getScheduled();
    list.removeWhere((c) => c.id == id);
    await _db.writeList<ScheduledCall>(
      AppConstants.boxCalls,
      _scheduledKey,
      list,
      (c) => c.toJson(),
    );
  }

  @override
  Future<List<CallRecord>> search(String query) async {
    final List<CallRecord> all = await getAll();
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((c) => c.contactName.toLowerCase().contains(q)).toList();
  }

  /// Closes the change-notification stream.
  ///
  /// Wired to `ref.onDispose` in the owning provider, so the controller is
  /// released when the [ProviderContainer] is torn down instead of leaking.
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
