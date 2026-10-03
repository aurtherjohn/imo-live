import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:imo_live/app/router.dart';
import 'package:imo_live/core/constants/app_constants.dart';
import 'package:imo_live/features/chats/presentation/chat_screen.dart';
import 'package:imo_live/features/chats/presentation/chat_search_screen.dart';
import 'package:imo_live/features/contacts/presentation/contact_info_screen.dart';
import 'package:imo_live/features/contacts/presentation/new_contact_screen.dart';
import 'package:imo_live/features/contacts/presentation/select_contact_screen.dart';

/// Route resolution guard.
///
/// `router_test.dart` asserts that every path is *registered*. This file
/// asserts that every path *resolves to the intended screen*.
///
/// GoRouter matches routes in declaration order and takes the first hit, so a
/// parameterised route declared above a static sibling silently swallows it:
/// `/chat/:id` matches `/chat/search`, and `/contact/:id` matches both
/// `/contact/new` and `/contact/select`. The result is a real, user-visible
/// dead end — tapping "Select contact" opened a broken contact-info screen.
/// Registration checks cannot catch this; only resolution can.
void main() {
  /// Pumps a router starting at [location] and returns nothing — assertions
  /// are made by the caller against the rendered widget tree.
  Future<void> pumpAt(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final GoRouter router = GoRouter(
      initialLocation: location,
      routes: appRouter.configuration.routes,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('/chat/search opens the search screen, not a chat',
      (WidgetTester tester) async {
    await pumpAt(tester, '${AppRoutes.chatSearch}?id=c1');

    expect(find.byType(ChatSearchScreen), findsOneWidget);
    expect(
      find.byType(ChatScreen),
      findsNothing,
      reason: '/chat/:id must not shadow /chat/search',
    );
  });

  testWidgets('/contact/select opens the contact picker, not contact info',
      (WidgetTester tester) async {
    await pumpAt(tester, AppRoutes.selectContact);

    expect(find.byType(SelectContactScreen), findsOneWidget);
    expect(
      find.byType(ContactInfoScreen),
      findsNothing,
      reason: '/contact/:id must not shadow /contact/select',
    );
  });

  testWidgets('/contact/new opens the new-contact form, not contact info',
      (WidgetTester tester) async {
    await pumpAt(tester, AppRoutes.newContact);

    expect(find.byType(NewContactScreen), findsOneWidget);
    expect(
      find.byType(ContactInfoScreen),
      findsNothing,
      reason: '/contact/:id must not shadow /contact/new',
    );
  });

  testWidgets('/contact/<id> still opens contact info',
      (WidgetTester tester) async {
    await pumpAt(tester, '${AppRoutes.contactInfo}/abc123');

    expect(find.byType(ContactInfoScreen), findsOneWidget);
  });

  testWidgets('/chat/<id> still opens the conversation',
      (WidgetTester tester) async {
    await pumpAt(tester, '${AppRoutes.chat}/abc123');

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(ChatSearchScreen), findsNothing);
  });
}
