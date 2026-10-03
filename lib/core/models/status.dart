import 'package:flutter/foundation.dart';

/// Type of a status update.
enum StatusType { text, image, video }

/// A 24-hour status update.
@immutable
class Status {
  const Status({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.type,
    this.text = '',
    this.mediaPath,
    this.backgroundColors = const <int>[0xFF1F1F24, 0xFF2A1420],
    this.textColor = 0xFFFFFFFF,
    this.fontSize = 30,
    this.caption = '',
    this.durationMs = 5000,
    this.createdAt,
    this.viewerIds = const <String>[],
    this.isOwn = false,
    this.isMuted = false,
    this.captionBackground,
  });

  final String id;
  final String authorId;
  final String authorName;
  final StatusType type;
  final String text;
  final String? mediaPath;

  /// Gradient endpoints for text statuses.
  final List<int> backgroundColors;
  final int textColor;
  final double fontSize;
  final String caption;
  final int durationMs;
  final DateTime? createdAt;
  final List<String> viewerIds;
  final bool isOwn;
  final bool isMuted;
  final int? captionBackground;

  bool get isViewed => viewerIds.isNotEmpty;

  /// Statuses expire after 24 hours.
  bool get isExpired {
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt!) > const Duration(hours: 24);
  }

  Duration get remaining {
    if (createdAt == null) return Duration.zero;
    final Duration elapsed = DateTime.now().difference(createdAt!);
    final Duration left = const Duration(hours: 24) - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  String get timeAgo {
    if (createdAt == null) return 'now';
    final Duration d = DateTime.now().difference(createdAt!);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Status copyWith({
    String? id,
    String? authorId,
    String? authorName,
    StatusType? type,
    String? text,
    String? mediaPath,
    List<int>? backgroundColors,
    int? textColor,
    double? fontSize,
    String? caption,
    int? durationMs,
    DateTime? createdAt,
    List<String>? viewerIds,
    bool? isOwn,
    bool? isMuted,
    int? captionBackground,
  }) =>
      Status(
        id: id ?? this.id,
        authorId: authorId ?? this.authorId,
        authorName: authorName ?? this.authorName,
        type: type ?? this.type,
        text: text ?? this.text,
        mediaPath: mediaPath ?? this.mediaPath,
        backgroundColors: backgroundColors ?? this.backgroundColors,
        textColor: textColor ?? this.textColor,
        fontSize: fontSize ?? this.fontSize,
        caption: caption ?? this.caption,
        durationMs: durationMs ?? this.durationMs,
        createdAt: createdAt ?? this.createdAt,
        viewerIds: viewerIds ?? this.viewerIds,
        isOwn: isOwn ?? this.isOwn,
        isMuted: isMuted ?? this.isMuted,
        captionBackground: captionBackground ?? this.captionBackground,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'type': type.name,
        'text': text,
        'mediaPath': mediaPath,
        'backgroundColors': backgroundColors,
        'textColor': textColor,
        'fontSize': fontSize,
        'caption': caption,
        'durationMs': durationMs,
        'createdAt': createdAt?.toIso8601String(),
        'viewerIds': viewerIds,
        'isOwn': isOwn,
        'isMuted': isMuted,
        'captionBackground': captionBackground,
      };

  factory Status.fromJson(Map<String, dynamic> json) => Status(
        id: json['id'] as String? ?? '',
        authorId: json['authorId'] as String? ?? '',
        authorName: json['authorName'] as String? ?? '',
        type: StatusType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => StatusType.text,
        ),
        text: json['text'] as String? ?? '',
        mediaPath: json['mediaPath'] as String?,
        backgroundColors:
            (json['backgroundColors'] as List<dynamic>?)?.cast<int>() ??
                const <int>[0xFF1F1F24, 0xFF2A1420],
        textColor: (json['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 30,
        caption: json['caption'] as String? ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 5000,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
        viewerIds:
            (json['viewerIds'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
        isOwn: json['isOwn'] as bool? ?? false,
        isMuted: json['isMuted'] as bool? ?? false,
        captionBackground: (json['captionBackground'] as num?)?.toInt(),
      );
}

/// Direction of a call relative to the local user.
enum CallDirection { incoming, outgoing }

/// Outcome of a call.
enum CallOutcome { answered, missed, declined, cancelled }

/// Whether the call was voice or video.
enum CallKind { voice, video }

/// A single entry in the call log.
@immutable
class CallRecord {
  const CallRecord({
    required this.id,
    required this.contactId,
    required this.contactName,
    required this.kind,
    required this.direction,
    required this.outcome,
    required this.timestamp,
    this.durationSeconds = 0,
    this.avatarPath,
    this.avatarColor,
  });

  final String id;
  final String contactId;
  final String contactName;
  final CallKind kind;
  final CallDirection direction;
  final CallOutcome outcome;
  final DateTime timestamp;
  final int durationSeconds;
  final String? avatarPath;
  final int? avatarColor;

  bool get isMissed =>
      outcome == CallOutcome.missed || outcome == CallOutcome.declined;

  String get durationLabel {
    if (durationSeconds <= 0) return '';
    final int m = durationSeconds ~/ 60;
    final int s = durationSeconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  CallRecord copyWith({
    String? id,
    String? contactId,
    String? contactName,
    CallKind? kind,
    CallDirection? direction,
    CallOutcome? outcome,
    DateTime? timestamp,
    int? durationSeconds,
    String? avatarPath,
    int? avatarColor,
  }) =>
      CallRecord(
        id: id ?? this.id,
        contactId: contactId ?? this.contactId,
        contactName: contactName ?? this.contactName,
        kind: kind ?? this.kind,
        direction: direction ?? this.direction,
        outcome: outcome ?? this.outcome,
        timestamp: timestamp ?? this.timestamp,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        avatarPath: avatarPath ?? this.avatarPath,
        avatarColor: avatarColor ?? this.avatarColor,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'contactId': contactId,
        'contactName': contactName,
        'kind': kind.name,
        'direction': direction.name,
        'outcome': outcome.name,
        'timestamp': timestamp.toIso8601String(),
        'durationSeconds': durationSeconds,
        'avatarPath': avatarPath,
        'avatarColor': avatarColor,
      };

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
        id: json['id'] as String? ?? '',
        contactId: json['contactId'] as String? ?? '',
        contactName: json['contactName'] as String? ?? '',
        kind: CallKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => CallKind.voice,
        ),
        direction: CallDirection.values.firstWhere(
          (e) => e.name == json['direction'],
          orElse: () => CallDirection.outgoing,
        ),
        outcome: CallOutcome.values.firstWhere(
          (e) => e.name == json['outcome'],
          orElse: () => CallOutcome.answered,
        ),
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        avatarPath: json['avatarPath'] as String?,
        avatarColor: (json['avatarColor'] as num?)?.toInt(),
      );
}

/// A scheduled call reminder.
@immutable
class ScheduledCall {
  const ScheduledCall({
    required this.id,
    required this.contactId,
    required this.contactName,
    required this.title,
    required this.scheduledAt,
    this.remindMinutesBefore = 10,
    this.kind = CallKind.voice,
    this.notes = '',
  });

  final String id;
  final String contactId;
  final String contactName;
  final String title;
  final DateTime scheduledAt;
  final int remindMinutesBefore;
  final CallKind kind;
  final String notes;

  ScheduledCall copyWith({
    String? id,
    String? contactId,
    String? contactName,
    String? title,
    DateTime? scheduledAt,
    int? remindMinutesBefore,
    CallKind? kind,
    String? notes,
  }) =>
      ScheduledCall(
        id: id ?? this.id,
        contactId: contactId ?? this.contactId,
        contactName: contactName ?? this.contactName,
        title: title ?? this.title,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        remindMinutesBefore: remindMinutesBefore ?? this.remindMinutesBefore,
        kind: kind ?? this.kind,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'contactId': contactId,
        'contactName': contactName,
        'title': title,
        'scheduledAt': scheduledAt.toIso8601String(),
        'remindMinutesBefore': remindMinutesBefore,
        'kind': kind.name,
        'notes': notes,
      };

  factory ScheduledCall.fromJson(Map<String, dynamic> json) => ScheduledCall(
        id: json['id'] as String? ?? '',
        contactId: json['contactId'] as String? ?? '',
        contactName: json['contactName'] as String? ?? '',
        title: json['title'] as String? ?? '',
        scheduledAt:
            DateTime.tryParse(json['scheduledAt'] as String? ?? '') ?? DateTime.now(),
        remindMinutesBefore: (json['remindMinutesBefore'] as num?)?.toInt() ?? 10,
        kind: CallKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => CallKind.voice,
        ),
        notes: json['notes'] as String? ?? '',
      );
}
