import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/gift.dart';
import '../utils/firestore_values.dart';
import '../utils/l10n.dart';
import '../utils/stream_retry.dart';

/// Points, premium and gifting, backed by Firestore.
///
/// ### Where the numbers live
///
///   * `users/{uid}.points` — the balance, denormalised so the header renders
///     without summing a ledger.
///   * `users/{uid}.isPremium` / `.premiumUntil` — the premium plan.
///   * `users/{uid}.earn` — the Watch-to-Earn allowance:
///     `{ adsWatchedToday, lastAdWatchedAt, lastAdResetAt, dailyLimit,
///     cooldownSeconds }`. A map rather than five top-level fields so the whole
///     window is one value: it is written as a unit and read as a unit.
///   * `users/{uid}/points_transactions/{txId}` — the ledger, which is the
///     record of *why* the balance is what it is.
///   * `users/{uid}/notifications/{id}` — what the recipient is told.
///
/// The older `adsWatchedDay` / `adsWatchedCount` pair is still read (and still
/// written) so an account created before the rolling window existed does not
/// lose its progress; [accountFrom] prefers `earn` whenever it is present.
///
/// ### Why every mutation is a transaction
///
/// A balance is read-modify-write, and every entry point is a button a user can
/// double-tap. Two concurrent rewards read the same balance and the second write
/// wins, so a user who taps twice gets paid once but spends nothing — or, on a
/// spend, gets the gift twice for one deduction. `runTransaction` makes the read
/// and the write atomic and retries on contention, which is the only correct
/// shape for this. The 24-hour cap and the 3-minute cooldown are enforced
/// *inside* that transaction for the same reason: a check in the UI is a
/// suggestion, not a limit.
///
/// ### Failure policy
///
/// Nothing here throws at the caller. A failed write returns a result with
/// `success: false` and a message worth showing, because every one of these is
/// triggered by a tap and an unhandled exception would surface as a crash
/// rather than "could not send".
class PointsService {
  PointsService({FirebaseFirestore? firestore}) : _db = firestore;

  static const String usersCollection = 'users';
  static const String transactionsCollection = 'points_transactions';
  static const String notificationsCollection = 'notifications';

  /// The `users/{uid}` field holding the whole ad-allowance window.
  static const String earnField = 'earn';

  /// Points granted for one completed rewarded ad.
  static const int pointsPerAd = 25;

  /// Rewarded ads a user may watch inside one 24-hour window.
  static const int dailyAdLimit = 24;

  /// How long the user must wait between two ads.
  static const Duration adCooldown = Duration(seconds: 180);

  /// The length of the allowance window. Anchored at the first ad of the
  /// window, not at midnight — see [PointsAccount.lastAdResetAt].
  static const Duration adWindow = PointsAccount.adWindow;

  /// The most points a user can earn from ads in one window.
  static const int dailyAdPointsCap = pointsPerAd * dailyAdLimit;

  /// The locked-out copy, verbatim, so the screen and the service cannot drift.
  static const String dailyLimitMessage =
      'Come back in 24 hours. $dailyAdLimit ads watched.';

  FirebaseFirestore? _db;

  FirebaseFirestore get _firestore => _db ??= FirebaseFirestore.instance;

