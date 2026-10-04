import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:imo_live/core/models/chat.dart';
import 'package:imo_live/core/models/contact.dart';
import 'package:imo_live/core/models/group.dart';
import 'package:imo_live/core/models/message.dart';
import 'package:imo_live/core/models/message_parts.dart';
import 'package:imo_live/local/database/local_chat_repository.dart';
import 'package:imo_live/local/database/local_contact_repository.dart';
import 'package:imo_live/local/database/local_database.dart';
import 'package:imo_live/local/database/local_group_repository.dart';
import 'package:imo_live/local/database/local_message_repository.dart';

/// Exercises the Hive-backed local repositories — the same code path the app
/// uses in offline mode. Each group clears the relevant store first so the
/// tests stay order-independent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  /// `Hive.initFlutter` resolves the app documents directory through
  /// `path_provider`, which has no implementation in a unit-test process. The
  /// channel is answered with a real temp directory instead.
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('imo_live_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tempDir.path,
    );
    await Hive.initFlutter(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  late LocalChatRepository chats;
  late LocalContactRepository contacts;
  late LocalMessageRepository messages;
  late LocalGroupRepository groups;

  setUpAll(() async {
    await LocalDatabase.instance.init();
    chats = LocalChatRepository();
    contacts = LocalContactRepository();
    messages = LocalMessageRepository();
    groups = LocalGroupRepository();
  });

  setUp(() async {
    await chats.clear();
    await contacts.clear();
    await messages.clear();
    await groups.clear();
  });

  Chat buildChat(String id, String title, DateTime at) => Chat(
        id: id,
        title: title,
        lastMessage: 'hi',
        lastTimestamp: at,
      );

  Message buildMessage(String id, String chatId, String body) => Message(
        id: id,
        chatId: chatId,
        senderId: 'self',
        senderName: 'You',
        direction: MessageDirection.outgoing,
        type: MessageType.text,
        content: body,
        status: MessageStatus.sent,
        timestamp: DateTime(2026, 5, 1),
      );

  group('LocalChatRepository', () {
    test('orders chats by most recent message', () async {
      await chats.save(buildChat('older', 'Older', DateTime(2026, 1, 1)));
      await chats.save(buildChat('newer', 'Newer', DateTime(2026, 6, 1)));

      final List<Chat> all = await chats.getAll();
      expect(all.length, 2);
      expect(all.first.id, 'newer');
      expect(all.last.id, 'older');
    });

    test('saving the same id updates instead of duplicating', () async {
      final Chat chat = buildChat('c1', 'First', DateTime(2026, 1, 1));
      await chats.save(chat);
      await chats.save(chat.copyWith(title: 'Renamed'));

      final List<Chat> all = await chats.getAll();
      expect(all.length, 1);
      expect(all.single.title, 'Renamed');
    });

    test('archive, pin and mute flags persist', () async {
      await chats.save(buildChat('c2', 'Flags', DateTime(2026, 1, 1)));

      await chats.setArchived('c2', true);
      await chats.setPinned('c2', true);
      await chats.setMuted('c2', true);

      final Chat? chat = await chats.findById('c2');
      expect(chat, isNotNull);
      expect(chat!.isArchived, isTrue);
      expect(chat.isPinned, isTrue);
      expect(chat.isMuted, isTrue);
    });

    test('markRead clears the unread counter', () async {
      await chats.save(
        buildChat('c3', 'Unread', DateTime(2026, 1, 1)).copyWith(unreadCount: 5),
      );
      await chats.markRead('c3');

      final Chat? chat = await chats.findById('c3');
      expect(chat!.unreadCount, 0);
      expect(chat.hasUnread, isFalse);
    });

    test('delete removes only the targeted chat', () async {
      await chats.saveAll(<Chat>[
        buildChat('keep', 'Keep', DateTime(2026, 1, 1)),
        buildChat('drop', 'Drop', DateTime(2026, 1, 1)),
      ]);

      await chats.delete('drop');

      final List<Chat> all = await chats.getAll();
      expect(all.length, 1);
      expect(all.single.id, 'keep');
    });
  });

  group('LocalContactRepository', () {
    test('finds a contact by phone number', () async {
      await contacts.save(
        const Contact(
          id: 'c1',
          firstName: 'Ada',
          lastName: 'Lovelace',
          phone: '+8801700000001',
        ),
      );

      final Contact? found = await contacts.findByPhone('+8801700000001');
      expect(found, isNotNull);
      expect(found!.firstName, 'Ada');
    });

    test('favourite and blocked flags persist', () async {
      await contacts.save(
        const Contact(
          id: 'c2',
          firstName: 'Grace',
          lastName: 'Hopper',
          phone: '+8801700000002',
        ),
      );

      await contacts.setFavorite('c2', true);
      await contacts.setBlocked('c2', true);

      final Contact? contact = await contacts.findById('c2');
      expect(contact!.isFavorite, isTrue);
      expect(contact.isBlocked, isTrue);
      expect((await contacts.getFavorites()).single.id, 'c2');
    });

    test('self profile is stored and retrievable', () async {
      const Contact me = Contact(
        id: 'self',
        firstName: 'Me',
        lastName: '',
        phone: '+880 1700 000000',
      );

      await contacts.saveSelfProfile(me);

      final Contact restored = await contacts.getSelfProfile();
      expect(restored.id, 'self');
      expect(restored.phone, '+880 1700 000000');
    });

    test('search matches across the full name', () async {
      await contacts.saveAll(<Contact>[
        const Contact(
          id: 'c3',
          firstName: 'Alan',
          lastName: 'Turing',
          phone: '+1',
        ),
        const Contact(
          id: 'c4',
          firstName: 'Katherine',
          lastName: 'Johnson',
          phone: '+2',
        ),
      ]);

      final List<Contact> hits = await contacts.search('turing');
      expect(hits.length, 1);
      expect(hits.single.id, 'c3');
    });
  });

  group('LocalMessageRepository', () {
    test('returns only messages for the requested chat', () async {
      await messages.saveAll(<Message>[
        buildMessage('m2', 'chat_a', 'second'),
        buildMessage('m1', 'chat_a', 'first'),
        buildMessage('m3', 'chat_b', 'elsewhere'),
      ]);

      final List<Message> a = await messages.getForChat('chat_a');
      expect(a.length, 2);
      expect(a.every((Message m) => m.chatId == 'chat_a'), isTrue);
    });

    test('star toggling is reflected by getStarred', () async {
      await messages.save(buildMessage('m4', 'chat_a', 'star me'));

      await messages.toggleStar('m4');
      final List<Message> starred = await messages.getStarred();
      expect(starred.length, 1);
      expect(starred.single.id, 'm4');

      await messages.toggleStar('m4');
      expect(await messages.getStarred(), isEmpty);
    });

    test('pin toggling is reflected by getPinned', () async {
      await messages.saveAll(<Message>[
        buildMessage('p1', 'chat_a', 'pin me'),
        buildMessage('p2', 'chat_a', 'leave me alone'),
        buildMessage('p3', 'chat_b', 'other chat'),
      ]);

      await messages.togglePin('p1');

      final List<Message> pinned = await messages.getPinned('chat_a');
      expect(pinned.length, 1);
      expect(pinned.single.id, 'p1');

      // Scoped to the chat: a pin in chat_b must not leak into chat_a.
      await messages.togglePin('p3');
      expect((await messages.getPinned('chat_a')).length, 1);

      await messages.togglePin('p1');
      expect(await messages.getPinned('chat_a'), isEmpty);
    });

    test('pinned order is newest first', () async {
      // buildMessage pins every timestamp to 2026-05-01, so the ordering has to
      // be stated explicitly here — otherwise both rows tie and the assertion
      // would pass for the wrong reason.
      await messages.saveAll(<Message>[
        buildMessage('p4', 'chat_a', 'older')
            .copyWith(timestamp: DateTime(2026, 5, 1, 9)),
        buildMessage('p5', 'chat_a', 'newer')
            .copyWith(timestamp: DateTime(2026, 5, 1, 17)),
      ]);
      await messages.togglePin('p4');
      await messages.togglePin('p5');

      final List<Message> pinned = await messages.getPinned('chat_a');
      expect(pinned.length, 2);
      expect(pinned.first.id, 'p5');
      expect(pinned.last.id, 'p4');
    });

    test('the pinned flag survives a JSON round-trip', () {
      final Message original =
          buildMessage('p6', 'chat_a', 'round trip').copyWith(isPinned: true);
      final Message restored = Message.fromJson(original.toJson());
      expect(restored.isPinned, isTrue);
    });

    test('search is scoped to a single chat when asked', () async {
      await messages.saveAll(<Message>[
        buildMessage('m5', 'chat_a', 'the quick brown fox'),
        buildMessage('m6', 'chat_a', 'lazy dog'),
        buildMessage('m7', 'chat_b', 'the quick brown fox'),
      ]);

      final List<Message> scoped =
          await messages.search('quick', chatId: 'chat_a');
      expect(scoped.length, 1);
      expect(scoped.single.id, 'm5');
    });

    test('editing replaces the stored body', () async {
      await messages.save(buildMessage('m8', 'chat_a', 'original'));
      await messages.edit('m8', 'edited');

      final Message? message = await messages.findById('m8');
      expect(message!.content, 'edited');
    });

    test('deleteForChat removes one conversation and keeps the rest', () async {
      await messages.saveAll(<Message>[
        buildMessage('m9', 'chat_a', 'a'),
        buildMessage('m10', 'chat_b', 'b'),
      ]);

      await messages.deleteForChat('chat_a');

      expect(await messages.getForChat('chat_a'), isEmpty);
      expect((await messages.getForChat('chat_b')).length, 1);
    });

    // --- delete for everyone: the window is enforced at the write ---------
    //
    // The action sheet hides the option outside the window, but hiding a
    // button is not enforcement: a menu left open past the deadline, or any
    // future call site, reaches this method directly. These tests assert the
    // *write* is refused and — just as important — that it reports the refusal
    // rather than returning as if it had succeeded.
    group('deleteForEveryone', () {
      Message fresh(String id, String body) => Message(
            id: id,
            chatId: 'chat_a',
            senderId: 'self',
            senderName: 'You',
            direction: MessageDirection.outgoing,
            type: MessageType.text,
            content: body,
            status: MessageStatus.sent,
            // `DateTime.now()` rather than a literal: this message has to be
            // inside the two-day window whenever the suite happens to run.
            timestamp: DateTime.now(),
          );

      test('retracts a recent outgoing message and reports success', () async {
        await messages.save(fresh('w1', 'regret this'));

        expect(await messages.deleteForEveryone('w1'), isTrue);

        final Message? after = await messages.findById('w1');
        expect(after!.isDeleted, isTrue);
        expect(after.content, isEmpty);
        expect(after.previewText, 'This message was deleted');
      });

      test('refuses an old message and leaves its body intact', () async {
        // `buildMessage` stamps 2026-05-01, far outside the two-day window.
        await messages.save(buildMessage('w2', 'chat_a', 'still here'));

        expect(
          await messages.deleteForEveryone('w2'),
          isFalse,
          reason: 'the refusal must be reported, not swallowed',
        );

        final Message? after = await messages.findById('w2');
        expect(after!.isDeleted, isFalse, reason: 'nothing may have changed');
        expect(after.content, 'still here');
      });

      test('refuses a message the user received', () async {
        await messages.save(
          Message(
            id: 'w3',
            chatId: 'chat_a',
            senderId: 'c1',
            senderName: 'Ada',
            direction: MessageDirection.incoming,
            type: MessageType.text,
            content: 'from Ada',
            status: MessageStatus.read,
            timestamp: DateTime.now(),
          ),
        );

        expect(await messages.deleteForEveryone('w3'), isFalse);
        expect((await messages.findById('w3'))!.content, 'from Ada');
      });

      test('reports failure for an unknown id instead of throwing', () async {
        expect(await messages.deleteForEveryone('does-not-exist'), isFalse);
      });
    });

    // --- delete for me: local by construction ----------------------------
    //
    // The defect these guard against is not "the option is missing" but "the
    // message comes back". `chatMirrorProvider` calls `save()` for *every*
    // message Firestore reports, on *every* snapshot — so a row that was only
    // removed from the list is written straight back by the next incoming
    // message, seconds later, with no error anywhere. The guarantee therefore
    // has to hold at the *write*, which is what these tests exercise.
    group('deleteForMe', () {
      test('removes the row and keeps the rest of the conversation', () async {
        await messages.saveAll(<Message>[
          buildMessage('d1', 'chat_a', 'keep me'),
          buildMessage('d2', 'chat_a', 'remove me'),
        ]);

        await messages.deleteForMe('d2');

        final List<Message> left = await messages.getForChat('chat_a');
        expect(left.map((Message m) => m.id), <String>['d1']);
        expect(await messages.findById('d2'), isNull);
      });

      test('a later save cannot resurrect it', () async {
        // The real defect, reproduced: the mirror re-delivers the whole page
        // whenever anything in the conversation changes.
        await messages.save(buildMessage('d3', 'chat_a', 'remove me'));
        await messages.deleteForMe('d3');

        await messages.save(buildMessage('d3', 'chat_a', 'remove me'));

        expect(
          await messages.findById('d3'),
          isNull,
          reason: 'the Firestore mirror must not restore a message the user '
              'removed for themselves',
        );
        expect(await messages.getForChat('chat_a'), isEmpty);
      });

      test('a later bulk save cannot resurrect it either', () async {
        await messages.save(buildMessage('d4', 'chat_a', 'remove me'));
        await messages.deleteForMe('d4');

        await messages.saveAll(<Message>[
          buildMessage('d5', 'chat_a', 'a new message'),
          buildMessage('d4', 'chat_a', 'remove me'),
        ]);

        final List<Message> left = await messages.getForChat('chat_a');
        expect(left.map((Message m) => m.id), <String>['d5']);
      });

      test('the removal survives a reload from disk', () async {
        // A fresh repository instance re-reads the box — the same thing that
        // happens on the next app launch. The removal has to be durable rather
        // than an in-memory list that dies with the process.
        await messages.save(buildMessage('d6', 'chat_a', 'remove me'));
        await messages.deleteForMe('d6');

        final LocalMessageRepository reopened = LocalMessageRepository();
        expect(await reopened.getForChat('chat_a'), isEmpty);

        await reopened.save(buildMessage('d6', 'chat_a', 'remove me'));
        expect(await reopened.findById('d6'), isNull);
      });

      test('clearing a conversation drops its removals with it', () async {
        // Otherwise the stale index outlives the chat it describes and
        // silently filters the fresh copy that arrives afterwards.
        await messages.save(buildMessage('d7', 'chat_a', 'remove me'));
        await messages.deleteForMe('d7');
        await messages.deleteForChat('chat_a');

        await messages.save(buildMessage('d7', 'chat_a', 'back again'));

        expect(await messages.findById('d7'), isNotNull);
      });

      test('a removal applies to one chat only', () async {
        await messages.saveAll(<Message>[
          buildMessage('d8', 'chat_a', 'a'),
          buildMessage('d9', 'chat_b', 'b'),
        ]);

        await messages.deleteForMe('d8');

        expect(await messages.getForChat('chat_a'), isEmpty);
        expect((await messages.getForChat('chat_b')).length, 1);
      });

      test('a removal never touches another chat with the same id', () async {
        // The index is keyed per chat, so the same id in a second conversation
        // must survive a removal made in the first.
        await messages.saveAll(<Message>[
          buildMessage('d10', 'chat_a', 'a'),
          buildMessage('d10', 'chat_b', 'b'),
        ]);

        await messages.deleteForMe('d10');

        // Whichever chat held it first loses it; the other must still have it,
        // otherwise the index leaked across conversations.
        final int remaining =
            (await messages.getForChat('chat_a')).length +
                (await messages.getForChat('chat_b')).length;
        expect(remaining, 1);
      });
    });
  });

  group('LocalGroupRepository', () {
    test('adding a member grows the group and deduplicates', () async {
      await groups.save(
        const Group(
          id: 'g1',
          name: 'Team',
          members: <GroupMember>[
            GroupMember(contactId: 'self', role: GroupRole.admin),
          ],
        ),
      );

      await groups.addMembers('g1', <String>['c1', 'c2']);
      await groups.addMembers('g1', <String>['c2']);

      final Group? group = await groups.findById('g1');
      expect(group!.memberCount, 3);
    });

    test('setRole promotes and demotes a member', () async {
      await groups.save(
        const Group(
          id: 'g2',
          name: 'Team',
          members: <GroupMember>[
            GroupMember(contactId: 'self', role: GroupRole.admin),
            GroupMember(contactId: 'c1', role: GroupRole.member),
          ],
        ),
      );

      await groups.setRole('g2', 'c1', GroupRole.admin);
      Group? group = await groups.findById('g2');
      expect(group!.admins.length, 2);

      await groups.setRole('g2', 'c1', GroupRole.member);
      group = await groups.findById('g2');
      expect(group!.admins.length, 1);
    });

    test('updatePermissions writes the new rules through', () async {
      await groups.save(const Group(id: 'g3', name: 'Team'));

      await groups.updatePermissions(
        'g3',
        const GroupPermissions().copyWith(addMembers: false),
      );

      final Group? group = await groups.findById('g3');
      expect(group!.permissions.addMembers, isFalse);
    });

    test('removing a member shrinks the group', () async {
      await groups.save(
        const Group(
          id: 'g4',
          name: 'Team',
          members: <GroupMember>[
            GroupMember(contactId: 'self', role: GroupRole.admin),
            GroupMember(contactId: 'c1', role: GroupRole.member),
          ],
        ),
      );

      await groups.removeMember('g4', 'c1');

      final Group? group = await groups.findById('g4');
      expect(group!.memberCount, 1);
    });
  });
}
