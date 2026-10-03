import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:imo_live/app/theme/app_theme.dart';
import 'package:imo_live/core/constants/app_constants.dart';
import 'package:imo_live/core/models/chat.dart';
import 'package:imo_live/core/models/contact.dart';
import 'package:imo_live/core/models/message.dart';
import 'package:imo_live/core/models/message_parts.dart';
import 'package:imo_live/core/services/file_service.dart';
import 'package:imo_live/features/misc/presentation/startup.dart';
import 'package:imo_live/local/database/local_chat_repository.dart';
import 'package:imo_live/local/database/local_database.dart';
import 'package:imo_live/local/database/local_message_repository.dart';

/// Regression tests for the black-screen startup failure and the bugs found
/// while fixing it.
///
/// The app previously shipped with `main()` as `runApp(const SizedBox())`, so
/// these tests pin down the invariants that keep it from happening again: the
/// entry point must build a real app, and no storage problem may ever leave
/// startup stuck.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('imo_live_startup_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tempDir.path,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Startup contract', () {
    test('the app entry point is not an empty placeholder', () {
      // Guards against the exact regression that caused the black screen: a
      // stubbed-out `main()` that renders `SizedBox` and nothing else. Read the
      // source so the check does not depend on executing the real `main()`.
      final String source = File('lib/main.dart').readAsStringSync();

      expect(
        source.contains('runApp('),
        isTrue,
        reason: 'main() must call runApp()',
      );
      expect(
        source.contains('WidgetsFlutterBinding.ensureInitialized()'),
        isTrue,
        reason: 'the binding must be initialised before any async work',
      );
      expect(
        source.contains('ProviderScope'),
        isTrue,
        reason: 'Riverpod providers require a ProviderScope at the root',
      );
      expect(
        source.contains('ErrorWidget.builder'),
        isTrue,
        reason: 'build errors must render visible UI, not a black screen',
      );
      expect(
        source.contains('runApp(const SizedBox())'),
        isFalse,
        reason: 'this is the bug that caused the black screen',
      );
    });

    test('bootstrapProvider completes even when storage is unavailable',
        () async {
      // No Hive box is open in this test, so every repository read fails. The
      // splash screen awaits this future and navigates afterwards — if it threw
      // or hung, the user would be stranded on a black splash screen.
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(bootstrapProvider.future).timeout(
            const Duration(seconds: 15),
            onTimeout: () => fail('bootstrapProvider hung and never completed'),
          );

      expect(
        container.read(startupCompleteProvider),
        isTrue,
        reason: 'startupComplete must always be set so the splash can advance',
      );
    });
  });

  group('LocalDatabase degradation', () {
    test('reads and writes are safe before init', () async {
      // `init()` has not run here. Every primitive must degrade to empty rather
      // than throwing, otherwise the first frame of the app crashes.
      final LocalDatabase db = LocalDatabase.instance;

      expect(db.readString('imo_does_not_exist', 'k'), isNull);
      expect(db.readInt('imo_does_not_exist', 'k'), isNull);
      expect(db.readList<Chat>('imo_does_not_exist', 'k', Chat.fromJson),
          isEmpty);
      expect(db.readJson('imo_does_not_exist', 'k'), isNull);

      // Writes become no-ops instead of throwing.
      await db.writeString('imo_does_not_exist', 'k', 'v');
      await db.delete('imo_does_not_exist', 'k');
      await db.clearBox('imo_does_not_exist');
    });

    test('readList skips malformed records instead of discarding the list',
        () async {
      // Use a box that `LocalDatabase.init()` actually opened — reads gate on
      // the internal open-box set, not raw Hive state.
      await Hive.initFlutter(tempDir.path);
      await LocalDatabase.instance.init();

      // One valid chat, one non-object entry (a bare string), and one whose
      // `id` is the wrong type and therefore throws inside the decoder.
      // `readList` used to map the whole array in one pass, so either of these
      // would have blanked the entire collection.
      const String payload = '["not-a-record",'
          '{"id":"c1","title":"Valid"},'
          '{"id":{"nested":"object"}}]';
      await Hive.box<dynamic>(AppConstants.boxChats).put('probe', payload);

      final List<Chat> chats = LocalDatabase.instance
          .readList<Chat>(AppConstants.boxChats, 'probe', Chat.fromJson);

      expect(
        chats.length,
        1,
        reason: 'a single bad record must not blank the whole collection',
      );
      expect(chats.first.title, 'Valid');
    });
  });

  group('Chat repository invariants', () {
    setUp(() async {
      await Hive.initFlutter(tempDir.path);
      await LocalDatabase.instance.init();
      await LocalDatabase.instance.clearAll();
    });

    test('an incoming message increments unread and sets the preview', () async {
      final LocalChatRepository chats = LocalChatRepository();
      final LocalMessageRepository messages = LocalMessageRepository();

      final DateTime now = DateTime.now();
      await chats.save(
        Chat(
          id: 'ch_test',
          title: 'Test',
          lastMessage: '',
          lastTimestamp: now.subtract(const Duration(minutes: 5)),
        ),
      );

      final Message incoming = Message(
        id: 'm1',
        chatId: 'ch_test',
        senderId: 'c_other',
        senderName: 'Other',
        content: 'Hello there',
        timestamp: now,
        direction: MessageDirection.incoming,
        status: MessageStatus.read,
      );
      await messages.save(incoming);

      // The notifier owns the unread rule; exercise the repository primitive it
      // delegates to.
      await chats.updateLastMessage('ch_test', incoming);
      await chats.incrementUnread('ch_test');

      final Chat? updated = await chats.findById('ch_test');
      expect(updated, isNotNull);
      expect(updated!.unreadCount, 1);
      expect(updated.lastMessage, 'Hello there');
      // An incoming message has no delivery tick.
      expect(updated.lastMessageStatus, isNull);
    });

    test('markRead resets the unread badge to zero', () async {
      final LocalChatRepository chats = LocalChatRepository();
      final DateTime now = DateTime.now();

      await chats.save(
        Chat(
          id: 'ch_read',
          title: 'Read me',
          lastMessage: 'hi',
          lastTimestamp: now,
          unreadCount: 7,
        ),
      );
      expect((await chats.findById('ch_read'))!.unreadCount, 7);

      await chats.markRead('ch_read');
      expect((await chats.findById('ch_read'))!.unreadCount, 0);
    });

    test('editing a message persists the new body and flags it edited',
        () async {
      final LocalMessageRepository messages = LocalMessageRepository();
      final DateTime now = DateTime.now();

      await messages.save(
        Message(
          id: 'm_edit',
          chatId: 'ch_edit',
          senderId: 'self',
          senderName: 'You',
          content: 'original',
          timestamp: now,
          direction: MessageDirection.outgoing,
          status: MessageStatus.sent,
        ),
      );

      await messages.edit('m_edit', 'corrected');

      final List<Message> stored = await messages.getForChat('ch_edit');
      expect(stored.single.content, 'corrected');
      expect(
        stored.single.isEdited,
        isTrue,
        reason: 'the edit flag must be set by edit(), not by a second write',
      );
    });
  });

  group('FilePickResult', () {
    test('reports a friendly error when permission is denied', () {
      const FilePickResult denied = FilePickResult(
        error: 'Permission needed',
        permissionDenied: true,
      );

      expect(denied.error, 'Permission needed');
      expect(denied.permissionDenied, isTrue);
      expect(denied.hasAttachments, isFalse);
    });

    test('an empty result without an error is a plain cancel', () {
      const FilePickResult cancelled = FilePickResult();
      expect(cancelled.error, isNull);
      expect(cancelled.permissionDenied, isFalse);
      expect(cancelled.hasAttachments, isFalse);
    });
  });

  group('Error widget', () {
    testWidgets('a failing widget renders an error widget, not a blank frame',
        (WidgetTester tester) async {
      // The default Flutter error box is red-on-grey, which reads as an empty
      // screen against this app's near-black background. Verifying that a build
      // failure still produces a rendered widget is what distinguishes a
      // visible error from the silent black screen this app shipped with.
      //
      // `ErrorWidget.builder` is restored inside the test body because the test
      // binding asserts it is unset by the time the body returns.
      final ErrorWidgetBuilder original = ErrorWidget.builder;
      ErrorWidget.builder = (FlutterErrorDetails details) => ErrorWidget(
            FlutterErrorDetails(exception: details.exception),
          );

      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: Builder(
                  builder: (_) => throw StateError('simulated build failure'),
                ),
              ),
            ),
          ),
        );

        expect(
          find.byType(ErrorWidget),
          findsOneWidget,
          reason: 'a build failure must render an error widget, not nothing',
        );
      } finally {
        ErrorWidget.builder = original;
        // Consume the reported exception so it does not fail the test run.
        tester.takeException();
      }
    });
  });

  group('Contact model', () {
    test('fullName tolerates a missing last name', () {
      const Contact single = Contact(id: 'c', firstName: 'Solo');
      expect(single.fullName.trim(), 'Solo');

      const Contact anonymous = Contact(id: 'c2', firstName: '');
      expect(anonymous.fullName.trim(), isEmpty);
    });
  });
}
