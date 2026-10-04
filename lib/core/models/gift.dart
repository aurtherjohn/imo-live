import 'package:flutter/foundation.dart';

import '../utils/firestore_values.dart';

/// A gift that can be sent to another user, paid for out of a points balance.
///
/// Gifts are a fixed catalogue rather than a free-form amount so that the cost
/// of any gift is knowable before it is sent, and so both sides can render the
/// same thing from the same id — a gift message carries [id] and [emoji] and
/// nothing else has to be looked up.
@immutable
class Gift {
  const Gift({
    required this.id,
    required this.name,
    required this.emoji,
    required this.points,
  });

  /// Stable id, stored on the message and the ledger entry.
  final String id;

  /// Display name, e.g. "Diamond".
  final String name;

  /// The glyph that renders the gift. Emoji rather than an asset so a gift
  /// needs no bundled image and cannot fail to load.
  final String emoji;

  /// What it costs the sender.
  final int points;

  /// The catalogue, cheapest first.
  static const List<Gift> catalogue = <Gift>[
    Gift(id: 'rose', name: 'Rose', emoji: '🌹', points: 10),
    Gift(id: 'heart', name: 'Heart', emoji: '❤️', points: 25),
    Gift(id: 'coffee', name: 'Coffee', emoji: '☕', points: 50),
    Gift(id: 'diamond', name: 'Diamond', emoji: '💎', points: 100),
    Gift(id: 'crown', name: 'Crown', emoji: '👑', points: 250),
    Gift(id: 'trophy', name: 'Trophy', emoji: '🏆', points: 500),
    Gift(id: 'rocket', name: 'Rocket', emoji: '🚀', points: 1000),
  ];

  /// Looks a gift up by id, or null when the id is not in the catalogue.
  ///
  /// Null rather than a placeholder: an unknown gift means the sender and this
  /// build disagree about the catalogue, and showing a made-up gift would
  /// misreport what was actually sent.
  static Gift? byId(String id) {
    for (final Gift gift in catalogue) {
      if (gift.id == id) return gift;
    }
    return null;
  }

  /// Encodes this gift as a message body.
  ///
  /// A delimited string rather than a JSON blob because the body is also what
  /// the chat-list preview and the search index read — those want plain text,
  /// and a JSON document would leak braces into both. The separator is `|`,
  /// which no gift name contains.
  String toMessageBody() => '$emoji|$name|$points';

  /// Decodes a [toMessageBody] string.
  ///
  /// Returns null for anything that is not a well-formed gift body, so a caller
  /// can fall back to rendering the raw text instead of inventing a gift. The
  /// points are carried in the body on purpose: the bubble can then report what
  /// was actually spent even if the catalogue has since changed.
  static ({String emoji, String name, int points})? decodeMessageBody(
    String content,
  ) {
    final List<String> parts = content.split('|');
    if (parts.length != 3) return null;
    final String emoji = parts[0].trim();
    final String name = parts[1].trim();
    final int? points = int.tryParse(parts[2].trim());
    if (emoji.isEmpty || name.isEmpty || points == null) return null;
    return (emoji: emoji, name: name, points: points);
  }
}

/// Which way points moved in one ledger entry.
enum PointsTransactionType { earn, spend }

/// Why points moved. Drives the icon and the wording in the history list.
enum PointsSource {
  /// A rewarded ad was watched to completion.
  rewardedAd,

  /// A premium plan was bought with points.
  premium,

  /// A gift was sent to somebody.
  giftSent,

  /// A gift was received from somebody.
  giftReceived,

  /// Anything granted outside the normal flows.
  bonus;

  /// The string stored in Firestore.
  String get id => switch (this) {
        PointsSource.rewardedAd => 'rewarded_ad',
        PointsSource.premium => 'premium',
        PointsSource.giftSent => 'gift_sent',
        PointsSource.giftReceived => 'gift_received',
        PointsSource.bonus => 'bonus',
      };

  /// Human label for the history row.
  String get label => switch (this) {
        PointsSource.rewardedAd => 'Watched an ad',
        PointsSource.premium => 'Premium',
        PointsSource.giftSent => 'Gift sent',
        PointsSource.giftReceived => 'Gift received',
        PointsSource.bonus => 'Bonus',
      };

