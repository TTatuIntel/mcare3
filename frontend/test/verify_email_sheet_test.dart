import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/auth/verify_email_sheet.dart';
import 'package:mcare/core/api/auth_api.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/otp_code_field.dart';

/// Verification as an interruption, not a destination.
///
/// It used to be a full page pushed over everything, which wiped the stack and
/// made a six-digit code look like the next stage of signing up. And the page
/// itself worked only for the one person who could read the mail and type into
/// the app on the same device: the countdown was invented locally rather than
/// read from the server, the boxes swallowed a pasted code five digits at a
/// time, and there was no way back if you had to go and check something.
void main() {
  setUp(() {
    AuthState.instance.signIn(
      const AppUser(
        id: 'p1',
        uniqueId: 'PT-001',
        firstName: 'Amara',
        lastName: 'Okonkwo',
        email: 'amara@example.com',
        role: UserRole.patient,
      ),
    );
  });

  Widget harness({VerificationDispatch? dispatch, String? status}) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => VerifyEmailSheet.show(
                context,
                dispatch: dispatch,
                initialStatus: status,
              ),
              child: const Text('Behind the sheet'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app);
    await tester.tap(find.text('Behind the sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('it opens over the page instead of replacing it', (tester) async {
    await open(tester, harness());

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.byType(OtpCodeField), findsOneWidget);
    expect(
      find.text('Behind the sheet'),
      findsOneWidget,
      reason: 'the app the person was using has to still be there',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('it names the inbox the code actually went to', (tester) async {
    await open(
      tester,
      harness(
        dispatch: const VerificationDispatch(
          delivered: true,
          channels: ['email', 'sms'],
          email: 'a••••a@example.com',
          phone: '+234•••••5678',
          smsAvailable: true,
          retryAfter: 45,
        ),
      ),
    );

    expect(
      find.textContaining('a••••a@example.com'),
      findsOneWidget,
      reason: 'an unaddressed "check your email" is no help on a shared device',
    );
    expect(find.textContaining('+234•••••5678'), findsOneWidget);
  });

  testWidgets('the countdown is the server cooldown, not an invented one', (
    tester,
  ) async {
    await open(
      tester,
      harness(
        dispatch: const VerificationDispatch(
          delivered: true,
          channels: ['email'],
          email: 'a••••a@example.com',
          retryAfter: 45,
        ),
      ),
    );

    expect(find.text('Resend code in 45s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend code in 44s'), findsOneWidget);
  });

  testWidgets('resend is offered once the cooldown runs out', (tester) async {
    await open(
      tester,
      harness(
        dispatch: const VerificationDispatch(
          delivered: true,
          channels: ['email'],
          email: 'a••••a@example.com',
          retryAfter: 2,
        ),
      ),
    );

    final button = find.widgetWithText(TextButton, 'Resend code in 2s');
    expect(tester.widget<TextButton>(button).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final ready = find.widgetWithText(TextButton, 'Resend code');
    expect(ready, findsOneWidget);
    expect(tester.widget<TextButton>(ready).onPressed, isNotNull);
  });

  testWidgets('SMS is offered only when there is a number to text', (
    tester,
  ) async {
    await open(
      tester,
      harness(
        dispatch: const VerificationDispatch(
          delivered: true,
          channels: ['email'],
          email: 'a••••a@example.com',
          smsAvailable: false,
        ),
      ),
    );

    expect(
      find.text('Send the code by SMS instead'),
      findsNothing,
      reason: 'a button that cannot work promises a way out that is not there',
    );
  });

  testWidgets('a number on file earns the SMS route', (tester) async {
    await open(
      tester,
      harness(
        dispatch: const VerificationDispatch(
          delivered: true,
          channels: ['email'],
          email: 'a••••a@example.com',
          phone: '+234•••••5678',
          smsAvailable: true,
        ),
      ),
    );

    expect(find.text('Send the code by SMS instead'), findsOneWidget);
  });

  testWidgets('a failed delivery says so instead of pretending', (
    tester,
  ) async {
    await open(
      tester,
      harness(
        dispatch: const VerificationDispatch(
          delivered: false,
          channels: [],
          email: 'a••••a@example.com',
        ),
      ),
    );

    expect(find.textContaining('could not deliver'), findsOneWidget);
  });

  testWidgets('a spent link is explained rather than silently ignored', (
    tester,
  ) async {
    await open(tester, harness(status: 'invalid'));

    expect(find.textContaining('expired or was already used'), findsOneWidget);
  });

  testWidgets('closing it returns the person to where they were', (
    tester,
  ) async {
    await open(tester, harness());

    await tester.tap(find.text('Verify later'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Verify your email'), findsNothing);
    expect(find.text('Behind the sheet'), findsOneWidget);
  });

  group('the code field', () {
    Future<OtpCodeFieldState> pumpField(
      WidgetTester tester, {
      ValueChanged<String>? onCompleted,
    }) async {
      final key = GlobalKey<OtpCodeFieldState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: OtpCodeField(
              key: key,
              onCompleted: onCompleted,
              autofocus: false,
            ),
          ),
        ),
      );
      return key.currentState!;
    }

    testWidgets('a pasted code fills every box, not just the first', (
      tester,
    ) async {
      String? completed;
      final state = await pumpField(tester, onCompleted: (c) => completed = c);

      // What a paste actually looks like: the whole string arrives in the
      // box that had focus. Six boxes each capped at one character used to
      // throw five digits of it away.
      await tester.enterText(find.byType(TextField).first, '482913');
      await tester.pump();

      expect(state.code, '482913');
      expect(completed, '482913');
    });

    testWidgets('a code pasted with spaces still lands', (tester) async {
      final state = await pumpField(tester);

      await tester.enterText(find.byType(TextField).first, '48 29 13');
      await tester.pump();

      expect(state.code, '482913');
    });

    testWidgets('typing one digit at a time still works', (tester) async {
      String? completed;
      final state = await pumpField(tester, onCompleted: (c) => completed = c);

      const digits = ['1', '2', '3', '4', '5', '6'];
      for (var i = 0; i < digits.length; i++) {
        await tester.enterText(find.byType(TextField).at(i), digits[i]);
        await tester.pump();
      }

      expect(state.code, '123456');
      expect(completed, '123456');
    });

    testWidgets('the first box accepts the platform one-time code', (
      tester,
    ) async {
      await pumpField(tester);

      final first = tester.widget<TextField>(find.byType(TextField).first);
      expect(
        first.autofillHints,
        contains(AutofillHints.oneTimeCode),
        reason: 'an SMS code the keyboard offers should not need retyping',
      );
    });

    testWidgets('clear empties the row', (tester) async {
      final state = await pumpField(tester);

      await tester.enterText(find.byType(TextField).first, '482913');
      await tester.pump();
      state.clear();
      await tester.pump();

      expect(state.code, '');
    });
  });
}
