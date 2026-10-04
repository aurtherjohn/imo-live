import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/gift.dart';
import 'package:imo_live/core/services/points_service.dart';
import 'package:imo_live/core/services/premium_service.dart';

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

    test('the daily limit is 24 ads', () {
      expect(PointsService.dailyAdLimit, 24);
    });

    test('the cooldown is 3 minutes and the window is 24 hours', () {
      expect(PointsService.adCooldown, const Duration(minutes: 3));
      expect(PointsService.adWindow, const Duration(hours: 24));
    });

    test('the lock message names the same number the cap enforces', () {
      // The message is shown verbatim to the user; if the cap changes and this
      // does not, the app tells them to come back after a number of ads it no
      // longer uses.
      expect(PointsService.dailyLimitMessage, contains('24 ads'));
      expect(PointsService.dailyLimitMessage, contains('24 hours'));
    });
  });

  group('PointsService.earnWindowFrom', () {
    test('reads the rolling window out of the earn map', () {
      final DateTime now = DateTime(2026, 10, 4, 12);
      final ({int watched, DateTime? lastWatched, DateTime? lastReset}) window =
          PointsService.earnWindowFrom(<String, dynamic>{
        'earn': <String, dynamic>{
          'adsWatchedToday': 5,
          'lastAdWatchedAt': Timestamp.fromDate(
            now.subtract(const Duration(minutes: 10)),
          ),
          'lastAdResetAt': Timestamp.fromDate(
            now.subtract(const Duration(hours: 2)),
          ),
          'dailyLimit': 24,
          'cooldownSeconds': 180,
        },
      }, now);

      expect(window.watched, 5);
      expect(window.lastWatched, isNotNull);
      expect(window.lastReset, isNotNull);
    });

    test('a window older than 24 hours reads as zero watched', () {
      final DateTime now = DateTime(2026, 10, 4, 12);
      final ({int watched, DateTime? lastWatched, DateTime? lastReset}) window =
          PointsService.earnWindowFrom(<String, dynamic>{
        'earn': <String, dynamic>{
          'adsWatchedToday': 24,
          'lastAdResetAt': Timestamp.fromDate(
            now.subtract(const Duration(hours: 24, minutes: 1)),
          ),
        },
      }, now);

      expect(window.watched, 0);
      // No running window, so the next claim opens a fresh one.
      expect(window.lastReset, isNull);
    });

    test('a stored count is clamped to the cap', () {
      // A hand-edited or corrupted document must not report more ads watched
      // than the cap allows — the UI renders this number directly.
      final DateTime now = DateTime(2026, 10, 4, 12);
      final ({int watched, DateTime? lastWatched, DateTime? lastReset}) window =
          PointsService.earnWindowFrom(<String, dynamic>{
        'earn': <String, dynamic>{
          'adsWatchedToday': 9999,
          'lastAdResetAt': Timestamp.fromDate(
            now.subtract(const Duration(minutes: 5)),
          ),
        },
      }, now);

      expect(window.watched, PointsService.dailyAdLimit);
    });

    test('an absent document is an empty window, not a crash', () {
      final ({int watched, DateTime? lastWatched, DateTime? lastReset}) window =
          PointsService.earnWindowFrom(null, DateTime(2026, 10, 4, 12));

      expect(window.watched, 0);
      expect(window.lastWatched, isNull);
      expect(window.lastReset, isNull);
    });
  });

  group('PointsService.countdown', () {
    test('formats as m:ss and pads the seconds', () {
      expect(PointsService.countdown(const Duration(minutes: 2, seconds: 45)),
          '2:45');
      expect(PointsService.countdown(const Duration(seconds: 9)), '0:09');
      expect(PointsService.countdown(Duration.zero), '0:00');
    });

    test('a negative remainder clamps to zero rather than rendering -1:-5', () {
      expect(PointsService.countdown(const Duration(seconds: -65)), '0:00');
    });
  });

  group('PointsAccount ad gating', () {
    test('the limit reads as reached at exactly the cap', () {
      const PointsAccount atCap = PointsAccount(adsWatchedToday: 24);
      const PointsAccount under = PointsAccount(adsWatchedToday: 23);

      expect(atCap.adLimitReached, isTrue);
      expect(under.adLimitReached, isFalse);
    });

    test('the cooldown counts down from the last ad, and expires', () {
      final DateTime now = DateTime(2026, 10, 4, 12);
      final PointsAccount account = PointsAccount(
        adsWatchedToday: 3,
        lastAdWatchedAt: now.subtract(const Duration(seconds: 75)),
      );

      // 180 s cooldown, 75 s elapsed → 105 s left.
      expect(account.cooldownRemainingAt(now), const Duration(seconds: 105));

      final DateTime later = now.add(const Duration(minutes: 3));
      expect(account.cooldownRemainingAt(later), Duration.zero);
    });

    test('no cooldown before the first ad', () {
      const PointsAccount fresh = PointsAccount();
      expect(fresh.cooldownRemainingAt(DateTime(2026, 10, 4, 12)), Duration.zero);
    });
  });

  group('PremiumService pricing', () {
    test('a month of premium costs a month of the maximum ad allowance', () {
      // The points rail is only an honest alternative to paying if the ads
      // really do pay for it — so this must stay equal to
      // `pointsPerAd * dailyAdLimit * 30`.
      expect(
        PremiumService.calculatePointsForPremium(),
        PointsService.pointsPerAd * PointsService.dailyAdLimit * 30,
      );
      expect(PremiumService.calculatePointsForPremium(), 18000);
    });

    test('the points plan is a 30-day plan at the calculated price', () {
      final PremiumPlan plan = PremiumService.pointsPlan;

      expect(plan.days, PremiumService.duration.inDays);
      expect(plan.points, PremiumService.calculatePointsForPremium());
    });

    test('every payment method round-trips through its stored id', () {
      for (final PremiumPaymentMethod method in PremiumPaymentMethod.values) {
        expect(PremiumPaymentMethod.fromId(method.id), method);
      }
    });

    test('every payment method has a destination to show the user', () {
      for (final PremiumPaymentMethod method in PremiumPaymentMethod.values) {
        final PremiumPaymentTarget target =
            PremiumPaymentTarget.targets[method]!;
        expect(target.destination, isNotEmpty);
        expect(target.instructions, isNotEmpty);
      }
    });
  });
}
