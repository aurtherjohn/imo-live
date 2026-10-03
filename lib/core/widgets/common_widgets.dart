import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../utils/formatters.dart';
import '../../app/theme/app_color_scheme.dart';
import '../utils/l10n.dart';
import 'brand_assets.dart';
import '../../app/app.dart' show prefersReducedMotion;

/// The app's standard top bar.
///
/// Deliberately custom rather than a plain [AppBar] so the title weight,
/// action spacing and subtitle alignment match the reference exactly.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.title = '',
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.bottom,
    this.showBack = false,
    this.onBack,
    this.titleWidget,
    this.centerTitle = false,
    this.height,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? titleWidget;
  final bool centerTitle;
  final double? height;

  @override
  Size get preferredSize => Size.fromHeight(
    (height ?? AppSizes.topBarHeight) + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: height ?? AppSizes.topBarHeight,
      leadingWidth: showBack ? 52 : null,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              tooltip: context.l10n.back,
              color: c.textPrimary,
            )
          : leading,
      centerTitle: centerTitle,
      titleSpacing: showBack ? 0 : AppSpacing.lg,
      title:
          titleWidget ??
          (subtitle == null
              ? Text(
                  title,
                  style: context.t.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: context.t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      style: context.t.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )),
      actions: <Widget>[
        ...actions,
        const SizedBox(width: AppSpacing.xs),
      ],
      bottom: bottom,
    );
  }
}

/// A single action icon sized for the top bar.
class TopBarAction extends StatelessWidget {
  const TopBarAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: AppIconSizes.md),
      tooltip: tooltip,
      color: color ?? context.c.textPrimary,
      splashRadius: 22,
    );
  }
}

/// Rounded, filled search field matching the reference styling.
class ITextField extends StatefulWidget {
  const ITextField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.readOnly = false,
    this.onTap,
    this.maxLines = 1,
    this.minLines,
    this.textCapitalization = TextCapitalization.sentences,
    this.keyboardType,
    this.obscureText = false,
    this.filled = true,
    this.enabled = true,
    this.contentPadding,
    this.style,
    this.focusNode,
    this.maxLength,
  });

  final TextEditingController? controller;
  final String hint;
  final Widget? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool readOnly;
  final VoidCallback? onTap;
  final int maxLines;
  final int? minLines;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool filled;
  final bool enabled;
  final EdgeInsets? contentPadding;
  final TextStyle? style;
  final FocusNode? focusNode;
  final int? maxLength;

  @override
  State<ITextField> createState() => _ITextFieldState();
}

class _ITextFieldState extends State<ITextField> {
  late final FocusNode _focusNode =
      widget.focusNode ?? FocusNode(debugLabel: 'ITextField');

