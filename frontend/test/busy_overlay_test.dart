import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/core/async/app_busy.dart';
import 'package:mcare/shared/widgets/loading/mcare_busy_overlay.dart';
import 'package:mcare/shared/widgets/loading/mcare_loading_mark.dart';

Widget _host() => MaterialApp(
  builder: (context, child) =>
      McareBusyOverlay(child: child ?? const SizedBox.shrink()),
  home: const Scaffold(body: Center(child: Text('SCREEN'))),
);

void main() {
  setUp(AppBusy.instance.reset);
  tearDown(AppBusy.instance.reset);

  testWidgets('does not collapse the app it wraps', (tester) async {
    await tester.pumpWidget(_host());
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getSize(find.byType(Scaffold)).height, screen.height);
    expect(find.text('SCREEN'), findsOneWidget);
  });

  testWidgets('critical work raises the branded loader immediately', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    AppBusy.instance.begin(
      blocking: true,
      message: 'Preparing your dashboard…',
    );
    await tester.pump();

    expect(find.byType(McareLoadingMark), findsOneWidget);
    expect(find.text('Preparing your dashboard…'), findsOneWidget);

    AppBusy.instance.end(blocking: true);
    await tester.pumpAndSettle();
    expect(find.byType(McareLoadingMark), findsNothing);
  });

  testWidgets('mark is centered, sized to the viewport, and card-free', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    AppBusy.instance.begin(blocking: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final halo = tester.getRect(find.byKey(const ValueKey('mcare-busy-mark')));
    expect(halo.center.dx, closeTo(screen.width / 2, 0.1));
    expect(halo.center.dy, closeTo(screen.height / 2, 0.1));
    // Scales with the viewport rather than sitting in a fixed-size card.
    expect(halo.width, greaterThanOrEqualTo(220));
    expect(halo.width, lessThanOrEqualTo(460));
    expect(halo.width, halo.height);

    // Exactly one blur: the page behind. There is no second, card-shaped one.
    expect(find.byType(BackdropFilter), findsOneWidget);

    AppBusy.instance.end(blocking: true);
    await tester.pumpAndSettle();
  });

  testWidgets('ordinary reads and writes do not raise a full-page loader', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    AppBusy.instance.begin();
    AppBusy.instance.begin(mutation: true);
    await tester.pump();

    expect(find.byType(McareLoadingMark), findsNothing);
    expect(find.byKey(const ValueKey('mcare-busy-active')), findsNothing);

    AppBusy.instance.end();
    AppBusy.instance.end(mutation: true);
  });

  testWidgets('blocking work prevents duplicate interaction until it ends', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            McareBusyOverlay(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                taps++;
                AppBusy.instance.begin(blocking: true);
              },
              child: const Text('CONTINUE'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('CONTINUE'));
    await tester.pump();
    await tester.tap(find.text('CONTINUE'), warnIfMissed: false);
    await tester.pump();
    expect(taps, 1);

    AppBusy.instance.end(blocking: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTINUE'));
    expect(taps, 2);
    AppBusy.instance.end(blocking: true);
  });

  testWidgets('background polling never raises it', (tester) async {
    await tester.pumpWidget(_host());

    await AppBusy.runBackground(() async {
      AppBusy.instance.begin(blocking: true);
    });
    await tester.pump();

    expect(find.byType(McareLoadingMark), findsNothing);
  });
}
