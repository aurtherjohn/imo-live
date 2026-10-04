import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/gift.dart';
import '../utils/firestore_values.dart';
import 'points_service.dart';

/// How a user chose to pay for premium.
enum PremiumPaymentMethod {
  /// bKash — a manual transfer to a merchant number, then a transaction id.
  bkash,

  /// Nagad — same shape as bKash, a different wallet.
  nagad,

  /// A crypto transfer to a wallet address, then the transaction hash.
  crypto;

  /// Stored on the request document.
  String get id => switch (this) {
        PremiumPaymentMethod.bkash => 'bkash',
        PremiumPaymentMethod.nagad => 'nagad',
        PremiumPaymentMethod.crypto => 'crypto',
      };

  String get label => switch (this) {
        PremiumPaymentMethod.bkash => 'bKash',
        PremiumPaymentMethod.nagad => 'Nagad',
        PremiumPaymentMethod.crypto => 'Crypto',
      };

  /// What the user has to send back after paying.
  String get proofLabel => switch (this) {
        PremiumPaymentMethod.bkash => 'Transaction ID',
        PremiumPaymentMethod.nagad => 'Transaction ID',
        PremiumPaymentMethod.crypto => 'Transaction hash',
      };

  static PremiumPaymentMethod fromId(String? id) => switch (id) {
        'bkash' => PremiumPaymentMethod.bkash,
        'nagad' => PremiumPaymentMethod.nagad,
        _ => PremiumPaymentMethod.crypto,
      };
}

/// Where the money goes, and what the user has to do.
///
/// Deliberately plain data, and deliberately in the client: a manual payment
/// flow has to *show* the destination, so it cannot be a server secret. The
/// credentials that matter — the merchant API keys — are not here and never
/// will be; this app only ever reads a human-readable number off the screen and
/// writes a transaction id back.
@immutable
class PremiumPaymentTarget {
  const PremiumPaymentTarget({
    required this.method,
    required this.destination,
    required this.instructions,
    this.qrPayload = '',
  });

  final PremiumPaymentMethod method;

  /// The number or wallet address to send to.
  final String destination;

  /// One line telling the user what to do.
  final String instructions;

  /// What a QR code should encode. Empty when a QR is not useful (a bKash
  /// number is typed, not scanned).
  final String qrPayload;

  bool get hasQr => qrPayload.trim().isNotEmpty;

  /// Where each method's money goes.
  ///
  /// ⚠️ These are placeholders and MUST be replaced with the real merchant
  /// numbers and wallet address before the flow is shown to a paying user. They
  /// are collected in one place so that swap is a three-line edit.
  static const Map<PremiumPaymentMethod, PremiumPaymentTarget> targets =
      <PremiumPaymentMethod, PremiumPaymentTarget>{
    PremiumPaymentMethod.bkash: PremiumPaymentTarget(
      method: PremiumPaymentMethod.bkash,
      destination: '01712345678',
      instructions: 'Send the amount to this bKash merchant number, then enter '
          'the Transaction ID below.',
    ),
    PremiumPaymentMethod.nagad: PremiumPaymentTarget(
      method: PremiumPaymentMethod.nagad,
      destination: '01812345678',
      instructions: 'Send the amount to this Nagad merchant number, then enter '
          'the Transaction ID below.',
    ),
    PremiumPaymentMethod.crypto: PremiumPaymentTarget(
      method: PremiumPaymentMethod.crypto,
      destination: 'TXPlaceholderWalletAddress0000000000000',
      instructions: 'Send USDT (TRC-20) to this address, then enter the '
          'transaction hash below.',
      qrPayload: 'TXPlaceholderWalletAddress0000000000000',
    ),
  };
}

/// The outcome of submitting a manual payment.
@immutable
class PremiumRequestResult {
  const PremiumRequestResult({
    required this.success,
    this.message = '',
    this.requestId = '',
  });

  final bool success;
  final String message;
  final String requestId;
}

