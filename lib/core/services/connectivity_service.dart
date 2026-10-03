import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Network transport type, normalised from the plugin's result.
enum NetworkStatus { wifi, mobile, ethernet, none, unknown }

extension NetworkStatusX on NetworkStatus {
  bool get isOnline => this != NetworkStatus.none;
  String get label => switch (this) {
        NetworkStatus.wifi => 'Wi-Fi',
        NetworkStatus.mobile => 'Mobile data',
        NetworkStatus.ethernet => 'Ethernet',
        NetworkStatus.none => 'No internet connection',
        NetworkStatus.unknown => 'Unknown',
      };
}

/// Monitors connectivity.
///
/// The app works fully offline; this service only drives the offline banner and
/// decides whether locally created messages stay in a pending state.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final StreamController<NetworkStatus> _controller =
      StreamController<NetworkStatus>.broadcast();

  NetworkStatus _status = NetworkStatus.unknown;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  NetworkStatus get status => _status;
  Stream<NetworkStatus> get stream => _controller.stream;

  Future<NetworkStatus> init() async {
    try {
      final List<ConnectivityResult> results =
          await _connectivity.checkConnectivity();
      _status = _map(results);
    } on Exception {
      _status = NetworkStatus.unknown;
    }
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final NetworkStatus next = _map(results);
      if (next != _status) {
        _status = next;
        if (!_controller.isClosed) _controller.add(next);
      }
    });
    return _status;
  }

  NetworkStatus _map(List<ConnectivityResult> results) {
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return NetworkStatus.none;
    }
    if (results.contains(ConnectivityResult.wifi)) return NetworkStatus.wifi;
    if (results.contains(ConnectivityResult.mobile)) return NetworkStatus.mobile;
    if (results.contains(ConnectivityResult.ethernet)) {
      return NetworkStatus.ethernet;
    }
    return NetworkStatus.unknown;
  }

  /// Active network type for the storage/network usage screens.
  String get networkLabel => _status.label;

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}

/// Resolves the MIME-ish category of a file from its extension.
///
/// Kept dependency-free: we only need enough fidelity to pick an icon and
/// decide whether a preview can be rendered.
class FileTypeDetector {
  const FileTypeDetector._();

  static bool isImage(String path) {
    final String ext = _ext(path);
    return const <String>['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic']
        .contains(ext);
  }

  static bool isVideo(String path) {
    final String ext = _ext(path);
    return const <String>['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v']
        .contains(ext);
  }

  static bool isAudio(String path) {
    final String ext = _ext(path);
    return const <String>['mp3', 'wav', 'aac', 'm4a', 'ogg', 'opus', 'flac']
        .contains(ext);
  }

  static bool isDocument(String path) => !isImage(path) && !isVideo(path) && !isAudio(path);

  static String _ext(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot == -1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  /// Short label used in document bubbles.
  static String label(String path) {
    final String ext = _ext(path);
    if (ext.isEmpty) return 'FILE';
    return ext.toUpperCase();
  }

  /// Human-readable size for a file on disk.
  static Future<int> sizeOf(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return 0;
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }
}
