import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/message_parts.dart';
import '../../core/permissions/permission_service.dart';
import '../../local/storage/file_storage_service.dart';
import '../constants/app_constants.dart';
import '../utils/l10n.dart';

/// Outcome of a file-picking operation.
///
/// Carries an optional [error] so the UI can explain a refusal instead of
/// silently doing nothing, which is what an empty list alone implied.
class FilePickResult {
  const FilePickResult({
    this.attachments = const <Attachment>[],
    this.error,
    this.permissionDenied = false,
  });

  final List<Attachment> attachments;
  final String? error;

  /// True when the failure was a refused permission, so the UI can point the
  /// user at system settings.
  final bool permissionDenied;

  bool get hasAttachments => attachments.isNotEmpty;
}

/// Picks documents and audio files and imports them into app storage.
class FileService {
  FileService({
    FileStorageService? storage,
    this.permissions = const PermissionService(),
  }) : _storage = storage ?? FileStorageService();

  final FileStorageService _storage;
  final PermissionService permissions;

  /// Document picker. Returns an empty list when the user cancels.
  Future<List<Attachment>> pickDocuments() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return <Attachment>[];
      return await _import(result, AppConstants.dirDocuments, MessageType.document);
    } on Exception {
      return <Attachment>[];
    }
  }

  /// Audio-only picker.
  ///
  /// Returns a [PickFailure] message when permission is refused so the caller
  /// can tell the user why nothing happened. Previously a plain denial fell
  /// through to the picker, which returned an empty result and produced a
  /// silent no-op.
  Future<FilePickResult> pickAudio() async {
    final PermissionResult permission =
        await permissions.request(AppPermission.audio);
    if (!permission.isGranted) {
      return FilePickResult(
        error: permission.messageFor(AppPermission.audio),
        permissionDenied: true,
      );
    }
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.audio,
      );
      if (result == null || result.files.isEmpty) {
        return const FilePickResult();
      }
      return FilePickResult(
        attachments: await _import(result, AppConstants.dirAudio, MessageType.audio),
      );
    } on Exception catch (e) {
      return FilePickResult(error: L10nRef.current.couldNotOpenThatAudioFile('$e'));
    }
  }

  Future<List<Attachment>> _import(
    FilePickerResult result,
    String folder,
    MessageType type,
  ) async {
    final List<Attachment> attachments = <Attachment>[];
    for (final PlatformFile file in result.files) {
      final String? sourcePath = file.path;
      if (sourcePath == null) continue;
      final String path = await _storage.importFile(File(sourcePath), folder);
      attachments.add(
        Attachment(
          id: 'att_${DateTime.now().microsecondsSinceEpoch}_${attachments.length}',
          type: type,
          localPath: path,
          fileName: file.name,
          mimeType: file.extension,
          sizeBytes: file.size,
        ),
      );
    }
    return attachments;
  }
}

/// Android/iOS share sheet.
class ShareService {
  const ShareService();

  /// Shares plain text through the platform share sheet.
  Future<void> shareText(String text, {String? subject}) async {
    if (text.trim().isEmpty) return;
    try {
      await Share.share(text, subject: subject);
    } on Exception {
      // Sharing can be unavailable in emulators; failing silently is correct.
    }
  }

  /// Shares a file (image, document, …).
  Future<void> shareFile(String path, {String? text}) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return;
      await Share.shareXFiles(<XFile>[XFile(path)], text: text);
    } on Exception {
      // Ignore — nothing useful to show the user.
    }
  }
}
