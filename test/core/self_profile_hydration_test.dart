import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/contact.dart';
import 'package:imo_live/core/services/remote_contact_service.dart';
import 'package:imo_live/features/chats/presentation/providers.dart';

/// The self profile is hydrated from `users/{uid}` when this device has nothing.
///
/// Google and Facebook sign-ins skip profile setup — `auth_gate` keys that
/// decision off Firebase Auth's `displayName`, which the OAuth providers fill in
/// — so without this lookup those users keep an empty local profile forever,
/// even though their directory document is complete.
///
/// The two pieces that decide the outcome are pure, so they are asserted here
/// rather than left implied by the provider's comments.
void main() {
  Contact blankLocal() => const Contact(id: 'self', firstName: '');

  RemoteProfile profile({
    String name = '',
    String username = '',
    String phone = '',
    String bio = '',
    bool isOnline = false,
    DateTime? lastSeen,
  }) =>
      RemoteProfile(
        uid: 'uid-1',
        name: name,
        username: username,
        phone: phone,
        bio: bio,
        isOnline: isOnline,
        lastSeen: lastSeen,
      );

  group('selfProfileHasIdentity', () {
    test('a first-run profile has no identity', () {
      expect(selfProfileHasIdentity(blankLocal()), isFalse);
    });

    test('whitespace alone is not an identity', () {
      expect(
        selfProfileHasIdentity(const Contact(id: 'self', firstName: '   ')),
        isFalse,
      );
    });

    test('a name counts', () {
      expect(
        selfProfileHasIdentity(const Contact(id: 'self', firstName: 'Rumi')),
        isTrue,
      );
    });

    test('a handle alone counts', () {
      expect(
        selfProfileHasIdentity(
          const Contact(id: 'self', firstName: '', username: 'rumi'),
        ),
        isTrue,
      );
    });

    test('a number alone counts', () {
      expect(
        selfProfileHasIdentity(
          const Contact(id: 'self', firstName: '', phone: '+8801700000000'),
        ),
        isTrue,
      );
    });
  });

  group('mergeDirectoryIntoSelf', () {
    test('fills a blank profile from the directory document', () {
      final Contact merged = mergeDirectoryIntoSelf(
        blankLocal(),
        profile(
          name: 'Rumi Ahmed',
          username: 'rumi',
          phone: '+8801700000000',
          bio: 'building things',
          isOnline: true,
        ),
      );

      expect(merged.firstName, 'Rumi');
      expect(merged.lastName, 'Ahmed');
      expect(merged.username, 'rumi');
      expect(merged.phone, '+8801700000000');
      expect(merged.bio, 'building things');
      expect(merged.isOnline, isTrue);
      expect(merged.isSelf, isTrue);
    });

    test('a single-word name leaves the surname empty', () {
      final Contact merged = mergeDirectoryIntoSelf(
        blankLocal(),
        profile(name: 'Rumi'),
      );

      expect(merged.firstName, 'Rumi');
      expect(merged.lastName, '');
    });

    test('a three-part name keeps the remainder as the surname', () {
      final Contact merged = mergeDirectoryIntoSelf(
        blankLocal(),
        profile(name: 'Rumi  ibn   Ahmed'),
      );

      expect(merged.firstName, 'Rumi');
      expect(merged.lastName, 'ibn Ahmed');
    });

    test('keeps the local id — sender attribution falls back to it', () {
      final Contact merged = mergeDirectoryIntoSelf(
        blankLocal(),
        profile(name: 'Rumi'),
      );

      expect(merged.id, 'self');
    });

    test('a sparse document does not blank what is already known', () {
      const Contact local = Contact(
        id: 'self',
        firstName: 'Rumi',
        username: 'rumi',
        phone: '+8801700000000',
        bio: 'kept',
      );

      final Contact merged = mergeDirectoryIntoSelf(local, profile());

      expect(merged.firstName, 'Rumi');
      expect(merged.username, 'rumi');
      expect(merged.phone, '+8801700000000');
      expect(merged.bio, 'kept');
    });

    test('local-only presentation state survives hydration', () {
      const Contact local = Contact(
        id: 'self',
        firstName: '',
        avatarPath: '/local/avatar.jpg',
        avatarColor: 0xFF00FF00,
        isFavorite: true,
      );

      final Contact merged = mergeDirectoryIntoSelf(
        local,
        profile(name: 'Rumi', username: 'rumi'),
      );

      expect(merged.avatarPath, '/local/avatar.jpg');
      expect(merged.avatarColor, 0xFF00FF00);
      expect(merged.isFavorite, isTrue);
    });

    test('presence comes from the document even when it says offline', () {
      const Contact local = Contact(
        id: 'self',
        firstName: 'Rumi',
        isOnline: true,
      );

      final Contact merged = mergeDirectoryIntoSelf(local, profile());

      expect(merged.isOnline, isFalse);
    });

    test('a missing lastSeen keeps the local one', () {
      final DateTime seen = DateTime(2026, 9, 26, 12);
      final Contact local = Contact(id: 'self', firstName: 'Rumi', lastSeen: seen);

      final Contact merged = mergeDirectoryIntoSelf(local, profile());

      expect(merged.lastSeen, seen);
    });
  });
}
