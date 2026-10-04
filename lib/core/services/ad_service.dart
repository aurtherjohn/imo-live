import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Every AdMob unit id this app uses.
///
/// ## Debug uses Google's test units, release uses ours
///
/// A real unit id served from a device that AdMob has not been told is a test
/// device is how a project collects an invalid-traffic strike, and a strike is
/// not appealable. So the ids are selected on [kDebugMode]:
///
///   * **debug / profile** — Google's published test units. Real ad requests,
///     no revenue, zero strike risk. Every unit renders the "Test Ad" label.
///   * **release** — the project's own units. These are the only ids that can
///     earn, and the only ones that must never be exercised from a debug build.
///
/// The app id in `AndroidManifest.xml` is a build-time constant and cannot be
/// switched at runtime, so it is the **real** app id (`ca-app-pub-1422297723856857`).
/// That combination is the correct one: the SDK is initialised for the real
/// account, while every ad *request* in a debug build still goes to a test
/// unit. An invalid-traffic strike is triggered by real units, not by a real
/// app id.
///
/// Every call site reads through [AdIds], so this file is the single swap
/// point — see also `RewardedAdService`, which reads [rewarded] and
/// [rewardedInterstitial] rather than holding its own copy.
class AdIds {
  const AdIds._();

  // ------------------------------------------------------- Google test units
  //
  // Published by Google for exactly this purpose. Safe to ship in a debug
  // build, and useless (deliberately) in a release one.

  static const String testAndroidAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String _testAndroidInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testAndroidRewarded =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testAndroidRewardedInterstitial =
      'ca-app-pub-3940256099942544/5354046379';
  static const String _testIosInterstitial =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testIosRewarded =
      'ca-app-pub-3940256099942544/1712485313';
  static const String _testIosRewardedInterstitial =
      'ca-app-pub-3940256099942544/6978759866';

  // --------------------------------------------------------- project's units
  //
  // Imo LIVE — AdMob account `ca-app-pub-1422297723856857`.

  /// The AdMob application id. Must match
  /// `com.google.android.gms.ads.APPLICATION_ID` in `AndroidManifest.xml`.
  static const String appId = 'ca-app-pub-1422297723856857~4467434947';

  static const String interstitialAndroid =
      'ca-app-pub-1422297723856857/9498512184';
  static const String rewardedAndroid =
      'ca-app-pub-1422297723856857/9604211556';
  static const String rewardedInterstitialAndroid =
      'ca-app-pub-1422297723856857/2028973866';

  /// iOS has no unit of its own yet — the project ships Android only. Falling
  /// back to the Android ids keeps this a compile-time error-free swap point
  /// rather than a null; an iOS release needs real iOS units added here.
  static const String interstitialIos = interstitialAndroid;
  static const String rewardedIos = rewardedAndroid;
  static const String rewardedInterstitialIos = rewardedInterstitialAndroid;

  /// Uses [defaultTargetPlatform] rather than `dart:io`'s `Platform` so the
  /// ids can be read in a unit test, where there is no platform.
  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static String get interstitial => kDebugMode
      ? (_isIOS ? _testIosInterstitial : _testAndroidInterstitial)
      : (_isIOS ? interstitialIos : interstitialAndroid);

  static String get rewarded => kDebugMode
      ? (_isIOS ? _testIosRewarded : _testAndroidRewarded)
      : (_isIOS ? rewardedIos : rewardedAndroid);

  static String get rewardedInterstitial => kDebugMode
      ? (_isIOS ? _testIosRewardedInterstitial : _testAndroidRewardedInterstitial)
      : (_isIOS ? rewardedInterstitialIos : rewardedInterstitialAndroid);
}

/// The event that made an interstitial a candidate.
///
/// Each trigger carries its own threshold, because they are not equally
/// disruptive: one channel post is a deliberate, completed action, whereas a
/// tab switch is incidental navigation and needs to happen several times before
/// an ad is defensible.
enum AdTrigger {
  /// After N messages have been sent in any chat.
  messagesSent,

