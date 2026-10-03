import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/message_parts.dart';

/// Pins the voice-note duration contract across the wire.
///
/// The bug this guards: `sendMessage` used to write only `mediaUrl` to
/// Firestore. The recorder measures the length and puts it on the *sender's*
/// [Attachment], so the sender's bubble showed the real time — but the
/// recipient rebuilt its attachment from the document alone, got no duration,
/// and rendered `0:00`. Worse, it stayed `0:00` until `just_audio` happened to
/// resolve a duration: forever if the note was never played, and possibly
/// forever even then on platforms that report duration late.
///
/// The asymmetry is the reason this needs a test rather than care: the sender
/// sees a correct bubble, so only the *other* phone ever shows the defect.
///
/// The mapping itself lives in a private function (`_attachmentFromRemote`), so
/// what is pinned here is the shape of the data it preserves — that an
/// [Attachment] round-trips its duration through the persisted JSON and that a
/// missing duration degrades to null rather than to a thrown cast.
void main() {
  group('Attachment.durationMs persists', () {
    test('a voice note keeps its measured duration through toJson/fromJson', () {
      const int recorded = 7420; // 0:07
      final Attachment sent = Attachment(
        id: 'att_1',
        type: MessageType.voice,
        localPath: '/data/user/0/app/files/voice_notes/c/v-1.m4a',
        fileName: 'v-1.m4a',
        sizeBytes: 40123,
        durationMs: recorded,
      );

      // What the sender holds, and what the receiver must end up with.
      final Attachment restored = Attachment.fromJson(sent.toJson());

      expect(restored.durationMs, recorded);
      expect(restored.type, MessageType.voice);
      expect(restored.isAudio, isTrue);
      // This is the string the bubble renders — the actual regression.
      expect(restored.readableDuration, isNot('0:00'));
      expect(restored.readableDuration, '0:07');
    });

    test('a non-voice attachment carries no duration', () {
      const Attachment photo =
          Attachment(id: 'a2', type: MessageType.image, remoteUrl: 'https://x/y.jpg');
      expect(photo.durationMs, isNull);
      expect(photo.toJson()['durationMs'], isNull);
      expect(Attachment.fromJson(photo.toJson()).durationMs, isNull);
    });

    test('an omitted duration decodes to null, not to a throw', () {
      // A document written before the field existed, or by a build that did not
      // send it. `as num?` on a missing key yields null; this asserts the
      // reader's tolerance so an old voice note degrades to `0:00` instead of
      // taking the whole message down.
      final Attachment legacy = Attachment.fromJson(<String, dynamic>{
        'id': 'old',
        'type': 'voice',
        'remoteUrl': 'https://pub-x.r2.dev/voice_notes/c/old.m4a',
      });
      expect(legacy.durationMs, isNull);
      expect(legacy.isAudio, isTrue);
      // No duration: the widget must not pretend it knows one.
      expect(legacy.readableDuration, '0:00');
    });

    test('the receiver-side shape (remote only, no local path) keeps duration',
        () {
      // Mirrors `_attachmentFromRemote`: a remote URL, no local file, and the
      // duration forwarded. The widget reads exactly this.
      final Attachment received = Attachment(
        id: 'm9',
        type: MessageType.voice,
        remoteUrl: 'https://pub-215c584aa24f47d792388de37c21b079.r2.dev'
            '/voice_notes/c/v-9.m4a',
        durationMs: 3300,
      );
      expect(received.localPath, isNull);
      expect(received.remoteUrl, startsWith('https://'));
      expect(received.durationMs, 3300);
      expect(received.readableDuration, '0:03');
    });
  });
}
