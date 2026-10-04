import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../../core/utils/l10n.dart';

/// A grouped settings section rendered on a card surface.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final List<Widget> children;
  final String? title;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title != null) SectionHeader(title: title!),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: AppRadius.rLg,
              border: Border.all(
                color: c.divider.withValues(alpha: 0.7),
                width: 0.8,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  children[i],
                  if (i != children.length - 1)
                    IListDivider(indent: AppSpacing.lg),
                ],
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              0,
            ),
            child: Text(
              footer!,
              style: context.t.bodySmall?.copyWith(
                color: c.textSecondary,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }
}

/// Label / value row used throughout the settings tree.
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.leadingIcon,
    this.leadingIconColor,
    this.valueColor,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? leadingIcon;
  final Color? leadingIconColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return SettingsTile(
      title: label,
      leadingIcon: leadingIcon,
      leadingIconColor: leadingIconColor,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodySmall?.copyWith(
                color: valueColor ?? c.textSecondary,
              ),
            ),
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: AppIconSizes.sm,
              color: c.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// A switch row with a title, optional description and live value.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leadingIcon,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? leadingIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? () => onChanged?.call(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            children: <Widget>[
              if (leadingIcon != null) ...<Widget>[
                Icon(
                  leadingIcon,
                  size: AppIconSizes.md,
                  color: c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: context.t.bodyLarge?.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: context.t.bodySmall?.copyWith(
                          color: c.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Switch.adaptive(
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a single-choice picker sheet and returns the chosen value.
Future<T?> showChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required List<({T value, String label, String? subtitle})> options,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      final AppColorScheme c = ctx.c;
      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadius.rXl,
            border: Border.all(color: c.divider, width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: AppRadius.rPill,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: ctx.t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ({T value, String label, String? subtitle}) option =
                        options[index];
                    final bool isSelected = option.value == selected;
                    return InkWell(
                      onTap: () => Navigator.of(ctx).pop(option.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.md,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    option.label,
                                    style: ctx.t.bodyLarge?.copyWith(
                                      color: isSelected
                                          ? c.accent
                                          : c.textPrimary,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                  if (option.subtitle != null) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(
                                      option.subtitle!,
                                      style: ctx.t.bodySmall?.copyWith(
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_rounded,
                                size: AppIconSizes.md,
                                color: c.accent,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The circular profile summary shown at the top of the settings screen.
class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({
    super.key,
    required this.name,
    required this.about,
    this.imagePath,
    this.imageUrl,
    this.colorSeed,
    required this.onTap,
    this.onQrTap,
  });

  final String name;
  final String about;
  final String? imagePath;
  final String? imageUrl;
  final int? colorSeed;
  final VoidCallback onTap;
  final VoidCallback? onQrTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: ICard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            IAvatar(
              name: name,
              imagePath: imagePath,
              imageUrl: imageUrl,
              colorSeed: colorSeed,
              size: AppSizes.avatarLg,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    about,
                    style: context.t.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            if (onQrTap != null)
              IconButton(
                onPressed: onQrTap,
                icon: const Icon(Icons.qr_code_rounded),
                tooltip: context.l10n.myQRCode,
                color: c.accent,
              ),
          ],
        ),
      ),
    );
  }
}

/// A descriptive banner clarifying where a feature's data lives.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    this.message =
        'Imo LIVE keeps a copy of your chats, contacts and media on this '
        'device, so every screen still works without a connection. When you are '
        'online, chats and messages sync through your Imo LIVE account.',
    this.icon = Icons.info_outline_rounded,
    this.color,
  });

  final String message;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Color tint = color ?? context.c.onInfo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: AppRadius.rMd,
          border: Border.all(color: tint.withValues(alpha: 0.32), width: 0.8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: AppIconSizes.sm, color: tint),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: context.t.bodySmall?.copyWith(
                  color: c.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
