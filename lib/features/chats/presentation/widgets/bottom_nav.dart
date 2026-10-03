import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../../core/utils/haptics.dart';

/// The persistent bottom navigation bar.
///
/// Selected tabs get an animated pill highlight behind the icon; labels fade
/// and shift subtly so switching feels responsive without being noisy.
class IBottomNav extends StatelessWidget {
  const IBottomNav({
    super.key,
    required this.index,
    required this.onSelect,
    required this.items,
    this.unreadCounts = const <int, int>{},
    this.badges = const <int, String>{},
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<IBottomNavItem> items;

  /// tab index -> unread count (rendered as a numeric badge).
  final Map<int, int> unreadCounts;

  /// tab index -> short text badge (e.g. "3" for updates).
  final Map<int, String> badges;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final double bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.divider, width: 0.6),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: AppSizes.bottomBarHeight,
        child: Row(
          children: List<Widget>.generate(items.length, (int i) {
            return Expanded(
              child: _NavButton(
                item: items[i],
                selected: i == index,
                onTap: () {
                  // Tick only on an actual change. Re-tapping the current tab is
                  // a no-op gesture, and buzzing for it makes the bar feel
                  // broken rather than responsive.
                  if (i != index) Haptics.tick();
                  onSelect(i);
                },
                unread: unreadCounts[i] ?? 0,
                badge: badges[i],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// One tab definition.
class IBottomNavItem {
  const IBottomNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String? semanticLabel;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.unread,
    this.badge,
  });

  final IBottomNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final int unread;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Semantics(
      button: true,
      selected: selected,
      label: item.semanticLabel ?? item.label,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: AppDurations.normal,
              curve: AppDurations.curve,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? c.accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: AppRadius.rPill,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  AnimatedSwitcher(
                    duration: AppDurations.fast,
                    child: Icon(
                      selected ? item.activeIcon : item.icon,
                      key: ValueKey<bool>(selected),
                      size: AppIconSizes.md,
                      color: selected ? c.accent : c.textSecondary,
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      right: -10,
                      top: -6,
                      child: UnreadBadge(count: unread, size: 17),
                    )
                  else if (badge != null && badge!.isNotEmpty)
                    Positioned(
                      right: -12,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: AppRadius.rPill,
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppDurations.fast,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c.accent : c.textSecondary,
                letterSpacing: 0.1,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact app-bar action showing a filter/sort label with a chevron.
class NavTextAction extends StatelessWidget {
  const NavTextAction({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      iconAlignment: IconAlignment.end,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: AppIconSizes.sm,
        color: context.c.textSecondary,
      ),
      label: Text(
        label,
        style: context.t.labelLarge?.copyWith(
          color: context.c.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Formats "3 unread" style subtitles consistently.
String unreadLabel(int count) =>
    count == 1 ? '1 unread message' : '$count unread messages';

/// Re-exported so feature files have one import for tile helpers.
typedef NavFormatter = DateFormatter;
