import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minio/minio.dart';

import '../config/app_secrets.dart';
import '../../local/storage/file_storage_service.dart';

/// Cloudflare R2 connection settings.
///
/// ---------------------------------------------------------------------------
/// DEVELOPMENT BUILD — every value reads an `--dart-define` first and falls back
/// to the hardcoded development credential in `lib/core/config/app_secrets.dart`.
///
/// That ordering is the production migration path: swapping to real keys is a
/// build-flag change, not a code change.
///
///   flutter build apk --release \
///     --dart-define=R2_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com \
///     --dart-define=R2_ACCESS_KEY=... \
///     --dart-define=R2_SECRET_KEY=... \
///     --dart-define=R2_BUCKET=... \
///     --dart-define=R2_PUBLIC_BASE_URL=https://cdn.example.com
///
/// The fallbacks are compiled into the binary as plaintext and are recoverable
/// from the APK. See the warning at the top of [AppSecrets].
/// ---------------------------------------------------------------------------
class R2Config {
  const R2Config._();

  /// S3 API endpoint, e.g. `https://1a2b3c4d5e6f.r2.cloudflarestorage.com`
  static const String endpoint = String.fromEnvironment(
    'R2_ENDPOINT',
    defaultValue: AppSecrets.r2EndpointUrl,
  );

  /// S3 access key id.
  static const String accessKey = String.fromEnvironment(
    'R2_ACCESS_KEY',
    defaultValue: AppSecrets.r2AccessKeyId,
  );

  /// S3 secret access key.
  static const String secretKey = String.fromEnvironment(
    'R2_SECRET_KEY',
    defaultValue: AppSecrets.r2SecretAccessKey,
  );

  /// The bucket that holds all app media.
  static const String bucket = String.fromEnvironment(
    'R2_BUCKET',
    defaultValue: AppSecrets.r2BucketName,
  );

  /// Public read URL for the bucket, used to build the links stored on messages.
  /// e.g. `https://pub-1a2b3c4d.r2.dev` or `https://cdn.example.com`
  ///
  /// Reads `--dart-define=R2_PUBLIC_BASE_URL` first, then falls back to
  /// [AppSecrets.r2PublicBaseUrl] — the same two-step order as every other R2
  /// value, so filling the secret in `app_secrets.dart` is enough to turn media
  /// on without a build flag.
  ///
  /// ⚠️ When both are empty, [effectivePublicBaseUrl] falls back to the signed
  /// S3 endpoint. Uploads still work; the links they return are not publicly
  /// readable until a bucket public URL or custom domain is configured.
  static const String publicBaseUrl = String.fromEnvironment(
    'R2_PUBLIC_BASE_URL',
    defaultValue: AppSecrets.r2PublicBaseUrl,
  );

  /// R2 requires the `auto` region — it is not a real AWS region, and signing
  /// with anything else produces `SignatureDoesNotMatch`.
  static const String region = 'auto';

  /// True once real credentials are present, i.e. an upload can be attempted.
  ///
  /// Deliberately does **not** require [publicBaseUrl]. Writing an object needs
  /// only the S3 credentials, and gating uploads on a public read URL would
  /// silently disable all media sharing on an otherwise fully configured
  /// bucket.
  static bool get isConfigured =>
      !endpoint.contains('REPLACE_WITH') &&
      !accessKey.contains('REPLACE_WITH') &&
      !secretKey.contains('REPLACE_WITH') &&
      !bucket.contains('REPLACE_WITH') &&
      endpoint.trim().isNotEmpty &&
      accessKey.trim().isNotEmpty &&
      secretKey.trim().isNotEmpty &&
      bucket.trim().isNotEmpty;

  /// True when a bucket public URL is set, so an uploaded link can be fetched
  /// by a recipient without credentials.
  static bool get hasPublicReadUrl => publicBaseUrl.trim().isNotEmpty;