  static PointsSource fromId(String? id) => switch (id) {
        'rewarded_ad' => PointsSource.rewardedAd,
        'premium' => PointsSource.premium,
        'gift_sent' => PointsSource.giftSent,
        'gift_received' => PointsSource.giftReceived,
        _ => PointsSource.bonus,
      };
}

/// One line of a user's points history.
///
/// The ledger is the source of truth for *why* a balance is what it is; the
/// balance itself is denormalised onto the user document so the header does not
/// have to sum the ledger on every frame.
@immutable
class PointsTransaction {
  const PointsTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.source,
    required this.description,
    this.dayKey = '',
    this.counterpartyId = '',
    this.counterpartyName = '',
    this.createdAt,
  });

  final String id;
  final PointsTransactionType type;

  /// Always positive; [type] carries the direction.
  final int amount;

  final PointsSource source;
  final String description;

  /// `YYYY-MM-DD`, used to bucket the daily ad allowance.
  final String dayKey;

  final String counterpartyId;
  final String counterpartyName;

  /// Server-stamped. Never a client clock — see the time-sync rule.
  final DateTime? createdAt;

  /// Signed amount, for display.
  int get signedAmount =>
      type == PointsTransactionType.earn ? amount : -amount;

  bool get isEarn => type == PointsTransactionType.earn;

  static PointsTransaction fromMap(String id, Map<String, dynamic> data) {
    return PointsTransaction(
      id: id,
      type: data['type'] == 'spend'
          ? PointsTransactionType.spend
          : PointsTransactionType.earn,
      amount: asInt(data['amount']),
      source: PointsSource.fromId(data['source'] as String?),
      description: data['description'] as String? ?? '',
      dayKey: data['dayKey'] as String? ?? '',
      counterpartyId: data['counterpartyId'] as String? ?? '',
      counterpartyName: data['counterpartyName'] as String? ?? '',
      createdAt: switch (data['createdAt']) {
        final Object value when value is DateTime => value,
        final Object value when value is int =>
          DateTime.fromMillisecondsSinceEpoch(value),
        _ => null,
      },
    );
  }
}

/// A premium plan that can be bought with points.
@immutable
class PremiumPlan {
  const PremiumPlan({
    required this.id,
    required this.name,
    required this.days,
    required this.points,
  });

  final String id;
  final String name;

  /// How long the plan lasts.
  final int days;

  /// What it costs in points.
  final int points;

  static const List<PremiumPlan> plans = <PremiumPlan>[
    PremiumPlan(id: 'month', name: '1 month', days: 30, points: 5000),
    PremiumPlan(id: 'quarter', name: '3 months', days: 90, points: 13500),
    PremiumPlan(id: 'year', name: '12 months', days: 365, points: 48000),
  ];
}

/// A user's points balance, premium state and daily ad-allowance state, as read
/// from `users/{uid}`.
@immutable
class PointsAccount {
  const PointsAccount({
    this.uid = '',
    this.points = 0,
    this.isPremium = false,
    this.premiumUntil,
    this.adsWatchedToday = 0,
    this.lastAdWatchedAt,
    this.lastAdResetAt,
    this.dailyAdLimit = 24,
    this.adCooldownSeconds = 180,
  });

  final String uid;
  final int points;

  /// True while a premium plan is running.
  ///
  /// Derived from [premiumUntil] where one is set, so a lapsed plan stops
  /// reporting premium without anybody having to clear the flag.
  final bool isPremium;

  /// When the current plan runs out, or null when there is none.
  final DateTime? premiumUntil;

  /// Ads watched inside the current 24-hour window, already reset to 0 when the
  /// window has rolled over. The UI reads this directly for "Today's ads: 7/24".
  final int adsWatchedToday;

  /// When the last ad was completed. Drives the 3-minute cooldown.
  ///
  /// Server-stamped, so it is the same instant for every device signed into the
  /// account. Null before the first ad ever watched.
  final DateTime? lastAdWatchedAt;

  /// When the current 24-hour window started.
  ///
  /// The window is anchored here rather than at midnight: the counter resets
  /// exactly 24 hours after the *first* ad of the window, which is what makes
  /// "come back in 24 hours" an honest statement.
  final DateTime? lastAdResetAt;

  /// How many ads the window allows.
  final int dailyAdLimit;

