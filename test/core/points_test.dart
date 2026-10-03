import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/gift.dart';
import 'package:imo_live/core/services/points_service.dart';

void main() {
  group('PointsService.dayKey', () {
    test('pads month and day to two digits', () {
      // The key is compared for equality against a stored string, so
      // '2026-9-8' and '2026-09-08' must not both be producible.
      expect(PointsService.dayKey(DateTime(2026, 9, 8)), '2026-09-08');
      expect(PointsService.dayKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(PointsService.dayKey(DateTime(2026, 1, 1)), '2026-01-01');
    });

    test('two moments in the same local day share a key', () {
      expect(
        PointsService.dayKey(DateTime(2026, 9, 8, 0, 0, 1)),
        PointsService.dayKey(DateTime(2026, 9, 8, 23, 59, 59)),
      );
    });
  });

  group('PointsService.accountFrom', () {
    test('a missing document is a zero balance, not a crash', () {
      final PointsAccount account = PointsService.accountFrom('u1', null);

      expect(account.uid, 'u1');
      expect(account.points, 0);
      expect(account.isPremium, isFalse);
      expect(account.adsWatchedToday, 0);
    });

    test('reads points and the daily ad count for today', () {
      final PointsAccount account = PointsService.accountFrom('u1', <String, dynamic>{
        'points': 1250,
        'adsWatchedDay': PointsService.dayKey(),
        'adsWatchedCount': 7,
      });

      expect(account.points, 1250);
      expect(account.adsWatchedToday, 7);
    });

    test("a count from an earlier day reads as zero today", () {
      // The allowance rolls over lazily: nothing has to clear the counter at
      // midnight, the read just stops believing a stale day.
      final PointsAccount account = PointsService.accountFrom('u1', <String, dynamic>{
        'points': 500,
        'adsWatchedDay': '2020-01-01',
        'adsWatchedCount': 20,
      });

      expect(account.adsWatchedToday, 0);
      // The balance is not affected by the rollover.
      expect(account.points, 500);
    });

    test('a malformed count is treated as zero', () {
      final PointsAccount account = PointsService.accountFrom('u1', <String, dynamic>{
        'points': 'lots',
        'adsWatchedDay': PointsService.dayKey(),
        'adsWatchedCount': null,
      });

      expect(account.points, 0);
      expect(account.adsWatchedToday, 0);
    });

    test('premium is active while premiumUntil is in the future', () {
      final DateTime future = DateTime.now().add(const Duration(days: 10));
      final PointsAccount account = PointsService.accountFrom('u1', <String, dynamic>{
        'isPremium': true,
        'premiumUntil': Timestamp.fromDate(future),
      });

      expect(account.premiumActive, isTrue);
      expect(account.premiumDaysLeft, greaterThanOrEqualTo(9));
    });

    test('a lapsed plan stops reporting premium', () {
      // `isPremium` is left true by the server — nothing clears it — so the
      // date has to be what decides.
      final DateTime past = DateTime.now().subtract(const Duration(days: 1));
      final PointsAccount account = PointsService.accountFrom('u1', <String, dynamic>{
        'isPremium': true,
        'premiumUntil': Timestamp.fromDate(past),
      });

      expect(account.premiumActive, isFalse);
      expect(account.premiumDaysLeft, 0);
    });

    test('isPremium false is not premium even with a future date', () {
      final DateTime future = DateTime.now().add(const Duration(days: 10));
      final PointsAccount account = PointsService.accountFrom('u1', <String, dynamic>{
        'isPremium': false,
        'premiumUntil': Timestamp.fromDate(future),
      });

      expect(account.premiumActive, isFalse);
    });
  });

  group('PointsService.dateOf', () {
    test('accepts a Timestamp, a DateTime and an int', () {
      final DateTime when = DateTime(2026, 9, 8, 12);
      expect(PointsService.dateOf(Timestamp.fromDate(when)), when);
      expect(PointsService.dateOf(when), when);
      expect(
        PointsService.dateOf(when.millisecondsSinceEpoch),
        when,
      );
    });

    test('returns null for anything it cannot read', () {
      // A fabricated date would be worse than none: it would show a gift as
      // having arrived now.
      expect(PointsService.dateOf(null), isNull);
      expect(PointsService.dateOf('yesterday'), isNull);
      expect(PointsService.dateOf(<String, dynamic>{}), isNull);
    });
  });

  group('PointsSource', () {
    test('round-trips through its stored id', () {
      for (final PointsSource source in PointsSource.values) {
        expect(PointsSource.fromId(source.id), source);
      }
    });

    test('an unknown source is a bonus rather than an error', () {
      expect(PointsSource.fromId('something_new'), PointsSource.bonus);
      expect(PointsSource.fromId(null), PointsSource.bonus);
    });
  });

  group('Gift catalogue', () {
    test('every gift has a unique id and a positive cost', () {
      final Set<String> ids = <String>{};
      for (final Gift gift in Gift.catalogue) {
        expect(ids.add(gift.id), isTrue, reason: '${gift.id} is duplicated');
        expect(gift.points, greaterThan(0));
        expect(gift.emoji, isNotEmpty);
        expect(gift.name, isNotEmpty);
      }
    });

    test('contains the gifts the spec calls out', () {
      expect(Gift.byId('rose'), isNotNull);
      expect(Gift.byId('diamond'), isNotNull);
      expect(Gift.byId('trophy'), isNotNull);
    });

    test('byId returns null for an unknown gift', () {
      expect(Gift.byId('unicorn'), isNull);
    });

    test('the catalogue is ordered cheapest first', () {
      final List<int> costs =
          Gift.catalogue.map((Gift g) => g.points).toList(growable: false);
      final List<int> sorted = List<int>.from(costs)..sort();
      expect(costs, sorted);
    });
  });

  group('Gift message encoding', () {
    test('round-trips every gift in the catalogue', () {
      for (final Gift gift in Gift.catalogue) {
        final ({String emoji, String name, int points})? decoded =
            Gift.decodeMessageBody(gift.toMessageBody());

        expect(decoded, isNotNull, reason: '${gift.id} did not decode');
        expect(decoded!.emoji, gift.emoji);
        expect(decoded.name, gift.name);
        expect(decoded.points, gift.points);
      }
    });

    test('a plain message does not decode as a gift', () {
      // This is the guard that keeps an ordinary message from rendering as a
      // gift bubble.
      expect(Gift.decodeMessageBody('hello there'), isNull);
      expect(Gift.decodeMessageBody(''), isNull);
      expect(Gift.decodeMessageBody('a|b'), isNull);
      expect(Gift.decodeMessageBody('a|b|c|d'), isNull);
    });

    test('a gift body with a non-numeric cost is rejected', () {
      expect(Gift.decodeMessageBody('🌹|Rose|free'), isNull);
    });

    test('a gift body with an empty part is rejected', () {
      expect(Gift.decodeMessageBody('|Rose|10'), isNull);
      expect(Gift.decodeMessageBody('🌹||10'), isNull);
    });
  });

  group('PremiumPlan', () {
    test('every plan costs less per day than the one before it', () {
      // The longer commitment should be the better deal, otherwise the pricing
      // is telling users to buy the short one.
      final List<double> perDay = PremiumPlan.plans
          .map((PremiumPlan p) => p.points / p.days)
          .toList(growable: false);

      for (int i = 1; i < perDay.length; i++) {
        expect(perDay[i], lessThan(perDay[i - 1]));
      }
    });

    test('the monthly plan costs the documented 5000 points', () {
      expect(
        PremiumPlan.plans.firstWhere((PremiumPlan p) => p.id == 'month').points,
        5000,
      );
    });
  });

  group('PointsTransaction', () {
    test('parses a ledger entry', () {
      final PointsTransaction entry = PointsTransaction.fromMap(
        'tx1',
        <String, dynamic>{
          'type': 'spend',
          'amount': 100,
          'source': 'gift_sent',
          'description': 'Diamond to Bob',
          'dayKey': '2026-09-08',
          'counterpartyId': 'bob',
          'counterpartyName': 'Bob',
        },
      );

      expect(entry.type, PointsTransactionType.spend);
      expect(entry.amount, 100);
      expect(entry.source, PointsSource.giftSent);
      expect(entry.isEarn, isFalse);
      expect(entry.signedAmount, -100);
      expect(entry.counterpartyId, 'bob');
    });

    test('an earn entry reports a positive signed amount', () {
      final PointsTransaction entry = PointsTransaction.fromMap(
        'tx2',
        <String, dynamic>{
          'type': 'earn',
          'amount': 25,
          'source': 'rewarded_ad',
        },
      );

      expect(entry.isEarn, isTrue);
      expect(entry.signedAmount, 25);
    });

    test('an empty entry is an earn of zero rather than a crash', () {
      final PointsTransaction entry =
          PointsTransaction.fromMap('tx3', <String, dynamic>{});

      expect(entry.amount, 0);
      expect(entry.isEarn, isTrue);
      expect(entry.createdAt, isNull);
    });
  });

  group('AppNotification', () {
    test('parses a gift receipt and keeps where it came from', () {
      final AppNotification note = AppNotification.fromMap(
        'n1',
        <String, dynamic>{
          'title': 'Alice sent you a Rose',
          'body': '🌹 +10 points',
          'icon': '🌹',
          'giftId': 'rose',
          'fromUid': 'alice',
          'chatId': 'chat_1',
          'read': false,
        },
      );

      expect(note.title, 'Alice sent you a Rose');
      expect(note.giftId, 'rose');
      expect(note.fromUid, 'alice');
      expect(note.chatId, 'chat_1');
      expect(note.read, isFalse);
    });

    test('a channel gift keeps the channel id', () {
      final AppNotification note = AppNotification.fromMap(
        'n2',
        <String, dynamic>{'channelId': 'chan_1'},
      );

      expect(note.channelId, 'chan_1');
      expect(note.chatId, isEmpty);
    });

    test('an empty document is an unread gift icon', () {
      final AppNotification note =
          AppNotification.fromMap('n3', <String, dynamic>{});

      expect(note.icon, '🎁');
      expect(note.read, isFalse);
      expect(note.createdAt, isNull);
    });
  });

  group('Daily ad allowance', () {
    test('the cap is the per-ad payout times the daily limit', () {
      expect(
        PointsService.dailyAdPointsCap,
        PointsService.pointsPerAd * PointsService.dailyAdLimit,
      );
    });

    test('the daily limit is 20 ads', () {
      expect(PointsService.dailyAdLimit, 20);
    });
  });
}