  /// The base URL used to build the link stored on a message.
  ///
  /// Falls back to `{endpoint}/{bucket}` when no public URL is configured. That
  /// URL is well-formed but requires SigV4 signing, so it resolves for this app
  /// and **not** for a recipient's `Image.network`. Set `R2_PUBLIC_BASE_URL`
  /// (an `r2.dev` URL, or a custom domain bound to the bucket) before media is
  /// expected to render on another device.
  static String get effectivePublicBaseUrl {
    final String base = publicBaseUrl.trim();
    return base.isEmpty ? '$endpoint/$bucket' : base;
  }
}

/// Uploads media to Cloudflare R2.
///
/// ### Why R2 and not Firebase Storage
///
/// Firebase Storage is not enabled on this project. R2 speaks the S3 API, so a
/// standard S3 client works against it unchanged — the only R2-specific details
/// are the `auto` region and the `*.r2.cloudflarestorage.com` endpoint, both
/// handled in [R2Config].
///
/// ### Offline-first
///
/// The local file is always the source of truth for the UI. Every upload first
/// imports the file into app-private storage ([FileStorageService.importFile])
/// and then pushes *that* copy to R2, so:
///
/// * the message bubble renders instantly from the local path, with no network;
/// * a failed or offline upload never loses the media — the local copy stays;
/// * re-sending only needs the cached path, not the original picker result.
///
/// Every method returns the public URL on success and `null` on failure, so
/// callers never have to handle a thrown storage error just to show a toast.
class StorageService {
  StorageService({FileStorageService? cache})
      : _cache = cache ?? FileStorageService();

  final FileStorageService _cache;

  Minio? _client;
  bool _clientFailed = false;

  /// Folder names inside the app's media directory, one per upload kind.
  static const String avatarFolder = 'avatars';
  static const String coverFolder = 'covers';
  static const String chatFolder = 'chat_media';
  static const String voiceFolder = 'voice_notes';
  static const String statusFolder = 'status';
  static const String fileFolder = 'files';

  bool get isConfigured => R2Config.isConfigured;

  /// The S3 client, built once. Returns null when R2 is not configured or the
  /// endpoint is malformed, so no caller has to guard the constructor.
  Minio? get _minio {
    if (_clientFailed) return null;
    if (!R2Config.isConfigured) return null;
    if (_client != null) return _client;

    try {
      final Uri uri = Uri.parse(R2Config.endpoint);
      final String host = uri.host;
      if (host.isEmpty) {
        debugPrint('R2 endpoint is not a valid URL: ${R2Config.endpoint}');
        _clientFailed = true;
        return null;
      }
      _client = Minio(
        endPoint: host,
        accessKey: R2Config.accessKey,
        secretKey: R2Config.secretKey,
        useSSL: uri.scheme != 'http',
        port: uri.hasPort ? uri.port : null,
        region: R2Config.region,
        // R2 does not serve virtual-hosted-style URLs
        // (`<bucket>.<account>.r2.cloudflarestorage.com` does not resolve), so
        // the bucket must stay in the path.
        pathStyle: true,
      );
      if (!R2Config.hasPublicReadUrl) {
        debugPrint(
          'R2: no public read URL configured — uploads will succeed, but the '
          'links they return require SigV4 signing and so will not render on '
          'another device. Set R2_PUBLIC_BASE_URL to the bucket\'s r2.dev URL '
          'or a custom domain bound to it.',
        );
      }
      return _client;
    } on Object catch (error) {
      debugPrint('R2 client could not be created: $error');
      _clientFailed = true;
      return null;
    }
  }

  // ------------------------------------------------------------- public API

  /// Uploads a profile picture under `avatars/{uid}/`.
  Future<String?> uploadAvatar(String filePath, String uid) =>
      uploadFile(filePath, folder: avatarFolder, owner: uid, kind: 'avatar');

  /// Uploads a profile cover image under `covers/{uid}/`.
  Future<String?> uploadCover(String filePath, String uid) =>
      uploadFile(filePath, folder: coverFolder, owner: uid, kind: 'cover');

