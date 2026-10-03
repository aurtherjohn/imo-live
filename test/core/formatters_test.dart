import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/utils/formatters.dart';
import 'package:intl/intl.dart';

/// Unit tests for the shared formatting helpers.
///
/// Where a helper delegates to `intl`, the expectation is computed with the
/// same `DateFormat` call rather than a hardcoded literal — that keeps the test
/// meaningful without becoming brittle across `intl` releases.
void main() {
  group('DateFormatter.duration', () {
    test('formats mm:ss with zero padding', () {
      expect(DateFormatter.duration(const Duration(seconds: 5)), '00:05');
      expect(DateFormatter.duration(const Duration(seconds: 75)), '01:15');
      expect(DateFormatter.duration(const Duration(minutes: 10)), '10:00');
      expect(DateFormatter.duration(const Duration(minutes: 125)), '125:00');
    });

    test('handles zero and negative-ish durations without throwing', () {
      expect(DateFormatter.duration(Duration.zero), '00:00');
    });
  });

  group('DateFormatter.longDuration', () {
    test('uses hours when the duration is at least an hour', () {
      expect(DateFormatter.longDuration(const Duration(hours: 1)), '1h 00m');
      expect(
        DateFormatter.longDuration(const Duration(hours: 2, minutes: 5)),
        '2h 05m',
      );
    });

    test('uses minutes and seconds below an hour', () {
      expect(
        DateFormatter.longDuration(const Duration(minutes: 5, seconds: 3)),
        '5m 03s',
      );
      expect(DateFormatter.longDuration(const Duration(seconds: 45)), '0m 45s');
    });
  });

  group('DateFormatter.remaining', () {
    test('scales the unit down as the status ages', () {
      expect(DateFormatter.remaining(const Duration(hours: 5)), '5h left');
      expect(DateFormatter.remaining(const Duration(minutes: 30)), '30m left');
      expect(DateFormatter.remaining(const Duration(seconds: 30)), 'expiring');
    });
  });

  group('DateFormatter.chatTimestamp', () {
    final DateTime now = DateTime.now();
    final DateTime todayAt = DateTime(now.year, now.month, now.day, 14, 5);

    test('a timestamp from today shows the clock time', () {
      expect(DateFormatter.chatTimestamp(todayAt), DateFormat.Hm().format(todayAt));
    });

    test('a timestamp from yesterday is labelled', () {
      final DateTime yesterday = todayAt.subtract(const Duration(days: 1));
      expect(DateFormatter.chatTimestamp(yesterday), 'Yesterday');
    });

    test('within the last week it shows the weekday', () {
      final DateTime threeDaysAgo = todayAt.subtract(const Duration(days: 3));
      expect(
        DateFormatter.chatTimestamp(threeDaysAgo),
        DateFormat.E().format(threeDaysAgo),
      );
    });

    test('older but in the same year shows a short month/day', () {
      final DateTime older = DateTime(now.year, 1, 15, 9, 0);
      // Only meaningful when "Jan 15" is genuinely more than a week ago.
      if (now.difference(older).inDays >= 7) {
        expect(
          DateFormatter.chatTimestamp(older),
          DateFormat.MMMd().format(older),
        );
      }
    });

    test('a previous year includes the year', () {
      final DateTime lastYear = DateTime(now.year - 1, 6, 1, 9, 0);
      expect(
        DateFormatter.chatTimestamp(lastYear),
        DateFormat.yMd().format(lastYear),
      );
    });
  });

  group('DateFormatter.daySeparator', () {
    test('labels today and yesterday, and names the weekday within a week', () {
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day, 10);

      expect(DateFormatter.daySeparator(today), 'Today');
      expect(
        DateFormatter.daySeparator(today.subtract(const Duration(days: 1))),
        'Yesterday',
      );

      final DateTime threeDaysAgo = today.subtract(const Duration(days: 3));
      expect(
        DateFormatter.daySeparator(threeDaysAgo),
        DateFormat.EEEE().format(threeDaysAgo),
      );
    });

    test('falls back to a full date beyond a week', () {
      final DateTime now = DateTime.now();
      final DateTime old = DateTime(now.year, 1, 5, 10);
      if (now.difference(old).inDays >= 7) {
        expect(DateFormatter.daySeparator(old), DateFormat.yMMMMd().format(old));
      }
    });
  });

  group('DateFormatter.lastSeen', () {
    test('very recent activity reads as "just now"', () {
      expect(
        DateFormatter.lastSeen(DateTime.now()),
        'last seen just now',
      );
    });

    test('hours-old activity uses today plus a clock time', () {
      final DateTime twoHoursAgo = DateTime.now().subtract(
        const Duration(hours: 2),
      );
      expect(DateFormatter.lastSeen(twoHoursAgo), startsWith('last seen today at'));
    });

    test('a few days back counts the days', () {
      final DateTime threeDaysAgo = DateTime.now().subtract(
        const Duration(days: 3),
      );
      expect(DateFormatter.lastSeen(threeDaysAgo), 'last seen 3 days ago');
    });

    test('a month back degrades to "recently"', () {
      final DateTime longAgo = DateTime.now().subtract(const Duration(days: 30));
      expect(DateFormatter.lastSeen(longAgo), 'last seen recently');
    });
  });

  group('DateFormatter.relative', () {
    test('buckets a timestamp into a short relative label', () {
      expect(
        DateFormatter.relative(DateTime.now().subtract(const Duration(seconds: 20))),
        'just now',
      );
      expect(
        DateFormatter.relative(DateTime.now().subtract(const Duration(minutes: 5))),
        '5m ago',
      );
      expect(
        DateFormatter.relative(DateTime.now().subtract(const Duration(hours: 3))),
        '3h ago',
      );
      expect(
        DateFormatter.relative(DateTime.now().subtract(const Duration(days: 1))),
        'yesterday',
      );
      expect(
        DateFormatter.relative(DateTime.now().subtract(const Duration(days: 3))),
        '3d ago',
      );
    });
  });

  group('DateFormatter.callTimestamp', () {
    test('today shows the clock, yesterday is labelled, older shows a date', () {
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day, 8, 30);
      expect(DateFormatter.callTimestamp(today), DateFormat.Hm().format(today));

      expect(
        DateFormatter.callTimestamp(today.subtract(const Duration(days: 1))),
        'Yesterday',
      );

      final DateTime longAgo = DateTime(now.year, 1, 4, 8, 30);
      if (now.difference(longAgo).inDays >= 7) {
        expect(
          DateFormatter.callTimestamp(longAgo),
          DateFormat('d MMM').format(longAgo),
        );
      }
    });
  });

  group('DateFormatter.time / monthYear', () {
    test('time is hours and minutes', () {
      final DateTime value = DateTime(2026, 3, 4, 9, 7);
      expect(DateFormatter.time(value), DateFormat.Hm().format(value));
    });

    test('monthYear renders the month and year', () {
      final DateTime value = DateTime(2026, 3, 4);
      expect(DateFormatter.monthYear(value), DateFormat.yMMMM().format(value));
    });
  });

  group('TextUtils', () {
    test('pluralises counts', () {
      expect(TextUtils.members(1), '1 member');
      expect(TextUtils.members(0), '0 members');
      expect(TextUtils.members(4), '4 members');

      expect(TextUtils.messageCount(1), '1 message');
      expect(TextUtils.messageCount(9), '9 messages');

      expect(TextUtils.callCount(1), '1 call');
      expect(TextUtils.callCount(2), '2 calls');

      expect(TextUtils.chatsCount(1), '1 chat');
      expect(TextUtils.chatsCount(7), '7 chats');
    });

    test('truncate trims and ellipsises only when needed', () {
      expect(TextUtils.truncate('hello', 10), 'hello');
      expect(TextUtils.truncate('  spaced  ', 10), 'spaced');
      expect(TextUtils.truncate('hello world', 5), 'hello…');
      // A trailing space exposed by the cut is removed before the ellipsis.
      expect(TextUtils.truncate('hello world', 6), 'hello…');
    });

    test('prettyPhone strips separators but keeps a leading plus', () {
      expect(TextUtils.prettyPhone('+880 1700-000000'), '+8801700000000');
      expect(TextUtils.prettyPhone('123'), '123');
    });

    test('isValidPhone enforces a plausible digit count', () {
      expect(TextUtils.isValidPhone('12345'), isFalse);
      expect(TextUtils.isValidPhone('123456'), isTrue);
      expect(TextUtils.isValidPhone('+880 1700 000000'), isTrue);
      expect(TextUtils.isValidPhone('1234567890123456'), isFalse);
    });

    test('remainingChars never goes negative', () {
      expect(TextUtils.remainingChars('abc', 5), 2);
      expect(TextUtils.remainingChars('abcde', 5), 0);
      expect(TextUtils.remainingChars('abcdefg', 5), 0);
    });
  });

  group('SizeFormatter', () {
    test('renders zero and small values as bytes', () {
      expect(SizeFormatter.format(0), '0 B');
      expect(SizeFormatter.format(-1), '0 B');
      expect(SizeFormatter.format(512), '512 B');
    });

    test('steps up through KB, MB and GB', () {
      expect(SizeFormatter.format(1024), '1.0 KB');
      expect(SizeFormatter.format(1536), '1.5 KB');
      expect(SizeFormatter.format(1024 * 1024), '1.0 MB');
      expect(SizeFormatter.format(1024 * 1024 * 1024), '1.0 GB');
    });

    test('drops the decimal once the value reaches three digits', () {
      expect(SizeFormatter.format(100 * 1024), '100 KB');
      expect(SizeFormatter.format(1024 * 1024 * 1024 * 2), '2.0 GB');
    });
  });
}
