import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';

/// Thin, typed wrapper around Hive.
///
/// The app stores every collection as a JSON-encoded list inside a single Hive
/// box. This keeps the schema flexible (models evolve without migrations) while
/// still giving us a durable, offline-first store. Binary media is never placed
/// here — only file paths produced by [FileStorageService].
class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  bool _ready = false;
  bool _degraded = false;
  final Set<String> _openBoxes = <String>{};

  /// The in-flight [init] call, so concurrent callers share one attempt.
  Future<void>? _initializing;

  /// Upper bound on `Hive.initFlutter`.
  ///
  /// This call awaits `path_provider`'s
  /// `getApplicationDocumentsDirectory()`. When that platform channel never
  /// answers — a missing plugin, a wedged call — the future simply never
  /// completes. Without a ceiling here, `init()` never returns, startup never
  /// finishes, and the app hangs before its first frame: the black screen.
  /// Storage is a convenience, so a timeout is always the right answer.
  static const Duration _initTimeout = Duration(seconds: 3);

  /// Upper bound on opening a single box.
  ///
  /// Reaching this means `Hive.initFlutter` succeeded but one file is wedged;
  /// degrading that one collection is far better than blocking the app.
  static const Duration _boxTimeout = Duration(milliseconds: 800);

  /// Directory name used for the local store.
  static const String _storageDir = 'imo_live';

  /// Every box the app needs, in startup order.
  static const List<String> _allBoxes = <String>[
    AppConstants.boxSettings,
    AppConstants.boxChats,
    AppConstants.boxMessages,
    AppConstants.boxContacts,
    AppConstants.boxGroups,
    AppConstants.boxCommunities,
    AppConstants.boxChannels,
    AppConstants.boxStatuses,
    AppConstants.boxCalls,
    AppConstants.boxProfile,
    AppConstants.boxMisc,
  ];

  bool get isReady => _ready;

  /// True when at least one box failed to open.
  ///
  /// The app stays usable in this state but the Settings screen surfaces a
  /// warning, because writes to a missing box would otherwise be lost.
  bool get isDegraded => _degraded;

  /// Names of the boxes that could not be opened.
  Set<String> get unavailableBoxes =>
      _allBoxes.where((String b) => !_openBoxes.contains(b)).toSet();

  /// Opens every box the app needs.
  ///
  /// Safe to call more than once and from several places at once: concurrent
  /// callers share a single attempt, and a finished attempt is never repeated.
  ///
  /// This method is guaranteed to **complete**. Every awaited platform call is
  /// bounded by a timeout, and every failure degrades the store instead of
  /// propagating — a hung storage layer must never be able to stop the app
  /// from drawing its first frame.
  Future<void> init() {
    if (_ready) return Future<void>.value();
    // Reuse the in-flight attempt so `main()`-era and in-app callers cannot
    // race each other into opening the same box twice.
    return _initializing ??= _initGuarded().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initGuarded() async {
    try {
      await Hive.initFlutter(_storageDir).timeout(_initTimeout);
    } on TimeoutException {
      // The exact bug that produced a permanently black screen: this await
      // never returned. Reported distinctly so it is obvious in `adb logcat`.
      debugPrint(
        'Hive.initFlutter did not respond within ${_initTimeout.inSeconds}s '
        '(path_provider platform call never completed). '
        'Continuing without local storage.',
      );
      _degraded = true;
      return;
    } on Object catch (error, stack) {
      debugPrint('Hive.initFlutter failed: $error\n$stack');
      // Without a storage directory not even the settings box can open. Leave
      // `_ready` false so a later retry is possible, and let startup continue.
      _degraded = true;
      return;
    }

    for (final String box in _allBoxes) {
      await _openBox(box, allowRecovery: true);
    }

    _ready = true;
  }

  /// Opens a single box, recovering from a corrupt file when asked to.
  ///
  /// Never throws: `Hive.isBoxOpen` raises a [HiveError] (an `Error`, not an
  /// `Exception`) when Hive was never initialised, and an unguarded call would
  /// escape `init()` and abort startup.
  Future<void> _openBox(String name, {required bool allowRecovery}) async {
    if (_openBoxes.contains(name)) return;

    try {
      if (Hive.isBoxOpen(name)) {
        _openBoxes.add(name);
        return;
      }
    } on Object catch (error) {
      debugPrint('Hive is not initialised, cannot open "$name": $error');
      _degraded = true;
      return;
    }

    try {
      await Hive.openBox<dynamic>(name).timeout(_boxTimeout);
      _openBoxes.add(name);
    } on Object catch (error) {
      debugPrint('Hive box "$name" failed to open: $error');

      if (!allowRecovery) {
        _degraded = true;
        return;
      }

      // Most common real-device cause: a partially written box file. Deleting
      // it loses that collection's data, which is strictly better than an app
      // that cannot start, so retry once from a clean file.
      try {
        await Hive.deleteBoxFromDisk(name).timeout(_boxTimeout);
        await Hive.openBox<dynamic>(name).timeout(_boxTimeout);
        _openBoxes.add(name);
        debugPrint('Hive box "$name" recovered after reset.');
      } on Object catch (retryError) {
        debugPrint('Hive box "$name" unrecoverable: $retryError');
        _degraded = true;
      }
    }
  }

  /// Retries boxes that are still unavailable. Used by the Settings screen when
  /// the user taps "Retry" on the storage warning.
  Future<bool> retryUnavailable() async {
    if (!_ready) await init();
    for (final String name in unavailableBoxes.toList()) {
      await _openBox(name, allowRecovery: false);
    }
    return unavailableBoxes.isEmpty;
  }

  /// Returns the box, or `null` when it is not open.
  ///
  /// Callers that can degrade gracefully should prefer this over [box]; it
  /// turns "storage is unavailable" into an empty result instead of a crash.
  Box<dynamic>? maybeBox(String name) {
    if (!_openBoxes.contains(name) || !Hive.isBoxOpen(name)) return null;
    return Hive.box<dynamic>(name);
  }

  Box<dynamic> box(String name) {
    final Box<dynamic>? target = maybeBox(name);
    if (target == null) {
      throw StateError(
        'Hive box "$name" is not open. Call LocalDatabase.instance.init() first.',
      );
    }
    return target;
  }

  // ------------------------------------------------------------- primitives
  //
  // Reads return empty/null and writes become no-ops when a box is
  // unavailable. Storage problems must degrade the app, never break it: a
  // missing box means "no saved data yet", not a crash on the home screen.

  Future<void> writeString(String boxName, String key, String value) async =>
      maybeBox(boxName)?.put(key, value);

  String? readString(String boxName, String key) {
    final Object? value = maybeBox(boxName)?.get(key);
    return value is String ? value : null;
  }

  Future<void> writeBool(String boxName, String key, bool value) async =>
      maybeBox(boxName)?.put(key, value);

  bool? readBool(String boxName, String key) {
    final Object? value = maybeBox(boxName)?.get(key);
    return value is bool ? value : null;
  }

  Future<void> writeInt(String boxName, String key, int value) async =>
      maybeBox(boxName)?.put(key, value);

  int? readInt(String boxName, String key) {
    final Object? value = maybeBox(boxName)?.get(key);
    return value is int ? value : (value is num ? value.toInt() : null);
  }

  Future<void> writeDouble(String boxName, String key, double value) async =>
      maybeBox(boxName)?.put(key, value);

  double? readDouble(String boxName, String key) {
    final Object? value = maybeBox(boxName)?.get(key);
    return value is num ? value.toDouble() : null;
  }

  Future<void> writeJson(
    String boxName,
    String key,
    Map<String, dynamic> value,
  ) async =>
      maybeBox(boxName)?.put(key, jsonEncode(value));

  Map<String, dynamic>? readJson(String boxName, String key) {
    final String? raw = readString(boxName, key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    } on Object {
      return null;
    }
  }

  /// Stores a list of models as one JSON array under [key].
  Future<void> writeList<T>(
    String boxName,
    String key,
    List<T> items,
    Map<String, dynamic> Function(T) encode,
  ) async =>
      maybeBox(boxName)?.put(key, jsonEncode(items.map(encode).toList()));

  /// Reads a JSON array back into models.
  ///
  /// A single malformed entry is skipped rather than discarding the whole
  /// collection — otherwise one bad record saved by an older build would blank
  /// out the entire chat list.
  List<T> readList<T>(
    String boxName,
    String key,
    T Function(Map<String, dynamic>) decode,
  ) {
    final String? raw = readString(boxName, key);
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      final List<T> items = <T>[];
      for (final Object? entry in decoded) {
        if (entry is! Map) continue;
        try {
          items.add(decode(Map<String, dynamic>.from(entry)));
        } on Object catch (error) {
          debugPrint('Skipping malformed record in "$boxName/$key": $error');
        }
      }
      return items;
    } on FormatException {
      return <T>[];
    } on Object {
      return <T>[];
    }
  }

  Future<void> delete(String boxName, String key) async =>
      maybeBox(boxName)?.delete(key);

  Future<void> clearBox(String boxName) async => maybeBox(boxName)?.clear();

  /// Wipes every user-data box. Used by Settings → Delete account (local).
  Future<void> clearAll() async {
    for (final String name in <String>[
      AppConstants.boxChats,
      AppConstants.boxMessages,
      AppConstants.boxContacts,
      AppConstants.boxGroups,
      AppConstants.boxCommunities,
      AppConstants.boxChannels,
      AppConstants.boxStatuses,
      AppConstants.boxCalls,
      AppConstants.boxMisc,
    ]) {
      await clearBox(name);
    }
  }

  /// Wipes **every** box, including the settings and profile boxes.
  ///
  /// This is the sign-out path, and it is deliberately wider than [clearAll].
  /// The reported bug was the previous account's chats, contacts, profile and
  /// phone number still being on screen after signing in as somebody else, and
  /// the cause was that nothing local was cleared at all. Clearing only the
  /// "content" boxes would have fixed the visible half and left the profile box
  /// — which holds the signed-in user's own name, phone and avatar — as the
  /// next leak.
  ///
  /// The cost is that device-level preferences (theme, language, wallpaper)
  /// reset to their defaults on sign-out. That is a real regression, and it is
  /// accepted on purpose: this app has no per-device preference store separate
  /// from the per-user one, so keeping the settings box is keeping a slice of
  /// the previous account.
  ///
  /// Boxes are cleared rather than deleted from disk so they stay open for the
  /// next account and no caller has to re-run [init].
  Future<void> clearUserData() async {
    for (final String name in _allBoxes) {
      await clearBox(name);
    }
  }

  /// Rough on-disk footprint of the key-value store, in bytes.
  int estimateBytes() {
    int total = 0;
    for (final String name in _allBoxes) {
      final Box<dynamic>? target = maybeBox(name);
      if (target == null) continue;
      for (final Object? value in target.values) {
        if (value is String) {
          total += value.length * 2;
        } else if (value is num || value is bool) {
          total += 8;
        }
      }
    }
    return total;
  }
}
