import 'package:flutter/material.dart';

import '../../shared/theme/app_layout.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';

/// Auth form aliases — delegates to [AppLayout] for app-wide uniformity.
abstract final class AuthFormLayout {
  static const double fieldGap = AppLayout.fieldGap;
  static const double sectionGap = AppLayout.sectionGap;
  static const double controlHeight = AppLayout.controlHeight;
  static const AppButtonSize buttonSize = AppButtonSize.md;
  static const bool denseFields = AppLayout.compactFields;

  /// Inline text links ("Forgot password?", "Create one") sitting next to body
  /// copy. Trims Material's default 16px side padding so the link lines up
  /// with the field edge instead of floating inside it.
  static final ButtonStyle inlineLinkStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.md,
    ),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(
      fontSize: AppLayout.body,
      fontWeight: FontWeight.w700,
    ),
  );
}
