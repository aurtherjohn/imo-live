import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/gift.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/points_service.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/services/rewarded_ad_service.dart';
import '../../auth/presentation/auth_providers.dart';

/// Points, premium and gifting, backed by Firestore.
final Provider<PointsService> pointsServiceProvider =
    Provider<PointsService>((Ref ref) => PointsService());

/// Premium purchases: the manual payment rail, the points rail and the
/// entitlement. Separate from [pointsServiceProvider] because it owns its own
/// collection (`premium_requests`) — the points service only knows the ledger.
final Provider<PremiumService> premiumServiceProvider =
    Provider<PremiumService>((Ref ref) => PremiumService());

/// The signed-in user's own premium purchase requests, newest first.
///
/// Watched rather than fetched so an admin approving a request updates the
/// screen without a reload.
final StreamProvider<List<PremiumRequest>> premiumRequestsProvider =
    StreamProvider<List<PremiumRequest>>((Ref ref) {
  final String uid = ref.watch(currentUidProvider);
  return ref.watch(premiumServiceProvider).watchMyRequests(uid);
});

/// The session-wide AdMob service — banner factory, interstitial pacing and the
/// foreground clock.
///
/// One instance for the whole app on purpose: the interstitial counters are a
/// global budget. Two instances would mean two independent "five messages"
/// counts, which is exactly the over-serving the pacing exists to prevent. See
/// [AdService].
final Provider<AdService> adServiceProvider = Provider<AdService>((Ref ref) {
  final AdService service = AdService();
  ref.onDispose(service.dispose);
  return service;
});

/// Whether this session should be shown ads at all.
///
/// The single gate every ad placement reads, so "premium means no ads" has one
/// answer instead of each slot deciding for itself.
final Provider<bool> adsAllowedProvider = Provider<bool>((Ref ref) {
  return !ref.watch(isPremiumProvider);
});

/// Rewarded-ad loading and display for the Watch-to-Earn flow.
///
/// A fresh instance per container: the loaded ad is single-use, so sharing one
/// across screens would let a screen show an ad another screen had already
/// consumed.
final Provider<RewardedAdService> rewardedAdServiceProvider =
    Provider<RewardedAdService>((Ref ref) {
  final RewardedAdService service = RewardedAdService();
  ref.onDispose(service.dispose);
  return service;
});

/// The signed-in user's balance, premium state and daily ad usage.
final StreamProvider<PointsAccount> pointsAccountProvider =
    StreamProvider<PointsAccount>((Ref ref) {
  final String uid = ref.watch(currentUidProvider);
  return ref.watch(pointsServiceProvider).watchAccount(uid);
});

/// The signed-in user's points ledger, newest first.
final StreamProvider<List<PointsTransaction>> pointsHistoryProvider =
    StreamProvider<List<PointsTransaction>>((Ref ref) {
  final String uid = ref.watch(currentUidProvider);
  return ref.watch(pointsServiceProvider).watchTransactions(uid);
});

/// In-app notifications for the signed-in user.
final StreamProvider<List<AppNotification>> appNotificationsProvider =
    StreamProvider<List<AppNotification>>((Ref ref) {
  final String uid = ref.watch(currentUidProvider);
  return ref.watch(pointsServiceProvider).watchNotifications(uid);
});

/// How many notifications are still unread, for the badge.
final Provider<int> unreadNotificationCountProvider = Provider<int>((Ref ref) {
  final List<AppNotification> list =
      ref.watch(appNotificationsProvider).valueOrNull ?? const <AppNotification>[];
  return list.where((AppNotification n) => !n.read).length;
});

/// True while the signed-in user's premium plan is running.
///
/// The single gate every premium feature reads, so "is this user premium" has
/// one answer rather than each screen interpreting the fields itself.
final Provider<bool> isPremiumProvider = Provider<bool>((Ref ref) {
  final PointsAccount? account = ref.watch(pointsAccountProvider).valueOrNull;
  return account?.premiumActive ?? false;
});

/// The balance, or 0 while it is still loading.
final Provider<int> pointsBalanceProvider = Provider<int>((Ref ref) {
  return ref.watch(pointsAccountProvider).valueOrNull?.points ?? 0;
});
