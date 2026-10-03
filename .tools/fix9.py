p='lib/local/database/local_group_repository.dart'
s=open(p,encoding='utf-8').read()
old = """  @override
  Future<void> clear() async {
    await _ensureLoaded();
    _cache = <Group>[];
    await _persist();
  }

  Future<Group> _mutate(String id, Group Function(Group) change) async {"""
new = """  /// Convenience bulk insert used by the demo seeder.
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

  Future<Group> _mutate(String id, Group Function(Group) change) async {"""
assert old in s
s=s.replace(old,new)
open(p,'w',encoding='utf-8').write(s)
print("ok")
