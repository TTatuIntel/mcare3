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

  // ── Loading system ─────────────────────────────────────────────────────────

  /// How long a wait must last before any loading indicator is allowed to
  /// appear. Below this, the user reads the transition as instant and a
  /// spinner only registers as a flash.
  static const Duration loaderDelay = Duration(milliseconds: 400);

  /// Once an indicator is on screen it stays at least this long, so a late
  /// response cannot make it blink out in the same breath it appeared.
  static const Duration loaderMinVisible = Duration(milliseconds: 500);

  /// Gate for layout-preserving skeletons. Much shorter than [loaderDelay]:
  /// a skeleton holds the page shape, so it does not read as a flash.
  static const Duration skeletonDelay = Duration(milliseconds: 150);

  /// One lap of the ECG pulse — matches the wordmark's heartbeat cycle.
  static const Duration pulseCycle = Duration(milliseconds: 1400);

  /// One lap of the global busy bar's comet.
  static const Duration busySweep = Duration(milliseconds: 1100);

  /// Fade between a loading placeholder and real content.
  static const Duration crossFade = Duration(milliseconds: 180);

  /// Standard easing for entrance/positional motion.
  static const Curve easeOut = Curves.easeOutCubic;

  /// Translate-Y for cards/sections settling in.
  static const double translateY = 18;
}
