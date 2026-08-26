import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import 'mcare_pulse.dart';

/// Preset footprints for [McareLoadingMark]. The value is the wordmark's cap
/// height; the lifeline and overall box are derived from it.
enum McareMarkSize {
  /// Fits inside a button or a dense toolbar without changing its height.
  button(15),

  /// A card header, a sheet, or a list section that is filling in.
  small(20),

  /// Default for a panel-sized wait.
  medium(28),

  /// Centrepiece for a full-page or first-paint wait.
  large(42);

  const McareMarkSize(this.height);

  final double height;
}

/// The mCare wordmark with its ECG lifeline, animated as a loading indicator.
///
/// This is the splash mark shrunk down: the wordmark breathes on a lub-dub
/// rhythm while a pulse travels the lifeline beneath it. Use it anywhere a
/// `CircularProgressIndicator` would otherwise appear.
///
/// Pass [color] to render the whole mark in a single colour — needed on filled
/// buttons, where the mark must match the button's foreground rather than the
/// brand palette.
class McareLoadingMark extends StatefulWidget {
  const McareLoadingMark({
    super.key,
    this.size = McareMarkSize.medium,
    this.color,
    this.semanticLabel = 'Loading',
  });

  final McareMarkSize size;

  /// Monochrome override. When null the mark uses the brand split: the "m" in
  /// the active role accent, "Care" in ink.
  final Color? color;

  /// Announced to screen readers. Pass `null` when a parent already describes
  /// the wait.
  final String? semanticLabel;

  /// Width this mark will occupy, for callers that need to reserve space.
  double get width => size.height * 3.1;

  @override
  State<McareLoadingMark> createState() => _McareLoadingMarkState();
}

class _McareLoadingMarkState extends State<McareLoadingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _ctrl = AnimationController(vsync: this, duration: AppMotion.pulseCycle);
    if (_reduceMotion) {
      _ctrl.value = 0.5;
    } else {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Lub-dub: a strong first beat, a softer second, then rest. Same shape as
  /// the wordmark's own heartbeat so the two read as one brand behaviour.
  static double _beatScale(double t) {
    if (t < 0.12) return 1.0 + (t / 0.12) * 0.055;
    if (t < 0.20) return 1.055 - ((t - 0.12) / 0.08) * 0.035;
    if (t < 0.30) return 1.02 + ((t - 0.20) / 0.10) * 0.035;
    if (t < 0.42) return 1.055 - ((t - 0.30) / 0.12) * 0.055;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.size.height;
    final fontSize = h * 0.72;
    final mono = widget.color;
    final accent = mono ?? Theme.of(context).colorScheme.primary;
    final ink =
        mono ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkInk
            : AppColors.brandInk);

    // The lifeline is drawn a little taller than the static logo's, so the
    // QRS spike stays legible at button size.
    final lineWidth = h * 1.25;
    final lineHeight = math.max(h * 0.32, 5.0);
    final stroke = (lineHeight * 0.20).clamp(1.0, 2.6);

    final mark = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: GoogleFonts.outfit(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: -fontSize * 0.02,
              height: 1.0,
            ),
            children: [
              TextSpan(
                text: 'm',
                style: TextStyle(color: accent),
              ),
              TextSpan(
                text: 'Care',
                style: TextStyle(color: ink),
              ),
            ],
          ),
        ),
        SizedBox(height: h * 0.06),
        SizedBox(
          width: lineWidth,
          height: lineHeight,
          child: CustomPaint(
            painter: McarePulsePainter(
              progress: _ctrl,
              color: accent,
              stroke: stroke,
              isStatic: _reduceMotion,
              // The mark is never wide enough for the full-length trace.
              compact: true,
            ),
          ),
        ),
      ],
    );

    final animated = _reduceMotion
        ? mark
        : AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) =>
                Transform.scale(scale: _beatScale(_ctrl.value), child: child),
            child: mark,
          );

    if (widget.semanticLabel == null) return animated;
    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: animated,
    );
  }
}