  /// Uploads a chat attachment, grouped per conversation so a chat can be
  /// cleaned up in one prefix delete.
  Future<String?> uploadChatMedia(
    String filePath, {
    required String chatId,
    required String kind,
  }) =>
      uploadFile(
        filePath,
        folder: chatFolder,
        owner: chatId,
        kind: kind,
      );

  /// Uploads a recorded voice note.
  Future<String?> uploadVoiceNote(String filePath, {required String chatId}) =>
      uploadFile(
        filePath,
        folder: voiceFolder,
        owner: chatId,
        kind: 'voice',
      );

  /// Uploads a status (story) image or video under `status/{uid}/`.
  Future<String?> uploadStatusMedia(String filePath, String uid) =>
      uploadFile(filePath, folder: statusFolder, owner: uid, kind: 'status');

  /// Uploads a document or any other file attachment.
  Future<String?> uploadDocument(String filePath, {required String chatId}) =>
      uploadFile(filePath, folder: fileFolder, owner: chatId, kind: 'file');

  /// Caches [filePath] locally, then uploads it to R2.
  ///
  /// Returns the public URL, or null when R2 is unconfigured/unreachable. The
  /// local copy is created either way — see the class docs.
  Future<String?> uploadFile(
    String filePath, {
    required String folder,
    String owner = '',
    String kind = 'media',
  }) async {
    final String cachedPath = await _cacheLocally(filePath, folder);
    if (cachedPath.isEmpty) return null;

    final Minio? client = _minio;
    if (client == null) {
      debugPrint(
        'R2 is not configured — "$filePath" was cached locally at '
        '"$cachedPath" but not uploaded. See R2Config for the values to fill '
        'in.',
      );
      return null;
    }

    final File file = File(cachedPath);
    if (!await file.exists()) {
      debugPrint('Upload source missing: $cachedPath');
      return null;
    }

    final String extension = _extensionOf(cachedPath);
    final String objectKey = _objectKey(
      folder: folder,
      owner: owner,
      kind: kind,
      extension: extension,
    );

    try {
      final int size = await file.length();
      final Stream<Uint8List> stream =
          file.openRead().map(Uint8List.fromList);

      await client.putObject(
        R2Config.bucket,
        objectKey,
        stream,
        size: size,
        metadata: <String, String>{
          'Content-Type': contentTypeFor(extension),
          // A week of edge caching: object keys are timestamped, so a replaced
          // avatar is a new key rather than a stale cached one.
          'Cache-Control': 'public, max-age=604800',
        },
      );

      return '${R2Config.effectivePublicBaseUrl.replaceAll(RegExp(r'/+$'), '')}/'
          '$objectKey';
    } on Object catch (error) {
      debugPrint('Upload to R2 ($objectKey) failed: $error');
      return null;
    }
  }

  /// Best-effort delete of a previously uploaded object, used when an avatar is
  /// replaced so old uploads do not accumulate.
  Future<void> deleteByUrl(String url) async {
    final Minio? client = _minio;
    if (client == null || url.trim().isEmpty) return;

    final String key = _keyFromUrl(url);
    if (key.isEmpty) return;

    try {
      await client.removeObject(R2Config.bucket, key);
    } on Object catch (error) {
      // A missing object is fine — the goal was for it to be gone.
      debugPrint('R2 delete of $key skipped: $error');
    }
  }

