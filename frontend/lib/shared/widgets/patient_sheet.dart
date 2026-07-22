import 'package:flutter/material.dart';

import 'glass_sheet.dart';

/// Patient-facing bottom sheet — delegates to [GlassSheet] for one uniform UX.
class PatientSheet {
  PatientSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    required Widget child,
    double maxHeightFactor = 0.92,
    double? maxWidth,
  }) {
    return GlassSheet.show<T>(
      context,
      title: title,
      subtitle: subtitle,
      maxHeightFactor: maxHeightFactor,
      maxWidth: maxWidth,
      child: child,
    );
  }
}
