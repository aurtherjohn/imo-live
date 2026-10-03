import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';

/// The meaning of a row key: a conversation, or a channel.
///
/// A notification carries only a string — the `chatId` in the FCM payload —
/// and the merged chat list carries a string as its `rowKey`. Both need to
/// decide which screen that string names, and they must agree, or a tap on a
/// channel notification lands on a conversation that does not exist.
///
/// ### Why conversations are prefixed too
///
/// A chat and a channel are both Firestore document ids, so the same string can
/// name both. A prefixed key makes that collision impossible in a `ValueKey`,
/// which Flutter would otherwise resolve by reusing the wrong row's element.
/// The prefix is therefore part of the *row key* contract but not part of the
/// *route*: [locationOf] strips it back off.
///
/// Keeping the parse in one place is what makes the agreement checkable: the
/// Cloud Function writes `channel:<id>` (see `functions/channel_push.js`) and
/// this is the only reader.
abstract final class RowKeys {
  const RowKeys._();

  /// The prefix marking a key as naming a channel.
  static const String channelPrefix = 'channel:';

  /// The prefix marking a key as naming a conversation.
  static const String chatPrefix = 'chat:';

  /// Builds the key for a channel row.
  static String channel(String channelId) => '$channelPrefix$channelId';

  /// Builds the key for a conversation row.
  static String chat(String chatId) => '$chatPrefix$chatId';

  /// True when [key] names a channel.
  static bool isChannel(String key) => key.startsWith(channelPrefix);

  /// True when [key] names a conversation.
  static bool isChat(String key) => key.startsWith(chatPrefix);

  /// The channel id inside [key], or null when it is not a channel key.
  ///
  /// A prefixed key with nothing after it is treated as not-a-channel: an
  /// empty channel id would push a route that renders "not found", which is a
  /// worse outcome than falling through to the conversation route.
  static String? channelIdOf(String key) {
    if (!isChannel(key)) return null;
    final String id = key.substring(channelPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// The conversation id inside [key], or null when it is not a chat key.
  static String? chatIdOf(String key) {
    if (!isChat(key)) return null;
    final String id = key.substring(chatPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// The router location [key] should open, or null when it names nothing.
  ///
  /// Pure and router-agnostic so it can be tested without a widget tree — the
  /// interesting part is the prefix decision, not the navigation.
  ///
  /// Accepts both a prefixed row key and a bare id, because a push sent by a
  /// client older than this change carries a bare `chatId`. The route always
  /// takes the bare id, so the prefix is removed rather than passed through.
  static String? locationOf(String key) {
    final String? channelId = channelIdOf(key);
    if (channelId != null) return '${AppRoutes.channelChat}/$channelId';

    if (key.isEmpty) return null;

    // A `chat:`-prefixed key is a row key; anything else is a bare id from an
    // older sender. Both map to the same route.
    final String? chatId = isChat(key) ? chatIdOf(key) : key;
    if (chatId == null || chatId.isEmpty) return null;
    return '${AppRoutes.chat}/$chatId';
  }

  /// Opens whichever screen [key] names.
  ///
  /// Does nothing for an unrecognised key: a notification whose payload the
  /// app cannot interpret must not navigate to a broken screen.
  static void open(GoRouter router, String key) {
    final String? location = locationOf(key);
    if (location == null) return;
    router.push(location);
  }
}
