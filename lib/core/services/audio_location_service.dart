import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/message_parts.dart';
import '../../core/permissions/permission_service.dart';
import '../../local/storage/file_storage_service.dart';
import '../constants/app_constants.dart';
import '../utils/l10n.dart';

/// A resolved device position, decoupled from the geolocator package.
class PlaceLocation {
  const PlaceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters = 0,
    this.label = '',
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String label;

  String get coordinates =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  Attachment toAttachment() => Attachment(
        id: 'att_${DateTime.now().microsecondsSinceEpoch}',
        type: MessageType.location,
        latitude: latitude,
        longitude: longitude,
        fileName: label.isEmpty ? 'Shared location' : label,
      );
}

/// Location resolution.
///
/// A map provider (Google Maps / OpenStreetMap) is intentionally not wired up:
/// [MapProviderConfig] marks the integration point. Everything the UI needs —
/// coordinates, label, static preview — works without one.
class LocationService {
  LocationService({this.permissions = const PermissionService()});

  final PermissionService permissions;

  Future<({PlaceLocation? location, String? error})> currentLocation() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (
          location: null,
          error: L10nRef.current.locationServicesAreOff,
        );
      }

      final PermissionResult permission =
          await permissions.request(AppPermission.location);
      if (!permission.isGranted) {
        return (
          location: null,
          error: permission.messageFor(AppPermission.location),
        );
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      return (
        location: PlaceLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          label: L10nRef.current.myLocation,
        ),
        error: null,
      );
    } on Exception catch (e) {
      return (location: null, error: L10nRef.current.couldNotDetermineYourLocation('$e'));
    }
  }

  /// Last known position — used when a fresh fix would take too long.
  Future<PlaceLocation?> lastKnown() async {
    try {
      final Position? position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return PlaceLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        label: L10nRef.current.approximateLocation,
      );
    } on Exception {
      return null;
    }
  }

  /// Tuning knobs for the future map integration.
  static const MapProviderConfig mapProvider = MapProviderConfig();

  /// Opens the platform map application for a coordinate pair.
  ///
  /// Uses `url_launcher` with a geo URI so no map SDK is required. The
  /// [MapProviderConfig] below is the integration point for a real map.
  Future<bool> openInMaps(double latitude, double longitude) async {
    final Uri uri = Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      final Uri web = Uri.parse(
        'https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude#map=17/$latitude/$longitude',
      );
      return await launchUrl(web, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}

/// REMOTE INTEGRATION POINT.
///
/// Set [enabled] and supply a [tileUrlTemplate] / API key when a real map
/// provider is configured. Until then the UI renders an offline preview card.
class MapProviderConfig {
  const MapProviderConfig({
    this.enabled = false,
    this.tileUrlTemplate = '',
    this.apiKey = '',
  });

  final bool enabled;
  final String tileUrlTemplate;
  final String apiKey;
}

/// State of an in-progress voice recording.
enum RecordingState { idle, recording, paused }

/// Result of a finished voice recording.
class VoiceRecordingResult {
  const VoiceRecordingResult({
    this.attachment,
    this.durationMs = 0,
    this.cancelled = false,
    this.error,
  });

  final Attachment? attachment;
  final int durationMs;
  final bool cancelled;
  final String? error;

  bool get isSuccess => attachment != null && !cancelled;
}

/// Records voice notes via the `record` package.
class AudioRecorderService {
  AudioRecorderService({
    AudioRecorder? recorder,
    FileStorageService? storage,
    this.permissions = const PermissionService(),
    this.callHoldsMicrophone,
  })  : _recorder = recorder ?? AudioRecorder(),
        _storage = storage ?? FileStorageService();

  final AudioRecorder _recorder;
  final FileStorageService _storage;
  final PermissionService permissions;

  /// Asks the call layer whether it is holding the capture right now, or null
  /// when no call layer is wired (tests, a build with calls disabled).
  ///
  /// Deliberately a live probe rather than a boolean fixed at construction: the
  /// state that matters is "is the capture held *at this instant*", and a
  /// remembered value is exactly the thing that goes stale — which is how the
  /// app came to report a call that was not there. It is consulted only to
  /// *explain* a failure the platform already produced. Recording is never
  /// refused on the strength of it: the platform's own answer is authoritative,
  /// and pre-empting it would invent a block that does not exist.
  final bool Function()? callHoldsMicrophone;

  final StreamController<Duration> _elapsed =
      StreamController<Duration>.broadcast();
  final StreamController<List<double>> _amplitude =
      StreamController<List<double>>.broadcast();

  Stream<Duration> get elapsedStream => _elapsed.stream;
  Stream<List<double>> get amplitudeStream => _amplitude.stream;

  Timer? _ticker;
  DateTime? _startedAt;
  Duration _accumulated = Duration.zero;
  String? _targetPath;
  RecordingState _state = RecordingState.idle;

  RecordingState get state => _state;
  bool get isRecording => _state == RecordingState.recording;

  Duration get elapsed {
    if (_state == RecordingState.recording && _startedAt != null) {
      return _accumulated + DateTime.now().difference(_startedAt!);
    }
    return _accumulated;
  }

  /// Begins recording. Safe to call only from [RecordingState.idle].
  Future<({bool ok, String? error})> start() async {
    if (_state != RecordingState.idle) return (ok: false, error: null);

    final PermissionResult permission =
        await permissions.request(AppPermission.microphone);
    if (!permission.isGranted) {
      return (ok: false, error: permission.messageFor(AppPermission.microphone));
    }

    try {
      if (!await _recorder.hasPermission()) {
        return (ok: false, error: L10nRef.current.microphoneAccessWasNot);
      }
      _targetPath = await _storage.reservePath(
        AppConstants.dirVoiceNotes,
        'm4a',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _targetPath!,
      );
      _state = RecordingState.recording;
      _startedAt = DateTime.now();
      _accumulated = Duration.zero;
      _startTicker();
      return (ok: true, error: null);
    } on Exception catch (e) {
      _state = RecordingState.idle;
      // The raw platform error for a busy capture is a native enum name that
      // says nothing a user can act on. When the call layer is still holding
      // the microphone, name that instead: it is the actual cause, and it is
      // the one thing the user can do something about.
      if (callHoldsMicrophone?.call() ?? false) {
        debugPrint(
          'Voice recording was refused while the call layer still held the '
          'microphone: $e',
        );
        return (
          ok: false,
          error:
              L10nRef.current.microphoneStillHeldByCall,
        );
      }
      return (ok: false, error: L10nRef.current.couldNotStartRecording('$e'));
    }
  }

  Future<bool> pause() async {
    if (_state != RecordingState.recording) return false;
    try {
      await _recorder.pause();
      _state = RecordingState.paused;
      _accumulated = elapsed;
      _startedAt = null;
      _stopTicker();
      _emitElapsed();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> resume() async {
    if (_state != RecordingState.paused) return false;
    try {
      await _recorder.resume();
      _state = RecordingState.recording;
      _startedAt = DateTime.now();
      _startTicker();
      return true;
    } on Exception {
      return false;
    }
  }

  /// Stops and keeps the file — the recording is ready to send.
  Future<VoiceRecordingResult> stopAndKeep() async {
    if (_state == RecordingState.idle) {
      return VoiceRecordingResult(error: L10nRef.current.noRecordingInProgress);
    }
    final Duration total = elapsed;
    try {
      final String? path = await _recorder.stop();
      _reset();
      final String finalPath = path ?? _targetPath ?? '';
      if (finalPath.isEmpty) {
        return VoiceRecordingResult(
          error: L10nRef.current.recordingCouldNotBeSaved,
        );
      }
      final File file = File(finalPath);
      final int size = await file.exists() ? await file.length() : 0;
      return VoiceRecordingResult(
        durationMs: total.inMilliseconds,
        attachment: Attachment(
          id: 'att_${DateTime.now().microsecondsSinceEpoch}',
          type: MessageType.voice,
          localPath: finalPath,
          fileName: finalPath.split(Platform.pathSeparator).last,
          sizeBytes: size,
          durationMs: total.inMilliseconds,
        ),
      );
    } on Exception catch (e) {
      _reset();
      return VoiceRecordingResult(error: L10nRef.current.couldNotFinishRecording('$e'));
    }
  }

  /// Stops and discards — used when the user slides to cancel.
  Future<VoiceRecordingResult> cancel() async {
    if (_state == RecordingState.idle) {
      return const VoiceRecordingResult(cancelled: true);
    }
    try {
      final String? path = await _recorder.stop();
      _reset();
      await _storage.deleteFile(path ?? _targetPath);
    } on Exception {
      _reset();
    }
    return const VoiceRecordingResult(cancelled: true);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      _emitElapsed();
      try {
        final Amplitude amplitude = await _recorder.getAmplitude();
        final double normalized =
            ((amplitude.current + 60) / 60).clamp(0.0, 1.0).toDouble();
        if (!_amplitude.isClosed) {
          _amplitude.add(<double>[normalized]);
        }
      } on Exception {
        // Amplitude is cosmetic — skip on failure.
      }
    });
  }

  void _emitElapsed() {
    if (!_elapsed.isClosed) _elapsed.add(elapsed);
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _reset() {
    _stopTicker();
    _state = RecordingState.idle;
    _startedAt = null;
    _accumulated = Duration.zero;
    _emitElapsed();
  }

  Future<void> dispose() async {
    _stopTicker();
    try {
      await _recorder.dispose();
    } on Exception {
      // Already disposed.
    }
    await _elapsed.close();
    await _amplitude.close();
  }
}
