import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/stream_retry.dart';

/// A profile that lives in the shared Imo LIVE directory (Firestore).
///
/// Deliberately separate from [Contact]: a [RemoteProfile] is *someone else's*
/// account, discovered by phone / email / @username / uid lookup, whereas a
/// [Contact] is an entry in the local user's own address book. They overlap
/// only in the fields a contact mirrors from the directory.
@immutable
class RemoteProfile {
  const RemoteProfile({
    required this.uid,
    required this.name,
    this.username = '',
    this.email = '',
    this.phone = '',
    this.bio = '',
    this.avatarUrl = '',
    this.coverUrl = '',
    this.isVerified = false,
    this.isOnline = false,
    this.lastSeen,
  });

  final String uid;
  final String name;
  final String username;
  final String email;
  final String phone;
  final String bio;
  final String avatarUrl;
  final String coverUrl;
  final bool isVerified;
  final bool isOnline;
  final DateTime? lastSeen;

  /// The handle shown under the name, e.g. `@imouser_042117`.
  String get handle => username.isEmpty ? '' : '@$username';

  bool get hasAvatar => avatarUrl.trim().isNotEmpty;

  String get initials {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final List<String> parts =
        trimmed.split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static RemoteProfile? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    return RemoteProfile(
      uid: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      username: (data['username'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim() ?? '',
      phone: (data['phone'] as String?)?.trim() ?? '',
      bio: (data['bio'] as String?)?.trim() ?? '',
      avatarUrl: (data['avatarUrl'] as String?)?.trim() ?? '',
      coverUrl: (data['coverUrl'] as String?)?.trim() ?? '',
      isVerified: data['isVerified'] as bool? ?? false,
      isOnline: data['isOnline'] as bool? ?? false,
      lastSeen: _readDate(data['lastSeen']),
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'name': name,
        'username': username,
        'email': email,
        'phone': phone,
        'bio': bio,
        'avatarUrl': avatarUrl,
        'coverUrl': coverUrl,
        'isVerified': isVerified,
        'isOnline': isOnline,
        'lastSeen': lastSeen?.toIso8601String(),
      };

  factory RemoteProfile.fromJson(Map<String, dynamic> json) => RemoteProfile(
        uid: json['uid'] as String? ?? '',
        name: json['name'] as String? ?? '',
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        bio: json['bio'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String? ?? '',
        coverUrl: json['coverUrl'] as String? ?? '',
        isVerified: json['isVerified'] as bool? ?? false,
        isOnline: json['isOnline'] as bool? ?? false,
        lastSeen: json['lastSeen'] == null
            ? null
            : DateTime.tryParse(json['lastSeen'] as String),
      );
}

/// Result of a directory lookup: either a real profile or an explicit miss.
@immutable
class LookupResult {
  const LookupResult.found(this.profile)
      : isFound = true,
        isUnavailable = false;
  const LookupResult.notFound()
      : profile = null,
        isFound = false,
        isUnavailable = false;

  /// Firestore could not be reached / is not configured. Callers show a
  /// neutral message instead of the "not on Imo LIVE" invite prompt, so a
  /// network blip is never mistaken for "this person has no account".
  const LookupResult.unavailable()
      : profile = null,
        isFound = false,
        isUnavailable = true;

  final RemoteProfile? profile;
  final bool isFound;
  final bool isUnavailable;
}

/// Real-time lookups against the shared Imo LIVE user directory.
///
/// The directory is indexed by four documents so each identifier resolves with
/// a single `get`, without a collection scan:
///
/// ```
/// users/{uid}                 the profile itself
/// usernames/{username}  -> uid
/// phones/{phoneNumber}  -> uid
/// emails/{email}        -> uid
/// ```
///
/// Every method is defensive: Firestore being unreachable (no network, no
/// Firebase project configured, missing rules) yields [LookupResult.unavailable]
/// rather than throwing into the widget tree.
class RemoteContactService {
  const RemoteContactService();

  static const String usersCollection = 'users';
  static const String usernamesCollection = 'usernames';
  static const String phonesCollection = 'phones';
  static const String emailsCollection = 'emails';

  FirebaseFirestore? get _db {
    try {
      return FirebaseFirestore.instance;
    } on Object {
      // Firebase was never initialised (e.g. a unit test without a project).
      return null;
    }
  }

  /// Canonical form used for the `phones/{number}` index.
  ///
  /// E.164 without the leading `+` is the natural, unambiguous key — it keeps
  /// the document id valid and makes `+880 1712…` and `8801712…` the same
  /// person.
  static String normalisePhone(String raw) {
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits;
  }

  /// Canonical form of [raw] **with the country code resolved**.
  ///
  /// Search has to accept the three shapes a person actually types for the same
  /// number, because each is a different string but only one is a `phones/{n}`
  /// document id:
  ///
  /// | typed            | resolved        | rule                        |
  /// | ---------------- | --------------- | --------------------------- |
  /// | `+8801712345678` | `8801712345678` | leading `+` → drop it       |
  /// | `8801712345678`  | `8801712345678` | already E.164 → as-is       |
  /// | `01712345678`    | `8801712345678` | national `0` → dial code    |
  ///
  /// [dialCode] is the caller's own country dial code without `+` (e.g. `880`).
  /// It is required — without it, `01712345678` cannot be told apart from a
  /// foreign number that merely starts with `0`, and guessing would silently
  /// send the lookup to the wrong person's profile.
  ///
  /// A number that already carries a country code is left alone: the national
  /// trunk `0` is never re-prefixed, which is what stops `017…` becoming
  /// `88088017…` when the caller's code is already `880`.
  static String resolvePhone(String raw, {required String dialCode}) {
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final String code = dialCode.replaceAll(RegExp(r'[^0-9]'), '');
    final bool startsWithPlus = raw.trimLeft().startsWith('+');

    // A leading `+` is an explicit, unambiguous country code — never rewrite it.
    if (startsWithPlus) return digits;

    // No country code on file: the digits are all we have, so use them as-is
    // rather than inventing a prefix.
    if (code.isEmpty) return digits;

    final String nationalTrunk = code.startsWith('0')
        ? code.substring(1)
        : code;

    // `0` + national number → the same number with the country code, trunk `0`
    // dropped. `01712345678` → `880` + `1712345678`.
    if (digits.startsWith('0')) {
      return '$nationalTrunk${digits.substring(1)}';
    }

    // Already carries the country code (`8801712…`) → leave it exactly as it is.
    if (digits.startsWith(nationalTrunk)) return digits;

    // A bare national number with no trunk prefix (`1712345678`) is the one
    // case that still needs the code glued on.
    return '$nationalTrunk$digits';
  }

  /// Canonical form used for the `emails/{email}` index.
  static String normaliseEmail(String raw) => raw.trim().toLowerCase();

  /// Canonical form used for the `usernames/{username}` index.
  static String normaliseUsername(String raw) =>
      raw.trim().toLowerCase().replaceAll('@', '');

  /// Resolves a registered profile for [phone], or reports a miss.
  Future<LookupResult> findByPhone(String phone) async {
    return _resolve(phonesCollection, normalisePhone(phone));
  }

  /// Resolves a registered profile for a number the user typed, applying the
  /// caller's country code when the number has none.
  ///
  /// Tries the resolved E.164 form first, then the bare digits, so a number
  /// stored without a country code still resolves. [dialCode] is the caller's
  /// own country dial code without `+` (e.g. `880`).
  Future<LookupResult> findByPhoneWithCountry(
    String phone, {
    required String dialCode,
  }) async {
    final String resolved = resolvePhone(phone, dialCode: dialCode);
    final String bare = normalisePhone(phone);

    final LookupResult asResolved = await _resolve(phonesCollection, resolved);
    if (asResolved.isFound || asResolved.isUnavailable) return asResolved;

    // Only worth a second read when the two forms differ — otherwise this is
    // the same `get` twice.
    if (bare.isNotEmpty && bare != resolved) {
      final LookupResult asBare = await _resolve(phonesCollection, bare);
      if (asBare.isFound || asBare.isUnavailable) return asBare;
    }
    return const LookupResult.notFound();
  }

  /// Resolves a registered profile for [email], or reports a miss.
  Future<LookupResult> findByEmail(String email) async {
    return _resolve(emailsCollection, normaliseEmail(email));
  }

  /// Resolves a registered profile for [username], or reports a miss.
  Future<LookupResult> findByUsername(String username) async {
    return _resolve(usernamesCollection, normaliseUsername(username));
  }

  /// Loads the profile document for a uid.
  Future<LookupResult> findByUid(String uid) async {
    final String id = uid.trim();
    if (id.isEmpty) return const LookupResult.notFound();
    final FirebaseFirestore? db = _db;
    if (db == null) return const LookupResult.unavailable();
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await db.collection(usersCollection).doc(id).get();
      final RemoteProfile? profile = RemoteProfile.fromDoc(doc);
      return profile == null
          ? const LookupResult.notFound()
          : LookupResult.found(profile);
    } on Object catch (error) {
      debugPrint('Directory lookup by uid failed: $error');
      return const LookupResult.unavailable();
    }
  }

  /// Resolves an identifier of unknown shape.
  ///
  /// This is what the smart search bar and the "New contact" phone field call:
  /// the caller does not have to know whether the user typed a phone number, an
  /// email, a `@handle` or a uid.
  ///
  /// [dialCode] is the caller's own country dial code without `+` (e.g. `880`),
  /// used only when [raw] is a number written without one — so `01712345678`
  /// resolves to the same person as `+8801712345678`. Pass an empty string to
  /// disable that resolution and treat the digits literally.
  Future<LookupResult> findByAnyIdentifier(
    String raw, {
    String dialCode = '',
  }) async {
    final String value = raw.trim();
    if (value.isEmpty) return Future<LookupResult>.value(const LookupResult.notFound());

    final bool looksLikeEmail = value.contains('@') && value.contains('.');
    if (looksLikeEmail) return findByEmail(value);

    // A leading `@` is always a handle, never a phone number.
    if (value.startsWith('@')) return findByUsername(value);

    final String digits = normalisePhone(value);
    // At least 6 digits and nothing else but separators ⇒ treat as a phone.
    if (digits.length >= 6 && RegExp(r'^[+0-9 ()\-]+$').hasMatch(value)) {
      final LookupResult byPhone = dialCode.isEmpty
          ? await findByPhone(digits)
          : await findByPhoneWithCountry(value, dialCode: dialCode);
      if (byPhone.isFound || byPhone.isUnavailable) return byPhone;
      return const LookupResult.notFound();
    }

    // Anything else: try the handle index, then a raw uid.
    final LookupResult byUsername = await findByUsername(value);
    if (byUsername.isFound || byUsername.isUnavailable) return byUsername;
    return findByUid(value);
  }

  /// Streams a live profile document, so verified badges, avatars and presence
  /// stay current while a screen is open.
  ///
  /// ⚠️ [retryStream] with an unbounded budget, not `handleError`. This backs
  /// the chat header and the profile page, so a swallowed error would freeze the
  /// other person's name, avatar and online dot on a stale reading for the rest
  /// of the session — with nothing on screen to say so.
  Stream<RemoteProfile?> watchProfile(String uid) {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.trim().isEmpty) {
      return Stream<RemoteProfile?>.value(null);
    }
    return retryStream<RemoteProfile?>(
      () => db
          .collection(usersCollection)
          .doc(uid.trim())
          .snapshots()
          .map(RemoteProfile.fromDoc),
      attempts: 0,
      onError: (Object error, int attempt) =>
          debugPrint('Watching profile $uid failed (attempt $attempt): $error'),
    );
  }

  /// Streams every directory profile whose [field] matches [prefix].
  ///
  /// Firestore has no `contains`, so smart search uses an anchored range query
  /// (`>= prefix` and `< prefix + \uf8ff`) — the standard prefix-search trick.
  /// It is served by the field index and returns matches in real time.
  ///
  /// Bounded retry: a caller replaces this stream on the next keystroke and
  /// already supplies an `onError`, so a transient blip is absorbed inside the
  /// debounce window while a permanent cause (a missing index) still reaches
  /// that handler instead of masquerading as "no results".
  Stream<List<RemoteProfile>> search({
    required String query,
    String field = 'username',
    int limit = 20,
  }) {
    final String prefix = query.trim().toLowerCase();
    final FirebaseFirestore? db = _db;
    if (db == null || prefix.isEmpty) {
      return Stream<List<RemoteProfile>>.value(const <RemoteProfile>[]);
    }
    return retryStream<List<RemoteProfile>>(
      () => db
          .collection(usersCollection)
          .where(field, isGreaterThanOrEqualTo: prefix)
          .where(field, isLessThan: '$prefix\uf8ff')
          .limit(limit)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map(RemoteProfile.fromDoc)
              .whereType<RemoteProfile>()
              .toList(growable: false)),
      onError: (Object error, int attempt) =>
          debugPrint('Directory search on $field failed (attempt $attempt): $error'),
    );
  }

  /// Streams every directory profile carrying [token] in `searchKeywords`.
  ///
  /// This is the closest thing Firestore offers to a substring search:
  /// `array-contains` over tokens that were materialised when the document was
  /// written — see `FirebaseAuthService.buildSearchKeywords`.
  ///
  /// It complements [search] rather than replacing it. The range query there
  /// requires the *entire field* to start with the text, so it finds a handle or
  /// a name from its beginning but nothing from the middle, and it can only look
  /// at one field at a time. Tokens are what make `tanv` find "Tanvir Ahmed" and
  /// what let one query span the name, the handle and the number together.
  ///
  /// Returns an empty stream for an empty token — `arrayContains` with `''`
  /// would match every document whose array happens to hold an empty string.
  Stream<List<RemoteProfile>> searchByKeywords({
    required String token,
    int limit = 20,
  }) {
    final String value = token.trim().toLowerCase();
    final FirebaseFirestore? db = _db;
    if (db == null || value.isEmpty) {
      return Stream<List<RemoteProfile>>.value(const <RemoteProfile>[]);
    }
    return retryStream<List<RemoteProfile>>(
      () => db
          .collection(usersCollection)
          .where('searchKeywords', arrayContains: value)
          .limit(limit)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map(RemoteProfile.fromDoc)
              .whereType<RemoteProfile>()
              .toList(growable: false)),
      onError: (Object error, int attempt) => debugPrint(
          'Directory keyword search for "$value" failed (attempt $attempt): $error'),
    );
  }

  /// Shared tail of the index-based lookups.
  Future<LookupResult> _resolve(String collection, String key) async {
    if (key.isEmpty) return const LookupResult.notFound();
    final FirebaseFirestore? db = _db;
    if (db == null) return const LookupResult.unavailable();
    try {
      final DocumentSnapshot<Map<String, dynamic>> index =
          await db.collection(collection).doc(key).get();
      final String? uid = index.data()?['uid'] as String?;
      if (uid == null || uid.isEmpty) return const LookupResult.notFound();
      return await findByUid(uid);
    } on Object catch (error) {
      debugPrint('Directory lookup in $collection/$key failed: $error');
      return const LookupResult.unavailable();
    }
  }
}
