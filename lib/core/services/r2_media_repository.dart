import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../features/chats/domain/repositories.dart';
import '../../local/storage/file_storage_service.dart';
import 'storage_service.dart';

/// The [MediaRepository] implementation used by the app.
///
/// It answers the same question the old local-only version did — "where does
/// this file live?" — and additionally pushes the file to Cloudflare R2.
///
/// ### Why the identifier stays a local path
///
/// Every caller of [upload] renders the result directly: an avatar through
/// `Image.file`, a group icon, a wallpaper. Returning a URL would break all of
/// them, and would make the UI depend on the network for something it already
/// has on disk. So the identifier remains the local path — the offline-first
/// contract — and the R2 upload happens alongside it, yielding a URL that the
/// messaging layer stores on the message it sends.
///
/// A failed upload is therefore never a failed save: the media is already on
/// the device, and only the ability to share it is deferred.
class R2MediaRepository implements MediaRepository {
  R2MediaRepository({StorageService? storage, FileStorageService? cache})
      : _storage = storage ?? StorageService(),
        _cache = cache ?? FileStorageService();

  final StorageService _storage;
  final FileStorageService _cache;

  @override
  Future<String> upload(String localPath) async {
    final String stored = await importLocally(localPath);

    // Fire-and-forget. The local copy is the source of truth; this only adds a
    // URL other people can fetch, and it is logged rather than thrown so a
    // network failure cannot fail a save.
    unawaited(
      _storage.uploadFile(stored, folder: StorageService.fileFolder),
    );

    return stored;
  }

  /// Imports [localPath] into app-private storage and returns the stable path.
  ///
  /// A file already inside the media directory is returned unchanged, so
  /// re-saving a picture does not duplicate it.
  Future<String> importLocally(String localPath) async {
    try {
      final File source = File(localPath);
      if (!await source.exists()) return localPath;

      final Directory root = await _cache.root();
      if (source.path.startsWith(root.path)) return source.path;

      return await _cache.importFile(source, StorageService.fileFolder);
    } on Object catch (error) {
      debugPrint('Local import of $localPath failed: $error');
      return localPath;
    }
  }

  @override
  Future<void> delete(String identifier) async {
    // A URL means the item reached R2; anything else is a local path.
    if (identifier.startsWith('http://') || identifier.startsWith('https://')) {
      await _storage.deleteByUrl(identifier);
      return;
    }
    await _cache.deleteFile(identifier);
  }

  @override
  Future<Map<String, int>> usageBreakdown() => _cache.usageBreakdown();

  @override
  Future<int> totalUsage() => _cache.totalSize();
}