  /// `YYYY-MM-DD` for [now], used as the daily bucket key.
  ///
  /// Local time, deliberately: "20 ads a day" means the user's day, not UTC's.
  /// The consequence is that the boundary moves if they travel, which is a
  /// better trade than resetting at an hour that feels arbitrary to them.
  static String dayKey([DateTime? now]) {
    final DateTime d = now ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _firestore.collection(usersCollection).doc(uid);

  // ------------------------------------------------------------------ reads

  /// Live view of a user's balance and premium state.
  ///
  /// Emits [PointsAccount.empty] rather than throwing when there is no uid or
  /// Firestore is unavailable, so the Earn screen renders a zero balance
  /// instead of an error.
  ///
  /// ⚠️ [retryStream], not `handleError`: this stream is what keeps "Today's
  /// ads" and the cooldown countdown live. A returning `handleError` closes the
  /// listener permanently, so one blip would freeze the counter on a stale
  /// number for the rest of the session — and the user would be told to come
  /// back in 24 hours based on a reading that stopped updating.
  Stream<PointsAccount> watchAccount(String uid) {
    if (uid.isEmpty) return Stream<PointsAccount>.value(PointsAccount.empty);
    try {
      return retryStream<PointsAccount>(
        () => _userRef(uid).snapshots().map(
              (DocumentSnapshot<Map<String, dynamic>> snap) =>
                  accountFrom(uid, snap.data()),
            ),
        attempts: 0,
        onError: (Object error, int attempt) =>
            debugPrint('watchAccount($uid) failed (attempt $attempt): $error'),
      );
    } on Object catch (error) {
      debugPrint('watchAccount($uid) unavailable: $error');
      return Stream<PointsAccount>.value(PointsAccount.empty);
    }
  }

  /// Reads the ad-allowance window out of a `users/{uid}` document.
  ///
  /// Returns the raw stored state plus the window rollover already applied, so
  /// the UI never has to decide whether a count is stale. A window whose
  /// [PointsAccount.lastAdResetAt] is 24 hours old reads as zero watched and no
  /// running window — which is what makes the allowance roll over with no
  /// scheduled job.
  @visibleForTesting
  static ({int watched, DateTime? lastWatched, DateTime? lastReset})
      earnWindowFrom(Map<String, dynamic>? data, DateTime now) {
    final Object? rawEarn = data?[earnField];
    final Map<String, dynamic> earn = rawEarn is Map
        ? Map<String, dynamic>.from(rawEarn)
        : const <String, dynamic>{};

    int watched = asInt(earn['adsWatchedToday']);
    final DateTime? lastWatched = asDate(earn['lastAdWatchedAt']);
    DateTime? lastReset = asDate(earn['lastAdResetAt']);

    if (earn.isEmpty) {
      // Legacy shape: a calendar-day bucket. Migrated on the next claim, but
      // read here so the count survives the upgrade.
      final String storedDay = data?['adsWatchedDay'] as String? ?? '';
      if (storedDay == dayKey(now)) {
        watched = asInt(data?['adsWatchedCount']);
        // Treat the legacy day as a window that opened at local midnight, so it
        // expires 24 h later rather than never.
        lastReset = DateTime(now.year, now.month, now.day);
      } else {
        watched = 0;
      }
    }

    if (lastReset != null && now.difference(lastReset) >= adWindow) {
      return (watched: 0, lastWatched: lastWatched, lastReset: null);
    }
    if (watched < 0) watched = 0;
    if (watched > dailyAdLimit) watched = dailyAdLimit;
    return (watched: watched, lastWatched: lastWatched, lastReset: lastReset);
  }

  /// Parses `users/{uid}` into a [PointsAccount].
  ///
  /// Split out from [watchAccount] so it is testable without a snapshot, and so
  /// the stale-window reset lives in exactly one place.
  @visibleForTesting
  static PointsAccount accountFrom(String uid, Map<String, dynamic>? data) {
    if (data == null) return PointsAccount(uid: uid);
    final DateTime now = DateTime.now();
    final ({int watched, DateTime? lastWatched, DateTime? lastReset}) window =
        earnWindowFrom(data, now);
    return PointsAccount(
      uid: uid,
      points: asInt(data['points']),
      isPremium: data['isPremium'] == true,
      premiumUntil: asDate(data['premiumUntil']),
      adsWatchedToday: window.watched,
      lastAdWatchedAt: window.lastWatched,
      lastAdResetAt: window.lastReset,
      dailyAdLimit: dailyAdLimit,
      adCooldownSeconds: adCooldown.inSeconds,
    );
  }

  /// A user's points history, newest first.
  Stream<List<PointsTransaction>> watchTransactions(
    String uid, {
    int limit = 50,
  }) {
    if (uid.isEmpty) {
      return Stream<List<PointsTransaction>>.value(const <PointsTransaction>[]);
    }
    try {
      return retryStream<List<PointsTransaction>>(
        () => _userRef(uid)
            .collection(transactionsCollection)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
                .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    PointsTransaction.fromMap(doc.id, doc.data()))
                .toList(growable: false)),
        attempts: 0,
        onError: (Object error, int attempt) => debugPrint(
            'watchTransactions($uid) failed (attempt $attempt): $error'),
      );
    } on Object catch (error) {
      debugPrint('watchTransactions($uid) unavailable: $error');
      return Stream<List<PointsTransaction>>.value(const <PointsTransaction>[]);
    }
  }

  /// A user's in-app notifications, newest first.
  Stream<List<AppNotification>> watchNotifications(
    String uid, {
    int limit = 30,
  }) {
    if (uid.isEmpty) {
      return Stream<List<AppNotification>>.value(const <AppNotification>[]);
    }
    try {
      return retryStream<List<AppNotification>>(
        () => _userRef(uid)
            .collection(notificationsCollection)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
                .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    AppNotification.fromMap(doc.id, doc.data()))
                .toList(growable: false)),
        attempts: 0,
        onError: (Object error, int attempt) => debugPrint(
            'watchNotifications($uid) failed (attempt $attempt): $error'),
      );
    } on Object catch (error) {
      debugPrint('watchNotifications($uid) unavailable: $error');
      return Stream<List<AppNotification>>.value(const <AppNotification>[]);
    }
  }

  // ---------------------------------------------------------------- earning

  /// Credits [pointsPerAd] for one watched rewarded ad.
  ///
  /// Three rules, all enforced *inside* the transaction against the same read
  /// that produces the new balance:
  ///
  ///   * at most [dailyAdLimit] ads in one [adWindow];
  ///   * at least [adCooldown] between two ads;
  ///   * the window restarts 24 h after the first ad of the previous window.
  ///
  /// Checking any of them in the UI first would be a suggestion, not a limit —
  /// two devices, or two fast taps, would both pass a pre-check and both be
  /// paid. The UI *does* pre-check, but only to avoid showing an ad that cannot
  /// be paid for.
  ///
  /// [viaRewardedInterstitial] only changes the ledger description; the payout
  /// and the rules are identical, because the user watched the same amount of
  /// advertising either way.
  Future<AdRewardResult> claimAdReward(
    String uid, {
    bool viaRewardedInterstitial = false,
  }) async {
    if (uid.isEmpty) {
      return AdRewardResult(
        outcome: AdRewardOutcome.notSignedIn,
        message: L10nRef.current.signInToStartEarning,
      );
    }
    final DocumentReference<Map<String, dynamic>> userRef = _userRef(uid);
    final DocumentReference<Map<String, dynamic>> txRef =
        userRef.collection(transactionsCollection).doc();
    final DateTime now = DateTime.now();
    final String today = dayKey(now);

    try {
      return await _firestore.runTransaction<AdRewardResult>(
        (Transaction tx) async {
          final DocumentSnapshot<Map<String, dynamic>> snap =
              await tx.get(userRef);
          final Map<String, dynamic>? data = snap.data();
          final int balance = asInt(data?['points']);

          final ({int watched, DateTime? lastWatched, DateTime? lastReset})
              window = earnWindowFrom(data, now);
          final int watched = window.watched;

          if (watched >= dailyAdLimit) {
            // The window started at `lastReset`; it ends a full 24 h later. When
            // the marker is missing (a legacy document at the cap) fall back to
            // "24 h from now", which is never earlier than the truth.
            final DateTime resetAt =
                (window.lastReset ?? now).add(adWindow);
            return AdRewardResult(
              outcome: AdRewardOutcome.dailyLimitReached,
              balance: balance,
              adsWatchedToday: watched,
              retryAfter: resetAt,
              message: dailyLimitMessage,
            );
          }

          final DateTime? lastWatched = window.lastWatched;
          if (lastWatched != null) {
            final Duration since = now.difference(lastWatched);
            if (since < adCooldown) {
              final DateTime nextAt = lastWatched.add(adCooldown);
              final int seconds = nextAt.difference(now).inSeconds;
              return AdRewardResult(
                outcome: AdRewardOutcome.cooldown,
                balance: balance,
                adsWatchedToday: watched,
                retryAfter: nextAt,
                message: 'Next ad in ${_mmss(seconds)}',
              );
            }
          }

          final int nextBalance = balance + pointsPerAd;
          final int nextWatched = watched + 1;
          // A missing marker means this claim opens a new window.
          final DateTime windowStart = window.lastReset ?? now;

          tx.set(
            userRef,
            <String, dynamic>{
              'points': nextBalance,
              earnField: <String, dynamic>{
                'adsWatchedToday': nextWatched,
                // Server-resolved on every timestamp, so ordering and the
                // cooldown are the same for every device on the account. A
                // client clock would let a device set an hour fast skip the
                // wait entirely.
                'lastAdWatchedAt': FieldValue.serverTimestamp(),
                'lastAdResetAt': window.lastReset == null
                    ? FieldValue.serverTimestamp()
                    : Timestamp.fromDate(windowStart),
                'dailyLimit': dailyAdLimit,
                'cooldownSeconds': adCooldown.inSeconds,
              },
              // Legacy mirror, so a build that predates the rolling window still
              // shows a sensible "today" count if the user downgrades.
              'adsWatchedDay': today,
              'adsWatchedCount': nextWatched,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          tx.set(txRef, <String, dynamic>{
            'type': 'earn',
            'amount': pointsPerAd,
            'source': PointsSource.rewardedAd.id,
            'description': viaRewardedInterstitial
                ? 'Watched a rewarded interstitial'
                : 'Watched a rewarded ad',
            'dayKey': today,
            'createdAt': FieldValue.serverTimestamp(),
          });

          return AdRewardResult(
            outcome: AdRewardOutcome.granted,
            pointsAwarded: pointsPerAd,
            balance: nextBalance,
            adsWatchedToday: nextWatched,
            message: L10nRef.current.pointsAwarded(pointsPerAd),
          );
        },
      );
    } on Object catch (error) {
      debugPrint('claimAdReward($uid) failed: $error');
      return AdRewardResult(
        outcome: AdRewardOutcome.failed,
        message: L10nRef.current.couldNotAddPoints,
      );
    }
  }

  /// `m:ss` for a countdown, e.g. `2:45`. Clamped at zero.
  static String _mmss(int seconds) {
    final int safe = seconds < 0 ? 0 : seconds;
    final int minutes = safe ~/ 60;
    final int rest = safe % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  /// `m:ss` for a countdown, exposed for the Earn screen's live timer.
  static String countdown(Duration remaining) => _mmss(remaining.inSeconds);

  // ---------------------------------------------------------------- premium

  /// Buys [plan] with points.
  ///
  /// A renewal extends from the current expiry rather than from now, so buying
  /// a second month while the first is still running gives two months instead
  /// of discarding the remainder.
  Future<GiftResult> redeemPremium({
    required String uid,
    required PremiumPlan plan,
  }) async {
    if (uid.isEmpty) {
      return GiftResult(success: false, message: L10nRef.current.signInFirst);
    }
    final DocumentReference<Map<String, dynamic>> userRef = _userRef(uid);
    final DocumentReference<Map<String, dynamic>> txRef =
        userRef.collection(transactionsCollection).doc();
    final DateTime now = DateTime.now();

    try {
      return await _firestore.runTransaction<GiftResult>(
        (Transaction tx) async {
          final DocumentSnapshot<Map<String, dynamic>> snap =
              await tx.get(userRef);
          final Map<String, dynamic>? data = snap.data();
          final int balance = asInt(data?['points']);

          if (balance < plan.points) {
            final int short = plan.points - balance;
            return GiftResult(
              success: false,
              balance: balance,
              message: L10nRef.current.youNeedMorePointsFor(short, plan.name),
            );
          }

          final DateTime? until = dateOf(data?['premiumUntil']);
          final DateTime base =
              (until != null && until.isAfter(now)) ? until : now;
          final DateTime next = base.add(Duration(days: plan.days));
          final int nextBalance = balance - plan.points;

          tx.set(
            userRef,
            <String, dynamic>{
              'points': nextBalance,
              'isPremium': true,
              'premiumUntil': Timestamp.fromDate(next),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          tx.set(txRef, <String, dynamic>{
            'type': 'spend',
            'amount': plan.points,
            'source': PointsSource.premium.id,
            'description': 'Premium — ${plan.name}',
            'dayKey': dayKey(now),
            'createdAt': FieldValue.serverTimestamp(),
          });

          return GiftResult(
            success: true,
            balance: nextBalance,
            message: '${L10nRef.current.premiumActiveUntil}'
                '${next.day}/${next.month}/${next.year}',
          );
        },
      );
    } on Object catch (error) {
      debugPrint('redeemPremium($uid) failed: $error');
      return GiftResult(
        success: false,
        message: L10nRef.current.couldNotActivatePremium,
      );
    }
  }

  // ----------------------------------------------------------------- gifts

  /// Sends [gift] from one user to another.
  ///
  /// Four writes in one transaction, because they are one event: the sender is
  /// debited, the recipient is credited, both ledgers record it, and the
  /// recipient is notified. A partial failure would leave points destroyed or
  /// duplicated, which is exactly what a transaction is for.
  ///
  /// [chatId] and [channelId] are carried onto the notification so tapping it
  /// can open the place the gift was sent.
  Future<GiftResult> sendGift({
    required String fromUid,
    required String fromName,
    required String toUid,
    required String toName,
    required Gift gift,
    String chatId = '',
    String channelId = '',
  }) async {
    if (fromUid.isEmpty) {
      return GiftResult(success: false, message: L10nRef.current.signInFirst);
    }
    if (toUid.isEmpty) {
      return GiftResult(
        success: false,
        message: L10nRef.current.thisContactHasNoAccount,
      );
    }
    if (fromUid == toUid) {
      return const GiftResult(
        success: false,
        message: "You can't send a gift to yourself",
      );
    }

    final DocumentReference<Map<String, dynamic>> fromRef = _userRef(fromUid);
    final DocumentReference<Map<String, dynamic>> toRef = _userRef(toUid);
    final DocumentReference<Map<String, dynamic>> fromTxRef =
        fromRef.collection(transactionsCollection).doc();
    final DocumentReference<Map<String, dynamic>> toTxRef =
        toRef.collection(transactionsCollection).doc();
    final DocumentReference<Map<String, dynamic>> noteRef =
        toRef.collection(notificationsCollection).doc();
    final String today = dayKey();
    final String senderLabel = fromName.trim().isEmpty ? 'Someone' : fromName;

    try {
      return await _firestore.runTransaction<GiftResult>(
        (Transaction tx) async {
          // Both balances are read before either is written: a transaction's
          // reads must all precede its writes.
          final DocumentSnapshot<Map<String, dynamic>> fromSnap =
              await tx.get(fromRef);
          final DocumentSnapshot<Map<String, dynamic>> toSnap =
              await tx.get(toRef);

          final int balance = asInt(fromSnap.data()?['points']);
          if (balance < gift.points) {
            final int short = gift.points - balance;
            return GiftResult(
              success: false,
              balance: balance,
              message: L10nRef.current.youNeedMorePointsForAGift(short, gift.name),
            );
          }

          final int recipientBalance = asInt(toSnap.data()?['points']);
          final int nextBalance = balance - gift.points;

          tx.set(
            fromRef,
            <String, dynamic>{
              'points': nextBalance,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          tx.set(
            toRef,
            <String, dynamic>{
              'points': recipientBalance + gift.points,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          tx.set(fromTxRef, <String, dynamic>{
            'type': 'spend',
            'amount': gift.points,
            'source': PointsSource.giftSent.id,
            'description': '${gift.name} to ${toName.trim().isEmpty ? 'a contact' : toName}',
            'dayKey': today,
            'counterpartyId': toUid,
            'counterpartyName': toName,
            'giftId': gift.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(toTxRef, <String, dynamic>{
            'type': 'earn',
            'amount': gift.points,
            'source': PointsSource.giftReceived.id,
            'description': '${gift.name} from $senderLabel',
            'dayKey': today,
            'counterpartyId': fromUid,
            'counterpartyName': senderLabel,
            'giftId': gift.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(noteRef, <String, dynamic>{
            'title': '$senderLabel sent you a ${gift.name}',
            'body': '${gift.emoji} +${gift.points} points',
            'icon': gift.emoji,
            'read': false,
            'giftId': gift.id,
            'fromUid': fromUid,
            'chatId': chatId,
            'channelId': channelId,
            'createdAt': FieldValue.serverTimestamp(),
          });

          return GiftResult(
            success: true,
            balance: nextBalance,
            message: L10nRef.current.giftSent(gift.emoji, gift.name),
          );
        },
      );
    } on Object catch (error) {
      debugPrint('sendGift($fromUid -> $toUid) failed: $error');
      return GiftResult(
        success: false,
        message: L10nRef.current.couldNotSendTheGift,
      );
    }
  }

  // ---------------------------------------------------------- notifications

  /// Marks every unread notification as read.
  Future<void> markNotificationsRead(String uid) async {
    if (uid.isEmpty) return;
    try {
      final QuerySnapshot<Map<String, dynamic>> unread = await _userRef(uid)
          .collection(notificationsCollection)
          .where('read', isEqualTo: false)
          .limit(100)
          .get();
      if (unread.docs.isEmpty) return;
      final WriteBatch batch = _firestore.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in unread.docs) {
        batch.update(doc.reference, <String, dynamic>{'read': true});
      }
      await batch.commit();
    } on Object catch (error) {
      debugPrint('markNotificationsRead($uid) failed: $error');
    }
  }

  /// Coerces whatever Firestore returned into a [DateTime].
  ///
  /// A thin alias for [asDate], kept because the ledger and the account both
  /// read dates and this is the name the tests use.
  @visibleForTesting
  static DateTime? dateOf(Object? value) => asDate(value);
}
