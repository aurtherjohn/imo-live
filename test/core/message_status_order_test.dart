import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/services/firestore_chat_service.dart';

/// The status guard decides whether a double tick means anything.
///
/// `updateMessageStatus` refuses to write a status that does not advance the
/// message, and that refusal is the only thing stopping a late `delivered` write
/// from walking back a `read`. The comparison it makes is pure, so it is
/// asserted here rather than left implied by a comment.
void main() {
  group('FirestoreMessageStatus wire contract', () {
    test('the wire values are stable — other clients read these strings', () {
      expect(FirestoreMessageStatus.sent, 'sent');
      expect(FirestoreMessageStatus.delivered, 'delivered');
      expect(FirestoreMessageStatus.read, 'read');
    });
  });

  group('status ordering', () {
    /// The exact predicate `updateMessageStatus` evaluates before writing:
    /// it writes only when the incoming status outranks the stored one.
    bool wouldAdvance(String stored, String incoming) =>
        FirestoreChatService.statusRank(stored) <
        FirestoreChatService.statusRank(incoming);

    test('sent < delivered < read', () {
      expect(
        FirestoreChatService.statusRank(FirestoreMessageStatus.sent),
        lessThan(
          FirestoreChatService.statusRank(FirestoreMessageStatus.delivered),
        ),
      );
      expect(
        FirestoreChatService.statusRank(FirestoreMessageStatus.delivered),
        lessThan(FirestoreChatService.statusRank(FirestoreMessageStatus.read)),
      );
    });

    test('a late delivered write cannot walk back a read', () {
      expect(
        wouldAdvance(FirestoreMessageStatus.read, FirestoreMessageStatus.delivered),
        isFalse,
      );
    });

    test('every genuine forward step is allowed through', () {
      expect(
        wouldAdvance(FirestoreMessageStatus.sent, FirestoreMessageStatus.delivered),
        isTrue,
      );
      expect(
        wouldAdvance(FirestoreMessageStatus.sent, FirestoreMessageStatus.read),
        isTrue,
      );
      expect(
        wouldAdvance(FirestoreMessageStatus.delivered, FirestoreMessageStatus.read),
        isTrue,
      );
    });

    test('repeating the same status is a no-op, not a rewrite', () {
      for (final String status in <String>[
        FirestoreMessageStatus.sent,
        FirestoreMessageStatus.delivered,
        FirestoreMessageStatus.read,
      ]) {
        expect(wouldAdvance(status, status), isFalse);
      }
    });

    test('an unknown wire value ranks as sent, so it cannot block an advance',
        () {
      expect(
        FirestoreChatService.statusRank('something-from-a-newer-client'),
        FirestoreChatService.statusRank(FirestoreMessageStatus.sent),
      );
      expect(
        wouldAdvance(
          'something-from-a-newer-client',
          FirestoreMessageStatus.delivered,
        ),
        isTrue,
      );
    });
  });
}
