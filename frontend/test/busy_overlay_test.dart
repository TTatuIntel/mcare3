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
    await tester.pump();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getSize(find.byType(Scaffold)).height, screen.height);
    expect(find.text('SCREEN'), findsOneWidget);
  });

  testWidgets('a slow write raises the mark on screen', (tester) async {
    await tester.pumpWidget(_host());

    AppBusy.instance.begin(mutation: true);
    await tester.pump();
    expect(find.byType(McareLoadingMark), findsNothing,
        reason: 'nothing before the delay gate opens');

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(McareLoadingMark), findsOneWidget);

    AppBusy.instance.end(mutation: true);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(McareLoadingMark), findsNothing);
  });

  testWidgets('a fast write never raises it', (tester) async {
    await tester.pumpWidget(_host());

    AppBusy.instance.begin(mutation: true);
    await tester.pump(const Duration(milliseconds: 120));
    AppBusy.instance.end(mutation: true);
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byType(McareLoadingMark), findsNothing);
  });

  testWidgets('a screen read never raises it', (tester) async {
    await tester.pumpWidget(_host());

    AppBusy.instance.begin(); // a GET, not a write
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(McareLoadingMark), findsNothing,
        reason: 'opening a screen must not throw up a blocking overlay');
    AppBusy.instance.end();
  });

  testWidgets('background polling never raises it', (tester) async {
    await tester.pumpWidget(_host());

    await AppBusy.runBackground(() async {
      AppBusy.instance.begin(mutation: true);
    });
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(McareLoadingMark), findsNothing);
  });
}