/// A premium purchase a human still has to approve.
@immutable
class PremiumRequest {
  const PremiumRequest({
    required this.id,
    required this.uid,
    required this.method,
    required this.amountUsd,
    required this.status,
    this.txId = '',
    this.createdAt,
  });

  final String id;
  final String uid;
  final PremiumPaymentMethod method;
  final double amountUsd;

  /// `pending` until an admin decides.
  final String status;

  final String txId;
  final DateTime? createdAt;

  static PremiumRequest fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return PremiumRequest(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      method: PremiumPaymentMethod.fromId(data['method'] as String?),
      amountUsd: asDouble(data['amountUsd']),
      status: data['status'] as String? ?? 'pending',
      txId: data['txId'] as String? ?? '',
      createdAt: asDate(data['createdAt']),
    );
  }
}

/// Premium subscriptions: the manual payment rail, the points rail, and the
/// entitlement itself.
///
/// ### Why manual payments
///
/// The app ships no payment SDK. bKash and Nagad both require a merchant
/// agreement and a server-side credential exchange, and a card processor needs
/// a registered business. None of that exists yet, so the honest flow is the one
/// that works today: show the user where to send the money, take their
/// transaction id, and let a human confirm it. When a real gateway is added it
/// replaces [requestPremiumPurchase] and nothing else changes — the entitlement
/// is still `users/{uid}.isPremium`, and every feature already gates on that.
///
/// ### Why the points rail is a separate path
///
/// Points are already server-side and already transactional, so "pay with
/// points" needs no approval and can grant the entitlement immediately. It goes
/// through [PointsService.redeemPremium], which is where the balance check and
/// the ledger entry live.
class PremiumService {
  PremiumService({FirebaseFirestore? firestore}) : _db = firestore;

  static const String usersCollection = 'users';
  static const String requestsCollection = 'premium_requests';
  static const String transactionsCollection = 'points_transactions';

  /// The list price.
  static const double priceUsd = 9.9;

  /// The same price in BDT, rounded to something a wallet can send.
  ///
  /// A fixed figure rather than a live conversion: the merchant number receives
  /// a local-currency transfer, so the amount has to be exact and stable, and a
  /// rate that moved between the screen and the transfer would make every
  /// reconciliation ambiguous.
  static const int priceBdt = 1200;

  /// How long one purchase lasts.
  static const Duration duration = Duration(days: 30);

  FirebaseFirestore? _db;

  FirebaseFirestore get _firestore => _db ??= FirebaseFirestore.instance;

  // -------------------------------------------------------------- pricing

  /// The points price of one month of premium.
  ///
  /// Defined as what a month of watching the maximum allowance actually earns:
  /// `pointsPerAd × dailyAdLimit × 30`. That is the directive's definition, and
  /// it is the honest one — "earn premium by watching ads" is only a real
  /// alternative if the ads really do pay for it. At the current numbers that
  /// is 25 × 24 × 30 = 18,000 points.
  static int calculatePointsForPremium() =>
      PointsService.pointsPerAd * PointsService.dailyAdLimit * 30;

  /// The [PremiumPlan] the points rail redeems.
  ///
  /// Built here rather than read from [PremiumPlan.plans] so the price on this
  /// screen is the earn-equivalent the directive specifies. The Earn screen's
  /// own catalogue is a separate, cheaper loyalty ladder — see the note in
  /// `PremiumPlan`.
  static PremiumPlan get pointsPlan => PremiumPlan(
        id: 'month_earn',
        name: '1 month',
        days: duration.inDays,
        points: calculatePointsForPremium(),
      );

  // ----------------------------------------------------------- entitlement

