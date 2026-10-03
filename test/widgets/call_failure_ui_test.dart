import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:imo_live/app/theme/app_theme.dart';
import 'package:imo_live/core/models/status.dart';
import 'package:imo_live/core/services/call_service.dart';
import 'package:imo_live/features/auth/presentation/auth_providers.dart';
import 'package:imo_live/features/calls/presentation/call_screen.dart';
import 'package:imo_live/features/chats/domain/repositories.dart';
import 'package:imo_live/features/chats/presentation/providers.dart';

/// A call service that fails immediately, with a message the user should see.
///
/// The point of this file is the last link in the chain: `AgoraCallService`
/// returns a reason, but that only helps if the *screen* renders it. Proving
/// the service sets `lastError` is not the same as proving the user reads it.
class _FailingCallService implements CallService {
  _FailingCallService({this.lastError});

  final StreamController<CallSessionState> _states =
      StreamController<CallSessionState>.broadcast();

  @override
  CallSessionState state = CallSessionState.idle;

  @override
  String? lastError;

  @override
  Stream<CallSessionState> get stateStream => _states.stream;

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Future<void> start({
    required String contactId,
    required String contactName,
    required bool isVideo,
  }) async {
    // Set before the state change, exactly as the real service does — the
    // screen captures `lastError` on the transition into `failed`.
    state = CallSessionState.failed;
    _states.add(CallSessionState.failed);
  }

  @override
  Future<void> accept() async {}

  @override
  Future<void> decline() async {}

  @override
  Future<void> end() async {}

  @override
  Future<void> toggleMute() async {}

  @override
  Future<void> toggleSpeaker() async {}

  @override
  Future<void> toggleCamera() async {}

  @override
  Future<void> switchCamera() async {}

  @override
  bool get isMuted => false;

  @override
  bool get isSpeakerOn => false;

  @override
  bool get isCameraOn => false;

  @override
  bool get isFrontCamera => true;

  @override
  Duration get elapsed => Duration.zero;

  @override
  bool get isRealCallAvailable => true;

  /// This fake never opens a capture — it exists to prove the *screen* renders
  /// a failure, and the screen must not depend on the microphone for that.
  @override
  bool get holdsMicrophone => false;

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

/// In-memory call log, so the screen's outcome write does not need the local
/// database (which is not initialised in a widget test).
class _MemoryCallRepository implements CallRepository {
  final List<CallRecord> _calls = <CallRecord>[];

  @override
  Future<List<CallRecord>> getAll() async => List<CallRecord>.of(_calls);

  @override
  Stream<List<CallRecord>> watchAll() =>
      Stream<List<CallRecord>>.value(_calls);

  @override
  Future<CallRecord> save(CallRecord record) async {
    _calls.add(record);
    return record;
  }

  @override
  Future<void> delete(String id) async =>
      _calls.removeWhere((CallRecord c) => c.id == id);

  @override
  Future<void> clear() async => _calls.clear();

  @override
  Future<void> clearHistory() async => _calls.clear();

  @override
  Future<List<ScheduledCall>> getScheduled() async => <ScheduledCall>[];

  @override
  Future<ScheduledCall> saveScheduled(ScheduledCall call) async => call;

  @override
  Future<void> deleteScheduled(String id) async {}

  @override
  Future<List<CallRecord>> search(String query) async => <CallRecord>[];
}

/// The screen ends a call by popping, or by `go('/calls')` when it cannot —
/// both are GoRouter extensions, so the harness has to provide a real router.
GoRouter _router({required bool isVideo}) => GoRouter(
      initialLocation: '/call',
      routes: <RouteBase>[
        GoRoute(
          path: '/call',
          builder: (BuildContext context, GoRouterState state) => CallScreen(
            contactId: 'uid-peer',
            contactName: 'Nadia',
            isVideo: isVideo,
            isOutgoing: true,
          ),
        ),
        GoRoute(
          path: '/calls',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('call history')),
        ),
      ],
    );

/// Pumps the screen until the failed state is on screen.
///
/// Deliberately stops **before** the screen's 700 ms hand-off delay: past it the
/// screen navigates away (`_leave` → `go('/calls')`) and the failure text is
/// gone. Tests assert at this point, then call [_drain] so no timer is pending
/// when they end.
Future<void> _pumpCallScreen(
  WidgetTester tester, {
  required _FailingCallService service,
  required _MemoryCallRepository repo,
  bool isVideo = false,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        callServiceProvider.overrideWithValue(service),
        callRepositoryProvider.overrideWithValue(repo),
        // Empty, so the screen skips the Firestore call-log mirror.
        currentUidProvider.overrideWithValue(''),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: _router(isVideo: isVideo),
      ),
    ),
  );

  // One frame for the post-frame callback that calls start(), then a little
  // more for the `failed` state to be built.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Advances past the screen's hand-off delay so no timer is left pending.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

void main() {
  testWidgets('a failed call shows the reason the service gave', (
    WidgetTester tester,
  ) async {
    final _FailingCallService service = _FailingCallService(
      lastError: 'Imo LIVE needs access to your microphone to continue.',
    );

    await _pumpCallScreen(
      tester,
      service: service,
      repo: _MemoryCallRepository(),
    );

    expect(
      find.text('Imo LIVE needs access to your microphone to continue.'),
      findsOneWidget,
      reason: 'the permission refusal must reach the user, not just the log',
    );

    await _drain(tester);
    await service.dispose();
  });

  testWidgets('a failed call with no reason falls back to a generic label', (
    WidgetTester tester,
  ) async {
    final _FailingCallService service = _FailingCallService();

    await _pumpCallScreen(
      tester,
      service: service,
      repo: _MemoryCallRepository(),
    );

    expect(find.text('Call failed'), findsOneWidget);

    await _drain(tester);
    await service.dispose();
  });

  testWidgets('the failure is written to the call log exactly once', (
    WidgetTester tester,
  ) async {
    final _MemoryCallRepository repo = _MemoryCallRepository();
    final _FailingCallService service = _FailingCallService(lastError: 'nope');

    await _pumpCallScreen(
      tester,
      service: service,
      repo: repo,
      isVideo: true,
    );

    expect((await repo.getAll()).length, 1);

    await _drain(tester);
    await service.dispose();
  });
}
