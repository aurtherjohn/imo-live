import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

/// Deep-links into the system settings screens the first-run flow points at.
///
/// Opening accessibility settings has no cross-platform API, so it goes through
/// a tiny Android method channel (`com.imo.live/system_settings`, implemented in
/// `MainActivity.kt`). That channel only *opens* screens — it reads and changes
/// nothing. Everything else falls back to `permission_handler`'s portable
/// `openAppSettings`, and a host with no platform implementation (widget tests,
/// desktop) simply reports `false`.
class SystemSettingsService {
  const SystemSettingsService();

  static const MethodChannel _channel =
      MethodChannel('com.imo.live/system_settings');

  /// Opens the OS accessibility settings list (Android only).
  Future<bool> openAccessibilitySettings() =>
      _invoke('openAccessibilitySettings');

  /// Opens this app's own settings page, where the runtime permissions and the
  /// notification toggle live.
  Future<bool> openAppSettings() async {
    if (await _invoke('openAppSettings')) return true;
    try {
      return await handler.openAppSettings();
    } on Object catch (error) {
      debugPrint('openAppSettings fallback failed: $error');
      return false;
    }
  }

  Future<bool> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on Object catch (error) {
      // MissingPluginException on tests/desktop, or a host that refused the
      // intent — either way the caller only needs a boolean.
      debugPrint('SystemSettingsService.$method failed: $error');
      return false;
    }
  }
}