  /// After N *different* chats have been opened.
  chatsOpened,

  /// After publishing a post to a channel.
  channelPost,

  /// After N bottom-navigation switches.
  tabSwitch,

  /// After the app has been in the foreground for five minutes.
  foreground,

  /// After a voice message has been recorded and sent.
  ///
  /// A completed recording is a deliberate, finished action — the same
  /// defensibility as [channelPost] — so its threshold is one.
  voiceMessage,

  /// After a media file has been saved to the device.
  ///
  /// Threshold is one, but this trigger is *also* throttled by the shared
  /// [AdService.interstitialCooldown]: a user saving ten photos in a row is one
  /// intent, not ten.
  mediaSaved,

  /// After the user accepts an incoming call.
  ///
  /// The single most disruptive placement in the app — the user is about to be
  /// in a call — so it fires **at most once per session**, and never on a call
  /// the user placed themselves. See [AdService.noteAndMaybeShowOncePerSession].
  callAccepted,
}

/// Trigger kinds that may only ever fire once in a session, however many times
/// the underlying event recurs.
const Set<AdTrigger> _oncePerSessionTriggers = <AdTrigger>{
  AdTrigger.callAccepted,
};

/// Central AdMob service: SDK init, interstitial pacing, native capability.
///
/// ### Why pacing lives here and not in the screens
///
/// "Show an interstitial after five messages" is a *global* budget, not a
/// per-screen one. If each screen counted its own, five messages in the chat
/// list plus five in the chat screen plus a tab switch would produce three
/// interstitials in a minute, which is the shape of an app users uninstall. The
/// counters therefore live on one object shared by the whole session.
///
/// ### Failure policy
///
/// Ads are an enhancement. Every method reports failure instead of throwing —
/// no fill, no network and a rooted device are all ordinary — and a failure to
/// load an interstitial must never delay the action that triggered it. The
/// caller fires [noteAndMaybeShow] without awaiting its result where latency
/// matters.
class AdService {
  AdService();

  /// Minimum time between two interstitials, regardless of trigger.
  static const Duration interstitialCooldown = Duration(seconds: 45);

  /// Hard ceiling per app session, so a long session cannot become an ad reel.
  static const int interstitialSessionCap = 12;

  /// How long the app must be foregrounded before the [AdTrigger.foreground]
  /// interstitial becomes a candidate.
  static const Duration foregroundInterval = Duration(minutes: 5);

  /// How long [init] waits for `MobileAds.initialize()` before giving up.
  ///
  /// ⚠️ The clock is a [Timer] this class owns rather than `Future.timeout`.
  /// `timeout` arms a timer *inside the future*, which cannot be cancelled: on
  /// a host where `initialize()` never answers — a widget test, or a device
  /// whose ad stack is wedged — that timer outlives the widget tree and trips
  /// `flutter_test`'s "a Timer is still pending even after the widget tree was
  /// disposed" invariant. Owning it means [dispose] can cancel it.
  static const Duration sdkInitTimeout = Duration(seconds: 20);

  /// The message shown whenever the ad stack cannot be reached.
  static const String unavailableMessage = 'Ads are unavailable on this device';

  /// Per-trigger thresholds.
  static const int messagesPerAd = 5;
  static const int chatsPerAd = 3;
  static const int tabSwitchesPerAd = 4;

  /// True once [trigger] has been shown its maximum for this session.
  final Set<AdTrigger> _spentThisSession = <AdTrigger>{};

  bool _sdkReady = false;
  bool _initialising = false;
  String? _lastError;

  /// The owned clock for an in-flight [init]. See [sdkInitTimeout].
  Timer? _initTimer;

  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;
  bool _showingInterstitial = false;

  DateTime? _lastShownAt;
  int _shownThisSession = 0;

  final Map<AdTrigger, int> _counters = <AdTrigger, int>{};

