import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/remote_contact_service.dart';

/// Which identifier the user typed into the smart search field.
///
/// Used only to steer the real-time Firestore query at the right index; the
/// result is always a list of real [RemoteProfile]s from the shared directory.
enum DirectoryQueryKind { phone, email, username, name, uid, unknown }

/// Where a search hit came from, which is what the row badge reports.
///
/// This is deliberately *not* derived from the profile: the same person is
/// "in your contacts" on one device and "on Imo LIVE" on another, and the user
/// is asking about *this* device's address book.
enum SearchResultSource {
  /// The person is already saved in the local contact list.
  contact,

  /// A registered Imo LIVE account that is not a saved contact.
  directory,
}

/// One search hit: a directory profile plus how it was found.
///
/// [localName] is the address-book name when the person is a saved contact —
/// it is what the user actually recognises, so it takes precedence over the
/// directory `name` for display. [source] drives the badge.
@immutable
class DirectoryHit {
  const DirectoryHit({
    required this.profile,
    required this.source,
    this.localName = '',
    this.relevance = 0,
  });

  final RemoteProfile profile;
  final SearchResultSource source;

  /// The saved contact's display name, or empty when this is a directory hit.
  final String localName;

  /// Higher sorts first. Exact match beats prefix, prefix beats partial.
  final int relevance;

  bool get isContact => source == SearchResultSource.contact;

  /// The name to render — the address-book name wins when there is one.
  String get displayName {
    if (localName.trim().isNotEmpty) return localName.trim();
    if (profile.name.trim().isNotEmpty) return profile.name.trim();
    return profile.handle;
  }
}

/// Ranks a hit against the query.
///
/// The bands are deliberately coarse and separated by 100 so a later addition
/// can slot a new band in without renumbering:
///
/// * `300` — the whole query matches the value exactly
/// * `200` — the value starts with the query (the "typing a prefix" case)
/// * `100` — the query appears somewhere inside the value
/// * `0`   — no textual match (kept last, never dropped)
///
/// Saved contacts get a small, bounded bonus so that a contact and a stranger
/// with the same name surface the contact first — but never enough to lift a
/// partial contact match above an exact directory match.
int scoreHit({
  required String query,
  required String name,
  required String username,
  required String phone,
  required bool isContact,
}) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return isContact ? 1 : 0;

  int best = 0;
  for (final String raw in <String>[name, username, phone]) {
    final String value = raw.trim().toLowerCase();
    if (value.isEmpty) continue;
    int score;
    if (value == q) {
      score = 300;
    } else if (value.startsWith(q)) {
      score = 200;
    } else if (value.contains(q)) {
      score = 100;
    } else {
      continue;
    }
    if (score > best) best = score;
  }
  // The contact bonus is < the 100-point band gap, so it only ever breaks ties.
  return best + (isContact ? 50 : 0);
}

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
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return DirectoryQueryKind.email;
    }
    // A number in any of the shapes a person types: `+8801712345678`,
    // `8801712345678`, `01712345678`, or the same with spaces/dashes/parentheses.
    // The 6-digit floor keeps a short numeric handle from being read as a phone.
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
    // A plain word: could be a display name or a handle, so both are searched.
    return DirectoryQueryKind.name;
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

  /// Merges directory hits with the caller's own address book.
  ///
  /// The address book is queried locally (no network, no cost) and the
  /// directory over Firestore; a person can appear in both, so the two lists
  /// are deduped on uid with the **contact record winning** — it carries the
  /// name the user saved, and that beats whatever the person calls themselves.
  ///
  /// [contacts] is a list of `(uid, name, phone, username)` tuples, kept
  /// untyped-free so this service does not depend on the `Contact` model. A
  /// contact is matched against the query on any of those fields.
  ///
  /// The result is sorted by [scoreHit] descending, ties broken by display name
  /// so the order is stable between rebuilds.
  static List<DirectoryHit> mergeWithContacts({
    required String query,
    required List<RemoteProfile> directoryProfiles,
    required List<({String uid, String name, String phone, String username})>
        contacts,
    required List<RemoteProfile> contactProfiles,
  }) {
    final Map<String, DirectoryHit> byUid = <String, DirectoryHit>{};

    // Directory first...
    for (final RemoteProfile profile in directoryProfiles) {
      byUid[profile.uid] = DirectoryHit(
        profile: profile,
        source: SearchResultSource.directory,
        relevance: scoreHit(
          query: query,
          name: profile.name,
          username: profile.username,
          phone: profile.phone,
          isContact: false,
        ),
      );
    }

    // ...then overwrite with the contact view, which always wins.
    for (final RemoteProfile profile in contactProfiles) {
      final ({String uid, String name, String phone, String username})? entry =
          _contactFor(profile.uid, contacts);
      final String localName = entry?.name ?? '';
      byUid[profile.uid] = DirectoryHit(
        profile: profile,
        source: SearchResultSource.contact,
        localName: localName,
        relevance: scoreHit(
          query: query,
          name: localName.isNotEmpty ? localName : profile.name,
          username: profile.username,
          phone: profile.phone,
          isContact: true,
        ),
      );
    }

    final List<DirectoryHit> hits = byUid.values.toList()
      ..sort((DirectoryHit a, DirectoryHit b) {
        final int byScore = b.relevance.compareTo(a.relevance);
        if (byScore != 0) return byScore;
        return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
      });
    return hits;
  }

  static ({String uid, String name, String phone, String username})? _contactFor(
    String uid,
    List<({String uid, String name, String phone, String username})> contacts,
  ) {
    for (final ({String uid, String name, String phone, String username}) c
        in contacts) {
      if (c.uid == uid) return c;
    }
    return null;
  }

  /// Debounces [query] and then resolves it.
  ///
  /// Every call supersedes the previous one, so a fast typist never sees the
  /// results of an abandoned prefix.
  ///
  /// [dialCode] is the caller's own country dial code without `+` (e.g. `880`),
  /// used to resolve a number typed without one (`01712345678`). It is read
  /// once per search rather than per keystroke, so a country change mid-query
  /// is picked up on the next keystroke.
  void search(String query, {String dialCode = ''}) {
    _timer?.cancel();
    _dialCode = dialCode;
    final String value = query.trim();
    if (value.isEmpty) {
      _generation++;
      _emit(const <RemoteProfile>[]);
      return;
    }
    _timer = Timer(debounce, () => _run(value));
  }

  String _dialCode = '';

  Future<void> _run(String value) async {
    final int generation = ++_generation;
    final DirectoryQueryKind kind = kindOf(value);

    // An exact identifier resolves to at most one person — a direct index hit.
    if (kind != DirectoryQueryKind.username && kind != DirectoryQueryKind.name) {
      final LookupResult result =
          await _directory.findByAnyIdentifier(value, dialCode: _dialCode);
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
    //
    // The prefix is the *resolved* number when the caller's country code is
    // known, so `0171…` finds the same rows as `+880171…`; the bare digits are
    // searched as well because older documents were written without a code.
    if (kind == DirectoryQueryKind.phone) {
      final String resolved = _dialCode.isEmpty
          ? RemoteContactService.normalisePhone(value)
          : RemoteContactService.resolvePhone(value, dialCode: _dialCode);
      collect(
        _directory.search(query: resolved, field: 'phoneLower'),
        'phone',
      );
      final String bare = RemoteContactService.normalisePhone(value);
      if (bare.isNotEmpty && bare != resolved) {
        collect(
          _directory.search(query: bare, field: 'phoneLower'),
          'phone-bare',
        );
      }
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