  bool _focused = false;
  late final bool _ownsFocusNode = widget.focusNode == null;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      textCapitalization: widget.textCapitalization,
      keyboardType:
          widget.keyboardType ??
          (widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      obscureText: widget.obscureText,
      cursorColor: c.accent,
      style: widget.style ?? context.t.bodyLarge,
      decoration: InputDecoration(
        hintText: widget.hint,
        counterText: '',
        filled: widget.filled,
        fillColor: c.inputFill,
        isDense: true,
        contentPadding:
            widget.contentPadding ??
            const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
        prefixIcon: widget.prefixIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  right: AppSpacing.sm,
                ),
                child: widget.prefixIcon,
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: widget.suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: OutlineInputBorder(
          borderRadius: AppRadius.rPill,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rPill,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.rPill,
          borderSide: BorderSide(
            color: c.accent.withValues(alpha: _focused ? 0.8 : 0),
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

/// The rounded search bar used on Chats and list screens.
class ISearchBar extends StatelessWidget {
  const ISearchBar({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.trailing,
    this.accentIcon = true,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;
  final Widget? trailing;
  final bool accentIcon;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Row(
      children: <Widget>[
        Expanded(
          child: ITextField(
            controller: controller,
            hint: hint,
            onChanged: onChanged,
            onTap: onTap,
            readOnly: readOnly,
            autofocus: autofocus,
            prefixIcon: Icon(
              Icons.search_rounded,
              size: AppIconSizes.sm,
              color: accentIcon ? c.accent : c.textSecondary,
            ),
            suffix: controller != null && controller!.text.isNotEmpty
                ? IconButton(
                    tooltip: context.l10n.clear,
                    onPressed: () {
                      controller!.clear();
                      onChanged?.call('');
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      size: AppIconSizes.sm,
                      color: c.textSecondary,
                    ),
                    splashRadius: 18,
                  )
                : null,
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

/// Section heading used inside settings and info pages.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: context.t.labelMedium?.copyWith(
                letterSpacing: 0.7,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small pill used for labels such as "Admin", "You", "Draft".
class IPill extends StatelessWidget {
  const IPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Color tone = color ?? context.c.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? tone : tone.withValues(alpha: 0.14),
        borderRadius: AppRadius.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ?icon == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 11, color: filled ? Colors.white : tone),
                    const SizedBox(width: 3),
                  ],
                ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: filled ? Colors.white : tone,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin separator inset to align with list content.
class IListDivider extends StatelessWidget {
  const IListDivider({
    super.key,
    this.indent = AppSizes.avatarMd + AppSpacing.lg + AppSpacing.md,
  });

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.6,
      indent: indent,
      color: context.c.divider,
    );
  }
}

/// Standard list tile used by settings, contact and info screens.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.leadingIcon,
    this.leadingIconColor,
    this.dense = false,
    this.titleColor,
    this.showDivider = false,
    this.trailingText,
    this.badge,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final IconData? leadingIcon;
  final Color? leadingIconColor;
  final bool dense;
  final Color? titleColor;
  final bool showDivider;
  final String? trailingText;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // `Material` with `type: transparency` gives the `InkWell` a host to
        // paint its splash onto without introducing an opaque layer. Without a
        // Material ancestor the splash silently does nothing (and the tap
        // target still works), so the tile looked inert on press in any context
        // that was not already wrapped in a Material.
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: dense ? AppSpacing.sm + 2 : AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  if (leading != null) ...<Widget>[
                    leading!,
                    const SizedBox(width: AppSpacing.lg),
                  ] else if (leadingIcon != null) ...<Widget>[
                    SizedBox(
                      width: 28,
                      child: Icon(
                        leadingIcon,
                        size: AppIconSizes.md,
                        color: leadingIconColor ?? c.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                title,
                                style: context.t.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: titleColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (badge != null) ...<Widget>[
                              const SizedBox(width: AppSpacing.sm),
                              badge!,
                            ],
                          ],
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: context.t.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailingText != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      trailingText!,
                      style: context.t.bodySmall?.copyWith(color: c.accent),
                    ),
                  ],
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    trailing!,
                  ] else if (onTap != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: AppIconSizes.md,
                      color: c.textSecondary.withValues(alpha: 0.6),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          IListDivider(
            indent: leading == null && leadingIcon == null ? AppSpacing.lg : 64,
          ),
      ],
    );
  }
}

/// A rounded surface used to group rows, with a subtle border.
class ICard extends StatelessWidget {
  const ICard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
    this.border = true,
  });

  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final Color? color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Widget content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: AppRadius.rLg,
        border: border
            ? Border.all(color: c.divider.withValues(alpha: 0.7), width: 0.8)
            : null,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: AppRadius.rLg, child: content),
    );
  }
}

