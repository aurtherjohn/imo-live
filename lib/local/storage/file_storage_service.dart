import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';

/// Organises media on disk.
///
/// Binary content lives in the app documents directory under a fixed set of
/// sub-folders. Repositories only ever persist the resulting path, which keeps
/// the key-value store small and makes a future cloud upload trivial — swap the
/// path for a remote URL and the UI is unchanged.
class FileStorageService {
  FileStorageService();

  Directory? _root;

  /// Base media directory, created lazily.
  Future<Directory> root() async {
    if (_root != null) return _root!;
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/imo_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir;
    return dir;
  }

  /// Returns (and creates) one of the named media sub-folders.
  Future<Directory> folder(String name) async {
    final Directory base = await root();
    final Directory dir = Directory('${base.path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// All managed folders, used by the storage usage screen.
  List<String> get managedFolders => const <String>[
        AppConstants.dirImages,
        AppConstants.dirVideos,
        AppConstants.dirAudio,
        AppConstants.dirDocuments,
        AppConstants.dirVoiceNotes,
        AppConstants.dirProfile,
        AppConstants.dirWallpapers,
        AppConstants.dirStatus,
      ];

  /// Copies [source] into the managed [folderName] and returns the new path.
  ///
  /// The original picker file is left untouched.
  Future<String> importFile(File source, String folderName,
      {String? renameTo}) async {
    final Directory dir = await folder(folderName);
    final String ext = _extension(source.path);
    final String base = renameTo ?? _timestampName();
    final String target = '${dir.path}/$base$ext';
    final File copy = await source.copy(target);
    return copy.path;
  }

  /// Writes raw bytes (camera capture, recorded audio) into a managed folder.
  Future<String> writeBytes(
    List<int> bytes,
    String folderName, {
    required String extension,
    String? name,
  }) async {
    final Directory dir = await folder(folderName);
    final String base = name ?? _timestampName();
    final String target = '${dir.path}/$base.$extension';
    final File file = File(target);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Reserves a path for a plugin that writes the file itself.
  Future<String> reservePath(String folderName, String extension) async {
    final Directory dir = await folder(folderName);
    return '${dir.path}/${_timestampName()}.$extension';
  }

  /// Size of one managed folder in bytes.
  Future<int> folderSize(String folderName) async {
    try {
      final Directory dir = await folder(folderName);
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final FileSystemEntity entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } on FileSystemException {
            // Skip transient or locked files.
          }
        }
      }
      return total;
    } on FileSystemException {
      return 0;
    }
  }

  /// Per-folder usage map for the storage screen.
  Future<Map<String, int>> usageBreakdown() async {
    final Map<String, int> result = <String, int>{};
    for (final String name in managedFolders) {
      result[name] = await folderSize(name);
    }
    return result;
  }

  Future<int> totalSize() async {
    final Map<String, int> map = await usageBreakdown();
    return map.values.fold<int>(0, (a, b) => a + b);
  }

  Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Nothing actionable — the file may already be gone.
    }
  }

  Future<int> countFiles(String folderName) async {
    try {
      final Directory dir = await folder(folderName);
      if (!await dir.exists()) return 0;
      int count = 0;
      await for (final FileSystemEntity e in dir.list()) {
        if (e is File) count++;
      }
      return count;
    } on FileSystemException {
      return 0;
    }
  }

  /// Deletes every file inside a managed folder, keeping the folder itself.
  ///
  /// Returns the number of files removed.
  Future<int> clearFolder(String folderName) async {
    int removed = 0;
    try {
      final Directory dir = await folder(folderName);
      if (!await dir.exists()) return 0;
      await for (final FileSystemEntity e in dir.list()) {
        if (e is File) {
          await e.delete();
          removed++;
        }
      }
    } on FileSystemException {
      // Partial deletion is acceptable — the caller only reports the count.
    }
    return removed;
  }

  String _extension(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot == -1) return '';
    return path.substring(dot);
  }

  String _timestampName() =>
      'imo_${DateTime.now().millisecondsSinceEpoch}';
}

/// Formats a byte count for display.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final String formatted =
      size >= 100 || unit == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
  return '$formatted ${units[unit]}';
}
