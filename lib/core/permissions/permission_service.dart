import 'package:permission_handler/permission_handler.dart';

/// The capabilities the app can ask the OS for.
///
/// Permissions are requested *only* when a feature actually needs them — never
/// in bulk at launch.
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
}

/// Outcome of a permission request, normalised for UI messaging.
enum PermissionResult { granted, denied, permanentlyDenied, restricted, notApplicable }

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

/// Thin wrapper over `permission_handler`.
///
/// Centralising this keeps permission logic out of widgets and makes it trivial
/// to stub in tests.
class PermissionService {
  const PermissionService();

  Permission _map(AppPermission permission) => switch (permission) {
        AppPermission.camera => Permission.camera,
        AppPermission.microphone => Permission.microphone,
        AppPermission.photos => Permission.photos,
        AppPermission.videos => Permission.videos,
        AppPermission.audio => Permission.audio,
        AppPermission.contacts => Permission.contacts,
        AppPermission.location => Permission.locationWhenInUse,
        AppPermission.notifications => Permission.notification,
        AppPermission.bluetooth => Permission.bluetooth,
      };

  /// Checks without prompting.
  Future<PermissionResult> check(AppPermission permission) async {
    try {
      return _normalize(await _map(permission).status);
    } on Exception {
      return PermissionResult.notApplicable;
    }
  }

  /// Prompts if needed, then returns the resulting state.
  Future<PermissionResult> request(AppPermission permission) async {
    try {
      final Permission target = _map(permission);
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
