import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/group.dart';
import 'package:imo_live/core/services/channel_service.dart';

/// The Firestore-timestamp contract for [Channel].
///
/// A channel document is written with `FieldValue.serverTimestamp()`, which
/// Firestore returns as a [Timestamp] — **not** a `String`. `Channel.fromJson`
/// is the Hive serialiser and reads ISO strings, so `channelFromDoc` converts
/// every date field on the way in.
///
/// The failure this guards against is not subtle. A date field that is written
/// as a server timestamp but missing from the conversion map reaches
/// `fromJson`, where `json['x'] as String` throws. It does not degrade to null;
/// it throws, on read, every time — which breaks the whole chat list for any
/// channel that has a post.
///
/// This test was written because exactly that shipped: `lastMessageAt` and
/// `lastReadAt` were added to the model and written by `addPost` /
/// `markChannelRead`, but not added to the conversion map.
void main() {
  /// A Firestore document as it actually comes back: real [Timestamp] values.
  Map<String, dynamic> firestoreDoc() => <String, dynamic>{
        'name': 'Dhaka News',
        'ownerId': 'uid-owner',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'lastUpdateAt': Timestamp.fromDate(DateTime.utc(2026, 2, 1)),
        'lastMessage': 'A new post',
        'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
        'lastReadAt': Timestamp.fromDate(DateTime.utc(2026, 2, 15)),
      };

  /// Asserts two instants are the same moment.
  ///
  /// `Timestamp.toDate()` returns a **local** [DateTime], so comparing against
  /// a `DateTime.utc` with `equals` fails on any machine not at UTC — which is
  /// a broken test, not a broken conversion. Comparing `microsecondsSinceEpoch`
  /// asks the question that actually matters: same instant?
  void expectSameInstant(DateTime? actual, DateTime expected) {
    expect(actual, isNotNull);
    expect(
      actual!.microsecondsSinceEpoch,
      expected.microsecondsSinceEpoch,
    );
  }

  group('channelFromDoc', () {
    test('a document with every date field converts without throwing', () {
      // The core regression: this call threw before every date field was
      // listed in channelFromDoc.
      expect(
        () => ChannelFirestoreService.channelFromDoc('c1', firestoreDoc()),
        returnsNormally,
      );
    });

    test('every date survives the conversion', () {
      final Channel channel =
          ChannelFirestoreService.channelFromDoc('c1', firestoreDoc());

      expectSameInstant(channel.createdAt, DateTime.utc(2026, 1, 1));
      expectSameInstant(channel.lastUpdateAt, DateTime.utc(2026, 2, 1));
      expectSameInstant(channel.lastMessageAt, DateTime.utc(2026, 3, 1));
      expectSameInstant(channel.lastReadAt, DateTime.utc(2026, 2, 15));
    });

    test('an unread channel stays unread through the conversion', () {
      // The unread badge is derived from these two, so a conversion that
      // silently dropped one would hide the badge rather than crash.
      final Channel channel =
          ChannelFirestoreService.channelFromDoc('c1', firestoreDoc());
      expect(channel.hasUnread, isTrue);
    });

    test('a read channel is not unread through the conversion', () {
      final Channel channel = ChannelFirestoreService.channelFromDoc(
        'c1',
        firestoreDoc()
          ..['lastReadAt'] = Timestamp.fromDate(DateTime.utc(2026, 3, 2)),
      );
      expect(channel.hasUnread, isFalse);
    });

    test('an unresolved server timestamp reads as null, not a crash', () {
      // A local snapshot of a just-written document has the sentinel pending,
      // which arrives as null. It must not be mistaken for a bad type.
      final Channel channel = ChannelFirestoreService.channelFromDoc(
        'c1',
        firestoreDoc()
          ..['lastMessageAt'] = null
          ..['createdAt'] = null,
      );
      expect(channel.lastMessageAt, isNull);
      expect(channel.createdAt, isNull);
      expectSameInstant(channel.lastUpdateAt, DateTime.utc(2026, 2, 1));
    });

    test('a legacy ISO string from an older build still parses', () {
      // Channels written before the model was Firestore-aware hold strings,
      // and remote_contact_service writes ISO too. Both must keep working.
      final Channel channel = ChannelFirestoreService.channelFromDoc(
        'c1',
        firestoreDoc()..['lastMessageAt'] = '2026-04-01T00:00:00.000Z',
      );
      expectSameInstant(channel.lastMessageAt, DateTime.utc(2026, 4, 1));
    });

    test('a document with no dates at all still converts', () {
      expect(
        () => ChannelFirestoreService.channelFromDoc(
          'c1',
          <String, dynamic>{'name': 'Empty'},
        ),
        returnsNormally,
      );
    });
  });

  group('Channel.fromJson date fields', () {
    test('the model reads ISO strings, as the Hive mirror writes them', () {
      // Guards the other half of the contract: if fromJson started accepting
      // only Timestamps, the local mirror would break instead.
      final Channel channel = Channel.fromJson(<String, dynamic>{
        'id': 'c1',
        'name': 'N',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'lastMessageAt': '2026-03-01T00:00:00.000Z',
        'lastReadAt': '2026-02-15T00:00:00.000Z',
      });
      expectSameInstant(channel.createdAt, DateTime.utc(2026, 1, 1));
      expectSameInstant(channel.lastMessageAt, DateTime.utc(2026, 3, 1));
      expectSameInstant(channel.lastReadAt, DateTime.utc(2026, 2, 15));
    });

    test('round-trips through toJson and back', () {
      final Channel before = ChannelFirestoreService.channelFromDoc(
        'c1',
        firestoreDoc(),
      );
      final Channel after = Channel.fromJson(before.toJson());

      expectSameInstant(after.createdAt, before.createdAt!);
      expectSameInstant(after.lastUpdateAt, before.lastUpdateAt!);
      expectSameInstant(after.lastMessageAt, before.lastMessageAt!);
      expectSameInstant(after.lastReadAt, before.lastReadAt!);
      expect(after.lastMessage, before.lastMessage);
    });
  });
}
