import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/message_parts.dart';
import '../../core/permissions/permission_service.dart';
import '../../local/storage/file_storage_service.dart';
import '../constants/app_constants.dart';
import '../utils/l10n.dart';

/// Result wrapper so callers can distinguish "user cancelled" from "failed".
class MediaPickResult {
  const MediaPickResult({
    this.attachments = const <Attachment>[],
    this.error,
    this.permissionDenied = false,
  });

  final List<Attachment> attachments;
  final String? error;
  final bool permissionDenied;

  bool get isEmpty => attachments.isEmpty;
  bool get hasError => error != null;
}

/// Picks and imports media from the device gallery.
class MediaService {
  MediaService({
    ImagePicker? picker,
    FileStorageService? storage,
    this.permissions = const PermissionService(),
  })  : _picker = picker ?? ImagePicker(),
        _storage = storage ?? FileStorageService();

  final ImagePicker _picker;
  final FileStorageService _storage;
  final PermissionService permissions;

  /// Runs the full pipeline: permission → pick → copy into app storage →
  /// describe as an [Attachment].
  Future<MediaPickResult> pickImages({
    bool multiple = false,
    bool fromCamera = false,
  }) async {
    // The image_picker plugin performs its own permission prompting on Android;
    // we only pre-check so we can surface a friendlier message.
    if (fromCamera) {
      final PermissionResult result =
          await permissions.request(AppPermission.camera);
      // `!result.isGranted` covers denied AND permanentlyDenied. Checking only
      // for `permanentlyDenied` let a plain denial fall through to the picker,
      // which returned nothing and produced a silent no-op — the user tapped
      // the camera button and nothing happened at all.
      if (!result.isGranted) {
        return MediaPickResult(
          error: result.messageFor(AppPermission.camera),
          permissionDenied: true,
        );
      }
    }

    try {
      final List<XFile> files =
          fromCamera ? await _captureSingle() : await _picker.pickMultiImage(imageQuality: 88);

      if (files.isEmpty) return const MediaPickResult();

      final List<Attachment> attachments = <Attachment>[];
      for (final XFile file in files.take(multiple ? 20 : 1)) {
        final String path = await _storage.importFile(
          File(file.path),
          AppConstants.dirImages,
        );
        attachments.add(
          Attachment(
            id: 'att_${DateTime.now().microsecondsSinceEpoch}_${attachments.length}',
            type: MessageType.image,
            localPath: path,
            fileName: path.split(Platform.pathSeparator).last,
            sizeBytes: await MediaFileHelper.sizeOf(path),
          ),
        );
      }
      return MediaPickResult(attachments: attachments);
    } on Exception catch (e) {
      return MediaPickResult(error: L10nRef.current.couldNotLoadTheImage('$e'));
    }
  }

  Future<List<XFile>> _captureSingle() async {
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );
    return shot == null ? <XFile>[] : <XFile>[shot];
  }

  /// Single-shot camera capture returning an imported attachment.
  Future<MediaPickResult> capturePhoto() async {
    final PermissionResult permission =
        await permissions.request(AppPermission.camera);
    if (!permission.isGranted) {
      return MediaPickResult(
        error: permission.messageFor(AppPermission.camera),
        permissionDenied: true,
      );
    }
    try {
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (shot == null) return const MediaPickResult();
      final String path =
          await _storage.importFile(File(shot.path), AppConstants.dirImages);
      return MediaPickResult(
        attachments: <Attachment>[
          Attachment(
            id: 'att_${DateTime.now().microsecondsSinceEpoch}',
            type: MessageType.image,
            localPath: path,
            fileName: path.split(Platform.pathSeparator).last,
            sizeBytes: await MediaFileHelper.sizeOf(path),
          ),
        ],
      );
    } on Exception catch (e) {
      return MediaPickResult(error: L10nRef.current.cameraIsUnavailable('$e'));
    }
  }

  /// Picks a video and imports it.
  Future<MediaPickResult> pickVideo({bool fromCamera = false}) async {
    final PermissionResult permission = await permissions.request(
      fromCamera ? AppPermission.camera : AppPermission.videos,
    );
    if (!permission.isGranted) {
      return MediaPickResult(
        error: permission.messageFor(
          fromCamera ? AppPermission.camera : AppPermission.videos,
        ),
        permissionDenied: true,
      );
    }
    try {
      final XFile? video = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null) return const MediaPickResult();
      final String path =
          await _storage.importFile(File(video.path), AppConstants.dirVideos);
      return MediaPickResult(
        attachments: <Attachment>[
          Attachment(
            id: 'att_${DateTime.now().microsecondsSinceEpoch}',
            type: MessageType.video,
            localPath: path,
            fileName: path.split(Platform.pathSeparator).last,
            sizeBytes: await MediaFileHelper.sizeOf(path),
            // The picker already decoded the container, so duration is free
            // here. The bubble's duration chip reads this; without it every
            // video showed no length at all.
            durationMs: await MediaFileHelper.videoDurationMs(path),
          ),
        ],
      );
    } on Exception catch (e) {
      return MediaPickResult(error: L10nRef.current.couldNotLoadTheVideo('$e'));
    }
  }
}

/// Small helper so media code does not reach into `dart:io` directly.
class MediaFileHelper {
  const MediaFileHelper._();

  static Future<int> sizeOf(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return 0;
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  /// Reads a video's duration in milliseconds, or `null` when it cannot be
  /// determined.
  ///
  /// Opens the container with `video_player` and closes it immediately — the
  /// initialise call decodes the header, which carries the duration, and no
  /// frame is ever presented. Returns null rather than 0 so the caller can tell
  /// "unknown" from "zero-length", and the bubble hides the chip in both cases.
  static Future<int?> videoDurationMs(String path) async {
    final VideoPlayerController controller =
        VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final Duration duration = controller.value.duration;
      return duration > Duration.zero ? duration.inMilliseconds : null;
    } on Object {
      // An unsupported container or a truncated file: no duration is a cosmetic
      // loss, so it must not fail the send.
      return null;
    } finally {
      await controller.dispose();
    }
  }
}
