import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/group.dart';
import '../../../features/chats/domain/repositories.dart';
import 'local_database.dart';

/// Hive-backed implementation for groups.
///
/// Shares the same list-of-models pattern as the other local repositories.

// ------------------------------------------------------------------ groups

class LocalGroupRepository implements GroupRepository {
  LocalGroupRepository({LocalDatabase? db}) : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final StreamController<List<Group>> _controller =
      StreamController<List<Group>>.broadcast();
  static const String _key = 'all_groups';

  List<Group> _cache = <Group>[];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _cache = _db.readList<Group>(AppConstants.boxGroups, _key, Group.fromJson);
    _loaded = true;
  }

  Future<void> _persist() async {
    await _db.writeList<Group>(
      AppConstants.boxGroups,
      _key,
      _cache,
      (g) => g.toJson(),
    );
    if (!_controller.isClosed) _controller.add(List<Group>.unmodifiable(_cache));
  }

  @override
  Future<List<Group>> getAll() async {
    await _ensureLoaded();
    return List<Group>.from(_cache);
  }

  @override
  Stream<List<Group>> watchAll() async* {
    await _ensureLoaded();
    yield List<Group>.from(_cache);
    yield* _controller.stream;
  }

  @override
  Future<Group?> findById(String id) async {
    await _ensureLoaded();
    for (final Group g in _cache) {
      if (g.id == id) return g;
    }
    return null;
  }

  @override
  Future<Group> save(Group group) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((g) => g.id == group.id);
    if (index == -1) {
      _cache.add(group);
    } else {
      _cache[index] = group;
    }
    await _persist();
    return group;
  }

  @override
  Future<void> delete(String id) async {
    await _ensureLoaded();
    _cache.removeWhere((g) => g.id == id);
    await _persist();
  }

  /// Convenience bulk insert used by the demo seeder.
  Future<void> saveAll(List<Group> groups) async {
    for (final Group group in groups) {
      final int index = _cache.indexWhere((g) => g.id == group.id);
      if (index == -1) {
        _cache.add(group);
      } else {
        _cache[index] = group;
      }
    }
    await _persist();
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    _cache = <Group>[];
    await _persist();
  }

  Future<Group> _mutate(String id, Group Function(Group) change) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((g) => g.id == id);
    if (index == -1) {
      throw StateError('Group $id not found');
    }
    _cache[index] = change(_cache[index]);
    await _persist();
    return _cache[index];
  }

  @override
  Future<Group> addMembers(String groupId, List<String> contactIds) => _mutate(
        groupId,
        (g) {
          final List<GroupMember> members = List<GroupMember>.from(g.members);
          for (final String id in contactIds) {
            if (!members.any((m) => m.contactId == id)) {
              members.add(
                GroupMember(contactId: id, joinedAt: DateTime.now()),
              );
            }
          }
          return g.copyWith(members: members);
        },
      );

  @override
  Future<Group> removeMember(String groupId, String contactId) => _mutate(
        groupId,
        (g) => g.copyWith(
          members: g.members.where((m) => m.contactId != contactId).toList(),
        ),
      );

  @override
  Future<Group> setRole(String groupId, String contactId, dynamic role) =>
      _mutate(
        groupId,
        (g) => g.copyWith(
          members: g.members.map((m) {
            if (m.contactId != contactId) return m;
            return m.copyWith(
              role: role is GroupRole ? role : m.role,
              canEditInfo: role == GroupRole.admin || role == GroupRole.owner,
            );
          }).toList(),
        ),
      );

  @override
  Future<Group> updatePermissions(String groupId, dynamic permissions) =>
      _mutate(
        groupId,
        (g) => g.copyWith(
          permissions: permissions is GroupPermissions
              ? permissions
              : g.permissions,
        ),
      );

  @override
  Future<List<Group>> search(String query) async {
    await _ensureLoaded();
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return List<Group>.from(_cache);
    return _cache
        .where((g) =>
            g.name.toLowerCase().contains(q) ||
            g.description.toLowerCase().contains(q))
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


