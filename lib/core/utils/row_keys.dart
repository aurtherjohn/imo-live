import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';

/// The meaning of a row key: a conversation.
///
/// A notification carries only a string — the `chatId` in the FCM payload —
/// and the chat list carries a string as its `rowKey`. Both need to decide
/// which screen that string names, and they must agree, or a tap on a
/// notification lands on a conversation that does not exist.
///
/// ### Why conversations are prefixed too
///
/// A chat and a group are both Firestore document ids, so the same string can
/// name both. A prefixed key makes that collision impossible in a `ValueKey`,
/// which Flutter would otherwise resolve by reusing the wrong row's element.
/// The prefix is therefore part of the *row key* contract but not part of the
/// *route*: [locationOf] strips it back off.
///
/// Keeping the parse in one place is what makes the agreement checkable.
abstract final class RowKeys {
  const RowKeys._();

  /// The prefix marking a key as naming a conversation.
  static const String chatPrefix = 'chat:';

  /// Builds the key for a conversation row.
  static String chat(String chatId) => '$chatPrefix$chatId';

  /// True when [key] names a conversation.
  static bool isChat(String key) => key.startsWith(chatPrefix);

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
