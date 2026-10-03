import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical helper for Firestore timestamps.
///
/// Every timestamp written to Firestore **must** come from [now] — never from
/// `DateTime.now()`. A client clock is user-controlled: a device set an hour
/// fast reorders every chat for both participants, and a device set a day fast
/// expires or un-expires a status for every reader. `FieldValue.serverTimestamp`
/// is resolved by Firestore itself, so ordering is monotonic across devices.
///
/// The only legitimate use of a client clock is *display* formatting and the
/// optimistic local echo of a message that has not round-tripped yet.
///
/// Reading is the mirror image: a value that came back from Firestore may be a
/// [Timestamp] (the normal case), or — before the server resolves it — `null`
/// on a local snapshot. Use [toLocal] to convert, and [resolve] when the field
/// might also be a raw `String`/`int` because it was written by an older build.
class FirebaseTime {
  const FirebaseTime._();

  /// The value to store: resolved by the server, never by this device.
  static FieldValue now() => FieldValue.serverTimestamp();

  /// Converts a stored Firestore value into a local [DateTime].
  ///
  /// Returns null when the server has not resolved the sentinel yet, which is
  /// exactly what a local snapshot of a just-written document looks like. A
  /// caller that needs to show *something* immediately should fall back to
  /// `DateTime.now()` for display only.
  static DateTime? toLocal(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      // Firestore also accepts a plain epoch-millis int.
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Like [toLocal], but never returns null — falls back to the local clock.
  ///
  /// For display only. Never write the result back to Firestore.
  static DateTime display(Object? value) => toLocal(value) ?? DateTime.now();
}
