import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/constants/app_constants.dart';
import 'package:imo_live/core/models/chat.dart';
import 'package:imo_live/core/models/contact.dart';
import 'package:imo_live/core/models/group.dart';
import 'package:imo_live/core/models/message.dart';
import 'package:imo_live/core/models/message_parts.dart';
import 'package:imo_live/core/models/settings.dart';
import 'package:imo_live/core/models/status.dart';
import 'package:imo_live/core/utils/formatters.dart';

void main() {
  group('AppConstants', () {
    test('uses the original Imo LIVE branding, never another product name', () {
      expect(AppConstants.appName, 'Imo LIVE');
      expect(AppConstants.appName.toLowerCase(), isNot(contains('whatsapp')));
      expect(AppConstants.appTagline.isNotEmpty, isTrue);
    });

    test('every declared route is a well-formed absolute path', () {
      const List<String> routes = <String>[
        AppRoutes.splash,
        AppRoutes.chats,
        AppRoutes.updates,
        AppRoutes.calls,
        AppRoutes.chat,
        AppRoutes.settings,
        AppRoutes.profile,
        AppRoutes.call,
        AppRoutes.globalSearch,
      ];
      for (final String route in routes) {
        expect(route.startsWith('/'), isTrue, reason: '$route must be absolute');
      }
    });
  });

  group('Contact', () {
    const Contact contact = Contact(
      id: 'c1',
      firstName: 'Ada',
      lastName: 'Lovelace',
      phone: '+44 20 7946 0958',
      isFavorite: true,
      isOnline: true,
    );

    test('derives a full name and initials', () {
      expect(contact.fullName, 'Ada Lovelace');
      expect(contact.initials, 'AL');
    });

    test('copyWith preserves untouched fields', () {
      final Contact updated = contact.copyWith(lastName: 'Byron');
      expect(updated.lastName, 'Byron');
      expect(updated.firstName, 'Ada');
      expect(updated.isFavorite, isTrue);
    });

    test('sorts deterministically via an upper-cased sort key', () {
      // sortedKey is deliberately upper-cased so ordering is case-insensitive.
      expect(contact.sortedKey, 'ADA LOVELACE');
      expect(
        contact.sortedKey,
        contact.fullName.toUpperCase(),
      );
    });
  });

  group('Chat', () {
    test('reports unread state from the counter and the manual flag', () {
      final Chat unread = Chat(
        id: 'x',
        title: 'A',
        lastMessage: 'hi',
        lastTimestamp: DateTime(2026, 1, 1),
        unreadCount: 3,
      );
      final Chat marked = Chat(
        id: 'y',
        title: 'B',
        lastMessage: 'yo',
        lastTimestamp: DateTime(2026, 1, 1),
        isMarkedUnread: true,
      );
      expect(unread.hasUnread, isTrue);
      expect(marked.hasUnread, isTrue);
    });

    test('serialises and restores every field through JSON', () {
      final Chat chat = Chat(
        id: 'chat_1',
        title: 'Design team',
        lastMessage: 'See you at 4',
        lastTimestamp: DateTime(2026, 3, 4, 10, 30),
        unreadCount: 2,
        isGroup: true,
        isArchived: true,
        isPinned: true,
      );
      final Chat restored = Chat.fromJson(chat.toJson());
      expect(restored.id, chat.id);
      expect(restored.title, chat.title);
      expect(restored.unreadCount, 2);
      expect(restored.isGroup, isTrue);
      expect(restored.isArchived, isTrue);
      expect(restored.isPinned, isTrue);
      expect(restored.lastTimestamp, chat.lastTimestamp);
    });
  });

  group('Message', () {
    test('reports outgoing direction and a deleted placeholder body', () {
      final Message message = Message(
        id: 'm1',
        chatId: 'chat_1',
        senderId: 'self',
        senderName: 'You',
        direction: MessageDirection.outgoing,
        type: MessageType.text,
        content: 'Hello',
        status: MessageStatus.delivered,
        timestamp: DateTime(2026, 1, 1),
      );
      expect(message.isOutgoing, isTrue);
      expect(message.previewText, 'Hello');

      final Message deleted = message.copyWith(isDeleted: true);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.previewText, 'This message was deleted');
    });

    // --- delete for everyone: author + two-day window --------------------
    //
    // This rule is the whole feature. It was also broken in a way no UI test
    // would have caught: the chat screen decided the option from
    // `chat.isGroup`, so "Delete for everyone" was missing from every 1:1 chat
    // and present in every group. These tests pin the rule itself, so the next
    // change to the menu cannot quietly re-break it.
    group('canDeleteForEveryone', () {
      Message sentAt(DateTime when, {MessageDirection? direction}) => Message(
            id: 'm',
            chatId: 'c',
            senderId: 'self',
            senderName: 'You',
            direction: direction ?? MessageDirection.outgoing,
            type: MessageType.text,
            content: 'Hello',
            status: MessageStatus.delivered,
            timestamp: when,
          );

      final DateTime sent = DateTime(2026, 9, 30, 12);

      test('is true for your own message just after sending', () {
        expect(sentAt(sent).canDeleteForEveryoneAt(sent), isTrue);
      });

      test('the window is two days', () {
        // Pinned explicitly. The length is a product decision, not a detail:
        // it is the difference between "you can take that back" and "you can
        // rewrite last week". Changing it should mean changing this test on
        // purpose.
        expect(Message.deleteForEveryoneWindow, const Duration(days: 2));
      });

      test('is true right up to the deadline and false one second past it', () {
        const Duration window = Message.deleteForEveryoneWindow;
        expect(
          sentAt(sent).canDeleteForEveryoneAt(sent.add(window - const Duration(seconds: 1))),
          isTrue,
          reason: 'still inside the window',
        );
        expect(
          sentAt(sent).canDeleteForEveryoneAt(sent.add(window)),
          isFalse,
          reason: 'the window is exclusive: exactly two days later is too late',
        );
        expect(
          sentAt(sent).canDeleteForEveryoneAt(sent.add(window + const Duration(seconds: 1))),
          isFalse,
        );
      });

      test('is false for a received message, however recent', () {
        // The regression guard for the real bug: retraction is about
        // authorship, not about how old the message is or whether the chat is a
        // group.
        expect(
          sentAt(sent, direction: MessageDirection.incoming)
              .canDeleteForEveryoneAt(sent),
          isFalse,
        );
      });

      test('is false once the message is already deleted', () {
        expect(
          sentAt(sent).copyWith(isDeleted: true).canDeleteForEveryoneAt(sent),
          isFalse,
        );
      });

      test('tolerates a timestamp slightly in the future', () {
        // Two devices' clocks disagree. Refusing to delete a message the user
        // just sent is a worse failure than allowing a retraction a few seconds
        // late, so a negative age counts as "inside the window".
        expect(
          sentAt(sent).canDeleteForEveryoneAt(sent.subtract(const Duration(seconds: 5))),
          isTrue,
        );
      });
    });

    test('round-trips through JSON preserving the timestamp', () {
      final Message message = Message(
        id: 'm2',
        chatId: 'chat_2',
        senderId: 'c1',
        senderName: 'Ada',
        direction: MessageDirection.incoming,
        type: MessageType.image,
        content: '',
        status: MessageStatus.read,
        timestamp: DateTime(2026, 6, 15, 8, 45),
        isStarred: true,
      );
      final Message restored = Message.fromJson(message.toJson());
      expect(restored.type, MessageType.image);
      expect(restored.status, MessageStatus.read);
      expect(restored.isStarred, isTrue);
      expect(restored.timestamp, message.timestamp);
    });
  });

  group('Group permissions', () {
    test('copyWith changes one permission and keeps the rest', () {
      const GroupPermissions permissions = GroupPermissions();
      final GroupPermissions updated =
          permissions.copyWith(addMembers: false, inviteViaLink: false);
      expect(updated.addMembers, isFalse);
      expect(updated.inviteViaLink, isFalse);
      expect(updated.sendMessages, permissions.sendMessages);
      expect(updated.editGroupInfo, permissions.editGroupInfo);
    });

    test('Group exposes member count and admin list', () {
      final Group group = Group(
        id: 'g1',
        name: 'Team',
        members: const <GroupMember>[
          GroupMember(contactId: 'self', role: GroupRole.admin),
          GroupMember(contactId: 'c1', role: GroupRole.member),
          GroupMember(contactId: 'c2', role: GroupRole.admin),
        ],
      );
      expect(group.memberCount, 3);
      expect(group.admins.length, 2);
    });
  });

  group('Status expiry', () {
    test('a fresh status is not expired and has time remaining', () {
      final Status status = Status(
        id: 's1',
        authorId: 'c1',
        authorName: 'Ada',
        type: StatusType.text,
        text: 'hi',
        createdAt: DateTime.now(),
      );
      expect(status.isExpired, isFalse);
      expect(status.remaining.inHours, greaterThanOrEqualTo(23));
    });

    test('a status older than 24 hours is expired with zero remaining', () {
      final Status status = Status(
        id: 's2',
        authorId: 'c1',
        authorName: 'Ada',
        type: StatusType.text,
        createdAt: DateTime.now().subtract(const Duration(hours: 30)),
      );
      expect(status.isExpired, isTrue);
      expect(status.remaining, Duration.zero);
    });
  });

  group('Call records', () {
    test('classifies missed and declined calls as missed', () {
      final CallRecord missed = CallRecord(
        id: 'r1',
        contactId: 'c1',
        contactName: 'Ada',
        kind: CallKind.voice,
        direction: CallDirection.incoming,
        outcome: CallOutcome.missed,
        timestamp: DateTime.now(),
      );
      expect(missed.isMissed, isTrue);

      final CallRecord declined = missed.copyWith(outcome: CallOutcome.declined);
      expect(declined.isMissed, isTrue);

      final CallRecord answered = missed.copyWith(
        outcome: CallOutcome.answered,
        durationSeconds: 65,
      );
      expect(answered.isMissed, isFalse);
      expect(answered.durationLabel, '1m 5s');
    });
  });

  group('Wallpaper and appearance settings', () {
    test('appearance round-trips theme mode, accent and font scale', () {
      const AppearanceSettings settings = AppearanceSettings(
        themeMode: AppThemeMode.dark,
        accentColor: 0xFFFF2D55,
        fontScale: 1.15,
      );
      final AppearanceSettings restored =
          AppearanceSettings.fromJson(settings.toJson());
      expect(restored.themeMode, AppThemeMode.dark);
      expect(restored.accentColor, 0xFFFF2D55);
      expect(restored.fontScale, closeTo(1.15, 0.0001));
    });
  });

  group('Country', () {
    test('produces a flag emoji and a display label from the ISO code', () {
      const Country country = Country(
        name: 'Bangladesh',
        iso: 'BD',
        dialCode: '+880',
      );
      expect(country.flagEmoji.isNotEmpty, isTrue);
      expect(country.dialCode, '+880');
      expect(country.flagEmoji, '🇧🇩');
    });
  });

  group('Formatters', () {
    test('duration renders minutes and zero-padded seconds', () {
      expect(
        DateFormatter.duration(const Duration(seconds: 65)),
        '01:05',
      );
      expect(
        DateFormatter.duration(const Duration(minutes: 2, seconds: 7)),
        '02:07',
      );
    });

    test('relative timestamps are human readable', () {
      expect(
        DateFormatter.relative(
          DateTime.now().subtract(const Duration(seconds: 20)),
        ),
        'just now',
      );
      expect(
        DateFormatter.relative(
          DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        '5m ago',
      );
      expect(
        DateFormatter.relative(
          DateTime.now().subtract(const Duration(hours: 3)),
        ),
        '3h ago',
      );
    });
  });

  group('TextUtils', () {
    test('pluralises member and message counts', () {
      expect(TextUtils.members(1), contains('1'));
      expect(TextUtils.members(4), contains('4'));
      expect(TextUtils.messageCount(1), isNotEmpty);
    });

    test('validates phone numbers', () {
      expect(TextUtils.isValidPhone('+8801700000000'), isTrue);
      expect(TextUtils.isValidPhone(''), isFalse);
    });

    test('truncates long strings with an ellipsis', () {
      final String long = 'x' * 500;
      final String short = TextUtils.truncate(long, 20);
      expect(short.length, lessThan(long.length));
      expect(short, endsWith('…'));
    });
  });
}
