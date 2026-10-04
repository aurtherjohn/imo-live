import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../local/database/local_database.dart';

/// Wipes every trace of the signed-out account from this device.
///
/// ### Why this exists
///
/// Signing out used to do exactly one thing — `FirebaseAuth.signOut()` — and
/// leave everything else in place. The next account to sign in on the same
/// device therefore inherited the previous account's chat list, messages,
/// contacts, profile (name, phone, avatar) and call history, because all of
/// those live in a fixed set of Hive boxes and a Firestore offline cache that
/// are shared by whoever is signed in. That is the reported "data is mixing"
/// bug, and it is a privacy defect, not a cosmetic one: a phone number shown
/// under the wrong account is somebody else's personal data.
///
/// ### What it clears, and what it cannot
///
/// * **Hive** — every box, via [LocalDatabase.clearUserData]. Cleared rather
///   than deleted so the boxes stay open for the next account.
/// * **SharedPreferences** — every key. Nothing in the app writes account data
///   there today, but a plugin can (Firebase Auth's session hint, for one), and
///   leaving a store untouched because "we do not use it" is how the next
///   plugin silently leaks.
/// * **Firestore offline cache** — terminated and cleared. The cache is keyed
///   by document path, not by user, so a cached `chats/{id}` from the previous
///   account can be served to the next one.
/// * **In-memory image cache** — the decoded bitmap cache, plus the live-image
///   cache. Avatars and chat media from the previous account would otherwise
///   keep rendering from memory after the wipe.
///
/// It deliberately does **not** touch `CachedNetworkImage`'s on-disk cache.
/// That cache is keyed by URL, so it can only ever return the exact image a URL
/// points at — it cannot surface one account's private file under another's.
/// Wiping it would cost every user a re-download of every avatar for no
/// isolation benefit. If that reasoning ever stops holding, this is the place
/// to add it.
///
/// ### What the caller still has to do
///
/// Clearing storage is not enough on its own: the repository and notifier
/// providers hold **in-memory** copies that were loaded from those boxes and
/// will happily keep serving them. The caller must invalidate them — see
/// `AuthController.signOut`, which is the only supported entry point.
class SessionReset {
  const SessionReset._();

  /// Runs the whole wipe. Never throws: every step is best-effort and logged,
  /// because a failure to clear one store must not leave the user stuck
  /// signed in.
  static Future<void> wipeLocalData() async {
    await _clearHive();
    await _clearPreferences();
    await _clearFirestoreCache();
    _clearImageCaches();
  }

  static Future<void> _clearHive() async {
    try {
      await LocalDatabase.instance.clearUserData();
    } on Object catch (error) {
      debugPrint('Session reset: Hive clear failed: $error');
    }
  }

  static Future<void> _clearPreferences() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } on Object catch (error) {
      debugPrint('Session reset: SharedPreferences clear failed: $error');
    }
  }

  /// Terminates the Firestore client and drops its on-disk cache.
  ///
  /// ⚠️ `clearPersistence()` is documented as only valid *before* the client has
  /// been used, and it throws otherwise. `terminate()` first is what makes it
  /// legal here — the client is shut down, so the cache is not in use. The
  /// default instance re-initialises itself on the next call, so Firestore
  /// keeps working for the account that signs in next.
  ///
  /// Both calls are wrapped: on a device where either is refused, the session
  /// still ends, and the stale-cache risk is reported rather than swallowed.
  static Future<void> _clearFirestoreCache() async {
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      await db.terminate();
      await db.clearPersistence();
    } on Object catch (error) {
      debugPrint('Session reset: Firestore cache clear failed: $error');
    }
  }

  static void _clearImageCaches() {
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    } on Object catch (error) {
      debugPrint('Session reset: image cache clear failed: $error');
    }
  }
}