  /// True once [MobileAds.initialize] has completed.
  bool get isReady => _sdkReady;

  /// Flips to true the moment the SDK is ready.
  ///
  /// Ad slots **listen** to this rather than calling [init] themselves. A
  /// banner that mounted a frame before init finished would otherwise show
  /// nothing for the rest of the session, and a slot that armed its own init
  /// clock would leave a pending timer behind when a widget test tears the tree
  /// down. One init at the root, everyone else waits on this.
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  /// The last failure, for display. Null once init succeeds.
  String? get lastError => _lastError;

  /// Initialises the Mobile Ads SDK once. Safe to call repeatedly.
  ///
  /// Bounded and non-throwing: a device with no ad stack must not be able to
  /// hang the first frame or crash a screen.
  ///
  /// The bound is a [Timer] this object owns (see [sdkInitTimeout]) so that
  /// [dispose] can cancel it. A timed-out attempt releases [_initialising], so
  /// a later call retries instead of caching the failure for the session —
  /// `MobileAds.initialize()` is idempotent, so retrying is free.
  Future<bool> init() async {
    if (_sdkReady) return true;
    if (_initialising) return false;
    _initialising = true;

    final Completer<bool> done = Completer<bool>();

    _initTimer?.cancel();
    _initTimer = Timer(sdkInitTimeout, () {
      if (done.isCompleted) return;
      debugPrint(
        'AdMob initialise gave no answer within ${sdkInitTimeout.inSeconds}s',
      );
      _lastError = unavailableMessage;
      _initialising = false;
      done.complete(false);
    });

    unawaited(
      MobileAds.instance.initialize().then(
        (InitializationStatus _) {
          _sdkReady = true;
          _lastError = null;
          // `ready` is disposed with this object; writing to it afterwards
          // would assert. A late answer from a torn-down app is simply dropped.
          if (!_disposed) ready.value = true;
          if (!done.isCompleted) done.complete(true);
        },
        onError: (Object error) {
          debugPrint('AdMob initialise failed: $error');
          _lastError = unavailableMessage;
          if (!done.isCompleted) done.complete(false);
        },
      ).whenComplete(() {
        _initialising = false;
        _initTimer?.cancel();
        _initTimer = null;
      }),
    );

    return done.future;
  }

  // ------------------------------------------------------------ interstitial

  /// Records that [trigger] happened and shows an interstitial if its budget
  /// and the global pacing allow it.
  ///
  /// Never throws and never blocks the caller's action: the show is fired and
  /// forgotten, so a slow ad load cannot make "send" feel slow.
  Future<void> noteAndMaybeShow(AdTrigger trigger) async {
    // A once-per-session trigger that has already been honoured does not even
    // get to increment: the event must not be able to accumulate credit that
    // a different trigger would then spend.
    if (_oncePerSessionTriggers.contains(trigger) &&
        _spentThisSession.contains(trigger)) {
      return;
    }

    _counters[trigger] = (_counters[trigger] ?? 0) + 1;
    if (!_thresholdReached(trigger)) return;
    if (!_pacingAllows()) return;

    final InterstitialAd? ad = _interstitial ?? await _loadInterstitial();
    if (ad == null) {
      // No fill. Leave the counter standing so the *next* qualifying action
      // tries again, rather than swallowing the opportunity silently.
      return;
    }

    // Consume the budget only once an ad is actually going to be shown.
    _counters[trigger] = 0;
    if (_oncePerSessionTriggers.contains(trigger)) {
      _spentThisSession.add(trigger);
    }
    await _showInterstitial(ad);
  }

  /// True when [trigger]'s counter has hit its threshold.
  bool _thresholdReached(AdTrigger trigger) {
    final int count = _counters[trigger] ?? 0;
    return switch (trigger) {
      AdTrigger.messagesSent => count >= messagesPerAd,
      AdTrigger.chatsOpened => count >= chatsPerAd,
      AdTrigger.channelPost => count >= 1,
      AdTrigger.tabSwitch => count >= tabSwitchesPerAd,
      AdTrigger.foreground => count >= 1,
      AdTrigger.voiceMessage => count >= 1,
      AdTrigger.mediaSaved => count >= 1,
      AdTrigger.callAccepted => count >= 1,
    };
  }

