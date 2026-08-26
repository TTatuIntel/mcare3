import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/core/async/app_busy.dart';
import 'package:mcare/shared/widgets/app_button.dart';
import 'package:mcare/shared/widgets/loading/delayed_loader.dart';
import 'package:mcare/shared/widgets/loading/mcare_pulse.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('DelayedLoader', () {
    testWidgets('mirrors loading state without a display timer', (
      tester,
    ) async {
      Widget build(bool loading) => _host(
        DelayedLoader(
          isLoading: loading,
          placeholder: const Text('LOADING'),
          child: const Text('CONTENT'),
        ),
      );

      await tester.pumpWidget(build(true));
      expect(find.text('LOADING'), findsOneWidget);
      expect(find.text('CONTENT'), findsNothing);

      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(find.text('LOADING'), findsNothing);
      expect(find.text('CONTENT'), findsOneWidget);
    });

    testWidgets('rapid completion is not prolonged artificially', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const DelayedLoader(
            isLoading: true,
            placeholder: Text('LOADING'),
            child: Text('CONTENT'),
          ),
        ),
      );

      await tester.pumpWidget(
        _host(
          const DelayedLoader(
            isLoading: false,
            placeholder: Text('LOADING'),
            child: Text('CONTENT'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CONTENT'), findsOneWidget);
      expect(find.text('LOADING'), findsNothing);
    });

    testWidgets('inline button exposes branded progress and blocks taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          AppButton(
            label: 'Save changes',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      );

      expect(find.text('Saving…'), findsOneWidget);
      expect(find.byType(McarePulse), findsOneWidget);
      await tester.tap(find.text('Saving…'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('disposes cleanly while loading', (tester) async {
      await tester.pumpWidget(
        _host(
          const DelayedLoader(
            isLoading: true,
            placeholder: Text('LOADING'),
            child: Text('CONTENT'),
          ),
        ),
      );
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AppBusy', () {
    setUp(AppBusy.instance.reset);
    tearDown(AppBusy.instance.reset);

    test('reads drive ambient progress but never block', () {
      AppBusy.instance.begin();
      expect(AppBusy.instance.isBusy, isTrue);
      expect(AppBusy.instance.isBlocking, isFalse);
      AppBusy.instance.end();
      expect(AppBusy.instance.isBusy, isFalse);
    });

    test('mutations remain inline unless explicitly promoted', () {
      AppBusy.instance.begin(mutation: true);
      expect(AppBusy.instance.isMutating, isTrue);
      expect(AppBusy.instance.isBlocking, isFalse);
      AppBusy.instance.end(mutation: true);
      expect(AppBusy.instance.isBusy, isFalse);
    });

    test('blocking operations expose and restore meaningful messages', () {
      AppBusy.instance.begin(blocking: true, message: 'Loading patient…');
      expect(AppBusy.instance.isBlocking, isTrue);
      expect(AppBusy.instance.blockingMessage, 'Loading patient…');

      AppBusy.instance.begin(blocking: true, message: 'Preparing chart…');
      expect(AppBusy.instance.blockingMessage, 'Preparing chart…');

      AppBusy.instance.end(blocking: true);
      expect(AppBusy.instance.blockingMessage, 'Loading patient…');
      AppBusy.instance.end(blocking: true);
      expect(AppBusy.instance.isBusy, isFalse);
    });

    test('only state edges notify', () {
      var notifications = 0;
      void listener() => notifications++;
      AppBusy.instance.addListener(listener);
      addTearDown(() => AppBusy.instance.removeListener(listener));

      AppBusy.instance.begin();
      AppBusy.instance.begin();
      expect(notifications, 1, reason: 'idle -> busy is one edge');

      AppBusy.instance.end();
      expect(notifications, 1, reason: 'still busy');

      AppBusy.instance.end();
      expect(notifications, 2, reason: 'busy -> idle');
    });

    test('background work is invisible to the UI', () async {
      await AppBusy.runBackground(() async {
        AppBusy.instance.begin();
        AppBusy.instance.begin(mutation: true, blocking: true);
        expect(AppBusy.instance.isBusy, isFalse);
        expect(AppBusy.instance.isBlocking, isFalse);
        AppBusy.instance.end();
        AppBusy.instance.end(mutation: true, blocking: true);
      });
      expect(AppBusy.instance.isBusy, isFalse);
    });

    test('the background marking survives an await', () async {
      await AppBusy.runBackground(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(AppBusy.isBackgroundWork, isTrue);
      });
      expect(AppBusy.isBackgroundWork, isFalse);
    });

    test('end below zero is a no-op', () {
      AppBusy.instance.end();
      AppBusy.instance.end(mutation: true, blocking: true);
      expect(AppBusy.instance.isBusy, isFalse);
    });

    test('run releases blocking state on success and failure', () async {
      await AppBusy.instance.run(
        () async => 1,
        blocking: true,
        message: 'Working…',
      );
      expect(AppBusy.instance.isBlocking, isFalse);

      await expectLater(
        AppBusy.instance.run(
          () async => throw StateError('boom'),
          blocking: true,
        ),
        throwsStateError,
      );
      expect(AppBusy.instance.isBusy, isFalse);
    });
  });
}
