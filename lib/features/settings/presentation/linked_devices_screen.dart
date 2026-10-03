import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Companion device management. Pairing itself needs a backend, and the UI
/// says so plainly rather than faking a QR handshake.
class LinkedDevicesScreen extends ConsumerWidget {
  const LinkedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LinkedDevice>> devicesAsync =
        ref.watch(linkedDevicesProvider);

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.linkedDevices, showBack: true),
      body: devicesAsync.when(
        loading: () => const Center(child: ILoader()),
        error: (Object e, StackTrace s) => errorStateFor(context, e),
        data: (List<LinkedDevice> devices) {
          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
            children: <Widget>[
              InfoBanner(
                icon: Icons.devices_rounded,
                message:
                    context.l10n.pairingASecondDeviceIs2,
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: ICard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: context.c.surfaceAlt,
                          borderRadius: AppRadius.rLg,
                        ),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: QrImageView(
                          data: 'imo://link/${AppConstants.appVersion}/local',
                          version: QrVersions.auto,
                          backgroundColor: Colors.transparent,
                          eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: context.c.textPrimary,
                          ),
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: context.c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        context.l10n.linkADevice,
                        style: context.t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        context.l10n.openImoLIVEOnAnother2,
                        textAlign: TextAlign.center,
                        style: context.t.bodySmall?.copyWith(
                          color: context.c.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ProminentButton(
                        label: context.l10n.pairADevice,
                        icon: Icons.qr_code_scanner_rounded,
                        expanded: true,
                        onPressed: () => showBackendRequiredDialog(
                          context,
                          feature: context.l10n.devicePairing,
                          detail:
                              context.l10n.aLinkedDeviceAuthenticatesAgainst,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SettingsGroup(
                title: context.l10n.devices,
                footer:
                    context.l10n.unlinkingRemovesADeviceFrom2,
                children: devices
                    .map(
                      (LinkedDevice device) => SettingsTile(
                        title: device.name,
                        subtitle:
                            '${device.platform} · ${_activeLabel(device.lastActive)}'
                            '${device.isCurrent ? ' · this device' : ''}',
                        leadingIcon: _iconFor(device.platform),
                        leadingIconColor:
                            device.isCurrent ? context.c.accent : null,
                        trailing: device.isCurrent
                            ? IPill(
                                label: context.l10n.current,
                                color: context.c.accent,
                                filled: true,
                              )
                            : TextButton(
                                onPressed: () async {
                                  final bool ok = await showConfirmDialog(
                                    context,
                                    title: context.l10n.unlink2(device.name),
                                    message:
                                        context.l10n.theDeviceIsRemovedFrom2,
                                    confirmLabel: context.l10n.unlink,
                                    destructive: true,
                                  );
                                  if (!ok) return;
                                  await ref
                                      .read(linkedDevicesProvider.notifier)
                                      .unlink(device.id);
                                  if (context.mounted) {
                                    iToast(context, context.l10n.unlinked(device.name));
                                  }
                                },
                                child: Text(context.l10n.unlink),
                              ),
                        onTap: () => showInfoDialog(
                          context,
                          title: device.name,
                          message:
                              context.l10n.platformLastActive(device.platform, DateFormatter.fullTimestamp(device.lastActive), device.isCurrent ? context.l10n.thisIsTheDeviceYou : context.l10n.linkedDeviceEntriesAre),
                        ),
                      ),
                    )
                    .toList(),
              ),

              SettingsGroup(
                title: context.l10n.security,
                children: <Widget>[
                  SettingsValueRow(
                    label: context.l10n.linkWithPhoneNumber,
                    value: 'Not available yet',
                    leadingIcon: Icons.phone_iphone_rounded,
                    onTap: () => showBackendRequiredDialog(
                      context,
                      feature: context.l10n.linkingWithAPhoneNumber,
                    ),
                  ),
                  SettingsValueRow(
                    label: context.l10n.logOutOfAllDevices,
                    value: 'Not available yet',
                    leadingIcon: Icons.logout_rounded,
                    onTap: () async {
                      final bool ok = await showConfirmDialog(
                        context,
                        title: context.l10n.removeAllLinkedDevices,
                        message:
                            context.l10n.everyNonCurrentEntryIs2,
                        confirmLabel: context.l10n.removeAll,
                        destructive: true,
                      );
                      if (!ok) return;
                      final List<LinkedDevice> others = ref
                          .read(linkedDevicesProvider)
                          .orEmpty
                          .where((LinkedDevice d) => !d.isCurrent)
                          .toList();
                      final LinkedDevicesNotifier notifier =
                          ref.read(linkedDevicesProvider.notifier);
                      for (final LinkedDevice d in others) {
                        await notifier.unlink(d.id);
                      }
                      if (context.mounted) {
                        iToast(context, context.l10n.linkedDevicesCleared);
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  static IconData _iconFor(String platform) {
    final String p = platform.toLowerCase();
    if (p.contains('ios') || p.contains('iphone')) return Icons.phone_iphone_rounded;
    if (p.contains('mac') || p.contains('desktop')) return Icons.laptop_mac_rounded;
    if (p.contains('web') || p.contains('browser')) return Icons.language_rounded;
    if (p.contains('tab')) return Icons.tablet_mac_rounded;
    return Icons.phone_android_rounded;
  }

  static String _activeLabel(DateTime? at) {
    if (at == null) return 'unknown activity';
    return DateFormatter.relative(at);
  }
}