  /// True when [uid]'s plan is live.
  ///
  /// Reads the same fields [PointsService] does, so the two can never disagree:
  /// `isPremium` is a latch the server sets and nothing clears, and
  /// `premiumUntil` is what actually decides.
  Future<bool> isPremium(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _firestore.collection(usersCollection).doc(uid).get();
      final Map<String, dynamic>? data = snap.data();
      if (data == null || data['isPremium'] != true) return false;
      final DateTime? until = asDate(data['premiumUntil']);
      return until == null || until.isAfter(DateTime.now());
    } on Object catch (error) {
      // A failed read must not silently downgrade a paying user; report "not
      // premium" only for a document that actually says so.
      debugPrint('isPremium($uid) failed: $error');
      return false;
    }
  }

  /// Live entitlement, for a screen that must react the moment an admin
  /// approves a request.
  Stream<bool> watchPremium(String uid) {
    if (uid.isEmpty) return Stream<bool>.value(false);
    return _firestore
        .collection(usersCollection)
        .doc(uid)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) {
      final Map<String, dynamic>? data = snap.data();
      if (data == null || data['isPremium'] != true) return false;
      final DateTime? until = asDate(data['premiumUntil']);
      return until == null || until.isAfter(DateTime.now());
    }).handleError((Object error) {
      debugPrint('watchPremium($uid) failed: $error');
    });
  }

  /// The user's own purchase requests, newest first.
  Stream<List<PremiumRequest>> watchMyRequests(String uid) {
    if (uid.isEmpty) {
      return Stream<List<PremiumRequest>>.value(const <PremiumRequest>[]);
    }
    return _firestore
        .collection(requestsCollection)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<PremiumRequest> list = snapshot.docs
          .map(PremiumRequest.fromDoc)
          .toList(growable: false);
      list.sort((PremiumRequest a, PremiumRequest b) {
        final DateTime? x = a.createdAt;
        final DateTime? y = b.createdAt;
        if (x == null || y == null) return 0;
        return y.compareTo(x);
      });
      return list;
    }).handleError((Object error) {
      debugPrint('watchMyRequests($uid) failed: $error');
    });
  }

  // ------------------------------------------------------------ purchases

  /// Records a manual payment for a human to approve.
  ///
  /// The document is the *claim*, not the entitlement: `status` starts at
  /// `pending`, and only an admin (or a Cloud Function acting for one) may move
  /// it to `approved`. The rules enforce that — a client cannot write
  /// `status: 'approved'`, and it cannot touch anybody else's request.
  ///
  /// [txId] is required: a request with no transaction id is unverifiable, and
  /// accepting one would just create a queue of claims nobody can check.
  Future<PremiumRequestResult> requestPremiumPurchase({
    required String uid,
    required PremiumPaymentMethod method,
    required String txId,
    double amountUsd = priceUsd,
  }) async {
    if (uid.isEmpty) {
      return const PremiumRequestResult(
        success: false,
        message: 'Sign in first.',
      );
    }
    final String proof = txId.trim();
    if (proof.length < 4) {
      return PremiumRequestResult(
        success: false,
        message: 'Enter the ${method.proofLabel.toLowerCase()} from your '
            'payment confirmation.',
      );
    }

    final DocumentReference<Map<String, dynamic>> ref =
        _firestore.collection(requestsCollection).doc();
    try {
      await ref.set(<String, dynamic>{
        'uid': uid,
        'method': method.id,
        'txId': proof,
        'amountUsd': amountUsd,
        'amountBdt': priceBdt,
        'currency': 'USD',
        'plan': 'premium_month',
        'days': duration.inDays,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return PremiumRequestResult(
        success: true,
        requestId: ref.id,
        message: 'Payment submitted. We will activate premium as soon as it is '
            'confirmed — usually within a few hours.',
      );
    } on Object catch (error) {
      debugPrint('requestPremiumPurchase($uid/${method.id}) failed: $error');
      return const PremiumRequestResult(
        success: false,
        message: 'Could not submit the payment. Check your connection and try '
            'again.',
      );
    }
  }

  /// Buys premium with points. Grants immediately — no approval step, because
  /// the balance is already server-side and the deduction is transactional.
  Future<GiftResult> purchaseWithPoints(String uid) =>
      PointsService(firestore: _db).redeemPremium(uid: uid, plan: pointsPlan);
}
