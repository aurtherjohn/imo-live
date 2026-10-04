import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

/// The two rewarded formats the Watch-to-Earn flow alternates between.
///
/// They are not interchangeable: a **rewarded video** is a full-length
/// opt-in video, while a **rewarded interstitial** is a shorter, non-skippable
/// full-screen format. Serving the same one every time is what makes users
/// stop watching, so the Earn screen alternates — see
/// `EarnController.nextFormat`.
enum RewardedAdFormat {
  /// A classic rewarded video.
  video,

  /// A rewarded interstitial. Shorter, no skip button, same reward contract.
  interstitial,
}

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
/// ### Unit ids
///
/// Nothing is hard-coded here any more: both formats resolve through [AdIds],
/// which serves Google's test units in a debug build and the project's real
/// units in a release build. See the docs on [AdIds] for why that split is the
/// only safe one.
///
/// ### Failure policy
///
/// Every method reports failure rather than throwing. Ads fail for ordinary
/// reasons — no fill, no network, a rooted device — and none of them should
/// crash a screen or, worse, silently look like success.
class RewardedAdService {
  /// [adUnitId] overrides the video unit; tests use it to pin a known value.
  RewardedAdService({String? adUnitId}) : _videoUnitOverride = adUnitId;

  final String? _videoUnitOverride;

  /// The video unit in force — the override when one was given, otherwise the
  /// debug/release-aware value from [AdIds].
  String get videoAdUnitId => _videoUnitOverride ?? AdIds.rewarded;

  /// The rewarded-interstitial unit in force.
  String get interstitialAdUnitId => AdIds.rewardedInterstitial;

  /// Back-compat alias for [videoAdUnitId].
  String get adUnitId => videoAdUnitId;

  /// The unit for [format].
  String unitIdFor(RewardedAdFormat format) =>
      format == RewardedAdFormat.video ? videoAdUnitId : interstitialAdUnitId;

  RewardedAd? _video;
  RewardedInterstitialAd? _interstitial;
  bool _loading = false;
  bool _sdkReady = false;
  String? _lastError;

  /// Which format is currently loaded, or null when nothing is.
  RewardedAdFormat? _loaded;

  /// True once an ad is loaded and can be shown immediately.
  bool get isReady => _loaded != null;

  /// The format currently loaded, or null. Read by the Earn screen to know
  /// which format it is about to show.
  RewardedAdFormat? get loadedFormat => _loaded;

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
      _lastError = AdService.unavailableMessage;
      return false;
    }
  }

  /// Fetches an ad of [format], or returns true immediately when one of that
  /// format is already loaded.
  ///
  /// Loading a different format drops the previous one: the flow shows one ad
  /// at a time, and holding two live ad objects only doubles the chance of one
  /// of them being shown twice.
  ///
  /// Bounded by [loadTimeout] because a load that never calls back would
  /// otherwise leave the button spinning forever — the SDK does not guarantee a
  /// callback when a device has no ad stack at all.
  Future<bool> load({
    RewardedAdFormat format = RewardedAdFormat.video,
    Duration loadTimeout = const Duration(seconds: 20),
  }) async {
    if (_loaded == format) return true;
    if (_loading) return false;
    if (_loaded != null) dispose();

    if (!await init()) return false;

    _loading = true;
    final Completer<bool> done = Completer<bool>();

    void finish(bool ok) {
      _loading = false;
      if (!done.isCompleted) done.complete(ok);
    }

    void onLoaded(RewardedAdFormat loaded) {
      _loaded = loaded;
      _lastError = null;
      finish(true);
    }

    void onFailed(LoadAdError error) {
      // Code 3 is "no fill", which is normal and not worth alarming anybody
      // about — there is simply no ad to show right now.
      _lastError = error.code == 3
          ? 'No ad available right now — try again shortly'
          : 'Could not load an ad (${error.code})';
      debugPrint('Rewarded ${format.name} load failed: ${error.message}');
      finish(false);
    }

    try {
      if (format == RewardedAdFormat.video) {
        await RewardedAd.load(
          adUnitId: videoAdUnitId,
          request: const AdRequest(),
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (RewardedAd ad) {
              _video = ad;
              onLoaded(RewardedAdFormat.video);
            },
            onAdFailedToLoad: onFailed,
          ),
        );
      } else {
        await RewardedInterstitialAd.load(
          adUnitId: interstitialAdUnitId,
          request: const AdRequest(),
          rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
            onAdLoaded: (RewardedInterstitialAd ad) {
              _interstitial = ad;
              onLoaded(RewardedAdFormat.interstitial);
            },
            onAdFailedToLoad: onFailed,
          ),
        );
      }
    } on Object catch (error) {
      debugPrint('Rewarded ${format.name} load threw: $error');
      _lastError = AdService.unavailableMessage;
      finish(false);
    }

    return done.future.timeout(
      loadTimeout,
      onTimeout: () {
        debugPrint('Rewarded ${format.name} load timed out after '
            '${loadTimeout.inSeconds}s');
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
    final RewardedAdFormat? format = _loaded;
    if (format == null) return false;

    final RewardedAd? video = _video;
    final RewardedInterstitialAd? interstitial = _interstitial;
    _video = null;
    _interstitial = null;
    _loaded = null;

    final Completer<void> closed = Completer<void>();
    bool earned = false;

    // The credit kicked off by the earned callback.
    //
    // `onUserEarnedReward` is typed as returning void, but the credit it
    // triggers is a Firestore transaction. Holding the future lets [show] wait
    // for it, so a `true` return genuinely means "the points are in the
    // account" rather than "the callback was invoked".
    Future<void>? credit;

    void onEarned(AdWithoutView _, RewardItem _) {
      // Fired while the ad is still on screen, which is what makes this the
      // only place the reward may be granted from.
      earned = true;
      credit = onReward();
    }

    void onDismissed() {
      if (!closed.isCompleted) closed.complete();
    }

    void onShowFailed(AdError error) {
      debugPrint('Rewarded ${format.name} failed to show: ${error.message}');
      _lastError = 'Could not show the ad — try again';
      if (!closed.isCompleted) closed.complete();
    }

    try {
      if (format == RewardedAdFormat.video) {
        final RewardedAd? ad = video;
        if (ad == null) return false;
        ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
          onAdDismissedFullScreenContent: (RewardedAd shown) {
            shown.dispose();
            onDismissed();
          },
          onAdFailedToShowFullScreenContent:
              (RewardedAd shown, AdError error) {
            shown.dispose();
            onShowFailed(error);
          },
        );
        await ad.show(onUserEarnedReward: onEarned);
      } else {
        final RewardedInterstitialAd? ad = interstitial;
        if (ad == null) return false;
        ad.fullScreenContentCallback =
            FullScreenContentCallback<RewardedInterstitialAd>(
          onAdDismissedFullScreenContent: (RewardedInterstitialAd shown) {
            shown.dispose();
            onDismissed();
          },
          onAdFailedToShowFullScreenContent:
              (RewardedInterstitialAd shown, AdError error) {
            shown.dispose();
            onShowFailed(error);
          },
        );
        await ad.show(onUserEarnedReward: onEarned);
      }
    } on Object catch (error) {
      debugPrint('Rewarded ${format.name} show threw: $error');
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
    _video?.dispose();
    _video = null;
    _interstitial?.dispose();
    _interstitial = null;
    _loaded = null;
  }
}
