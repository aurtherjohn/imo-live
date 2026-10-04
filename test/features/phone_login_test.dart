import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/constants/app_constants.dart';
import 'package:imo_live/core/models/country.dart';
import 'package:imo_live/core/services/firebase_auth_service.dart';
import 'package:imo_live/features/auth/presentation/auth_providers.dart';
import 'package:imo_live/features/auth/presentation/screens/phone_login_screen.dart';
import 'package:imo_live/features/auth/presentation/widgets/auth_widgets.dart';

/// Guards the phone sign-in flow.
///
/// Three things are being pinned here, none of which the compiler can check:
///
/// 1. **The derived address is a fixed contract.** It is computed in two places
///    that must agree — signup writes it, login recomputes it — and if they ever
///    drift, every phone account becomes unreachable with no error to explain
///    why. It is also what a signed-out login depends on, since the rules deny a
///    signed-out Firestore read.
/// 2. **The country table parses.** It is a 250-row string, and a single
///    malformed row would silently drop a country rather than fail.
/// 3. **The screen lays out.** It is the one thing a build cannot prove and this
///    environment cannot run: the phone field puts the country selector in the
///    `prefixIcon` slot, which is a constrained layout — an unbounded or
///    overflowing child there is a red screen at runtime and nothing at all at
///    compile time.
void main() {
  group('Countries', () {
    test('the table parses and covers the world', () {
      expect(Countries.all.length, greaterThan(200));
      // Every row survived the split; a malformed line is dropped silently, so
      // a short table is the only symptom it would ever produce.
      expect(
        Countries.all.every((Country c) => c.isoCode.length == 2),
        isTrue,
        reason: 'every country must carry a two-letter ISO code',
      );
      expect(
        Countries.all.every((Country c) =>
            c.name.isNotEmpty && RegExp(r'^\d+$').hasMatch(c.dialCode)),
        isTrue,
        reason: 'every country must have a name and a digits-only dial code',
      );
    });

    test('Bangladesh is present and is the default', () {
      final Country? bd = Countries.byIso('BD');
      expect(bd, isNotNull);
      expect(bd!.dialCode, '880');
      expect(bd.dial, '+880');
      expect(Countries.defaultCountry.isoCode, 'BD');
    });

    test('flags are derived from the ISO code', () {
      // Two regional indicator symbols ligate into the flag; there is no image
      // asset behind this, so a wrong offset shows as tofu rather than a
      // missing file.
      expect(flagEmoji('BD'), '\u{1F1E7}\u{1F1E9}');
      expect(flagEmoji('us'), '\u{1F1FA}\u{1F1F8}');
      expect(flagEmoji(''), '');
      expect(flagEmoji('XYZ'), '');
    });

    test('search finds a country by name, code and dial code', () {
      expect(Countries.search('bang').first.isoCode, 'BD');
      expect(Countries.search('BD').first.isoCode, 'BD');
      expect(Countries.search('880').first.isoCode, 'BD');
      // A prefix match outranks an interior one: `ind` must not surface
      // Trinidad and Tobago first.
      expect(Countries.search('ind').first.name, 'India');
    });

    test('a query with no letters does not match everything', () {
      // The dial-code branch is gated on the query actually containing digits,
      // or `contains` would match half the table for a one-letter query.
      final List<Country> results = Countries.search('zzzz');
      expect(results, isEmpty);
    });
  });

  group('phone identity', () {
    test('the derived address is stable and normalised', () {
      const String digits = '8801712345678';
      final String email = AppConstants.phoneAuthEmailFor(digits);
      expect(email, 'p8801712345678@phone.imolive.app');

      // Punctuation must not change the result — the number arrives from a text
      // field the user may have pasted into.
      expect(AppConstants.phoneAuthEmailFor('+880 1712-345678'), email);
    });

    test('phone addresses are distinguishable from real ones', () {
      expect(
        AppConstants.isPhoneAuthEmail('p8801712345678@phone.imolive.app'),
        isTrue,
      );
      expect(
        AppConstants.isPhoneAuthEmail('P8801712345678@PHONE.IMOLIVE.APP'),
        isTrue,
      );
      expect(AppConstants.isPhoneAuthEmail('someone@example.com'), isFalse);
      // A domain that merely *ends* with the same letters is not ours.
      expect(AppConstants.isPhoneAuthEmail('a@notphone.imolive.app'), isFalse);
      expect(AppConstants.isPhoneAuthEmail(null), isFalse);
    });

    test('the suggested handle matches the documented shape', () {
      final String handle = FirebaseAuthService.generateUsernameFromName(
        firstName: 'Tanvir',
        lastName: 'Ahmed',
      );
      expect(handle, matches(RegExp(r'^tanvir\.ahmed\d{3}$')));
    });

    test('the handle survives punctuation and non-Latin names', () {
      final String punctuated = FirebaseAuthService.generateUsernameFromName(
        firstName: "O'Brien",
        lastName: 'de la Cruz',
      );
      expect(punctuated, matches(RegExp(r'^obrien\.delacruz\d{3}$')));

      // A name with nothing ASCII in it must still produce a usable handle
      // rather than an empty base — the suffix alone is not a handle.
      final String nonLatin = FirebaseAuthService.generateUsernameFromName(
        firstName: 'তানভীর',
        lastName: 'আহমেদ',
      );
      expect(nonLatin, matches(RegExp(r'^user\d{3}$')));
    });
  });

  group('search keywords', () {
    test('tokens cover prefixes of every word in the name', () {
      final List<String> tokens = FirebaseAuthService.buildSearchKeywords(
        name: 'Tanvir Ahmed',
        firstName: 'Tanvir',
        lastName: 'Ahmed',
        username: 'tanvir.ahmed482',
        phone: '8801712345678',
      );
      for (final String expected in <String>[
        'tanvir', // the word itself
        'tan', // a short prefix
        'tanv', // a longer one
        'ahmed',
        'tanvir ahmed', // the whole value, so a two-word query matches
        'tanvir.ahmed482', // the handle
        '8801712345678', // the number, whole
      ]) {
        expect(tokens, contains(expected), reason: 'missing token "$expected"');
      }
    });

    test('the number is not prefix-expanded', () {
      // Thirteen digits of prefixes would be pure index weight; the `phoneLower`
      // range query already serves a numeric prefix search.
      final List<String> tokens = FirebaseAuthService.buildSearchKeywords(
        name: '',
        phone: '8801712345678',
      );
      expect(tokens, <String>['8801712345678']);
    });

    test('an empty profile yields no tokens, and never an empty string', () {
      // An empty token in the array would match every `arrayContains: ''`
      // query, which is the one way this field could leak the whole directory.
      final List<String> tokens = FirebaseAuthService.buildSearchKeywords(
        name: '   ',
      );
      expect(tokens, isEmpty);
      expect(tokens, isNot(contains('')));
    });
  });

  group('PhoneLoginScreen', () {
    Future<void> pump(WidgetTester tester, {Size size = const Size(420, 1000)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PhoneLoginScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('lays out with the default country and no exceptions',
        (WidgetTester tester) async {
      await pump(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PhoneLoginScreen), findsOneWidget);
      // The locked dial prefix, and the field itself.
      expect(find.text('+880'), findsOneWidget);
      expect(find.text('\u{1F1E7}\u{1F1E9}'), findsOneWidget);
    });

    testWidgets('the signup half shows names, handle and PIN',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('First name'), findsOneWidget);
      expect(find.text('Last name'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Create Account'), findsWidgets);
    });

    testWidgets('the login half drops the signup-only fields',
        (WidgetTester tester) async {
      await pump(tester);

      // `.first` because "Login" appears twice in signup mode: once as the
      // segment and once as the footer link's action. The segment comes first in
      // the tree.
      await tester.tap(find.text('Login').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('First name'), findsNothing);
      expect(find.text('Last name'), findsNothing);
      expect(find.text('Username'), findsNothing);
      // The number and the PIN are all a returning user needs.
      expect(find.text('+880'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
    });

    testWidgets('the country sheet opens and filters', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.text('+880'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Select country'), findsOneWidget);

      // Addressed by its own hint rather than by index: the phone screen's
      // fields are `TextFormField`s, which contain a `TextField` each, so a
      // positional finder would land on one of those instead of the sheet's
      // search box.
      await tester.enterText(
        find.widgetWithText(TextField, 'Search country or code'),
        'bang',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Bangladesh is the only match for that prefix, and it is listed with its
      // dial code.
      expect(find.text('Bangladesh'), findsOneWidget);
      expect(find.text('+880'), findsWidgets);
    });
  });

  // ==========================================================================
  // The submit path.
  //
  // This is the half of the flow a build cannot prove and a unit test of
  // `phoneAuthEmailFor` does not reach: the screen has to turn what the user
  // typed into the E.164 digits the derived address is computed from. Get that
  // wrong and the account is still created — under a different address — so the
  // user can never sign back in and nothing anywhere reports an error. It is the
  // one bug in this feature that is silent, which is why it gets its own group.
  //
  // The auth layer is replaced with a recorder, so these tests exercise the real
  // widget, the real validators and the real formatters, and assert on the
  // argument that reaches the service.
  // ==========================================================================
  group('PhoneLoginScreen — the digits it submits', () {
    late _Submission submission;

    Future<void> pump(WidgetTester tester) async {
      submission = _Submission();
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authControllerProvider.overrideWith(
              () => _CapturingAuthController(submission),
            ),
          ],
          child: const MaterialApp(home: PhoneLoginScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    /// Addresses the boxes positionally, so the count is asserted first: if a
    /// field is ever inserted, the test fails loudly instead of quietly typing
    /// the PIN into the username box.
    Future<void> type(WidgetTester tester, Map<int, String> byIndex) async {
      for (final MapEntry<int, String> entry in byIndex.entries) {
        await tester.enterText(
          find.byType(TextFormField).at(entry.key),
          entry.value,
        );
      }
      await tester.pump();
    }

    /// The submit button sits below the fold on a phone-sized viewport, and
    /// `AuthScaffold` scrolls, so it has to be brought into view before the tap
    /// or the tap lands on nothing.
    ///
    /// Addressed by widget type, not by text: `_ModeSwitch` renders its own
    /// segment labelled "Create Account", so `find.text('Create Account').first`
    /// taps the mode pill — which is already selected, so it does nothing at all
    /// and every assertion below silently reads an empty capture.
    Future<void> tapButton(WidgetTester tester, String label) async {
      final Finder button = find.widgetWithText(AuthPrimaryButton, label);
      expect(button, findsOneWidget, reason: 'expected one submit button "$label"');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('a national number loses its trunk 0 and gains the dial code',
        (WidgetTester tester) async {
      await pump(tester);
      // phone, first, last, username, pin.
      expect(find.byType(TextFormField), findsNWidgets(5));

      await type(tester, <int, String>{
        0: '01712345678',
        1: 'Tanvir',
        2: 'Ahmed',
        4: '482913',
      });
      await tapButton(tester, 'Create Account');

      expect(submission.signedUp, isTrue);
      // The whole point: `+8801712345678`, never `+88001712345678`.
      expect(submission.digits, '8801712345678');
      expect(submission.first, 'Tanvir');
      expect(submission.last, 'Ahmed');
      expect(submission.pin, '482913');
    });

    testWidgets('an already-international number is not prefixed twice',
        (WidgetTester tester) async {
      await pump(tester);

      await type(tester, <int, String>{
        0: '8801712345678',
        1: 'Tanvir',
        2: 'Ahmed',
        4: '482913',
      });
      await tapButton(tester, 'Create Account');

      // Pasting a full number is the common case for a returning user, and
      // `880` + `880...` would address an account that does not exist.
      expect(submission.digits, '8801712345678');
    });

    testWidgets('spacing and punctuation in a pasted number are ignored',
        (WidgetTester tester) async {
      await pump(tester);

      await type(tester, <int, String>{
        0: '01712 345 678',
        1: 'Tanvir',
        2: 'Ahmed',
        4: '482913',
      });
      await tapButton(tester, 'Create Account');

      expect(submission.digits, '8801712345678');
    });

    testWidgets('a blank username submits the suggestion shown on screen',
        (WidgetTester tester) async {
      await pump(tester);

      await type(tester, <int, String>{
        0: '01712345678',
        1: 'Tanvir',
        2: 'Ahmed',
        4: '482913',
        // Index 3 — the username box — deliberately left empty.
      });
      await tapButton(tester, 'Create Account');

      // What the user saw is what they get; an empty handle must not reach the
      // service, which would leave the account with no way to be found.
      expect(submission.username, matches(RegExp(r'^tanvir\.ahmed\d{3}$')));
    });

    testWidgets('a typed username is submitted verbatim', (WidgetTester tester) async {
      await pump(tester);

      await type(tester, <int, String>{
        0: '01712345678',
        1: 'Tanvir',
        2: 'Ahmed',
        3: 'boss.999',
        4: '482913',
      });
      await tapButton(tester, 'Create Account');

      expect(submission.username, 'boss.999');
    });

    testWidgets('login mode sends only the number and the PIN',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.text('Login').first);
      await tester.pumpAndSettle();
      // The signup-only fields are gone, so a returning user is asked for the
      // two things they have.
      expect(find.byType(TextFormField), findsNWidgets(2));

      await type(tester, <int, String>{0: '01712345678', 1: '482913'});
      await tapButton(tester, 'Login with Phone');

      expect(submission.signedIn, isTrue);
      expect(submission.signedUp, isFalse);
      expect(submission.digits, '8801712345678');
      expect(submission.pin, '482913');
    });

    testWidgets('picking another country re-codes the number',
        (WidgetTester tester) async {
      await pump(tester);

      // The dial code is only useful if the selector actually feeds it.
      await tester.tap(find.text('+880'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search country or code'),
        'india',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('India'));
      await tester.pumpAndSettle();

      expect(find.text('+91'), findsOneWidget);

      await type(tester, <int, String>{
        0: '09876543210',
        1: 'Tanvir',
        2: 'Ahmed',
        4: '482913',
      });
      await tapButton(tester, 'Create Account');

      // `09876543210` in India is `+919876543210`.
      expect(submission.digits, '919876543210');
    });

    testWidgets('a PIN under six digits never reaches the service',
        (WidgetTester tester) async {
      await pump(tester);

      await type(tester, <int, String>{
        0: '01712345678',
        1: 'Tanvir',
        2: 'Ahmed',
        4: '123',
      });
      await tapButton(tester, 'Create Account');

      expect(submission.signedUp, isFalse);
      expect(submission.signedIn, isFalse);
      expect(find.text('Use at least 6 digits'), findsOneWidget);
    });

    // A national number can begin with the same digits as the dial code. India is
    // the clear case: the code is `91` and Indian mobiles start with `9`, so
    // `9123456789` is a national number, not `+91 23456789`. A bare
    // `startsWith(dial)` check reads it as already-international, drops the code,
    // and creates the account under `p9123456789@phone.imolive.app` while the user
    // believes they registered `+919123456789` — an account they can never reach
    // again, with no error anywhere. Hence its own pair of tests.
    testWidgets('a national number that begins with the dial code keeps the code',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.text('+880'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search country or code'),
        'india',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('India'));
      await tester.pumpAndSettle();
      expect(find.text('+91'), findsOneWidget);

      await type(tester, <int, String>{
        0: '9123456789',
        1: 'Tanvir',
        2: 'Ahmed',
        4: '482913',
      });
      await tapButton(tester, 'Create Account');

      expect(submission.digits, '919123456789');
    });

    testWidgets('a pasted international number is still not prefixed twice',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.text('+880'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search country or code'),
        'india',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('India'));
      await tester.pumpAndSettle();

      // The other half of the same decision: 12 digits cannot be an Indian
      // national number, so this one *is* already international.
      await type(tester, <int, String>{
        0: '919876543210',
        1: 'Tanvir',
        2: 'Ahmed',
        4: '482913',
      });
      await tapButton(tester, 'Create Account');

      expect(submission.digits, '919876543210');
    });
  });
}

/// What the screen handed to the auth layer.
class _Submission {
  bool signedUp = false;
  bool signedIn = false;
  String digits = '';
  String pin = '';
  String first = '';
  String last = '';
  String username = '';
}

/// A real [AuthController] with the network taken out.
///
/// [build] is overridden to skip `authStateProvider`, so these tests need no
/// Firebase binding — they assert on the argument the screen computes, not on
/// what the service would do with it.
class _CapturingAuthController extends AuthController {
  _CapturingAuthController(this.submission);

  final _Submission submission;

  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  @override
  Future<AuthOutcome> signUpWithPhone({
    required String phoneDigits,
    required String pin,
    required String firstName,
    required String lastName,
    String username = '',
  }) async {
    submission
      ..signedUp = true
      ..digits = phoneDigits
      ..pin = pin
      ..first = firstName
      ..last = lastName
      ..username = username;
    return const AuthOutcome.success('fake-uid');
  }

  @override
  Future<AuthOutcome> signInWithPhone({
    required String phoneDigits,
    required String pin,
  }) async {
    submission
      ..signedIn = true
      ..digits = phoneDigits
      ..pin = pin;
    return const AuthOutcome.success('fake-uid');
  }
}
