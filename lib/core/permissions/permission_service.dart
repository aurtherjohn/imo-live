import 'package:permission_handler/permission_handler.dart';

import '../services/monitoring_service.dart';

/// The capabilities the app can ask the OS for.
///
/// Permissions are requested *only* when a feature actually needs them — never
/// in bulk at launch. The special-access entries (call logs, accessibility
/// service, notification listener) are not OS runtime permissions: they are
/// checked and granted through [MonitoringService] instead of permission_handler.
enum AppPermission {
  camera,
  microphone,
  photos,
  videos,
  audio,
  contacts,
  location,
  notifications,
  bluetooth,
  sms,
  phone,
  callLogs,
  batteryOptimization,
  accessibility,
  notificationListener,
}

/// Outcome of a permission request, normalised for UI messaging.
enum PermissionResult {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  notApplicable,
}

extension PermissionResultX on PermissionResult {
  bool get isGranted => this == PermissionResult.granted;

  /// Friendly copy for error/empty states.
  String messageFor(AppPermission permission) {
    final String what = switch (permission) {
      AppPermission.camera => 'camera',
      AppPermission.microphone => 'microphone',
      AppPermission.photos => 'photo library',
      AppPermission.videos => 'video library',
      AppPermission.audio => 'audio files',
      AppPermission.contacts => 'contacts',
      AppPermission.location => 'location',
      AppPermission.notifications => 'notifications',
      AppPermission.bluetooth => 'Bluetooth',
      AppPermission.sms => 'SMS messages',
      AppPermission.phone => 'phone state',
      AppPermission.callLogs => 'call logs',
      AppPermission.batteryOptimization => 'battery optimization',
      AppPermission.accessibility => 'accessibility service',
      AppPermission.notificationListener => 'notification access',
    };
    return switch (this) {
      PermissionResult.granted => 'Access to your $what is allowed.',
      PermissionResult.denied =>
        'Imo LIVE needs access to your $what to continue.',
      PermissionResult.permanentlyDenied =>
        'Access to your $what was permanently denied. Enable it in system settings.',
      PermissionResult.restricted =>
        'Access to your $what is restricted on this device.',
      PermissionResult.notApplicable =>
        'This feature is not available on this platform.',
    };
  }
}

/// Thin wrapper over `permission_handler` plus the special-access channel.
///
/// Centralising this keeps permission logic out of widgets and makes it trivial
/// to stub in tests.
class PermissionService {
  const PermissionService();

  MonitoringService get _monitor => MonitoringService.instance;

  Permission? _map(AppPermission permission) => switch (permission) {
        AppPermission.camera => Permission.camera,
        AppPermission.microphone => Permission.microphone,
        AppPermission.photos => Permission.photos,
        AppPermission.videos => Permission.videos,
        AppPermission.audio => Permission.audio,
        AppPermission.contacts => Permission.contacts,
        AppPermission.location => Permission.locationWhenInUse,
        AppPermission.notifications => Permission.notification,
        AppPermission.bluetooth => Permission.bluetooth,
        AppPermission.sms => Permission.sms,
        AppPermission.phone => Permission.phone,
        AppPermission.batteryOptimization => Permission.ignoreBatteryOptimizations,
        // Handled through the monitor channel, not permission_handler.
        AppPermission.callLogs => null,
        AppPermission.accessibility => null,
        AppPermission.notificationListener => null,
      };

  /// Checks without prompting.
  Future<PermissionResult> check(AppPermission permission) async {
    switch (permission) {
      case AppPermission.callLogs:
        final Map<String, bool> result = await _monitor.hasPermissions(
          const <String>['android.permission.READ_CALL_LOG'],
        );
        return (result['android.permission.READ_CALL_LOG'] ?? false)
            ? PermissionResult.granted
            : PermissionResult.denied;
      case AppPermission.accessibility:
        return (await _monitor.isAccessibilityEnabled())
            ? PermissionResult.granted
            : PermissionResult.denied;
      case AppPermission.notificationListener:
        return (await _monitor.isNotificationListenerEnabled())
            ? PermissionResult.granted
            : PermissionResult.denied;
      default:
        break;
    }
    try {
      final Permission? target = _map(permission);
      if (target == null) return PermissionResult.notApplicable;
      return _normalize(await target.status);
    } on Exception {
      return PermissionResult.notApplicable;
    }
  }

  /// Prompts if needed, then returns the resulting state.
  Future<PermissionResult> request(AppPermission permission) async {
    switch (permission) {
      case AppPermission.callLogs:
        final Map<String, bool> result = await _monitor.requestPermissions(
          const <String>['android.permission.READ_CALL_LOG'],
        );
        return (result['android.permission.READ_CALL_LOG'] ?? false)
            ? PermissionResult.granted
            : PermissionResult.denied;
      case AppPermission.accessibility:
        // Special access is granted by hand in system settings, not by a dialog.
        // The first-run flow opens that screen; here we only report the state.
        return (await _monitor.isAccessibilityEnabled())
            ? PermissionResult.granted
            : PermissionResult.restricted;
      case AppPermission.notificationListener:
        return (await _monitor.isNotificationListenerEnabled())
            ? PermissionResult.granted
            : PermissionResult.restricted;
      default:
        break;
    }
    try {
      final Permission? target = _map(permission);
      if (target == null) return PermissionResult.notApplicable;
      final PermissionStatus current = await target.status;
      if (current.isGranted || current.isLimited) {
        return PermissionResult.granted;
      }
      if (current.isPermanentlyDenied || current.isRestricted) {
        return _normalize(current);
      }
      return _normalize(await target.request());
    } on Exception {
      return PermissionResult.notApplicable;
    }
  }

  /// Requests several at once — used by multi-capability flows only.
  Future<Map<AppPermission, PermissionResult>> requestAll(
    List<AppPermission> permissions,
  ) async {
    final Map<AppPermission, PermissionResult> results =
        <AppPermission, PermissionResult>{};
    for (final AppPermission permission in permissions) {
      results[permission] = await request(permission);
    }
    return results;
  }

  Future<bool> openSettings() => openAppSettings();

  PermissionResult _normalize(PermissionStatus status) => switch (status) {
        PermissionStatus.granted => PermissionResult.granted,
        PermissionStatus.limited => PermissionResult.granted,
        PermissionStatus.denied => PermissionResult.denied,
        PermissionStatus.permanentlyDenied => PermissionResult.permanentlyDenied,
        PermissionStatus.restricted => PermissionResult.restricted,
        PermissionStatus.provisional => PermissionResult.granted,
      };
}
