import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/main.dart';
import 'package:mcare/shared/bootstrap/app_bootstrap.dart';
import 'package:mcare/shared/bootstrap/launch_readiness.dart';
import 'package:mcare/shared/widgets/brand_logo.dart';

void main() {
  testWidgets('App boots to landing', (WidgetTester tester) async {
    // Use a realistic laptop viewport; the default 800x600 test surface is
    // smaller than any device the landing screen is designed for.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    AppBootstrap.fastMode = true;
    LaunchReadiness.instance.reset();
    await tester.pumpWidget(const McareApp());
    // The landing screen runs looping ambient animations, so pumpAndSettle
    // would never settle — pump a fixed window instead.
    for (var i = 0; i < 20 && find.byType(BrandLogo).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(BrandLogo), findsWidgets);
  });
}
