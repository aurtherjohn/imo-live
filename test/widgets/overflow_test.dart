import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/app/theme/app_theme.dart';
import 'package:imo_live/core/models/chat.dart';
import 'package:imo_live/core/widgets/common_widgets.dart';
import 'package:imo_live/core/widgets/i_avatar.dart';
import 'package:imo_live/features/chats/presentation/widgets/chat_tile.dart';
import 'package:imo_live/features/settings/presentation/widgets/settings_widgets.dart';

/// Narrow-screen / large-text overflow guard.
///
/// The smallest phone width the app supports is 320dp, and Android lets users
/// scale fonts to 1.6x. A `Row` whose children cannot shrink throws a
/// RenderFlex overflow — which in a test surfaces as a reported exception, so
/// simply pumping the widget and asserting no exception is a genuine check.
///
/// This is the scenario a real user hits with "Display size: largest" +
/// "Font size: largest" on a small phone.
const double _narrowWidth = 320;
const double _textScale = 1.6;

Future<void> pumpNarrow(
  WidgetTester tester,
  Widget child, {
  double scale = _textScale,
}) async {
  tester.view.physicalSize = const Size(_narrowWidth, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            // Keep the real size/insets; only the text scale is exaggerated.
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
}

Chat buildChat({
  String title = 'Design team',
  String lastMessage = 'See you tomorrow',
  String draft = '',
  bool isTyping = false,
  bool isOutgoing = false,
  int unreadCount = 0,
  bool isGroup = false,
}) {
  return Chat(
    id: 'c1',
    title: title,
    lastMessage: lastMessage,
    lastTimestamp: DateTime(2026, 9, 22, 14, 5),
    draft: draft,
    isTyping: isTyping,
    lastMessageIsOutgoing: isOutgoing,
    unreadCount: unreadCount,
    isGroup: isGroup,
    memberCount: isGroup ? 8 : 1,
  );
}

void main() {
  group('Overflow at 320dp / 1.6x text scale', () {
    testWidgets('IPill keeps a long label inside the row', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        const Center(child: IPill(label: 'Group administrator')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ProminentButton survives a long expanded label', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        Center(
          child: ProminentButton(
            label: 'Create community',
            icon: Icons.groups_rounded,
            onPressed: () {},
            expanded: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SettingsValueRow ellipsises a long value', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        SettingsValueRow(
          label: 'Media, links and documents',
          value: '1 234 items, 5.6 GB used',
          leadingIcon: Icons.photo_library_outlined,
          onTap: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SettingsTile handles a long title and subtitle', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        SettingsTile(
          title: 'Disappearing messages and media retention',
          subtitle:
              'Decide how long new messages stay on this device before they '
              'are removed automatically',
          leadingIcon: Icons.timer_outlined,
          onTap: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChatTile copes with a long title, preview and badge', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        ChatTile(
          chat: buildChat(
            title: 'Extremely long conversation title that keeps going',
            lastMessage:
                'This is a very long last message preview that should be '
                'ellipsised rather than overflowing the tile',
            unreadCount: 128,
          ),
          onTap: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChatTile typing state does not overflow', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        ChatTile(chat: buildChat(isTyping: true), onTap: () {}),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChatTile draft state does not overflow', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        ChatTile(
          chat: buildChat(
            draft: 'An unfinished draft that is quite long indeed',
          ),
          onTap: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChatTile outgoing tick state does not overflow', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        ChatTile(
          chat: buildChat(
            lastMessage: 'Sent from my phone',
            isOutgoing: true,
          ),
          onTap: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChatTile group variant does not overflow', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        ChatTile(
          chat: buildChat(
            title: 'Weekend football group with a long name',
            isGroup: true,
            lastMessage: 'Ahmed: I will bring the ball',
          ),
          onTap: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState does not overflow with long copy', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        EmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'No chats yet',
          message:
              'Start a conversation and it will show up here, ready for you '
              'to pick up where you left off.',
          actionLabel: 'Start a new chat',
          onAction: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('IAvatar with a badge renders at narrow width', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        const Center(child: IAvatar(name: 'Ada Lovelace', badgeCount: 99)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppTopBar title does not overflow', (
      WidgetTester tester,
    ) async {
      await pumpNarrow(
        tester,
        Scaffold(
          appBar: const AppTopBar(
            title: 'A rather long screen title that needs to fit',
            showBack: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
