import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/remote_contact_service.dart';

/// Which identifier the user typed into the smart search field.
///
/// Used only to steer the real-time Firestore query at the right index; the
/// result is always a list of real [RemoteProfile]s from the shared directory.
enum DirectoryQueryKind { phone, email, username, name, uid, unknown }

/// A debounced, real-time search over the Imo LIVE user directory.
///
/// Wraps [RemoteContactService] so the UI never talks to Firestore directly and
/// every screen shares one debounce window (~350 ms), the same behaviour the
/// search bar in every messaging app has: type, pause, results stream in.
class DirectorySearchService {
  DirectorySearchService({RemoteContactService? directory})
      : _directory = directory ?? const RemoteContactService();

  final RemoteContactService _directory;

  static const Duration debounce = Duration(milliseconds: 350);

  Timer? _timer;
  int _generation = 0;
  final StreamController<List<RemoteProfile>> _results =
      StreamController<List<RemoteProfile>>.broadcast();

  /// Profiles matching the most recent query, pushed as they resolve.
  Stream<List<RemoteProfile>> get stream => _results.stream;

  /// Classifies a raw query string.
  static DirectoryQueryKind kindOf(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) return DirectoryQueryKind.unknown;
    if (value.startsWith('@')) return DirectoryQueryKind.username;
    if (value.contains('@') && value.contains('.')) {
      return DirectoryQueryKind.email;
    }
    if (RegExp(r'^[+0-9 ()\-]+$').hasMatch(value) &&
        value.replaceAll(RegExp(r'[^0-9]'), '').length >= 6) {
      return DirectoryQueryKind.phone;
    }
    // A 20+ character opaque token is almost certainly a Firebase uid.
    if (value.length >= 20 && !value.contains(' ')) {
      return DirectoryQueryKind.uid;
    }
    // A multi-word query is a display name: nobody's handle contains a space.
    if (value.contains(' ')) return DirectoryQueryKind.name;
    return DirectoryQueryKind.username;
  }

  /// Human-readable label for the "searching by X" hint under the field.
  static String labelFor(DirectoryQueryKind kind) => switch (kind) {
        DirectoryQueryKind.phone => 'phone number',
        DirectoryQueryKind.email => 'email address',
        DirectoryQueryKind.username => '@username',
        DirectoryQueryKind.name => 'name',
        DirectoryQueryKind.uid => 'user ID',
        DirectoryQueryKind.unknown => 'name or number',
      };

  /// Debounces [query] and then resolves it.
  ///
  /// Every call supersedes the previous one, so a fast typist never sees the
  /// results of an abandoned prefix.
  void search(String query) {
    _timer?.cancel();
    final String value = query.trim();
    if (value.isEmpty) {
      _generation++;
      _emit(const <RemoteProfile>[]);
      return;
    }
    _timer = Timer(debounce, () => _run(value));
  }

  Future<void> _run(String value) async {
    final int generation = ++_generation;
    final DirectoryQueryKind kind = kindOf(value);

    // An exact identifier resolves to at most one person — a direct index hit.
    if (kind != DirectoryQueryKind.username && kind != DirectoryQueryKind.name) {
      final LookupResult result = await _directory.findByAnyIdentifier(value);
      if (generation != _generation) return;
      if (result.isFound && result.profile != null) {
        _emit(<RemoteProfile>[result.profile!]);
        return;
      }
      if (result.isUnavailable) {
        // Firestore is unreachable. Reporting "no matches" here would read as
        // "this person has no account", which is a different and wrong claim.
        _emit(const <RemoteProfile>[]);
        return;
      }
      // A miss on the index is not yet a miss overall: a profile can carry the
      // digits in `phoneLower` without a `phones/{number}` entry. Fall through
      // to the range query for a phone number rather than reporting a flat miss.
      if (kind != DirectoryQueryKind.phone) {
        _emit(const <RemoteProfile>[]);
        return;
      }
    }

    // A handle prefix, a display-name prefix, a token or a number prefix can
    // each match many people, so stream the relevant queries and merge them.
    //
    // Searching only handles is why typing a person's actual name found
    // nothing: `name` was never indexed, so the obvious query had no index to
    // hit. `users/{uid}.nameLowercase` is written alongside `name` for exactly
    // this, and `searchKeywords` covers what the two range queries cannot —
    // matches in the middle of a word, and one query spanning several fields.
    //
    // TODO: Algolia/Typesense for advanced search — prefix range queries cannot
    // do fuzzy matching, ranking or multi-word-token search, and they are
    // case-insensitive only because of the denormalised lowercase field.
    final Map<String, RemoteProfile> merged = <String, RemoteProfile>{};

    void publish() {
      if (generation != _generation) return;
      _emit(merged.values.toList(growable: false));
    }

    final List<StreamSubscription<List<RemoteProfile>>> subs =
        <StreamSubscription<List<RemoteProfile>>>[];

    void collect(
      Stream<List<RemoteProfile>> source,
      String label,
    ) {
      subs.add(
        source.listen(
          (List<RemoteProfile> profiles) {
            // Merge on uid: a person whose handle, name and tokens all match
            // must appear once, not three times. First writer wins, which is
            // why the handle stream is subscribed first.
            for (final RemoteProfile profile in profiles) {
              merged.putIfAbsent(profile.uid, () => profile);
            }
            publish();
          },
          onError: (Object error) =>
              debugPrint('Directory $label search failed: $error'),
        ),
      );
    }

    collect(
      _directory.search(
        query: RemoteContactService.normaliseUsername(value),
        field: 'username',
      ),
      'handle',
    );

    // Only worth a second query when the text could be a name — an
    // `@`-prefixed query is unambiguously a handle.
    if (!value.startsWith('@')) {
      collect(
        _directory.search(query: value, field: 'nameLowercase'),
        'name',
      );
      collect(
        _directory.searchByKeywords(token: value),
        'keyword',
      );
    }

    // A numeric query also gets an anchored range over the denormalised number,
    // which finds a profile whose number was never given an index document.
    if (kind == DirectoryQueryKind.phone) {
      collect(
        _directory.search(
          query: RemoteContactService.normalisePhone(value),
          field: 'phoneLower',
        ),
        'phone',
      );
    }

    // The streams are short-lived: cancelled as soon as the debounce window is
    // superseded, which keeps `search` from leaking listeners while the user is
    // still typing.
    for (final StreamSubscription<List<RemoteProfile>> sub in _active) {
      await sub.cancel();
    }
    _active = subs;
  }

  List<StreamSubscription<List<RemoteProfile>>> _active =
      <StreamSubscription<List<RemoteProfile>>>[];

  void _emit(List<RemoteProfile> profiles) {
    if (!_results.isClosed) _results.add(profiles);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    for (final StreamSubscription<List<RemoteProfile>> sub in _active) {
      await sub.cancel();
    }
    _active = <StreamSubscription<List<RemoteProfile>>>[];
    await _results.close();
  }
}
