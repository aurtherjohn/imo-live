import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Localization parity guard.
///
/// The app ships two locales — English (`app_en.arb`) and বাংলা (`app_bn.arb`).
/// A key that exists in only one of them is a real runtime defect: the missing
/// locale silently falls back (or renders an empty string) on a user's device.
/// These tests pin the invariant "every key exists in BOTH files", plus the
/// placeholder/type contract between them.
void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> bn;

  /// Translation keys only — ARB metadata entries are prefixed with `@`.
  Set<String> keysOf(Map<String, dynamic> arb) =>
      arb.keys.where((String k) => !k.startsWith('@')).toSet();

  setUpAll(() {
    en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    bn = jsonDecode(File('lib/l10n/app_bn.arb').readAsStringSync())
        as Map<String, dynamic>;
  });

  group('ARB files', () {
    test('both locale files exist and parse as JSON objects', () {
      expect(File('lib/l10n/app_en.arb').existsSync(), isTrue);
      expect(File('lib/l10n/app_bn.arb').existsSync(), isTrue);
      expect(en, isNotEmpty);
      expect(bn, isNotEmpty);
    });

    test('declare the expected @@locale marker', () {
      expect(en['@@locale'], 'en');
      expect(bn['@@locale'], 'bn');
    });
  });

  group('key parity', () {
    test('every English key exists in বাংলা', () {
      final Set<String> missing = keysOf(en).difference(keysOf(bn));
      expect(
        missing,
        isEmpty,
        reason: 'missing from app_bn.arb: ${missing.toList()..sort()}',
      );
    });

    test('every বাংলা key exists in English', () {
      final Set<String> extra = keysOf(bn).difference(keysOf(en));
      expect(
        extra,
        isEmpty,
        reason: 'not present in app_en.arb: ${extra.toList()..sort()}',
      );
    });

    test('the two key sets are exactly equal', () {
      expect(keysOf(bn), equals(keysOf(en)));
    });
  });

  group('translation values', () {
    test('no key maps to an empty or whitespace-only string', () {
      for (final MapEntry<String, dynamic> entry in <String, dynamic>{
        ...en,
        ...bn,
      }.entries) {
        if (entry.key.startsWith('@')) continue;
        expect(entry.value, isA<String>(), reason: '${entry.key} is not a String');
        expect(
          (entry.value as String).trim(),
          isNotEmpty,
          reason: '${entry.key} has an empty translation',
        );
      }
    });

    test('both locales declare the same placeholder names per key', () {
      final RegExp placeholder = RegExp(r'\{([a-zA-Z0-9_]+)\}');

      for (final String key in keysOf(en)) {
        Set<String> namesIn(Object? value) {
          if (value is! String) return <String>{};
          return placeholder
              .allMatches(value)
              .map((RegExpMatch m) => m.group(1)!)
              .toSet();
        }

        expect(
          namesIn(bn[key]),
          equals(namesIn(en[key])),
          reason: 'placeholder mismatch for "$key"',
        );
      }
    });

    test('a spot check of critical strings is actually translated', () {
      // Guard against a copy-paste of the English file into the বাংলা one.
      // (Brand strings such as `appName` are intentionally identical in both
      // locales, so they are not part of this check.)
      expect(bn['tabChats'], isNot(equals(en['tabChats'])));
      expect(bn['settings'], isNot(equals(en['settings'])));
      expect(bn['search'], isNot(equals(en['search'])));
      expect(bn['cancel'], isNot(equals(en['cancel'])));
    });
  });

  group('generated localizations', () {
    late String generated;
    late String enImpl;
    late String bnImpl;

    setUpAll(() {
      generated = File('lib/l10n/app_localizations.dart').readAsStringSync();
      enImpl = File('lib/l10n/app_localizations_en.dart').readAsStringSync();
      bnImpl = File('lib/l10n/app_localizations_bn.dart').readAsStringSync();
    });

    /// How many placeholders the template ARB declares for [key].
    int arityOf(String key) {
      final Object? meta = en['@$key'];
      final Object? placeholders = meta is Map ? meta['placeholders'] : null;
      return placeholders is Map ? placeholders.length : 0;
    }

    /// True when [source] declares [key] with the arity the ARB implies.
    ///
    /// A key with no placeholders is generated as a plain getter
    /// (`String get settings;`); one with placeholders is generated as a
    /// *method* (`String countSelected(int count);`). Asserting on
    /// `String get $key;` alone therefore fails for every placeholder key —
    /// which is exactly what happened when the interpolated strings were
    /// converted. Deriving the expected shape from the ARB also checks the
    /// parameter count, so a metadata block that silently loses a placeholder
    /// is caught here rather than at a call site.
    bool declaresKey(String source, String key) {
      final int arity = arityOf(key);
      final RegExp re = RegExp(
        'String (?:get )?${RegExp.escape(key)}'
        r'(?:\(([^)]*)\))?'
        r'(?![A-Za-z0-9_])',
      );
      final Match? match = re.firstMatch(source);
      if (match == null) return false;
      final String? args = match.group(1);
      if (arity == 0) {
        return args == null && match.group(0)!.contains('get ');
      }
      if (args == null) return false;
      // `dart format` leaves a trailing comma in a parameter list it had to
      // split across lines, so `'a, b,'.split(',').length` is 3, not 2. Counting
      // empty segments made the longest message in the ARB look as though it
      // declared the wrong number of parameters.
      final List<String> params = args
          .split(',')
          .map((String p) => p.trim())
          .where((String p) => p.isNotEmpty)
          .toList();
      return params.length == arity;
    }

    test('the declaration check is not vacuous', () {
      // A helper that always returned true would make the two tests above
      // meaningless, so pin both directions explicitly.
      expect(declaresKey(generated, 'thisKeyDoesNotExist'), isFalse);
      expect(declaresKey('', 'settings'), isFalse);
      // Right name, wrong arity.
      expect(
        declaresKey('String pollGoingMaybe(int a);', 'pollGoingMaybe'),
        isFalse,
      );
      // A getter where the ARB says there are placeholders.
      expect(
        declaresKey('String get pollGoingMaybe;', 'pollGoingMaybe'),
        isFalse,
      );
      // A method where the ARB says there are none.
      expect(declaresKey('String settings(int a);', 'settings'), isFalse);
    });

    test('the generated base class declares every key', () {
      for (final String key in keysOf(en)) {
        expect(
          declaresKey(generated, key),
          isTrue,
          reason: 'generated AppLocalizations has no getter or method for "$key"',
        );
      }
    });

    test('both generated locale implementations override every key', () {
      for (final String key in keysOf(en)) {
        expect(
          declaresKey(enImpl, key),
          isTrue,
          reason: 'AppLocalizationsEn does not implement "$key"',
        );
        expect(
          declaresKey(bnImpl, key),
          isTrue,
          reason: 'AppLocalizationsBn does not implement "$key"',
        );
      }
    });
  });
}