  /// How long the user must wait between two ads.
  final int adCooldownSeconds;

  static const PointsAccount empty = PointsAccount();

  /// True when a premium plan is live right now.
  bool get premiumActive {
    if (!isPremium) return false;
    final DateTime? until = premiumUntil;
    if (until == null) return true;
    return until.isAfter(DateTime.now());
  }

  /// Whole days left on the plan, or 0.
  int get premiumDaysLeft {
    final DateTime? until = premiumUntil;
    if (until == null) return 0;
    final Duration left = until.difference(DateTime.now());
    return left.isNegative ? 0 : left.inDays;
  }

  /// The window's length. Kept next to [lastAdResetAt] so the two cannot drift.
  static const Duration adWindow = Duration(hours: 24);

  Duration get adCooldown => Duration(seconds: adCooldownSeconds);

  /// The daily allowance is used up.
  bool get adLimitReached => adsWatchedToday >= dailyAdLimit;

  /// When the current window rolls over, or null when no window is running.
  DateTime? get adsResetAt => lastAdResetAt?.add(adWindow);

  /// How long until the next ad may be watched.
  ///
  /// Zero when the button is free. The limit is *not* considered here — a caller
  /// that needs "can I watch right now" must also check [adLimitReached].
  Duration cooldownRemainingAt(DateTime now) {
    final DateTime? last = lastAdWatchedAt;
    if (last == null) return Duration.zero;
    final Duration left = last.add(adCooldown).difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// The outcome of trying to claim a rewarded-ad payout.
enum AdRewardOutcome {
  /// Points were granted.
  granted,

  /// The 24-hour window's allowance is already used up.
  dailyLimitReached,

  /// Not enough time has passed since the previous ad.
  cooldown,

  /// No signed-in account to credit.
  notSignedIn,

  /// Firestore refused the write.
  failed,
}

/// What happened when an ad payout was claimed.
@immutable
class AdRewardResult {
  const AdRewardResult({
    required this.outcome,
    this.pointsAwarded = 0,
    this.balance = 0,
    this.adsWatchedToday = 0,
    this.message = '',
    this.retryAfter,
  });

  final AdRewardOutcome outcome;
  final int pointsAwarded;

  /// The balance after the award, so the UI can show the new total without a
  /// second read that might arrive late.
  final int balance;

  final int adsWatchedToday;
  final String message;

  /// When the next ad becomes available, for [AdRewardOutcome.cooldown] and
  /// [AdRewardOutcome.dailyLimitReached]. Null for the other outcomes.
  final DateTime? retryAfter;

  bool get isSuccess => outcome == AdRewardOutcome.granted;
}

/// What happened when a gift was sent.
@immutable
class GiftResult {
  const GiftResult({
    required this.success,
    this.message = '',
    this.balance = 0,
  });

  final bool success;
  final String message;
  final int balance;
}

/// An in-app notification, stored at `users/{uid}/notifications/{id}`.
///
/// Deliberately separate from the local push notifications: a gift has to reach
/// the recipient even when their device is offline at the moment it is sent, so
/// it is written to Firestore and read back when they next open the app.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.icon = '🎁',
    this.read = false,
    this.giftId = '',
    this.fromUid = '',
    this.chatId = '',
    this.channelId = '',
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String icon;
  final bool read;

  /// The gift this notification is about, or empty when it is not a gift.
  final String giftId;

  /// Who triggered it.
  final String fromUid;

  /// Where the gift was sent, so tapping the row can open that place. Both are
  /// empty for a notification that did not come from a conversation.
  final String chatId;
  final String channelId;

  final DateTime? createdAt;

  static AppNotification fromMap(String id, Map<String, dynamic> data) {
    return AppNotification(
      id: id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      icon: data['icon'] as String? ?? '🎁',
      read: data['read'] == true,
      giftId: data['giftId'] as String? ?? '',
      fromUid: data['fromUid'] as String? ?? '',
      chatId: data['chatId'] as String? ?? '',
      channelId: data['channelId'] as String? ?? '',
      createdAt: switch (data['createdAt']) {
        final Object value when value is DateTime => value,
        final Object value when value is int =>
          DateTime.fromMillisecondsSinceEpoch(value),
        _ => null,
      },
    );
  }
}
