import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/features/auth/presentation/otp_screen.dart';

/// Guards the email-verification screen's *shape*.
///
/// This screen used to be six OTP boxes, which was wrong: Firebase's
/// `sendEmailVerification()` sends a **link**, so there was nothing for the
/// boxes to receive and no way forward for the user. Nothing in the compiler or
/// the analyzer objects to a digit box being reintroduced here — it compiles,
/// it renders, and it is only wrong in the sense that it can never be satisfied.
/// Hence a test.
///
/// No Firebase binding is needed: `FirebaseAuthService.authStateChanges()` is
/// defensive and falls back to a null stream, and the poll's
/// `isEmailVerified()` short-circuits on a null `currentUser`. Both timers are
/// cancelled by `dispose()`, so each test unmounts before finishing — a pending
/// periodic timer would otherwise fail the test.
void main() {
  group('OtpScreen (link-based email verification)', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: OtpScreen())),
      );
      // Explicit pumps rather than `pumpAndSettle`: the 1-second countdown
      // calls setState on every tick, so there is never a frame-free moment for
      // `pumpAndSettle` to settle into.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    /// Unmounts so `dispose()` cancels the countdown and poll timers.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('shows the link instructions and no code boxes',
        (WidgetTester tester) async {
      await pump(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Verify your email'), findsOneWidget);

      // The regression this whole change exists to prevent: an input for a code
      // that Firebase never sends.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);

      // The three instructions, addressed by their own copy so a rewrite that
      // drops one is caught rather than silently passing.
      expect(
        find.text('Open your email inbox and click the confirmation link.'),
        findsOneWidget,
      );
      expect(
        find.text("If you don't see it, check your spam folder."),
        findsOneWidget,
      );
      expect(
        find.text('After confirming, return to this app.'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('hides the resend behind the cooldown, then offers it',
        (WidgetTester tester) async {
      await pump(tester);

      // A resend button that is live immediately invites a request Firebase
      // throttles, so it is deliberately hidden for the first minute.
      expect(find.text('Resend email'), findsNothing);

      await tester.pump(const Duration(seconds: 61));

      expect(find.text('Resend email'), findsOneWidget);

      await unmount(tester);
    });
  });
}
