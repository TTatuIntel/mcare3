import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/widgets/loading/app_busy_bar.dart';

void main() {
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
}
