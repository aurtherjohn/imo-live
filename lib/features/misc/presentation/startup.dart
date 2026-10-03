import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../local/database/local_settings_repository.dart';
import '../../../local/database/local_database.dart';
import '../../chats/presentation/providers.dart';

/// Initialises every local service.
///
/// This is the single place that knows about startup ordering:
/// storage → settings → ready.
///
/// The app ships with **no** fabricated content. A fresh install opens with an
/// empty chat list, an empty contact list and a blank profile; everything on
/// screen is either entered by the user or read from the device address book.
///
/// Every step is individually guarded. Nothing here is a prerequisite for the
/// first frame — if a step fails the user still gets a working app, so failures
/// are logged and skipped.
class StartupService {
  StartupService(this.ref);

  final Ref ref;

  Future<void> run() async {
    // Storage is bounded twice over: `LocalDatabase.init` timeouts every
    // platform call internally, and this ceiling catches anything it misses.
    // The app is fully usable from in-memory defaults, so waiting is never
    // worth a stuck splash screen.
    await _guard(
      'storage',
      () => LocalDatabase.instance
          .init()
          .timeout(const Duration(seconds: 6)),
    );

    // Publish the outcome so screens can tell "empty because new" apart from
    // "empty because storage is unavailable".
    ref.read(storageReadyStateProvider.notifier).state =
        LocalDatabase.instance.isReady;
    if (!LocalDatabase.instance.isReady) {
      ref.read(startupFailedProvider.notifier).state = true;
    }

    if (LocalDatabase.instance.isReady) {
      // Prime settings so the theme does not flash on first frame.
      await _guard('settings cache', () async {
        await LocalSettingsRepository().getAppearance();
        await LocalSettingsRepository().getLanguage();
        await LocalSettingsRepository().getWallpaper();
      });
    } else {
      debugPrint(
        'Storage unavailable — starting with empty local state. '
        'Missing boxes: ${LocalDatabase.instance.unavailableBoxes}',
      );
    }

    // Notifications are optional — never block startup on them.
    await _guard(
      'notifications',
      () => ref.read(notificationServiceProvider).init(),
    );
  }

  /// Runs [step], swallowing and logging any failure.
  ///
  /// Startup must complete even when an individual step cannot: a failure here
  /// must never leave the user stranded on the splash screen.
  Future<void> _guard(String name, Future<void> Function() step) async {
    try {
      await step();
    } on Object catch (error, stack) {
      debugPrint('Startup step "$name" failed: $error\n$stack');
    }
  }
}

/// True once startup finished.
final StateProvider<bool> startupCompleteProvider =
    StateProvider<bool>((Ref ref) => false);

/// Progress label shown on the splash screen.
final StateProvider<String> startupStageProvider =
    StateProvider<String>((Ref ref) => 'Starting up');

/// True when startup could not open local storage.
///
/// Surfaced on the home screen so the user is told why their data is empty,
/// instead of seeing a populated app one launch and an empty one the next.
final StateProvider<bool> startupFailedProvider =
    StateProvider<bool>((Ref ref) => false);

/// Runs startup exactly once.
///
/// This provider never throws: any failure is recorded in
/// [startupFailedProvider] and the future still completes, so the splash screen
/// can always hand off to the home screen.
final FutureProvider<void> bootstrapProvider =
    FutureProvider<void>((Ref ref) async {
  // Riverpod forbids one provider from mutating another *during* its own
  // initialisation. The first `stage()` used to run synchronously before the
  // first suspension point, which tripped that assertion and made the whole
  // startup fail. Yielding first moves every mutation out of the build phase.
  await Future<void>.delayed(Duration.zero);

  void stage(String label) =>
      ref.read(startupStageProvider.notifier).state = label;

  stage('Opening local storage');
  final StartupService service = StartupService(ref);
  try {
    await service.run();
  } on Object catch (error, stack) {
    // Belt and braces: `StartupService.run` already guards each step, but a
    // throw from the outer sequence must still not strand the splash screen.
    debugPrint('Startup failed: $error\n$stack');
    ref.read(startupFailedProvider.notifier).state = true;
  } finally {
    ref.read(startupCompleteProvider.notifier).state = true;
  }
});

/// Purges expired statuses and disappearing messages on demand.
final FutureProvider<int> purgeProvider = FutureProvider<int>((Ref ref) async {
  final int statuses = await ref.read(statusRepositoryProvider).purgeExpired();
  final int messages = await ref.read(messageRepositoryProvider).purgeExpired();
  return statuses + messages;
});

/// Network summary used by the storage & network screen.
final Provider<String> networkLabelProvider = Provider<String>((Ref ref) {
  final NetworkStatus status = ref.watch(networkStatusProvider).valueOrNull ??
      NetworkStatus.unknown;
  return status.label;
});

/// Opens the splash → chats transition.
void goToChats(BuildContext context) => context.go(AppRoutes.chats);
