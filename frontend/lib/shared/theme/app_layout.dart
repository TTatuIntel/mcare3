import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// Shared content sizing for the entire application.
///
/// Single source of truth for control heights, spacing rhythm, logo scale,
/// and canonical text sizes. Screens and shared widgets reference these tokens
/// instead of magic numbers.
abstract final class AppLayout {
  AppLayout._();

  // --- Logo -----------------------------------------------------------------
  static const double logoTopBar = 46;
  static const double logoRail = 40;
  static const double logoSplash = 104;

  // --- Form controls --------------------------------------------------------
  static const double controlHeight = 48;
  static const double controlIconSize = 18;
  static const EdgeInsets controlPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 12);
  static const BoxConstraints controlConstraints =
      BoxConstraints(minHeight: 48, maxHeight: 56);
  static const double controlPrefixWidth = 48;

  // --- Spacing rhythm -------------------------------------------------------
  static const double fieldGap = AppSpacing.lg;
  static const double sectionGap = AppSpacing.xl;
  static const double pageHeaderGap = AppSpacing.xl;
  static const double pageFooterGap = AppSpacing.lg;

  // --- Canonical text sizes (pair with [AppTypography]) ---------------------
  static const double pageTitle = 24;
  static const double sectionTitle = 18;
  static const double body = 14;
  static const double label = 12.5;
  static const double caption = 12;
  static const double link = 15;

  /// Default compact field style used app-wide.
  static const bool compactFields = true;
}
