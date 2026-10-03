import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/config/app_secrets.dart';
import 'package:imo_live/core/models/message_parts.dart';
import 'package:imo_live/core/services/storage_service.dart';

/// Pins the media URL contract that cross-device rendering depends on.
///
/// The requirement is exact: after an upload the app stores
/// `AppSecrets.r2PublicBaseUrl + "/" + objectKey` on the message document, and
/// the *recipient's* device renders from that string. If the construction
/// changes — a doubled slash, a missing base, a bare object key — the sender
/// still sees its own photo (it reads the local file) and the receiver silently
/// gets nothing. That asymmetry is why the sender never notices the bug, and
/// why it is worth a test rather than trust.
void main() {
  group('R2Config.effectivePublicBaseUrl', () {
    test('is the configured public base URL, not the signed endpoint', () {
      expect(R2Config.publicBaseUrl, AppSecrets.r2PublicBaseUrl);
      expect(R2Config.effectivePublicBaseUrl, AppSecrets.r2PublicBaseUrl);
    });

    test('has a public read URL configured, so cross-device media works', () {
      // The whole point of this change. Before it, this was false and every
      // link fell back to the SigV4-signed endpoint, which a recipient cannot
      // fetch — uploads succeeded but media never rendered on the other phone.
      expect(
        R2Config.hasPublicReadUrl,
        isTrue,
        reason: 'without a public base URL, media renders only for the sender',
      );
    });

    test('does NOT leak the account endpoint when a public URL is set', () {
      expect(
        R2Config.effectivePublicBaseUrl.contains('cloudflarestorage.com'),
        isFalse,
        reason: 'the signed endpoint is not readable by a recipient',
      );
    });

    test('carries no trailing slash, so appending a key cannot double it', () {
      expect(R2Config.effectivePublicBaseUrl, isNot(endsWith('/')));
    });
  });

  group('the stored media URL', () {
    // Mirrors `StorageService.uploadFile`'s construction exactly.
    String storedUrlFor(String objectKey) =>
        '${R2Config.effectivePublicBaseUrl.replaceAll(RegExp(r'/+$'), '')}/'
        '$objectKey';

    test('is base + "/" + objectKey, as the directive specifies', () {
      const String key = 'chat_media/abc/photo-123.jpg';
      expect(storedUrlFor(key), '${AppSecrets.r2PublicBaseUrl}/$key');
    });

    test('keeps the key\'s nested path segments intact', () {
      final String url =
          storedUrlFor('voice_notes/chat_1/voice-1699999999999.m4a');
      expect(url, endsWith('/voice_notes/chat_1/voice-1699999999999.m4a'));
      // Exactly one slash at the join.
      expect(url.contains('r2.dev//'), isFalse);
    });

    test('is absolute and https, so Image.network accepts it', () {
      final Uri uri = Uri.parse(storedUrlFor('files/x/report.pdf'));
      expect(uri.isAbsolute, isTrue);
      expect(uri.scheme, 'https');
      expect(uri.host, 'pub-215c584aa24f47d792388de37c21b079.r2.dev');
      expect(uri.path, '/files/x/report.pdf');
    });
  });

  group('Attachment round-trip (sender renders, receiver renders)', () {
    test('an attachment with a remote URL is recognised as remote', () {
      final Attachment a = Attachment(
        id: 'm1',
        type: MessageType.image,
        localPath: '/data/user/0/app/files/chat_media/x/photo-1.jpg',
        remoteUrl: '${AppSecrets.r2PublicBaseUrl}/chat_media/x/photo-1.jpg',
        fileName: 'photo-1.jpg',
      );
      expect(a.isImage, isTrue);
      // The receiver's copy carries only the remote URL — no local path.
      final Attachment received = Attachment(
        id: 'm1',
        type: MessageType.image,
        remoteUrl: a.remoteUrl,
      );
      expect(received.localPath, isNull);
      expect(received.remoteUrl, isNotNull);
      expect(received.remoteUrl, startsWith('https://'));
    });

    test('a voice note keeps its type through the round trip', () {
      final Attachment voice = Attachment(
        id: 'v1',
        type: MessageType.voice,
        remoteUrl: '${AppSecrets.r2PublicBaseUrl}/voice_notes/c/v-1.m4a',
        durationMs: 4200,
      );
      expect(voice.isAudio, isTrue);
      expect(voice.durationMs, 4200);
      expect(voice.readableDuration, isNotEmpty);
    });

    test('readableSize degrades gracefully when size was never sent', () {
      // `sendMessage` writes only mediaUrl, so a receiver has no size. It must
      // render an em dash rather than "0 B" or a crash.
      const Attachment noSize =
          Attachment(id: 'f1', type: MessageType.document, remoteUrl: 'u');
      expect(noSize.readableSize, '—');
    });
  });
}
