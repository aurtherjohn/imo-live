import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/group.dart';
import '../../../features/chats/domain/repositories.dart';
import 'local_database.dart';

/// Hive-backed implementations for groups, communities, channels and statuses.
///
/// They share the same list-of-models pattern as the other local repositories.

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

// ------------------------------------------------------------- communities

class LocalCommunityRepository implements CommunityRepository {
  LocalCommunityRepository({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final StreamController<List<Community>> _controller =
      StreamController<List<Community>>.broadcast();
  static const String _key = 'all_communities';

  List<Community> _cache = <Community>[];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _cache = _db.readList<Community>(
      AppConstants.boxCommunities,
      _key,
      Community.fromJson,
    );
    _loaded = true;
  }

  Future<void> _persist() async {
    await _db.writeList<Community>(
      AppConstants.boxCommunities,
      _key,
      _cache,
      (c) => c.toJson(),
    );
    if (!_controller.isClosed) _controller.add(List<Community>.unmodifiable(_cache));
  }

  @override
  Future<List<Community>> getAll() async {
    await _ensureLoaded();
    return List<Community>.from(_cache);
  }

  @override
  Stream<List<Community>> watchAll() async* {
    await _ensureLoaded();
    yield List<Community>.from(_cache);
    yield* _controller.stream;
  }

  @override
  Future<Community?> findById(String id) async {
    await _ensureLoaded();
    for (final Community c in _cache) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<Community> save(Community community) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == community.id);
    if (index == -1) {
      _cache.add(community);
    } else {
      _cache[index] = community;
    }
    await _persist();
    return community;
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
    _cache = <Community>[];
    await _persist();
  }

  @override
  Future<Community> addGroup(String communityId, String groupId) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == communityId);
    if (index == -1) throw StateError('Community $communityId not found');
    final List<String> groups = List<String>.from(_cache[index].groupIds);
    if (!groups.contains(groupId)) groups.add(groupId);
    _cache[index] = _cache[index].copyWith(groupIds: groups);
    await _persist();
    return _cache[index];
  }

  @override
  Future<Community> createAnnouncementGroup(String communityId) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == communityId);
    if (index == -1) throw StateError('Community $communityId not found');
    final Community community = _cache[index];
    final String announcementId = 'announce_${community.id}';
    if (community.announcementChatId == null) {
      _cache[index] = community.copyWith(announcementChatId: announcementId);
      await _persist();
    }
    return _cache[index];
  }

  /// Closes the change-notification stream.
  ///
  /// Wired to `ref.onDispose` in the owning provider, so the controller is
  /// released when the [ProviderContainer] is torn down instead of leaking.
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

// ---------------------------------------------------------------- channels

class LocalChannelRepository implements ChannelRepository {
  LocalChannelRepository({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final StreamController<List<Channel>> _controller =
      StreamController<List<Channel>>.broadcast();
  static const String _key = 'all_channels';

  List<Channel> _cache = <Channel>[];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _cache = _db.readList<Channel>(
      AppConstants.boxChannels,
      _key,
      Channel.fromJson,
    );
    _loaded = true;
  }

  Future<void> _persist() async {
    await _db.writeList<Channel>(
      AppConstants.boxChannels,
      _key,
      _cache,
      (c) => c.toJson(),
    );
    if (!_controller.isClosed) _controller.add(List<Channel>.unmodifiable(_cache));
  }

  @override
  Future<List<Channel>> getAll() async {
    await _ensureLoaded();
    return List<Channel>.from(_cache);
  }

  @override
  Stream<List<Channel>> watchAll() async* {
    await _ensureLoaded();
    yield List<Channel>.from(_cache);
    yield* _controller.stream;
  }

  @override
  Future<Channel?> findById(String id) async {
    await _ensureLoaded();
    for (final Channel c in _cache) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<Channel> save(Channel channel) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == channel.id);
    if (index == -1) {
      _cache.add(channel);
    } else {
      _cache[index] = channel;
    }
    await _persist();
    return channel;
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
    _cache = <Channel>[];
    await _persist();
  }

  Future<void> _mutate(String id, Channel Function(Channel) change) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _cache[index] = change(_cache[index]);
    await _persist();
  }

  @override
  Future<void> setFollowing(String id, bool following) => _mutate(
        id,
        (c) => c.copyWith(
          isFollowing: following,
          unreadCount: following ? c.unreadCount : 0,
          followerCount: following
              ? c.followerCount + 1
              : (c.followerCount > 0 ? c.followerCount - 1 : 0),
        ),
      );

  @override
  Future<void> setMuted(String id, bool muted) =>
      _mutate(id, (c) => c.copyWith(isMuted: muted));

  @override
  Future<List<Channel>> getFollowed() async {
    await _ensureLoaded();
    return _cache.where((c) => c.isFollowing).toList();
  }

  @override
  Future<List<Channel>> search(String query) async {
    await _ensureLoaded();
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return List<Channel>.from(_cache);
    return _cache
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.description.toLowerCase().contains(q) ||
            c.category.toLowerCase().contains(q))
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
