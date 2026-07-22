import 'package:flutter/animation.dart';

/// Motion tokens — defined once, used everywhere. See section 7 of the spec.
class AppMotion {
  AppMotion._();

  /// Total duration of an entry stagger across a list of items.
  static const Duration entryStagger = Duration(milliseconds: 320);

  /// Duration of a single item's slide+fade entry.
  static const Duration itemEntry = Duration(milliseconds: 220);

  /// Page transitions.
  static const Duration page = Duration(milliseconds: 320);

  /// Faster page transitions for snappier navigation.
  static const Duration pageFast = Duration(milliseconds: 240);

  /// Micro-interactions: button press, toggle, chip select.
  static const Duration micro = Duration(milliseconds: 160);

  /// Skeleton shimmer loop.
  static const Duration shimmer = Duration(milliseconds: 1200);

  /// Standard easing for entrance/positional motion.
  static const Curve easeOut = Curves.easeOutCubic;

  /// Translate-Y for cards/sections settling in.
  static const double translateY = 18;
}