  bool _pacingAllows() {
    if (!_sdkReady) return false;
    if (_showingInterstitial) return false;
    if (_shownThisSession >= interstitialSessionCap) return false;
    final DateTime? last = _lastShownAt;
    if (last != null &&
        DateTime.now().difference(last) < interstitialCooldown) {
      return false;
    }
    return true;
  }

  Future<InterstitialAd?> _loadInterstitial() async {
    if (_interstitial != null) return _interstitial;
    if (_loadingInterstitial) return null;
    if (!await init()) return null;

    _loadingInterstitial = true;
    final Completer<InterstitialAd?> done = Completer<InterstitialAd?>();
    try {
      await InterstitialAd.load(
        adUnitId: AdIds.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            _interstitial = ad;
            if (!done.isCompleted) done.complete(ad);
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint('Interstitial load failed: ${error.code} ${error.message}');
            if (!done.isCompleted) done.complete(null);
          },
        ),
      );
    } on Object catch (error) {
      debugPrint('InterstitialAd.load threw: $error');
      if (!done.isCompleted) done.complete(null);
    } finally {
      _loadingInterstitial = false;
    }

    return done.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        debugPrint('Interstitial load timed out');
        return null;
      },
    );
  }

  Future<void> _showInterstitial(InterstitialAd ad) async {
    _showingInterstitial = true;
    _interstitial = null;
    final Completer<void> closed = Completer<void>();

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (InterstitialAd shown) {
        shown.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent:
          (InterstitialAd shown, AdError error) {
        debugPrint('Interstitial failed to show: ${error.message}');
        shown.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );

    try {
      await ad.show();
      _shownThisSession++;
      _lastShownAt = DateTime.now();
    } on Object catch (error) {
      debugPrint('Interstitial show threw: $error');
    }

    // `show` resolves when the ad is presented, so wait for the dismissal
    // before allowing another one — otherwise a second trigger could open an
    // ad underneath a live one.
    await closed.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => debugPrint('Interstitial dismissal never arrived'),
    );
    _showingInterstitial = false;

    // Warm the next one so the following trigger is instant.
    unawaited(_loadInterstitial());
  }

  // ------------------------------------------------------- foreground timer

  Timer? _foregroundTimer;

  /// Starts the five-minute foreground clock, or resumes it after a pause.
  ///
  /// Restarted (not merely resumed) on every foreground transition so the
  /// interval measures *continuous* foreground time — a user who backgrounds
  /// the app after four minutes and returns does not get an ad immediately.
  void startForegroundClock() {
    if (_disposed) return;
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer(foregroundInterval, () {
      unawaited(noteAndMaybeShow(AdTrigger.foreground));
    });
  }

  /// Stops the foreground clock while the app is not visible.
  void stopForegroundClock() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
  }

  /// Drops the preloaded interstitial, stops the clock, and cancels every
  /// timer this object owns.
  ///
  /// ⚠️ **Idempotent, and it has to be.** Two owners release this service — the
  /// root widget's `dispose` and `adServiceProvider`'s `ref.onDispose` — and
  /// whichever runs second would otherwise re-`dispose` [ready] and assert
  /// `A ValueNotifier<bool> was used after being disposed`.
  ///
  /// ⚠️ It must also leave **no pending timer** behind: `flutter_test` asserts
  /// exactly that once the widget tree is torn down, and a real hot restart
  /// leaks the same way.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopForegroundClock();
    _initTimer?.cancel();
    _initTimer = null;
    _interstitial?.dispose();
    _interstitial = null;
    ready.dispose();
  }

  /// True once [dispose] has run. Nothing may arm a timer after this.
  bool _disposed = false;
}
