import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/gift.dart';
import '../utils/firestore_values.dart';
import '../utils/l10n.dart';

/// Points, premium and gifting, backed by Firestore.
///
/// ### Where the numbers live
///
///   * `users/{uid}.points` — the balance, denormalised so the header renders
///     without summing a ledger.
///   * `users/{uid}.isPremium` / `.premiumUntil` — the premium plan.
///   * `users/{uid}.adsWatchedDay` / `.adsWatchedCount` — the daily ad
///     allowance, as a counter rather than a query. A counter is one read and
///     needs no composite index; counting ledger entries would need both.
///   * `users/{uid}/points_transactions/{txId}` — the ledger, which is the
///     record of *why* the balance is what it is.
///   * `users/{uid}/notifications/{id}` — what the recipient is told.
///
/// ### Why every mutation is a transaction
///
/// A balance is read-modify-write, and every entry point is a button a user can
/// double-tap. Two concurrent rewards read the same balance and the second write
/// wins, so a user who taps twice gets paid once but spends nothing — or, on a
/// spend, gets the gift twice for one deduction. `runTransaction` makes the read
/// and the write atomic and retries on contention, which is the only correct
/// shape for this.
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

  /// Points granted for one completed rewarded ad.
  static const int pointsPerAd = 25;

  /// Rewarded ads a user may watch in a day.
  static const int dailyAdLimit = 20;

  /// The most points a user can earn from ads in one day.
  static const int dailyAdPointsCap = pointsPerAd * dailyAdLimit;

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
  Stream<PointsAccount> watchAccount(String uid) {
    if (uid.isEmpty) return Stream<PointsAccount>.value(PointsAccount.empty);
    try {
      return _userRef(uid)
          .snapshots()
          .map((DocumentSnapshot<Map<String, dynamic>> snap) =>
              accountFrom(uid, snap.data()))
          .handleError((Object error) {
        debugPrint('watchAccount($uid) failed: $error');
      });
    } on Object catch (error) {
      debugPrint('watchAccount($uid) unavailable: $error');
      return Stream<PointsAccount>.value(PointsAccount.empty);
    }
  }

  /// Parses `users/{uid}` into a [PointsAccount].
  ///
  /// Split out from [watchAccount] so it is testable without a snapshot, and so
  /// the stale-day reset lives in exactly one place: a stored count from an
  /// earlier day is reported as 0 today, which is what lets the allowance roll
  /// over without a scheduled job to clear it.
  @visibleForTesting
  static PointsAccount accountFrom(String uid, Map<String, dynamic>? data) {
    if (data == null) return PointsAccount(uid: uid);
    final String storedDay = data['adsWatchedDay'] as String? ?? '';
    return PointsAccount(
      uid: uid,
      points: asInt(data['points']),
      isPremium: data['isPremium'] == true,
      premiumUntil: dateOf(data['premiumUntil']),
      adsWatchedToday: storedDay == dayKey()
          ? asInt(data['adsWatchedCount'])
          : 0,
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
      return _userRef(uid)
          .collection(transactionsCollection)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  PointsTransaction.fromMap(doc.id, doc.data()))
              .toList(growable: false))
          .handleError((Object error) {
        debugPrint('watchTransactions($uid) failed: $error');
      });
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
      return _userRef(uid)
          .collection(notificationsCollection)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  AppNotification.fromMap(doc.id, doc.data()))
              .toList(growable: false))
          .handleError((Object error) {
        debugPrint('watchNotifications($uid) failed: $error');
      });
    } on Object catch (error) {
      debugPrint('watchNotifications($uid) unavailable: $error');
      return Stream<List<AppNotification>>.value(const <AppNotification>[]);
    }
  }

  // ---------------------------------------------------------------- earning

  /// Credits [pointsPerAd] for one watched rewarded ad.
  ///
  /// The daily cap is enforced *inside* the transaction, against the same read
  /// that produces the new balance. Checking it in the UI first would be a
  /// suggestion, not a limit — two devices, or two fast taps, would both pass a
  /// pre-check and both be paid.
  Future<AdRewardResult> claimAdReward(String uid) async {
    if (uid.isEmpty) {
      return AdRewardResult(
        outcome: AdRewardOutcome.notSignedIn,
        message: L10nRef.current.signInToStartEarning,
      );
    }
    final DocumentReference<Map<String, dynamic>> userRef = _userRef(uid);
    final DocumentReference<Map<String, dynamic>> txRef =
        userRef.collection(transactionsCollection).doc();
    final String today = dayKey();

    try {
      return await _firestore.runTransaction<AdRewardResult>(
        (Transaction tx) async {
          final DocumentSnapshot<Map<String, dynamic>> snap =
              await tx.get(userRef);
          final Map<String, dynamic>? data = snap.data();
          final int balance = asInt(data?['points']);

          final String storedDay = data?['adsWatchedDay'] as String? ?? '';
          final int watched =
              storedDay == today ? asInt(data?['adsWatchedCount']) : 0;

          if (watched >= dailyAdLimit) {
            return AdRewardResult(
              outcome: AdRewardOutcome.dailyLimitReached,
              balance: balance,
              adsWatchedToday: watched,
              message: "That's all $dailyAdLimit ads for today — "
                  'come back tomorrow',
            );
          }

          final int nextBalance = balance + pointsPerAd;
          final int nextWatched = watched + 1;

          tx.set(
            userRef,
            <String, dynamic>{
              'points': nextBalance,
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
            'description': 'Watched a rewarded ad',
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
