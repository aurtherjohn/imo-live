import re
p='lib/features/chats/presentation/providers.dart'
s=open(p,encoding='utf-8').read()

# 1) Provider.family / StreamProvider.family / FutureProvider.family as explicit type annotations
#    -> drop the annotation, keep `final xProvider = Provider.family(...)`.
s = re.sub(
    r"final Provider\.family<AsyncValue<[^>]+>, String> (\w+) =\s*\n\s*Provider\.family<[^>]+>\(\(",
    lambda m: f"final {m.group(1)} = Provider.family<AsyncValue<Contact?>, String>((",
    s)

# Simpler: replace specific declaration prefixes with inferred finals.
s = s.replace("final Provider.family<AsyncValue<Contact?>, String> contactByIdProvider =\n    Provider.family<AsyncValue<Contact?>, String>(",
              "final contactByIdProvider = Provider.family<AsyncValue<Contact?>, String>(")
s = s.replace("final Provider.family<AsyncValue<Chat?>, String> chatByIdProvider =\n    Provider.family<AsyncValue<Chat?>, String>(",
              "final chatByIdProvider = Provider.family<AsyncValue<Chat?>, String>(")
s = s.replace("final StreamProvider.family<Chat?, String> chatStreamProvider =\n    StreamProvider.family<Chat?, String>(",
              "final chatStreamProvider = StreamProvider.family<Chat?, String>(")
s = s.replace("final StreamProvider.family<List<Message>, String> messagesProvider =\n    StreamProvider.family<List<Message>, String>(",
              "final messagesProvider = StreamProvider.family<List<Message>, String>(")
s = s.replace("final Provider.family<AsyncValue<Group?>, String> groupByIdProvider =\n    Provider.family<AsyncValue<Group?>, String>(",
              "final groupByIdProvider = Provider.family<AsyncValue<Group?>, String>(")
s = s.replace("final Provider.family<AsyncValue<Community?>, String> communityByIdProvider =\n    Provider.family<AsyncValue<Community?>, String>(",
              "final communityByIdProvider = Provider.family<AsyncValue<Community?>, String>(")
s = s.replace("final Provider.family<AsyncValue<Channel?>, String> channelByIdProvider =\n    Provider.family<AsyncValue<Channel?>, String>(",
              "final channelByIdProvider = Provider.family<AsyncValue<Channel?>, String>(")
s = s.replace("final FutureProvider.family<List<SearchHit>, String> globalSearchProvider =\n    FutureProvider.family<List<SearchHit>, String>(",
              "final globalSearchProvider = FutureProvider.family<List<SearchHit>, String>(")

# 2) CommunitiesNotifier.update collides with AsyncNotifier.update -> rename to save
s = s.replace("""  Future<void> update(Community community) async {
    await _repo.save(community);
    await refresh();
  }""","""  Future<void> persist(Community community) async {
    await _repo.save(community);
    await refresh();
  }""")

# 3) unnecessary nullable generic in family results: AsyncValue<Chat?> is intended (nullable element)
open(p,'w',encoding='utf-8').write(s)
print("providers patched")
