import 'package:flutter/material.dart';

/// Delivery state of an outgoing message.
enum MessageStatus {
  /// Not yet handed off — stored only on device.
  pending,

  /// Handed off to the transport.
  sent,

  /// Reached the recipient's device.
  delivered,

  /// Recipient opened the chat.
  read,

  /// Transport reported a failure.
  failed,
}

/// Kind of content a message carries. Drives which bubble renders.
enum MessageType {
  text,
  image,
  video,
  audio,
  voice,
  document,
  location,
  contact,
  poll,
  event,
  sticker,
  system,

  /// A gift the sender paid for with points.
  ///
  /// Carries the gift's emoji and name in the message body rather than a
  /// reference to the catalogue: the conversation has to keep rendering
  /// correctly even if the catalogue later changes or drops that gift.
  gift,
}

/// Direction of a message relative to the local user.
enum MessageDirection { incoming, outgoing }

/// A single emoji reaction left on a message.
@immutable
class MessageReaction {
  const MessageReaction({
    required this.emoji,
    required this.senderId,
    required this.senderName,
  });

  final String emoji;
  final String senderId;
  final String senderName;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'emoji': emoji,
        'senderId': senderId,
        'senderName': senderName,
      };

  factory MessageReaction.fromJson(Map<String, dynamic> json) => MessageReaction(
        emoji: json['emoji'] as String? ?? '',
        senderId: json['senderId'] as String? ?? '',
        senderName: json['senderName'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is MessageReaction &&
      other.emoji == emoji &&
      other.senderId == senderId;

  @override
  int get hashCode => Object.hash(emoji, senderId);
}

/// A poll option with its accumulated votes.
@immutable
class PollOption {
  const PollOption({
    required this.id,
    required this.text,
    this.voterIds = const <String>[],
  });

  final String id;
  final String text;
  final List<String> voterIds;

  int get votes => voterIds.length;

  PollOption copyWith({String? text, List<String>? voterIds}) => PollOption(
        id: id,
        text: text ?? this.text,
        voterIds: voterIds ?? this.voterIds,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'voterIds': voterIds,
      };

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        voterIds:
            (json['voterIds'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
      );
}

/// Poll metadata attached to a [Message].
///
/// When [correctOptionId] is set the poll behaves as a quiz: voters see right or
/// wrong feedback instead of plain result bars, and results stay hidden from
/// anyone who has not answered yet.
@immutable
class Poll {
  const Poll({
    required this.question,
    required this.options,
    this.allowMultiple = false,
    this.correctOptionId,
  });

  final String question;
  final List<PollOption> options;
  final bool allowMultiple;

  /// The winning option for a quiz. `null` means an ordinary poll.
  final String? correctOptionId;

  /// True when this poll grades its answers.
  bool get isQuiz => correctOptionId != null && correctOptionId!.isNotEmpty;

  int get totalVotes =>
      options.fold<int>(0, (sum, o) => sum + o.votes);

  PollOption? get correctOption => isQuiz
      ? options.where((PollOption o) => o.id == correctOptionId).firstOrNull
      : null;

  Poll copyWith({
    List<PollOption>? options,
    String? question,
    String? correctOptionId,
  }) =>
      Poll(
        question: question ?? this.question,
        options: options ?? this.options,
        allowMultiple: allowMultiple,
        correctOptionId: correctOptionId ?? this.correctOptionId,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'question': question,
        'options': options.map((o) => o.toJson()).toList(),
        'allowMultiple': allowMultiple,
        'correctOptionId': correctOptionId,
      };

  factory Poll.fromJson(Map<String, dynamic> json) => Poll(
        question: json['question'] as String? ?? '',
        options: (json['options'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => PollOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        allowMultiple: json['allowMultiple'] as bool? ?? false,
        correctOptionId: json['correctOptionId'] as String?,
      );
}

/// RSVP responses for an event message.
enum RsvpStatus { none, going, maybe, notGoing }

/// Event metadata attached to a [Message].
@immutable
class EventInfo {
  const EventInfo({
    required this.title,
    required this.start,
    this.end,
    this.location = '',
    this.description = '',
    this.rsvps = const <String, RsvpStatus>{},
  });

  final String title;
  final DateTime start;
  final DateTime? end;
  final String location;
  final String description;

  /// contactId -> response
  final Map<String, RsvpStatus> rsvps;

  EventInfo copyWith({
    String? title,
    DateTime? start,
    DateTime? end,
    String? location,
    String? description,
    Map<String, RsvpStatus>? rsvps,
  }) =>
      EventInfo(
        title: title ?? this.title,
        start: start ?? this.start,
        end: end ?? this.end,
        location: location ?? this.location,
        description: description ?? this.description,
        rsvps: rsvps ?? this.rsvps,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'location': location,
        'description': description,
        'rsvps': rsvps.map((k, v) => MapEntry(k, v.name)),
      };

  factory EventInfo.fromJson(Map<String, dynamic> json) => EventInfo(
        title: json['title'] as String? ?? '',
        start: DateTime.tryParse(json['start'] as String? ?? '') ?? DateTime.now(),
        end: json['end'] == null ? null : DateTime.tryParse(json['end'] as String),
        location: json['location'] as String? ?? '',
        description: json['description'] as String? ?? '',
        rsvps: (json['rsvps'] as Map<String, dynamic>? ?? <String, dynamic>{}).map(
          (k, v) => MapEntry(
            k,
            RsvpStatus.values.firstWhere(
              (e) => e.name == v,
              orElse: () => RsvpStatus.none,
            ),
          ),
        ),
      );
}

/// A file/media attachment referenced by a message.
///
/// Binary payloads are never stored in preferences — only the local file path
/// plus lightweight metadata. [remoteUrl] is the integration point for a
/// future cloud storage backend.
@immutable
class Attachment {
  const Attachment({
    required this.id,
    required this.type,
    this.localPath,
    this.remoteUrl,
    this.fileName,
    this.mimeType,
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnailPath,
    this.latitude,
    this.longitude,
    this.contactName,
    this.contactPhone,
  });

  final String id;
  final MessageType type;
  final String? localPath;
  final String? remoteUrl;
  final String? fileName;
  final String? mimeType;
  final int sizeBytes;
  final double? width;
  final double? height;
  final int? durationMs;
  final String? thumbnailPath;
  final double? latitude;
  final double? longitude;
  final String? contactName;
  final String? contactPhone;

  bool get isImage => type == MessageType.image;
  bool get isVideo => type == MessageType.video;
  bool get isAudio => type == MessageType.audio || type == MessageType.voice;
  bool get isDocument => type == MessageType.document;

  /// Returns a copy with the named fields replaced.
  ///
  /// Every field is nullable-tolerated the same way the constructor is, so
  /// passing `null` means "leave it alone" rather than "clear it" — which is
  /// what the call sites need (enriching an attachment with a thumbnail it may
  /// not have managed to produce).
  Attachment copyWith({
    String? id,
    MessageType? type,
    String? localPath,
    String? remoteUrl,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    double? width,
    double? height,
    int? durationMs,
    String? thumbnailPath,
    double? latitude,
    double? longitude,
    String? contactName,
    String? contactPhone,
  }) =>
      Attachment(
        id: id ?? this.id,
        type: type ?? this.type,
        localPath: localPath ?? this.localPath,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        fileName: fileName ?? this.fileName,
        mimeType: mimeType ?? this.mimeType,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        width: width ?? this.width,
        height: height ?? this.height,
        durationMs: durationMs ?? this.durationMs,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        contactName: contactName ?? this.contactName,
        contactPhone: contactPhone ?? this.contactPhone,
      );

  String get fileExtension {
    final String name = fileName ?? localPath ?? '';
    final int dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toUpperCase();
  }

  String get readableSize {
    if (sizeBytes <= 0) return '—';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double size = sizeBytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
  }

  String get readableDuration {
    final int ms = durationMs ?? 0;
    final int totalSeconds = ms ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'localPath': localPath,
        'remoteUrl': remoteUrl,
        'fileName': fileName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'thumbnailPath': thumbnailPath,
        'latitude': latitude,
        'longitude': longitude,
        'contactName': contactName,
        'contactPhone': contactPhone,
      };

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String? ?? '',
        type: MessageType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MessageType.text,
        ),
        localPath: json['localPath'] as String?,
        remoteUrl: json['remoteUrl'] as String?,
        fileName: json['fileName'] as String?,
        mimeType: json['mimeType'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        width: (json['width'] as num?)?.toDouble(),
        height: (json['height'] as num?)?.toDouble(),
        durationMs: (json['durationMs'] as num?)?.toInt(),
        thumbnailPath: json['thumbnailPath'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        contactName: json['contactName'] as String?,
        contactPhone: json['contactPhone'] as String?,
      );
}

/// A lightweight descriptor of a quoted message, embedded in replies.
@immutable
class ReplyPreview {
  const ReplyPreview({
    required this.messageId,
    required this.senderName,
    required this.preview,
    this.type = MessageType.text,
  });

  final String messageId;
  final String senderName;
  final String preview;
  final MessageType type;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'messageId': messageId,
        'senderName': senderName,
        'preview': preview,
        'type': type.name,
      };

  factory ReplyPreview.fromJson(Map<String, dynamic> json) => ReplyPreview(
        messageId: json['messageId'] as String? ?? '',
        senderName: json['senderName'] as String? ?? '',
        preview: json['preview'] as String? ?? '',
        type: MessageType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MessageType.text,
        ),
      );
}
