import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/main.dart';
import 'package:mcare/shared/bootstrap/app_bootstrap.dart';
import 'package:mcare/shared/bootstrap/launch_readiness.dart';
import 'package:mcare/shared/widgets/brand_logo.dart';

void main() {
  testWidgets('landing actually paints pixels after boot', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    AppBootstrap.fastMode = true;
    LaunchReadiness.instance.reset();
    await tester.pumpWidget(const McareApp());

    for (var i = 0; i < 40 && find.byType(BrandLogo).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(tester.takeException(), isNull, reason: 'boot threw');

    // Navigator must fill the viewport.
    final navSize = tester.getSize(find.byType(Navigator).first);
    debugPrint('NAVIGATOR SIZE: $navSize');
    expect(navSize.height, greaterThan(100), reason: 'navigator collapsed');
    expect(navSize.width, greaterThan(100), reason: 'navigator collapsed');

    // And the logo must be a real, visible size.
    expect(find.byType(BrandLogo), findsWidgets);
    final logoSize = tester.getSize(find.byType(BrandLogo).first);
    debugPrint('BRANDLOGO SIZE: $logoSize');
    expect(logoSize.height, greaterThan(4), reason: 'logo collapsed');

    // The `finally` in _runBootstrap is the only thing that releases the
    // splash. If this is ever false, the app is stranded behind it.
    expect(
      LaunchReadiness.instance.bootstrapComplete,
      isTrue,
      reason: 'bootstrap must always settle, even on failure',
    );
  });
}
