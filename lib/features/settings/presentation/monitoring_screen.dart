import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/services/monitoring_service.dart';
import '../../../core/utils/l10n.dart';
import '../../../core/widgets/common_widgets.dart';
import 'widgets/settings_widgets.dart';

/// Settings screen for the monitoring stack.
///
/// Shows the three special-access toggles, the always-on foreground service
/// and a live feed of everything the stack has captured (SMS, calls,
/// notifications, foreground app changes) plus the device info. Every value is
/// read straight from the native side through [MonitoringService].
class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with WidgetsBindingObserver {
  bool _accessibility = false;
  bool _notificationAccess = false;
  bool _serviceRunning = false;
  MonitorDeviceInfo? _deviceInfo;
  List<MonitorEvent> _events = const <MonitorEvent>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final MonitoringService monitor = MonitoringService.instance;
    final bool accessibility = await monitor.isAccessibilityEnabled();
    final bool notificationAccess = await monitor.isNotificationListenerEnabled();
    final bool serviceRunning = await monitor.isServiceRunning();
    final MonitorDeviceInfo? info = await monitor.getDeviceInfo();
    final List<MonitorEvent> events = await monitor.getEvents(limit: 200);
    if (!mounted) return;
    setState(() {
      _accessibility = accessibility;
      _notificationAccess = notificationAccess;
      _serviceRunning = serviceRunning;
      _deviceInfo = info;
      _events = events;
      _loading = false;
    });
  }

  Future<void> _startService() async {
    await MonitoringService.instance.startService();
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _stopService() async {
    await MonitoringService.instance.stopService();
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _clearEvents() async {
    await MonitoringService.instance.clearEvents();
    if (!mounted) return;
    await _refresh();
  }

  String _bytes(int bytes) {
    if (bytes <= 0) return '—';
    final double mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppTopBar(title: l10n.monitoring, showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
              children: <Widget>[
                // ------------------------------------------------ special access
                SettingsGroup(
                  title: l10n.monitoring,
                  children: <Widget>[
                    _statusRow(
                      context,
                      label: l10n.accessibility,
                      value: _accessibility ? l10n.on : l10n.off,
                      icon: Icons.accessibility_new_rounded,
                      granted: _accessibility,
                      onTap: () => MonitoringService.instance
                          .openAccessibilitySettings(),
                    ),
                    _statusRow(
                      context,
                      label: l10n.notificationAccess,
                      value: _notificationAccess ? l10n.on : l10n.off,
                      icon: Icons.notifications_active_outlined,
                      granted: _notificationAccess,
                      onTap: () => MonitoringService.instance
                          .openNotificationListenerSettings(),
                    ),
                  ],
                ),
                // ------------------------------------------------- background
                SettingsGroup(
                  title: l10n.backgroundService,
                  children: <Widget>[
                    _statusRow(
                      context,
                      label: l10n.backgroundService,
                      value: _serviceRunning ? l10n.running : l10n.stopped,
                      icon: Icons.sync_rounded,
                      granted: _serviceRunning,
                      onTap: _serviceRunning ? _stopService : _startService,
                      actionLabel:
                          _serviceRunning ? l10n.stop : l10n.start,
                    ),
                  ],
                ),
                // -------------------------------------------------- device info
                if (_deviceInfo != null)
                  SettingsGroup(
                    title: l10n.deviceInfo,
                    children: <Widget>[
                      _infoRow(context, l10n.model, _deviceInfo!.model),
                      _infoRow(
                        context,
                        l10n.manufacturer,
                        _deviceInfo!.manufacturer,
                      ),
                      _infoRow(context, l10n.device, _deviceInfo!.device),
                      _infoRow(
                        context,
                        l10n.androidVersion,
                        '${_deviceInfo!.androidVersion} (SDK ${_deviceInfo!.sdkInt})',
                      ),
                      _infoRow(context, 'Build', _deviceInfo!.buildId),
                      _infoRow(
                        context,
                        'Memory',
                        _bytes(_deviceInfo!.totalMemoryBytes),
                      ),
                      _infoRow(
                        context,
                        'Screen',
                        '${_deviceInfo!.screenWidth} × ${_deviceInfo!.screenHeight} '
                            '(${_deviceInfo!.densityDpi} dpi)',
                      ),
                      _infoRow(context, 'Device ID', _deviceInfo!.androidId ?? '—'),
                    ],
                  ),
                // ------------------------------------------------- recent activity
                SettingsGroup(
                  title: l10n.recentActivity,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xs,
                      ),
                      child: Row(
                        children: <Widget>[
                          TextButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(l10n.refresh),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _events.isEmpty ? null : _clearEvents,
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            label: Text(l10n.clear),
                          ),
                        ],
                      ),
                    ),
                    if (_events.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          l10n.noRecentActivity,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.c.textSecondary,
                              ),
                        ),
                      )
                    else
                      for (final MonitorEvent event in _events)
                        _eventRow(context, event),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _statusRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required bool granted,
    required VoidCallback onTap,
    String? actionLabel,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: context.c.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: granted
                    ? context.c.onSuccess.withValues(alpha: 0.12)
                    : context.c.onDanger.withValues(alpha: 0.12),
                borderRadius: AppRadius.rPill,
              ),
              child: Text(
                value,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: granted
                          ? context.c.onSuccess
                          : context.c.onDanger,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: context.c.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.c.textSecondary,
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(BuildContext context, MonitorEvent event) {
    final l10n = context.l10n;
    final IconData icon;
    final String title;
    switch (event.type) {
      case 'sms':
        icon = Icons.sms_rounded;
        title = l10n.sms;
        break;
      case 'call':
        icon = Icons.call_rounded;
        title = l10n.callLogs;
        break;
      case 'notification':
        icon = Icons.notifications_rounded;
        title = l10n.notifications;
        break;
      case 'app':
        icon = Icons.apps_rounded;
        title = l10n.app;
        break;
      default:
        icon = Icons.info_outline_rounded;
        title = l10n.eventService;
    }
    final String subtitle = _describe(event);
    final DateTime when = DateTime.fromMillisecondsSinceEpoch(event.timestamp);
    final String time =
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: context.c.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.c.textSecondary,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            time,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.c.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  String _describe(MonitorEvent event) {
    final Map<String, Object?> d = event.data;
    switch (event.type) {
      case 'sms':
        return '${d['from'] ?? ''}: ${d['body'] ?? ''}'.trim();
      case 'call':
        return '${d['name'] ?? ''} — ${d['callType'] ?? ''} '
            '(${d['durationSeconds'] ?? 0}s)'.trim();
      case 'notification':
        final String app = d['app']?.toString() ?? '';
        final String title = d['title']?.toString() ?? '';
        final String text = d['text']?.toString() ?? '';
        return '$app — $title ${text.isNotEmpty ? "· $text" : ""}'.trim();
      case 'app':
        return d['name']?.toString() ?? '';
      case 'service':
        return d['event']?.toString() ?? '';
      default:
        return d.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    }
  }
}
