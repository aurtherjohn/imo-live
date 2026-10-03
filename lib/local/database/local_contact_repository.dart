import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../features/chats/domain/repositories.dart';
import 'local_database.dart';

/// Hive-backed implementation of [ContactRepository].
class LocalContactRepository implements ContactRepository {
  LocalContactRepository({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;
  final StreamController<List<Contact>> _controller =
      StreamController<List<Contact>>.broadcast();

  static const String _key = 'all_contacts';
  static const String _selfKey = 'self_profile';

  List<Contact> _cache = <Contact>[];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _cache = _db.readList<Contact>(
      AppConstants.boxContacts,
      _key,
      Contact.fromJson,
    );
    _loaded = true;
  }

  Future<void> _persist() async {
    await _db.writeList<Contact>(
      AppConstants.boxContacts,
      _key,
      _cache,
      (c) => c.toJson(),
    );
    if (!_controller.isClosed) {
      _controller.add(List<Contact>.unmodifiable(_cache));
    }
  }

  List<Contact> get _sorted {
    final List<Contact> copy = List<Contact>.from(_cache);
    copy.sort((a, b) => a.sortedKey.compareTo(b.sortedKey));
    return copy;
  }

  @override
  Future<List<Contact>> getAll() async {
    await _ensureLoaded();
    return _sorted;
  }

  @override
  Stream<List<Contact>> watchAll() async* {
    await _ensureLoaded();
    yield _sorted;
    yield* _controller.stream.map((_) => _sorted);
  }

  @override
  Future<Contact?> findById(String id) async {
    await _ensureLoaded();
    for (final Contact c in _cache) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<Contact?> findByPhone(String phone) async {
    await _ensureLoaded();
    final String normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.isEmpty) return null;
    for (final Contact c in _cache) {
      if (c.phone.replaceAll(RegExp(r'[^0-9]'), '') == normalized) return c;
    }
    return null;
  }

  @override
  Future<Contact> save(Contact contact) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == contact.id);
    if (index == -1) {
      _cache.add(contact);
    } else {
      _cache[index] = contact;
    }
    await _persist();
    return contact;
  }

  @override
  Future<void> saveAll(List<Contact> contacts) async {
    await _ensureLoaded();
    for (final Contact contact in contacts) {
      final int index = _cache.indexWhere((c) => c.id == contact.id);
      if (index == -1) {
        _cache.add(contact);
      } else {
        _cache[index] = contact;
      }
    }
    await _persist();
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
    _cache = <Contact>[];
    await _persist();
  }

  Future<void> _mutate(String id, Contact Function(Contact) change) async {
    await _ensureLoaded();
    final int index = _cache.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _cache[index] = change(_cache[index]);
    await _persist();
  }

  @override
  Future<void> setFavorite(String id, bool favorite) =>
      _mutate(id, (c) => c.copyWith(isFavorite: favorite));

  @override
  Future<void> setBlocked(String id, bool blocked) =>
      _mutate(id, (c) => c.copyWith(isBlocked: blocked));

  @override
  Future<void> reorderFavorites(List<String> orderedIds) async {
    await _ensureLoaded();
    final Map<String, int> order = <String, int>{
      for (int i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };
    for (int i = 0; i < _cache.length; i++) {
      final int? position = order[_cache[i].id];
      if (position != null) {
        _cache[i] = _cache[i].copyWith(isFavorite: true);
      }
    }
    await _persist();
  }

  @override
  Future<List<Contact>> getFavorites() async {
    await _ensureLoaded();
    final List<Contact> favs = _cache.where((c) => c.isFavorite).toList();
    favs.sort((a, b) => a.sortedKey.compareTo(b.sortedKey));
    return favs;
  }

  @override
  Future<List<Contact>> getBlocked() async {
    await _ensureLoaded();
    final List<Contact> blocked = _cache.where((c) => c.isBlocked).toList();
    blocked.sort((a, b) => a.sortedKey.compareTo(b.sortedKey));
    return blocked;
  }

  @override
  Future<Contact> getSelfProfile() async {
    final Map<String, dynamic>? json =
        _db.readJson(AppConstants.boxProfile, _selfKey);
    if (json != null) return Contact.fromJson(json);
    // A first-run profile is intentionally blank. Nothing is invented for the
    // user — the UI shows its "add a phone number" / "tap to add an about"
    // placeholders until they fill the fields in themselves.
    const Contact fallback = Contact(
      id: 'self',
      firstName: '',
      phone: '',
      bio: '',
      isSelf: true,
    );
    return fallback;
  }

  @override
  Future<void> saveSelfProfile(Contact contact) => _db.writeJson(
        AppConstants.boxProfile,
        _selfKey,
        contact.copyWith(isSelf: true).toJson(),
      );

  @override
  Future<List<Contact>> search(String query) async {
    await _ensureLoaded();
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return _sorted;
    return _cache.where((c) {
      return c.fullName.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q) ||
          c.bio.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.sortedKey.compareTo(b.sortedKey));
  }

  /// Closes the change-notification stream.
  ///
  /// Wired to `ref.onDispose` in the owning provider, so the controller is
  /// released when the [ProviderContainer] is torn down instead of leaking.
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
