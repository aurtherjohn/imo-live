import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/chat.dart';

/// Regression cover for the "User Not Found" profile bug.
///
/// A direct chat's [Chat.id] is the composite `uidA_uidB` produced by
/// `FirestoreChatService.chatIdFor`, *not* a uid. The contact screen resolves
/// `users/{uid}`, so any code path that passed the chat id as a user id always
/// missed and rendered "Contact not found". [Chat.peerUid] is now the single
/// place that converts a chat back into the other person's uid; these tests pin
/// down both the happy path and every ambiguous case that must return null
/// instead of guessing.
void main() {
  Chat direct({required List<String> members, String id = 'alice_bob'}) => Chat(
        id: id,
        title: 'Bob',
        lastMessage: '',
        lastTimestamp: DateTime(2026, 1, 1),
        memberIds: members,
      );

  group('Chat.peerUid', () {
    test('returns the other uid for a two-member direct chat', () {
      final Chat chat = direct(members: <String>['alice', 'bob']);
      expect(chat.peerUid('alice'), 'bob');
      expect(chat.peerUid('bob'), 'alice');
    });

    test('never returns the chat id, which is a composite and not a uid', () {
      final Chat chat = direct(
        members: <String>['alice', 'bob'],
        id: 'alice_bob',
      );
      expect(chat.peerUid('alice'), isNot(chat.id));
      expect(chat.peerUid('alice'), isNot(contains('_')));
    });

    test('returns null when the signed-in uid is unknown', () {
      final Chat chat = direct(members: <String>['alice', 'bob']);
      expect(chat.peerUid(''), isNull);
    });

    test('returns null when the signed-in uid is not a member', () {
      // A chat mirrored from another account: we cannot tell which of the two
      // remaining members is the peer, so guessing would be wrong half the time.
      final Chat chat = direct(members: <String>['alice', 'bob']);
      expect(chat.peerUid('carol'), isNull);
    });

    test('returns null when the member list is empty', () {
      expect(direct(members: <String>[]).peerUid('alice'), isNull);
    });

    test('returns null when more than one other member remains', () {
      final Chat chat = direct(members: <String>['alice', 'bob', 'carol']);
      expect(chat.peerUid('alice'), isNull);
    });

    test('returns null when the only other member id is blank', () {
      final Chat chat = direct(members: <String>['alice', '']);
      expect(chat.peerUid('alice'), isNull);
    });

    test('returns null for groups', () {
      final Chat group = Chat(
        id: 'grp_1',
        title: 'Team',
        lastMessage: '',
        lastTimestamp: DateTime(2026, 1, 1),
        isGroup: true,
        memberIds: <String>['alice', 'bob'],
      );

      expect(group.peerUid('alice'), isNull, reason: '${group.id} has no peer');
    });
  });

  group('Chat.isDirect', () {
    test('is true only for a plain one-to-one conversation', () {
      expect(direct(members: <String>['alice', 'bob']).isDirect, isTrue);
      expect(
        direct(members: <String>['alice', 'bob']).copyWith(isGroup: true).isDirect,
        isFalse,
      );
    });
  });
}
