import 'package:flutter/material.dart';

import 'app_colors.dart';

/// One elevation language: subtle, soft, layered.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> none = <BoxShadow>[];

  static const List<BoxShadow> subtle = [
    BoxShadow(
      color: Color(0x0F0F172A),
      blurRadius: 16,
      offset: Offset(0, 4),
      spreadRadius: -2,
    ),
  ];

  static const List<BoxShadow> subtleDark = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 20,
      offset: Offset(0, 6),
      spreadRadius: -4,
    ),
  ];

  /// Theme-aware card shadow — visible on both light and dark surfaces.
  static List<BoxShadow> card(BuildContext context) =>
      AppPalette.isDark(context) ? subtleDark : subtle;

  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 24,
      offset: Offset(0, 12),
      spreadRadius: -6,
    ),
    BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 40,
      offset: Offset(0, 20),
      spreadRadius: -12,
    ),
    BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4)),
  ];

  static List<BoxShadow> tintedFloating(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.18),
      blurRadius: 24,
      offset: const Offset(0, 14),
      spreadRadius: -6,
    ),
  ];
}