/// Centred, polished empty state with optional action.
///
/// Supply either [icon] (the norm — a themed glyph on a tinted disc) or
/// [imageAsset] for the handful of states that are a brand moment rather than a
/// semantic one, such as an empty chat list on a fresh install.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon,
    this.imageAsset,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.compact = false,
  }) : assert(icon != null || imageAsset != null,
            'EmptyState needs an icon or an imageAsset');

  /// Themed glyph. Ignored when [imageAsset] is set.
  final IconData? icon;

  /// An image to draw instead of [icon].
  ///
  /// The tinted disc behind the glyph is dropped in this mode: the logo is
  /// already a circular mark, so a second circle behind it just reads as a
  /// misplaced ring.
  final String? imageAsset;

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (imageAsset != null)
              BrandMark(
                asset: imageAsset!,
                size: compact ? 64 : 88,
                semanticLabel: title,
              )
            else
              Container(
                width: compact ? 72 : 96,
                height: compact ? 72 : 96,
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: compact ? 32 : 42,
                  color: iconColor ?? c.textSecondary.withValues(alpha: 0.7),
                ),
              ),
            SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xxl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.t.titleMedium,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state with a retry affordance.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  /// Overrides the default title.
  ///
  /// Null resolves to [context.l10n.somethingWentWrong] in [build] — a
  /// hardcoded default here would leak English into every other locale.
  final String? title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: context.c.onWarning),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title ?? context.l10n.somethingWentWrong,
              style: context.t.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(
                color: context.c.textSecondary,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(context.l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Logs [error] and returns a generic [ErrorState].
///
/// Use this instead of `ErrorState(message: '$e')`. The raw exception belongs in
/// the debug log, not on the user's screen, and the message must be localised.
ErrorState errorStateFor(
  BuildContext context,
  Object error, {
  VoidCallback? onRetry,
}) {
  debugPrint('ErrorState: $error');
  return ErrorState(
    message: context.l10n.theRestOfTheApp,
    onRetry: onRetry,
  );
}

/// Shimmer placeholder used while lists load.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = AppRadius.md,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A shimmer is decoration, never information: it must stop entirely when
    // the platform asks for reduced motion. Toggled here rather than in initState
    // because reading the accessibility flag requires a BuildContext.
    if (prefersReducedMotion(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2, 0),
              end: Alignment(0 + t * 2, 0),
              colors: <Color>[c.surfaceAlt, c.elevated, c.surfaceAlt],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton row shaped like a chat tile, shown before data is ready.
class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key, this.rows = 8});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: rows,
      itemBuilder: (BuildContext context, int index) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              const ShimmerBox(
                width: AppSizes.avatarMd,
                height: AppSizes.avatarMd,
                radius: 100,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ShimmerBox(width: 120 + (index % 3) * 40, height: 13),
                    const SizedBox(height: AppSpacing.sm),
                    ShimmerBox(width: 180 + (index % 4) * 30, height: 11),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small circular progress used inside buttons.
class ILoader extends StatelessWidget {
  const ILoader({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color ?? context.c.accent,
      ),
    );
  }
}

/// Animated three-dot typing indicator.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    super.key,
    this.color,
    this.dotSize = 5,
    this.spacing = 3,
  });

  final Color? color;
  final double dotSize;
  final double spacing;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.typingDot,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color dot = widget.color ?? context.c.accent;
    return Semantics(
      label: context.l10n.typing2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(3, (int index) {
              final double phase = (_controller.value + index * 0.2) % 1.0;
              final double lift = (phase < 0.5 ? phase : 1 - phase) * 2;
              return Padding(
                padding: EdgeInsets.only(
                  right: index == 2 ? 0 : widget.spacing,
                ),
                child: Transform.translate(
                  offset: Offset(0, -lift * 2.5),
                  child: Opacity(
                    opacity: 0.45 + lift * 0.55,
                    child: Container(
                      width: widget.dotSize,
                      height: widget.dotSize,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Icon + text row used in empty states that need a call to action.
/// A full-width primary action.
///
/// [onPressed] is nullable so an action whose preconditions are unmet renders
/// as *visibly disabled* rather than as a button that silently does nothing.
/// `FilledButton` already draws the disabled treatment for a null callback.
class ProminentButton extends StatelessWidget {
  const ProminentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final Widget button = FilledButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: AppIconSizes.sm),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Formats a section of relative time for informational rows.
String relativeTime(DateTime value) => DateFormatter.relative(value);

/// Shared snackbar helper used across the app.
void iToast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color: isError ? isError ? context.c.onDanger : context.c.onSuccess : isError ? context.c.onDanger : context.c.onSuccess,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
}
