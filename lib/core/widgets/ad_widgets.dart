import 'package:flutter/material.dart';

import '../utils/l10n.dart';

/// The small "Ad" chip shown above a paid placement.
///
/// The app carries no banner or native inventory: every ad it shows is either
/// an interstitial (full-screen, between actions) or a rewarded video, and
/// AdMob renders both of those itself — there is no Flutter-side surface to
/// label. This survives only because a caller may want to mark a slot, and
/// because removing it would break the `ad` ARB key's last reference.
///
/// ⚠️ If nothing references this after the Phase-1 ad change, delete it along
/// with the `ad` key in `lib/l10n/*.arb`.
class AdSlotLabel extends StatelessWidget {
  const AdSlotLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        context.l10n.ad,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: Theme.of(context)
              .textTheme
              .labelSmall
              ?.color
              ?.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
