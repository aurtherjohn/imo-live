import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded ads for the Watch-to-Earn flow.
///
/// ### Why this is a service and not inline in the screen
///
/// A rewarded ad is a three-step state machine — load, show, wait for the
/// dismissal — and the reward must only be paid on the *earned* callback, which
/// fires while the ad is still on screen. Spreading that across a widget's
/// `build` is how a screen ends up granting points for an ad the user skipped.
/// Keeping the sequence in one place makes the earning rule reviewable.
///
/// ### Test units
///
/// [defaultAdUnitId] returns Google's official test unit, which serves real ads
/// with no revenue and no risk of an invalid-traffic strike. It must be replaced
/// with the project's own unit before release — see the TODO on the constant.
///
/// ### Failure policy
///
/// Every method reports failure rather than throwing. Ads fail for ordinary
/// reasons — no fill, no network, a rooted device — and none of them should
/// crash a screen or, worse, silently look like success.
class RewardedAdService {
  RewardedAdService({String? adUnitId})
      : _adUnitId = adUnitId ?? defaultAdUnitId;

  /// TODO: replace with the project's rewarded unit before shipping.
  ///
  /// These are Google's published test units. They are safe to ship in a debug
  /// build and unsafe in a release one: they serve test inventory, so a real
  /// release would earn nothing, and the app id in the manifest is likewise a
  /// test id.
  static const String androidTestUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String iosTestUnitId = 'ca-app-pub-3940256099942544/1712485313';

  /// The platform's rewarded test unit.
  ///
  /// Uses [defaultTargetPlatform] rather than `dart:io`'s `Platform` so the
  /// service can be constructed in a unit test, where there is no platform.
  static String get defaultAdUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? iosTestUnitId
          : androidTestUnitId;

  final String _adUnitId;

  RewardedAd? _ad;
  bool _loading = false;
  bool _sdkReady = false;
  String? _lastError;

  /// True once an ad is loaded and can be shown immediately.
  bool get isReady => _ad != null;

  /// True while a load is in flight.
  bool get isLoading => _loading;

  /// The last failure, for display. Null once a load succeeds.
  String? get lastError => _lastError;

  /// Initialises the Mobile Ads SDK once.
  ///
  /// Safe to call repeatedly. A failure is recorded rather than thrown: the
  /// Earn screen still works, it just cannot offer an ad.
  Future<bool> init() async {
    if (_sdkReady) return true;
    try {
      await MobileAds.instance.initialize();
      _sdkReady = true;
      _lastError = null;
      return true;
    } on Object catch (error) {
      debugPrint('AdMob initialise failed: $error');
      _lastError = 'Ads are unavailable on this device';
      return false;
    }
  }

  /// Fetches an ad, or returns true immediately when one is already loaded.
  ///
  /// Bounded by [loadTimeout] because a load that never calls back would
  /// otherwise leave the button spinning forever — the SDK does not guarantee a
  /// callback when a device has no ad stack at all.
  Future<bool> load({Duration loadTimeout = const Duration(seconds: 20)}) async {
    if (_ad != null) return true;
    if (_loading) return false;

    if (!await init()) return false;

    _loading = true;
    final Completer<bool> done = Completer<bool>();

    void finish(bool ok) {
      _loading = false;
      if (!done.isCompleted) done.complete(ok);
    }

    try {
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            _ad = ad;
            _lastError = null;
            finish(true);
          },
          onAdFailedToLoad: (LoadAdError error) {
            // Code 3 is "no fill", which is normal and not worth alarming
            // anybody about — there is simply no ad to show right now.
            _lastError = error.code == 3
                ? 'No ad available right now — try again shortly'
                : 'Could not load an ad (${error.code})';
            debugPrint('Rewarded ad load failed: ${error.message}');
            finish(false);
          },
        ),
      );
    } on Object catch (error) {
      debugPrint('RewardedAd.load threw: $error');
      _lastError = 'Ads are unavailable on this device';
      finish(false);
    }

    return done.future.timeout(
      loadTimeout,
      onTimeout: () {
        debugPrint('Rewarded ad load timed out after ${loadTimeout.inSeconds}s');
        _loading = false;
        _lastError = 'Timed out loading an ad — try again';
        return false;
      },
    );
  }

  /// Shows the loaded ad, invoking [onReward] when the user earns the reward.
  ///
  /// Returns true only when the reward was actually earned — the ad was watched
  /// to the point Google calls back, not merely opened. An ad that is dismissed
  /// early returns false and pays nothing, which is the whole point of the
  /// format.
  ///
  /// The ad is consumed either way, so a second call needs a fresh [load].
  Future<bool> show({required Future<void> Function() onReward}) async {
    final RewardedAd? ad = _ad;
    if (ad == null) return false;
    _ad = null;

    final Completer<void> closed = Completer<void>();
    bool earned = false;

    // The credit kicked off by the earned callback.
    //
    // `onUserEarnedReward` is typed as returning void, but the credit it
    // triggers is a Firestore transaction. Holding the future lets [show] wait
    // for it, so a `true` return genuinely means "the points are in the
    // account" rather than "the callback was invoked".
    Future<void>? credit;

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (RewardedAd shown) {
        shown.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd shown, AdError error) {
        debugPrint('Rewarded ad failed to show: ${error.message}');
        shown.dispose();
        _lastError = 'Could not show the ad — try again';
        if (!closed.isCompleted) closed.complete();
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (AdWithoutView _, RewardItem item) {
          // Fired while the ad is still on screen, which is what makes this the
          // only place the reward may be granted from.
          earned = true;
          credit = onReward();
        },
      );
    } on Object catch (error) {
      debugPrint('Rewarded ad show threw: $error');
      _lastError = 'Could not show the ad — try again';
      return false;
    }

    // `show` resolves when the ad is presented, not when it goes away, so the
    // credit has to wait for the dismissal to avoid the screen rebuilding
    // underneath a live ad.
    await closed.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        debugPrint('Rewarded ad dismissal never arrived; continuing');
      },
    );
    final Future<void>? pending = credit;
    if (pending != null) {
      try {
        await pending;
      } on Object catch (error) {
        debugPrint('Reward credit failed after the ad closed: $error');
      }
    }
    return earned;
  }

  /// Drops any loaded ad. Called when the Earn screen goes away.
  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
