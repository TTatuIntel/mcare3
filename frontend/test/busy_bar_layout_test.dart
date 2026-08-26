import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/core/async/app_busy.dart';
import 'package:mcare/shared/widgets/loading/app_busy_bar.dart';

void main() {
  setUp(AppBusy.instance.reset);
  tearDown(AppBusy.instance.reset);

  testWidgets('AppBusyBar does not collapse the app it wraps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppBusyBar(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('HOME'))),
      ),
    );
    await tester.pump();

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final scaffoldSize = tester.getSize(find.byType(Scaffold));

    expect(find.text('HOME'), findsOneWidget);
    expect(
      scaffoldSize.height,
      screen.height,
      reason: 'Scaffold must fill the viewport, not collapse to zero',
    );
    expect(scaffoldSize.width, screen.width);
  });

  testWidgets('bar follows attended work and yields to blocking overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppBusyBar(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('HOME')),
      ),
    );

    AnimatedOpacity opacity() => tester.widget(find.byType(AnimatedOpacity));
    expect(opacity().opacity, 0);

    AppBusy.instance.begin();
    await tester.pump();
    expect(opacity().opacity, 1);

    AppBusy.instance.begin(blocking: true);
    await tester.pump();
    expect(opacity().opacity, 0);

    AppBusy.instance.end(blocking: true);
    AppBusy.instance.end();
    await tester.pump();
    expect(opacity().opacity, 0);
  });
}
