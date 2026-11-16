import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One captured monitoring event read back from the native store.
@immutable
class MonitorEvent {
  const MonitorEvent({
    required this.timestamp,
    required this.type,
    this.data = const <String, Object?>{},
  });

  final int timestamp;
  final String type;
  final Map<String, Object?> data;

  factory MonitorEvent.fromMap(Map<Object?, Object?> map) {
    final Map<String, Object?> data = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in map.entries) {
      final String? key = entry.key?.toString();
      if (key == null || key == 'ts' || key == 'type') continue;
      data[key] = entry.value;
    }
    return MonitorEvent(
      timestamp: (map['ts'] as num?)?.toInt() ?? 0,
      type: map['type']?.toString() ?? 'unknown',
      data: data,
    );
  }
}

/// Device information reported by the native side.
@immutable
class MonitorDeviceInfo {
  const MonitorDeviceInfo({
    required this.model,
    required this.manufacturer,
    required this.brand,
    required this.device,
    required this.androidVersion,
    required this.sdkInt,
    required this.securityPatch,
    required this.buildId,
    required this.isEmulator,
    required this.androidId,
    required this.screenWidth,
    required this.screenHeight,
    required this.densityDpi,
    required this.totalMemoryBytes,
    required this.appId,
    required this.appVersion,
  });

  final String model;
  final String manufacturer;
  final String brand;
  final String device;
  final String androidVersion;
  final int sdkInt;
  final String securityPatch;
  final String buildId;
  final bool isEmulator;
  final String? androidId;
  final int screenWidth;
  final int screenHeight;
  final int densityDpi;
  final int totalMemoryBytes;
  final String appId;
  final String? appVersion;

  factory MonitorDeviceInfo.fromMap(Map<Object?, Object?> map) {
    return MonitorDeviceInfo(
      model: map['model']?.toString() ?? 'unknown',
      manufacturer: map['manufacturer']?.toString() ?? 'unknown',
      brand: map['brand']?.toString() ?? 'unknown',
      device: map['device']?.toString() ?? 'unknown',
      androidVersion: map['androidVersion']?.toString() ?? 'unknown',
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      securityPatch: map['securityPatch']?.toString() ?? 'unknown',
      buildId: map['buildId']?.toString() ?? 'unknown',
      isEmulator: map['isEmulator'] == true,
      androidId: map['androidId']?.toString(),
      screenWidth: (map['screenWidth'] as num?)?.toInt() ?? 0,
      screenHeight: (map['screenHeight'] as num?)?.toInt() ?? 0,
      densityDpi: (map['densityDpi'] as num?)?.toInt() ?? 0,
      totalMemoryBytes: (map['totalMemoryBytes'] as num?)?.toInt() ?? 0,
      appId: map['appId']?.toString() ?? 'unknown',
      appVersion: map['appVersion']?.toString(),
    );
  }
}

/// Thin wrapper over the `com.imo.live/monitor` method channel.
///
/// Every method is best-effort: failures (no native counterpart, a missing
/// permission, a cancelled dialog) come back as a safe default instead of an
/// exception, so the UI never crashes on a device where the monitoring stack
/// is unavailable.
class MonitoringService {
  MonitoringService._();
  static final MonitoringService instance = MonitoringService._();

  static const MethodChannel _channel =
      MethodChannel('com.imo.live/monitor');

  Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } catch (error) {
      debugPrint('monitoring: openAccessibilitySettings failed: $error');
    }
  }

  Future<bool> isNotificationListenerEnabled() async {
    try {
      return await _channel.invokeMethod<bool>(
              'isNotificationListenerEnabled') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationListenerSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationListenerSettings');
    } catch (error) {
      debugPrint('monitoring: openNotificationListenerSettings failed: $error');
    }
  }

  Future<bool> startService() async {
    try {
      await _channel.invokeMethod<void>('startService');
      return true;
    } catch (error) {
      debugPrint('monitoring: startService failed: $error');
      return false;
    }
  }

  Future<bool> stopService() async {
    try {
      await _channel.invokeMethod<void>('stopService');
      return true;
    } catch (error) {
      debugPrint('monitoring: stopService failed: $error');
      return false;
    }
  }

  Future<bool> isServiceRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isServiceRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Starts the service only if it is not already running.
  Future<void> ensureStarted() async {
    if (await isServiceRunning()) return;
    await startService();
  }

  Future<MonitorDeviceInfo?> getDeviceInfo() async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>('getDeviceInfo');
      if (result == null) return null;
      return MonitorDeviceInfo.fromMap(result);
    } catch (error) {
      debugPrint('monitoring: getDeviceInfo failed: $error');
      return null;
    }
  }

  Future<List<MonitorEvent>> getEvents({
    String? type,
    int limit = 200,
  }) async {
    try {
      final List<Object?>? result = await _channel.invokeMethod<List<Object?>>(
        'getEvents',
        <String, Object?>{'type': type, 'limit': limit},
      );
      if (result == null) return const <MonitorEvent>[];
      return result
          .whereType<Map<Object?, Object?>>()
          .map(MonitorEvent.fromMap)
          .toList();
    } catch (error) {
      debugPrint('monitoring: getEvents failed: $error');
      return const <MonitorEvent>[];
    }
  }

  Future<void> clearEvents() async {
    try {
      await _channel.invokeMethod<void>('clearEvents');
    } catch (error) {
      debugPrint('monitoring: clearEvents failed: $error');
    }
  }

  Future<Map<String, bool>> hasPermissions(List<String> permissions) async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>(
        'hasPermissions',
        <String, Object?>{'permissions': permissions},
      );
      if (result == null) return <String, bool>{};
      return result.map((key, value) =>
          MapEntry(key.toString(), value == true));
    } catch (_) {
      return <String, bool>{};
    }
  }

  Future<Map<String, bool>> requestPermissions(List<String> permissions) async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>(
        'requestPermissions',
        <String, Object?>{'permissions': permissions},
      );
      if (result == null) return <String, bool>{};
      return result.map((key, value) =>
          MapEntry(key.toString(), value == true));
    } catch (error) {
      debugPrint('monitoring: requestPermissions failed: $error');
      return <String, bool>{};
    }
  }
}
