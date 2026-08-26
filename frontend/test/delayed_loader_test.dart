import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/core/async/app_busy.dart';
import 'package:mcare/shared/widgets/loading/delayed_loader.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('DelayedLoader', () {
    testWidgets('a fast wait never shows the loader', (tester) async {
      Widget build(bool loading) => _host(
            DelayedLoader(
              isLoading: loading,
              delay: const Duration(milliseconds: 400),
              placeholder: const Text('LOADING'),
              child: const Text('CONTENT'),
            ),
          );

      await tester.pumpWidget(build(true));

      // 100 ms in — still inside the gate, so content keeps rendering.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('LOADING'), findsNothing);
      expect(find.text('CONTENT'), findsOneWidget);

      // Resolves at 150 ms, comfortably before the 400 ms gate.
      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('LOADING'), findsNothing);
      expect(find.text('CONTENT'), findsOneWidget);
    });

    testWidgets('a slow wait shows the loader once the gate opens',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const DelayedLoader(
            isLoading: true,
            delay: Duration(milliseconds: 400),
            placeholder: Text('LOADING'),
            child: Text('CONTENT'),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 399));
      expect(find.text('LOADING'), findsNothing);

      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump(const Duration(milliseconds: 200)); // cross-fade
      expect(find.text('LOADING'), findsOneWidget);
    });

    testWidgets('once shown the loader honours its minimum visible time',
        (tester) async {
      Widget build(bool loading) => _host(
            DelayedLoader(
              isLoading: loading,
              delay: const Duration(milliseconds: 100),
              minVisible: const Duration(milliseconds: 500),
              placeholder: const Text('LOADING'),
              child: const Text('CONTENT'),
            ),
          );

      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('LOADING'), findsOneWidget);

      // Response lands right after the loader appeared — it must not blink out.
      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('LOADING'), findsOneWidget);

      // After the minimum visible window it hands back to content.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('CONTENT'), findsOneWidget);
    });

    testWidgets('disposes cleanly while a wait is still pending',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const DelayedLoader(
            isLoading: true,
            placeholder: Text('LOADING'),
            child: Text('CONTENT'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('AppBusy', () {
    setUp(AppBusy.instance.reset);
    tearDown(AppBusy.instance.reset);

    test('tracks concurrent operations and only flips at the edges', () {
      var notifications = 0;
      void listener() => notifications++;
      AppBusy.instance.addListener(listener);
      addTearDown(() => AppBusy.instance.removeListener(listener));

      expect(AppBusy.instance.isBusy, isFalse);

      AppBusy.instance.begin();
      AppBusy.instance.begin();
      expect(AppBusy.instance.count, 2);
      expect(AppBusy.instance.isBusy, isTrue);
      expect(notifications, 1, reason: 'only the 0 -> 1 edge notifies');

      AppBusy.instance.end();
      expect(AppBusy.instance.isBusy, isTrue);
      expect(notifications, 1);

      AppBusy.instance.end();
      expect(AppBusy.instance.isBusy, isFalse);
      expect(notifications, 2, reason: 'the 1 -> 0 edge notifies');
    });

    test('end() below zero is a no-op', () {
      AppBusy.instance.end();
      expect(AppBusy.instance.count, 0);
      expect(AppBusy.instance.isBusy, isFalse);
    });

    test('track releases the counter on success and on failure', () async {
      await AppBusy.instance.track(Future<int>.value(1));
      expect(AppBusy.instance.count, 0);

      await expectLater(
        AppBusy.instance.track(Future<int>.error(StateError('boom'))),
        throwsStateError,
      );
      expect(AppBusy.instance.count, 0);
    });
  });
}
