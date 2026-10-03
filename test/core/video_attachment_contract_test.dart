import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/message_parts.dart';

/// Guards the two fields the video bubble reads but that nothing used to write.
///
/// The failure mode here is invisible: a video whose attachment carries no
/// `thumbnailPath` and no `durationMs` still renders — just with a grey
/// placeholder and no length chip. Nothing throws, no test fails, and the app
/// looks "done" in a screenshot review. These tests pin the data contract so
/// the gap cannot reopen silently.
void main() {
  group('Attachment.copyWith', () {
    const Attachment base = Attachment(
      id: 'att_1',
      type: MessageType.video,
      localPath: '/data/videos/clip.mp4',
      fileName: 'clip.mp4',
      sizeBytes: 2048,
      durationMs: 12000,
    );

    test('replaces only the named field', () {
      final Attachment enriched =
          base.copyWith(thumbnailPath: '/data/thumbnails/t.png');

      expect(enriched.thumbnailPath, '/data/thumbnails/t.png');
      // Everything else must survive untouched — an enriching copy that dropped
      // the local path would break playback for the sender.
      expect(enriched.id, base.id);
      expect(enriched.type, base.type);
      expect(enriched.localPath, base.localPath);
      expect(enriched.fileName, base.fileName);
      expect(enriched.sizeBytes, base.sizeBytes);
      expect(enriched.durationMs, base.durationMs);
    });

    test('null leaves an existing value alone rather than clearing it', () {
      final Attachment withThumb =
          base.copyWith(thumbnailPath: '/t.png').copyWith(durationMs: 20000);

      expect(withThumb.thumbnailPath, '/t.png');
      expect(withThumb.durationMs, 20000);
    });

    test('can set a field that was previously null', () {
      const Attachment noDuration = Attachment(
        id: 'att_2',
        type: MessageType.video,
        localPath: '/v.mp4',
      );
      expect(noDuration.durationMs, isNull);
      expect(noDuration.copyWith(durationMs: 5000).durationMs, 5000);
    });
  });

  group('video attachment serde', () {
    test('thumbnailPath and durationMs survive a JSON round-trip', () {
      const Attachment original = Attachment(
        id: 'att_video',
        type: MessageType.video,
        remoteUrl: 'https://example.test/clip.mp4',
        fileName: 'clip.mp4',
        sizeBytes: 900000,
        durationMs: 47000,
        thumbnailPath: '/data/thumbnails/poster.png',
      );

      final Attachment restored =
          Attachment.fromJson(original.toJson());

      expect(restored.thumbnailPath, '/data/thumbnails/poster.png');
      expect(restored.durationMs, 47000);
      expect(restored.type, MessageType.video);
      expect(restored.remoteUrl, 'https://example.test/clip.mp4');
    });

    test('a JSON payload predating the fields decodes to null, not a throw', () {
      // Older messages on the server have no thumbnailPath key at all. Reading
      // one must not crash the chat list.
      final Map<String, dynamic> legacy = <String, dynamic>{
        'id': 'old',
        'type': 'video',
        'localPath': null,
        'remoteUrl': 'https://example.test/old.mp4',
        'fileName': 'old.mp4',
        'sizeBytes': 100,
      };

      final Attachment attachment = Attachment.fromJson(legacy);
      expect(attachment.thumbnailPath, isNull);
      expect(attachment.durationMs, isNull);
      expect(attachment.isVideo, isTrue);
    });
  });

  group('readableDuration', () {
    test('formats under a minute with a zero-padded seconds field', () {
      const Attachment a = Attachment(
        id: 'a',
        type: MessageType.video,
        durationMs: 7000,
      );
      expect(a.readableDuration, '0:07');
    });

    test('formats minutes and seconds', () {
      const Attachment a = Attachment(
        id: 'a',
        type: MessageType.video,
        durationMs: 125000,
      );
      expect(a.readableDuration, '2:05');
    });

    test('a missing duration reads as 0:00 rather than throwing', () {
      const Attachment a = Attachment(id: 'a', type: MessageType.video);
      expect(a.readableDuration, '0:00');
    });
  });
}
