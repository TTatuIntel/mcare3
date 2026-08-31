import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/auth/forgot_password_view.dart';
import 'package:mcare/shared/theme/app_theme.dart';

void main() {
  Widget harness({ResetPasswordArgs? initialReset}) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () =>
                  ForgotPasswordView.show(context, initialReset: initialReset),
              child: const Text('Open recovery'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('forgot password opens as a modal over the current screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.tap(find.text('Open recovery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('password-recovery-flow')),
      findsOneWidget,
    );
    expect(find.text('Account recovery'), findsOneWidget);
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Email link'), findsOneWidget);
    expect(find.text('SMS code'), findsOneWidget);
    expect(find.text('Open recovery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reset deep link opens the final step in the same modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        initialReset: const ResetPasswordArgs(
          email: 'patient@example.com',
          token: 'one-time-token',
        ),
      ),
    );
    await tester.tap(find.text('Open recovery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('recovery-reset')), findsOneWidget);
    expect(find.text('Create a new password'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm new password'), findsOneWidget);
    expect(find.text('Reset code'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
