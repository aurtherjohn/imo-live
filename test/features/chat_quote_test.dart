import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/models/message.dart';
import 'package:imo_live/core/models/message_parts.dart';
import 'package:imo_live/features/chats/domain/chat_service.dart';

/// The receive path used to drop the quote entirely.
///
/// Firestore stores only the **id** a reply points at, and `_toLocal` cannot
/// turn that into a `ReplyPreview` on its own, so every reply arrived on the
/// recipient's device with no quote above it — the sender's copy was fine, which
/// is why the bug was invisible from the device that sent it.
///
/// [quoteFor] is the pure rule that rebuilds it, so it can be pinned here
/// without a backend.
void main() {
  Message target({
    String id = 'm1',
    String senderId = 'peer',
    String content = 'the original',
    MessageDirection direction = MessageDirection.incoming,
    MessageType type = MessageType.text,
    bool isDeleted = false,
  }) =>
      Message(
        id: id,
        chatId: 'c',
        senderId: senderId,
        senderName: '',
        content: content,
        timestamp: DateTime(2026, 10, 1, 12),
        direction: direction,
        type: type,
        status: MessageStatus.delivered,
        isDeleted: isDeleted,
      );

  group('quoteFor', () {
    test('rebuilds the quote from the message being replied to', () {
      final ReplyPreview? quote = quoteFor(
        replyId: 'm1',
        target: target(),
        senderName: 'Ada',
      );

      expect(quote, isNotNull);
      expect(quote!.messageId, 'm1');
      expect(quote.senderName, 'Ada');
      expect(quote.preview, 'the original');
      expect(quote.type, MessageType.text);
    });

    test('carries the original type rather than defaulting to text', () {
      // The quote renders a type glyph. Defaulting it to `text` would put a
      // speech bubble beside a voice note.
      final ReplyPreview? quote = quoteFor(
        replyId: 'm1',
        target: target(type: MessageType.voice, content: ''),
        senderName: 'Ada',
      );

      expect(quote!.type, MessageType.voice);
      expect(quote.preview, 'Voice message');
    });

    test('says a withdrawn original was deleted', () {
      final ReplyPreview? quote = quoteFor(
        replyId: 'm1',
        target: target(content: '', isDeleted: true),
        senderName: 'Ada',
      );

      expect(quote!.preview, 'This message was deleted');
    });

    test('is null when the message is not a reply', () {
      expect(
        quoteFor(replyId: '', target: target(), senderName: 'Ada'),
        isNull,
      );
    });

    test('is null when the original cannot be found', () {
      // A quote box with nothing in it reads as a rendering fault; no quote
      // reads as "there is nothing to show".
      expect(
        quoteFor(replyId: 'gone', target: null, senderName: ''),
        isNull,
      );
    });

    test('bounds a long preview', () {
      // The quote is persisted on the message row, so an unbounded copy of the
      // original would be stored again for every reply to it.
      final ReplyPreview? quote = quoteFor(
        replyId: 'm1',
        target: target(content: 'x' * 400),
        senderName: 'Ada',
      );

      expect(quote!.preview.length, lessThan(400));
      expect(quote.preview.endsWith('…'), isTrue);
    });
  });
}