  /// Uploads and reports progress, for a media bubble's progress bar.
  Future<String?> uploadWithProgress(
    String filePath, {
    required String folder,
    String owner = '',
    void Function(double)? onProgress,
  }) async {
    // The underlying client reports bytes rather than a fraction, and the
    // cached file is the authoritative size, so progress is scaled here.
    final String cachedPath = await _cacheLocally(filePath, folder);
    if (cachedPath.isEmpty) return null;

    final Minio? client = _minio;
    if (client == null) return null;

    final File file = File(cachedPath);
    if (!await file.exists()) return null;

    final int size = await file.length();
    final String objectKey = _objectKey(
      folder: folder,
      owner: owner,
      kind: 'media',
      extension: _extensionOf(cachedPath),
    );

    try {
      await client.putObject(
        R2Config.bucket,
        objectKey,
        file.openRead().map(Uint8List.fromList),
        size: size,
        metadata: <String, String>{
          'Content-Type': contentTypeFor(_extensionOf(cachedPath)),
        },
        onProgress: size <= 0
            ? null
            : (int sent) => onProgress?.call((sent / size).clamp(0.0, 1.0)),
      );
      return '${R2Config.effectivePublicBaseUrl.replaceAll(RegExp(r'/+$'), '')}/'
          '$objectKey';
    } on Object catch (error) {
      debugPrint('Upload to R2 ($objectKey) failed: $error');
      return null;
    }
  }

  // ---------------------------------------------------------------- helpers

  /// Copies [filePath] into the app's media directory.
  ///
  /// Returns the cached path, or the original when the copy fails — an
  /// unwritable cache must not block an upload that could still succeed.
  Future<String> _cacheLocally(String filePath, String folder) async {
    try {
      final File source = File(filePath);
      if (!await source.exists()) {
        debugPrint('Upload source missing: $filePath');
        return '';
      }
      // Already inside app storage (a re-send, or a voice note the recorder
      // wrote directly) — importing it again would just duplicate the file.
      final Directory root = await _cache.root();
      if (source.path.startsWith(root.path)) return source.path;

      return await _cache.importFile(source, folder);
    } on Object catch (error) {
      debugPrint('Local cache of $filePath failed, uploading in place: $error');
      return filePath;
    }
  }

  /// `{folder}/{owner}/{kind}-{timestamp}{ext}`, with the empty owner dropped.
  ///
  /// The timestamp keeps successive uploads of the same picture from
  /// overwriting each other, which would otherwise leave a stale image in the
  /// CDN cache.
  static String _objectKey({
    required String folder,
    required String owner,
    required String kind,
    required String extension,
  }) {
    final String scope = owner.trim().isEmpty ? 'shared' : owner.trim();
    final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
    return '$folder/$scope/$kind-$stamp$extension';
  }

  /// Recovers the object key from a public URL, for deletes.
  static String _keyFromUrl(String url) {
    try {
      final Uri uri = Uri.parse(url);
      final String base = Uri.parse(R2Config.effectivePublicBaseUrl).path;
      String path = uri.path;
      if (base.isNotEmpty && path.startsWith(base)) {
        path = path.substring(base.length);
      }
      return path.replaceAll(RegExp(r'^/+'), '');
    } on Object {
      return '';
    }
  }

  static String _extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '.jpg';
    final String ext = path.substring(dot).toLowerCase();
    // Guard against a pathological extension being used as a path segment.
    return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext) ? ext : '.jpg';
  }

  /// MIME type for an extension. Public so the upload UI can label a file
  /// before it is sent.
  static String contentTypeFor(String extension) => switch (extension) {
        '.png' => 'image/png',
        '.gif' => 'image/gif',
        '.webp' => 'image/webp',
        '.heic' => 'image/heic',
        '.mp4' => 'video/mp4',
        '.mov' => 'video/quicktime',
        '.m4a' => 'audio/mp4',
        '.mp3' => 'audio/mpeg',
        '.aac' => 'audio/aac',
        '.wav' => 'audio/wav',
        '.ogg' => 'audio/ogg',
        '.opus' => 'audio/opus',
        '.pdf' => 'application/pdf',
        '.zip' => 'application/zip',
        '.txt' => 'text/plain',
        _ => 'application/octet-stream',
      };
}

/// The storage upload boundary.
final Provider<StorageService> storageServiceProvider =
    Provider<StorageService>((Ref ref) => StorageService());
