import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chats/presentation/providers.dart';
import '../../../../core/utils/l10n.dart';

/// Warns that incoming calls cannot reach this device.
///
/// ### What it is for
///
/// The incoming-call listener is the only thing that rings the phone. When it
/// fails there is no partial behaviour to fall back on — no call rings at all —
/// and the symptom is indistinguishable from an app that is simply broken. That
/// is exactly how a missing Firestore index once presented: a caller heard it
/// ring out while the callee's phone did nothing, and the only trace was a
/// `debugPrint` in logcat that nobody was reading.
///
/// ### Why it is no longer a permanent nag
///
/// It used to be unconditional while an error existed, and the error it was
/// reacting to was spurious: the listener was bound to an empty uid by a
/// non-reactive provider, so it never even opened a real query and the banner
/// appeared on every login. Two changes fix that:
///
/// * [callUidProvider] now tracks the auth stream, so the listener binds to a
///   real uid and the spurious error is gone at the source.
/// * This banner is dismissible. A genuine listener failure is worth reporting,
///   but a user who has read it must be able to clear it — a strip that cannot
///   be dismissed is one users learn to ignore, which defeats the purpose.
///
/// It is rendered only inside the signed-in shell, so by construction it can
/// only be seen while the app is foregrounded; it makes no claim about
/// background delivery, which is the missing FCM sender's problem, not this
/// banner's.
class CallListenerBanner extends ConsumerStatefulWidget {
  const CallListenerBanner({super.key});

  @override
  ConsumerState<CallListenerBanner> createState() => _CallListenerBannerState();
}

class _CallListenerBannerState extends ConsumerState<CallListenerBanner> {
  /// Cleared when the user dismisses the notice. Reset whenever the listener
  /// recovers and fails again, so a *new* failure is reported again.
  bool _dismissed = false;
  bool _hadError = false;

  @override
  Widget build(BuildContext context) {
    final Object? error = ref.watch(incomingCallsProvider).error;

    // A recovery rearms the banner, so the next failure is not silently
    // swallowed by an old dismissal.
    if (error == null) {
      _hadError = false;
      _dismissed = false;
      return const SizedBox.shrink();
    }
    if (!_hadError) {
      _hadError = true;
      _dismissed = false;
    }
    if (_dismissed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: const Color(0xFF3A1010),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 6,
        left: 16,
        right: 8,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.phone_disabled_rounded,
            size: 15,
            color: Color(0xFFFF6B6B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Incoming calls can't ring on this device right now",
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFFFFD5D5),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _dismissed = true),
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFFFFD5D5),
            ),
            tooltip: context.l10n.dismiss,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
