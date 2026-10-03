/// Tolerant readers for values coming back out of Firestore.
///
/// ### Why these exist
///
/// Firestore has no schema, so a field's runtime type is whatever the last
/// writer put there — an older build, a console edit, a migration or a bug can
/// all leave a number stored as a string or a date stored as a raw epoch.
///
/// The obvious cast is also the dangerous one:
///
/// ```dart
/// (data['points'] as num?)?.toInt() ?? 0   // throws on '100'
/// ```
///
/// `as num?` yields null only for null. For a string it throws a
/// [TypeError] — inside a build method that is a red screen, and inside a
/// `runTransaction` it aborts the whole transaction. A zero, or a null date, is
/// almost always a better answer than either.
///
/// Use these for anything read out of Firestore. The `fromJson` methods that
/// read the local Hive mirror can keep their casts: this app wrote those values
/// and controls their shape.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Coerces a Firestore value into an `int`.
///
/// Accepts an int, a double, a numeric string, or null. Anything else is 0.
int asInt(Object? value) => switch (value) {
      null => 0,
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value.trim()) ?? 0,
      _ => 0,
    };

/// Coerces a Firestore value into a `double`.
double asDouble(Object? value) => switch (value) {
      null => 0,
      num() => value.toDouble(),
      String() => double.tryParse(value.trim()) ?? 0,
      _ => 0,
    };

/// Coerces a Firestore value into a [DateTime].
///
/// Server timestamps arrive as [Timestamp]; a write that has not yet been
/// acknowledged locally can arrive as an epoch int. Returns null for anything
/// else — a fabricated "now" would misreport when something happened, which is
/// worse than showing nothing.
DateTime? asDate(Object? value) => switch (value) {
      Timestamp() => value.toDate(),
      DateTime() => value,
      int() => DateTime.fromMillisecondsSinceEpoch(value),
      String() => DateTime.tryParse(value),
      _ => null,
    };

/// Coerces a Firestore value into a `bool`. Only `true` is true.
bool asBool(Object? value) => value == true;

/// Coerces a Firestore value into a trimmed `String`. Anything else is empty.
String asString(Object? value) => switch (value) {
      String() => value.trim(),
      null => '',
      _ => value.toString(),
    };

/// Reads a nested map, or an empty one when the field is absent or the wrong
/// shape — so a caller can index into the result without a null check.
Map<String, dynamic> asMap(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

/// Reads a list, or an empty one. Elements keep their original type, so callers
/// should `whereType` before using them.
List<Object?> asList(Object? value) => value is List ? value : <Object?>[];
