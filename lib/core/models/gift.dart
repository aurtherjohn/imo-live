import 'package:flutter/foundation.dart';

/// A gift that can be sent to another user, paid for out of a points balance.
///
/// Gifts are a fixed catalogue rather than a free-form amount so that the cost
/// of any gift is knowable before it is sent, and so both sides can render the
/// same thing from the same id — a gift message carries [id] and [emoji] and
/// nothing else has to be looked up.
@immutable
class Gift {
  const Gift({
    required this.id,
    required this.name,
    required this.emoji,
    required this.points,
  });

  /// Stable id, stored on the message and the ledger entry.
  final String id;

  /// Display name, e.g. "Diamond".
  final String name;

  /// The glyph that renders the gift. Emoji rather than an asset so a gift
  /// needs no bundled image and cannot fail to load.
  final String emoji;

  /// What it costs the sender.
  final int points;

  /// The catalogue, cheapest first.
  static const List<Gift> catalogue = <Gift>[
    Gift(id: 'rose', name: 'Rose', emoji: '🌹', points: 10),
    Gift(id: 'heart', name: 'Heart', emoji: '❤️', points: 25),
    Gift(id: 'coffee', name: 'Coffee', emoji: '☕', points: 50),
    Gift(id: 'diamond', name: 'Diamond', emoji: '💎', points: 100),
    Gift(id: 'crown', name: 'Crown', emoji: '👑', points: 250),
    Gift(id: 'trophy', name: 'Trophy', emoji: '🏆', points: 500),
    Gift(id: 'rocket', name: 'Rocket', emoji: '🚀', points: 1000),
  ];

  /// Looks a gift up by id, or null when the id is not in the catalogue.
  ///
  /// Null rather than a placeholder: an unknown gift means the sender and this
  /// build disagree about the catalogue, and showing a made-up gift would
  /// misreport what was actually sent.
  static Gift? byId(String id) {
    for (final Gift gift in catalogue) {
      if (gift.id == id) return gift;
    }
    return null;
  }

  /// Encodes this gift as a message body.
  ///
  /// A delimited string rather than a JSON blob because the body is also what
  /// the chat-list preview and the search index read — those want plain text,
  /// and a JSON document would leak braces into both. The separator is `|`,
  /// which no gift name contains.
  String toMessageBody() => '$emoji|$name|$points';

  /// Decodes a [toMessageBody] string.
  ///
  /// Returns null for anything that is not a well-formed gift body, so a caller
  /// can fall back to rendering the raw text instead of inventing a gift. The
  /// points are carried in the body on purpose: the bubble can then report what
  /// was actually spent even if the catalogue has since changed.
  static ({String emoji, String name, int points})? decodeMessageBody(
    String content,
  ) {
    final List<String> parts = content.split('|');
    if (parts.length != 3) return null;
    final String emoji = parts[0].trim();
    final String name = parts[1].trim();
    final int? points = int.tryParse(parts[2].trim());
    if (emoji.isEmpty || name.isEmpty || points == null) return null;
    return (emoji: emoji, name: name, points: points);
  }
}
