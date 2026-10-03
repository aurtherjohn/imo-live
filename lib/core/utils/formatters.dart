import 'package:intl/intl.dart';

/// Date/time formatting shared across the app.
class DateFormatter {
  const DateFormatter._();

  /// Chat-list style timestamp: time today, "Yesterday", weekday within a week,
  /// otherwise a short numeric date.
  static String chatTimestamp(DateTime timestamp) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final int diff = today.difference(day).inDays;

    if (diff == 0) return DateFormat.Hm().format(timestamp);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.E().format(timestamp);
    if (timestamp.year == now.year) return DateFormat.MMMd().format(timestamp);
    return DateFormat.yMd().format(timestamp);
  }

  /// Time only — used inside message bubbles.
  static String time(DateTime timestamp) => DateFormat.Hm().format(timestamp);

  /// Full timestamp used in chat search results and star/archived screens.
  static String fullTimestamp(DateTime timestamp) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final int diff = today.difference(day).inDays;

    if (diff == 0) return 'Today, ${DateFormat.Hm().format(timestamp)}';
    if (diff == 1) return 'Yesterday, ${DateFormat.Hm().format(timestamp)}';
    if (diff < 7) {
      return '${DateFormat.EEEE().format(timestamp)}, ${DateFormat.Hm().format(timestamp)}';
    }
    return DateFormat('d MMM y, HH:mm').format(timestamp);
  }

  /// Day separator shown between message groups.
  static String daySeparator(DateTime timestamp) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final int diff = today.difference(day).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.EEEE().format(timestamp);
    return DateFormat.yMMMMd().format(timestamp);
  }

  /// "Last seen" phrasing.
  static String lastSeen(DateTime timestamp) {
    final Duration diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'last seen just now';
    if (diff.inSeconds < 60) return 'last seen ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'last seen today at ${time(timestamp)}';
    if (diff.inDays == 1) return 'last seen yesterday';
    if (diff.inDays < 7) return 'last seen ${diff.inDays} days ago';
    return 'last seen recently';
  }

  /// Relative label for statuses and calls.
  static String relative(DateTime timestamp) {
    final Duration diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.yMd().format(timestamp);
  }

  /// Call log label, e.g. "Today, 14:05".
  static String callTimestamp(DateTime timestamp) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final int diff = today.difference(day).inDays;

    if (diff == 0) return DateFormat.Hm().format(timestamp);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.E().format(timestamp);
    return DateFormat('d MMM').format(timestamp);
  }

  /// mm:ss for recordings and call durations.
  static String duration(Duration value) {
    final int minutes = value.inMinutes;
    final int seconds = value.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// "1h 05m" style for long durations.
  static String longDuration(Duration value) {
    if (value.inHours > 0) {
      return '${value.inHours}h ${(value.inMinutes % 60).toString().padLeft(2, '0')}m';
    }
    return '${value.inMinutes}m ${(value.inSeconds % 60).toString().padLeft(2, '0')}s';
  }

  /// Header for the starred/archived message lists.
  static String monthYear(DateTime timestamp) =>
      DateFormat.yMMMM().format(timestamp);

  /// Remaining status lifetime, e.g. "5h left".
  static String remaining(Duration value) {
    if (value.inHours >= 1) return '${value.inHours}h left';
    if (value.inMinutes >= 1) return '${value.inMinutes}m left';
    return 'expiring';
  }
}

/// Counts and plurals used in empty states and labels.
class TextUtils {
  const TextUtils._();

  static String members(int count) =>
      count == 1 ? '1 member' : '$count members';

  static String messageCount(int count) =>
      count == 1 ? '1 message' : '$count messages';

  static String callCount(int count) => count == 1 ? '1 call' : '$count calls';

  static String chatsCount(int count) =>
      count == 1 ? '1 chat' : '$count chats';

  /// Abbreviates a large count the way a social surface does: 999, 1.2K, 3.4M.
  ///
  /// Used for follower counts, reaction tallies and post views, where the exact
  /// number matters less than the magnitude and the row must not overflow.
  static String compactCount(int count) {
    if (count < 1000) return '$count';
    if (count < 1000000) {
      final double thousands = count / 1000;
      return '${_trim(thousands)}K';
    }
    final double millions = count / 1000000;
    return '${_trim(millions)}M';
  }

  /// One decimal place, dropping a trailing `.0` so `1.0K` reads as `1K`.
  static String _trim(double value) {
    final String text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  /// `1,234` — grouped digits for an exact figure.
  static String grouped(int count) {
    final String digits = count.abs().toString();
    final StringBuffer out = StringBuffer(count < 0 ? '-' : '');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// Trims a preview string to [max] characters with an ellipsis.
  static String truncate(String input, int max) {
    final String value = input.trim();
    if (value.length <= max) return value;
    return '${value.substring(0, max).trimRight()}…';
  }

  /// Formats a phone number with light grouping for readability.
  static String prettyPhone(String raw) {
    final String digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length <= 4) return digits;
    return digits;
  }

  /// Validates that a phone number has a plausible digit count.
  static bool isValidPhone(String raw) {
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 6 && digits.length <= 15;
  }

  /// Returns the chars still allowed before [limit] (for counters).
  static int remainingChars(String value, int limit) =>
      (limit - value.length).clamp(0, limit);
}

/// Builds the "100 MB" style strings used by storage screens.
class SizeFormatter {
  const SizeFormatter._();

  static String format(int bytes) {
    if (bytes <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final String text = (size >= 100 || unit == 0)
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }
}
