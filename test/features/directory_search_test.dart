import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/constants/country_data.dart';
import 'package:imo_live/core/services/remote_contact_service.dart';
import 'package:imo_live/features/search/domain/directory_search_service.dart';

/// Builds a directory profile with just the fields the search logic reads.
RemoteProfile _profile({
  required String uid,
  String name = '',
  String username = '',
  String phone = '',
  String email = '',
}) =>
    RemoteProfile(
      uid: uid,
      name: name,
      username: username,
      phone: phone,
      email: email,
    );

void main() {
  group('phone resolution — the same number in three shapes', () {
    // The whole point: a `phones/{n}` document id is E.164 digits only, but a
    // person types the national form with a trunk `0` far more often than the
    // international one. All three of these must land on the same document.
    const String dial = '880';

    test('a leading + is dropped, digits kept', () {
      expect(
        RemoteContactService.resolvePhone('+8801712345678', dialCode: dial),
        '8801712345678',
      );
    });

    test('an already-E.164 number is left alone', () {
      expect(
        RemoteContactService.resolvePhone('8801712345678', dialCode: dial),
        '8801712345678',
      );
    });

    test('a national number with a trunk 0 gets the country code', () {
      expect(
        RemoteContactService.resolvePhone('01712345678', dialCode: dial),
        '8801712345678',
      );
    });

    test('separators are ignored', () {
      expect(
        RemoteContactService.resolvePhone('+880 (171) 234-5678', dialCode: dial),
        '8801712345678',
      );
      expect(
        RemoteContactService.resolvePhone('017 1234 5678', dialCode: dial),
        '8801712345678',
      );
    });

    test('the trunk 0 is never doubled onto the country code', () {
      // The failure this guards against: `0` + code `880` naive-concatenated
      // would give `88088017…`, which nobody's document id is.
      final String once =
          RemoteContactService.resolvePhone('01712345678', dialCode: dial);
      final String twice =
          RemoteContactService.resolvePhone(once, dialCode: dial);
      expect(twice, once);
    });

    test('a bare national number with no trunk prefix gets the code', () {
      expect(
        RemoteContactService.resolvePhone('1712345678', dialCode: dial),
        '8801712345678',
      );
    });

    test('an unknown dial code leaves the digits literal rather than guessing', () {
      // Without a country there is no honest answer, so the input is used as-is.
      expect(
        RemoteContactService.resolvePhone('01712345678', dialCode: ''),
        '01712345678',
      );
    });

    test('a leading + is honoured even when it disagrees with the caller country', () {
      // An explicit + is the user telling us the country; never second-guess it.
      expect(
        RemoteContactService.resolvePhone('+8801712345678', dialCode: '1'),
        '8801712345678',
      );
    });
  });

  group('CountryData.byDialPrefix', () {
    test('recovers the country from E.164 digits', () {
      expect(CountryData.byDialPrefix('8801712345678')?.iso, 'BD');
    });

    test('longest prefix wins, not shortest', () {
      // `1` is a dial code (US) and so is `91` (India). A number starting `91`
      // must resolve to India, not to a country whose code is `9`.
      expect(CountryData.byDialPrefix('919876543210')?.iso, 'IN');
    });

    test('empty input yields null rather than a default', () {
      expect(CountryData.byDialPrefix(''), isNull);
    });
  });

  group('kindOf — input type detection', () {
    test('a + prefixed number is a phone', () {
      expect(
        DirectorySearchService.kindOf('+8801712345678'),
        DirectoryQueryKind.phone,
      );
    });

    test('a national number with a trunk 0 is a phone', () {
      expect(
        DirectorySearchService.kindOf('01712345678'),
        DirectoryQueryKind.phone,
      );
    });

    test('an @ prefix is a username even with dots', () {
      expect(
        DirectorySearchService.kindOf('@rakib.123'),
        DirectoryQueryKind.username,
      );
    });

    test('an email is recognised', () {
      expect(
        DirectorySearchService.kindOf('rakib@example.com'),
        DirectoryQueryKind.email,
      );
    });

    test('a plain word is treated as a name, not a handle-only query', () {
      // Regression guard: returning `username` here meant typing a person's
      // actual name never searched the name index.
      expect(
        DirectorySearchService.kindOf('Rakib'),
        DirectoryQueryKind.name,
      );
    });

    test('a multi-word query is a name', () {
      expect(
        DirectorySearchService.kindOf('Rakib Hasan'),
        DirectoryQueryKind.name,
      );
    });

    test('a long opaque token is a uid', () {
      expect(
        DirectorySearchService.kindOf('aBcD1234eFgH5678iJkL'),
        DirectoryQueryKind.uid,
      );
    });

    test('an empty query is unknown', () {
      expect(DirectorySearchService.kindOf('  '), DirectoryQueryKind.unknown);
    });
  });

  group('scoreHit — exact > prefix > partial, contacts break ties', () {
    int score(String q, String name, {bool contact = false}) => scoreHit(
          query: q,
          name: name,
          username: '',
          phone: '',
          isContact: contact,
        );

    test('an exact match outranks a prefix match', () {
      expect(score('rakib', 'Rakib'), greaterThan(score('rakib', 'Rakibul')));
    });

    test('a prefix match outranks a mid-string match', () {
      expect(
        score('rakib', 'Rakibul'),
        greaterThan(score('rakib', 'Md Rakib')),
      );
    });

    test('a mid-string match still scores above zero', () {
      expect(score('rakib', 'Md Rakib'), greaterThan(0));
    });

    test('a non-match scores zero', () {
      expect(score('rakib', 'Salma'), 0);
    });

    test('matching is case-insensitive both ways', () {
      expect(score('RAKIB', 'rakib'), score('rakib', 'Rakib'));
    });

    test('a contact bonus cannot lift a partial above an exact directory hit', () {
      // The bonus is bounded below the 100-point band gap, so this ordering is
      // stable no matter which side is the contact.
      final int partialContact =
          score('rakib', 'Md Rakib', contact: true);
      final int exactDirectory = score('rakib', 'Rakib');
      expect(exactDirectory, greaterThan(partialContact));
    });

    test('at equal band a contact outranks a stranger', () {
      expect(
        score('rakib', 'Rakib', contact: true),
        greaterThan(score('rakib', 'Rakib')),
      );
    });

    test('the handle and phone fields are searched too', () {
      final int byHandle = scoreHit(
        query: 'rakib',
        name: 'Someone',
        username: 'rakib123',
        phone: '',
        isContact: false,
      );
      final int byPhone = scoreHit(
        query: '0171',
        name: 'Someone',
        username: '',
        phone: '01712345678',
        isContact: false,
      );
      expect(byHandle, greaterThan(0));
      expect(byPhone, greaterThan(0));
    });
  });

  group('mergeWithContacts — dedupe by uid, contact view wins', () {
    test('a person in both lists appears once', () {
      final List<DirectoryHit> hits = DirectorySearchService.mergeWithContacts(
        query: 'rakib',
        directoryProfiles: <RemoteProfile>[
          _profile(uid: 'u1', name: 'Rakib Hasan', username: 'rakib'),
        ],
        contacts: <({String uid, String name, String phone, String username})>[
          (uid: 'u1', name: 'Rakib (office)', phone: '', username: 'rakib'),
        ],
        contactProfiles: <RemoteProfile>[
          _profile(uid: 'u1', name: 'Rakib Hasan', username: 'rakib'),
        ],
      );
      expect(hits.length, 1);
      expect(hits.single.source, SearchResultSource.contact);
      expect(hits.single.localName, 'Rakib (office)');
    });

    test('the address-book name is what gets displayed', () {
      final List<DirectoryHit> hits = DirectorySearchService.mergeWithContacts(
        query: 'rakib',
        directoryProfiles: <RemoteProfile>[
          _profile(uid: 'u1', name: 'Rakib Hasan'),
        ],
        contacts: <({String uid, String name, String phone, String username})>[
          (uid: 'u1', name: 'Boss', phone: '', username: ''),
        ],
        contactProfiles: <RemoteProfile>[_profile(uid: 'u1', name: 'Rakib Hasan')],
      );
      expect(hits.single.displayName, 'Boss');
    });

    test('a stranger is labelled as a directory hit', () {
      final List<DirectoryHit> hits = DirectorySearchService.mergeWithContacts(
        query: 'salma',
        directoryProfiles: <RemoteProfile>[_profile(uid: 'u2', name: 'Salma')],
        contacts: const <({String uid, String name, String phone, String username})>[],
        contactProfiles: const <RemoteProfile>[],
      );
      expect(hits.single.source, SearchResultSource.directory);
      expect(hits.single.isContact, isFalse);
    });

    test('results are ordered best-match first', () {
      final List<DirectoryHit> hits = DirectorySearchService.mergeWithContacts(
        query: 'rakib',
        directoryProfiles: <RemoteProfile>[
          _profile(uid: 'partial', name: 'Md Rakib'),
          _profile(uid: 'prefix', name: 'Rakibul'),
          _profile(uid: 'exact', name: 'Rakib'),
        ],
        contacts: const <({String uid, String name, String phone, String username})>[],
        contactProfiles: const <RemoteProfile>[],
      );
      expect(
        hits.map((DirectoryHit h) => h.profile.uid).toList(),
        <String>['exact', 'prefix', 'partial'],
      );
    });

    test('a contact outside the directory results still appears', () {
      // An offline contact, or one saved before they had an account: the
      // address book is the source of truth for "do I know this person".
      final List<DirectoryHit> hits = DirectorySearchService.mergeWithContacts(
        query: 'karim',
        directoryProfiles: const <RemoteProfile>[],
        contacts: <({String uid, String name, String phone, String username})>[
          (uid: 'c9', name: 'Karim', phone: '', username: ''),
        ],
        contactProfiles: <RemoteProfile>[_profile(uid: 'c9', name: 'Karim')],
      );
      expect(hits.single.profile.uid, 'c9');
      expect(hits.single.isContact, isTrue);
    });

    test('an empty query keeps contacts ahead of directory rows', () {
      final List<DirectoryHit> hits = DirectorySearchService.mergeWithContacts(
        query: '',
        directoryProfiles: <RemoteProfile>[_profile(uid: 'd', name: 'Zed')],
        contacts: <({String uid, String name, String phone, String username})>[
          (uid: 'c', name: 'Amir', phone: '', username: ''),
        ],
        contactProfiles: <RemoteProfile>[_profile(uid: 'c', name: 'Amir')],
      );
      expect(hits.first.isContact, isTrue);
    });
  });
}
