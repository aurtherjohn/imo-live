import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/call_signaling_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/webrtc_call_service.dart';
import '../../../core/utils/l10n.dart';
import '../../calls/presentation/widgets/call_listener_banner.dart';
import '../../updates/presentation/providers/updates_providers.dart';
import 'providers.dart';
import 'widgets/bottom_nav.dart';

/// The bottom-navigation tabs, in the order the bar renders them.
///
/// These are **not** free-standing numbers: index N is the Nth
/// `StatefulShellBranch` declared in `lib/app/router.dart`. The bar and the
/// branches have to stay the same length and in the same order, because
/// `goBranch(index)` navigates by position.
///
/// The two lists drifted apart once already: the bar carried a fifth
/// "Communities" item after that feature was removed, while the router still
/// declared four branches. Every tab from that point on opened the wrong
/// screen, and the last one indexed past the end of the branch list
/// entirely. `test/app/router_test.dart` guards the pairing.
enum _ShellTab {
  chats,
  updates,
  contacts,
  calls;

  /// The number of tabs the bar renders, and therefore the number of shell
  /// branches the router has to declare.
  static int get count => values.length;
}

/// The persistent app shell holding the four main tabs.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  /// The call currently being rung out, so the same ring is not opened twice.
  ///
  /// Cleared whenever no call is ringing, which is what lets a *second* call
  /// ring after the first one ends.
  String? _ringingCallId;

  /// Opens the call screen for an incoming ring.
  ///
  /// The shell is the right host for this: it is mounted for the whole signed-in
  /// session, so a ring arrives wherever the user happens to be. The call screen
  /// itself needs no changes — it already renders a ringing state with
  /// accept/decline, and [CallService.accept] joins the call.
  void _ring(CallDocument call) {
    final CallService calls = ref.read(callServiceProvider);
    if (calls is WebRtcCallService) {
      // Hand the service the document id before the user answers: `accept()`
      // takes no arguments, and declining needs the id too, to stop the
      // caller's phone ringing.
      //
      // There is deliberately no second branch. WebRTC is the only real
      // provider; the Agora path that used to be handled here was removed
      // along with the provider swap, so a branch for it could only ever be
      // dead code pretending that stack is still live.
      calls.pendingCallId = call.id;
    }

    final String name =
        call.callerName.isEmpty ? 'Unknown' : call.callerName;
    context.push(
      '${AppRoutes.call}?id=${Uri.encodeComponent(call.callerId)}'
      '&name=${Uri.encodeComponent(name)}'
      '&video=${call.isVideo}'
      '&outgoing=0',
    );
  }

  @override
  Widget build(BuildContext context) {
    final int unreadChats = ref.watch(totalUnreadProvider);
    final int unreadUpdates = ref.watch(unreadStatusCountProvider);
    final int missedCalls = ref.watch(missedCallCountProvider);

    ref.listen<AsyncValue<List<CallDocument>>>(incomingCallsProvider,
        (AsyncValue<List<CallDocument>>? previous,
        AsyncValue<List<CallDocument>> next) {
      final List<CallDocument> ringing =
          next.valueOrNull ?? const <CallDocument>[];
      if (ringing.isEmpty) {
        // Nothing ringing: release the latch so the next call can ring.
        _ringingCallId = null;
        return;
      }
      final CallDocument call = ringing.first;
      if (call.id == _ringingCallId) return;
      _ringingCallId = call.id;
      _ring(call);
    });

    return Scaffold(
      body: Column(
        children: <Widget>[
          // Both banners are persistent strips that own the status-bar inset
          // while they are visible, so the ring warning goes first: it is the
          // more serious of the two — offline is recoverable by moving, a dead
          // ring listener is not.
          const CallListenerBanner(),
          const _ConnectivityBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppDurations.normal,
              switchInCurve: AppDurations.curve,
              switchOutCurve: AppDurations.curve,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.012),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(widget.navigationShell.currentIndex),
                child: widget.navigationShell,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: IBottomNav(
        index: widget.navigationShell.currentIndex,
        onSelect: (int index) {
          // `goBranch` navigates by *position*, so an index past the end of
          // the branch list is a programming error, not a user error. The
          // assert names the offending index instead of leaving a bare
          // go_router range error to be read out of a stack trace.
          assert(
            index >= 0 && index < _ShellTab.count,
            'bottom-nav index $index has no matching shell branch',
          );
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
          );
        },
        items: <IBottomNavItem>[
          IBottomNavItem(
            label: context.l10n.tabChats,
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_rounded,
          ),
          IBottomNavItem(
            label: context.l10n.tabUpdates,
            icon: Icons.donut_large_rounded,
            activeIcon: Icons.donut_large_rounded,
          ),
          IBottomNavItem(
            label: context.l10n.tabContacts,
            icon: Icons.contacts_outlined,
            activeIcon: Icons.contacts_rounded,
          ),
          IBottomNavItem(
            label: context.l10n.tabCalls,
            icon: Icons.call_outlined,
            activeIcon: Icons.call_rounded,
          ),
        ],
        unreadCounts: <int, int>{_ShellTab.chats.index: unreadChats},
        badges: <int, String>{
          if (unreadUpdates > 0) _ShellTab.updates.index: '$unreadUpdates',
          if (missedCalls > 0) _ShellTab.calls.index: '$missedCalls',
        },
      ),
    );
  }
}

/// A slim banner that appears when the device loses connectivity.
///
/// The app remains fully navigable offline; this only informs the user that
/// new messages will stay in a pending state.
class _ConnectivityBanner extends ConsumerStatefulWidget {
  const _ConnectivityBanner();

  @override
  ConsumerState<_ConnectivityBanner> createState() =>
      _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<_ConnectivityBanner> {
  @override
  Widget build(BuildContext context) {
    final AsyncValue<NetworkStatus> status = ref.watch(networkStatusProvider);
    final NetworkStatus value = status.valueOrNull ?? NetworkStatus.unknown;
    final bool offline = value == NetworkStatus.none;

    return AnimatedSize(
      duration: AppDurations.normal,
      curve: AppDurations.curve,
      alignment: Alignment.topCenter,
      child: offline
          ? Container(
              width: double.infinity,
              color: const Color(0xFF3A2A10),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 6,
                bottom: 6,
                left: 16,
                right: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 15,
                    color: Color(0xFFFFB020),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.noInternetConnection,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFFFD79A),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
