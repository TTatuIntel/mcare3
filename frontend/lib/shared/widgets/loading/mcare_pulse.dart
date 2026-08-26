import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import 'mcare_ecg_path.dart';

/// Preset footprints for [McarePulse].
enum McarePulseSize {
  /// Smallest legible trace — for an icon-button slot or a 14–20px indicator
  /// slot where even the inline size would overflow.
  micro(20, 8, 1.3),

  /// Sits inside a button or a table row without changing its height.
  inline(26, 10, 1.6),

  /// Trailing indicator for a list row, chip, or field.
  small(36, 13, 1.9),

  /// Default for a card or panel that is filling in.
  medium(58, 20, 2.4),

  /// Centrepiece for a full-page or first-paint wait.
  large(96, 30, 3.0);

  const McarePulseSize(this.width, this.height, this.stroke);

  final double width;
  final double height;
  final double stroke;
}

/// The mCare loading mark: a pulse that travels the ECG lifeline and flares as
/// it crosses the QRS spike.
///
/// This is the same geometry as the wordmark's lifeline, so a wait reads as the
/// brand breathing rather than a generic spinner. Honours the platform
/// reduce-motion setting by holding a static trace.
class McarePulse extends StatefulWidget {
  const McarePulse({
    super.key,
    this.size = McarePulseSize.medium,
    this.color,
    this.semanticLabel = 'Loading',
  });

  final McarePulseSize size;

  /// Defaults to the active role accent (`colorScheme.primary`).
  final Color? color;

  /// Announced to screen readers. Pass `null` to stay silent when a parent
  /// already describes the wait.
  final String? semanticLabel;

  @override
  State<McarePulse> createState() => _McarePulseState();
}

class _McarePulseState extends State<McarePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
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

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final painter = McarePulsePainter(
      progress: _ctrl,
      color: color,
      stroke: widget.size.stroke,
      isStatic: _reduceMotion,
      compact: widget.size == McarePulseSize.micro ||
          widget.size == McarePulseSize.inline,
    );

    final canvas = SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: CustomPaint(painter: painter),
    );

    if (widget.semanticLabel == null) return canvas;
    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: canvas,
    );
  }
}

class McarePulsePainter extends CustomPainter {
  McarePulsePainter({
    required this.progress,
    required this.color,
    required this.stroke,
    required this.isStatic,
    this.compact = false,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double stroke;
  final bool isStatic;

  /// Use the compact waveform so the spike survives at small sizes.
  final bool compact;

  /// Length of the bright comet as a fraction of the whole trace.
  static const double _cometFraction = 0.24;

  /// Number of tail segments used to fake a gradient along the path.
  static const int _tailSegments = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final path = McareEcgPath.build(size, compact: compact);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final total = metric.length;
    if (total <= 0) return;

    Paint strokePaint(double alpha, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
      ..strokeWidth = width;

    // ── Resting trace ────────────────────────────────────────────────────────
    canvas.drawPath(path, strokePaint(isStatic ? 0.34 : 0.16, stroke * 0.72));

    if (isStatic) return;

    // The comet runs off the right edge, then re-enters from the left, so the
    // head position sweeps a full comet-length past both ends.
    final t = progress.value;
    final span = total + total * _cometFraction;
    final headDistance = t * span;
    final cometLength = total * _cometFraction;

    // ── Comet tail ───────────────────────────────────────────────────────────
    for (var i = 0; i < _tailSegments; i++) {
      final near = headDistance - cometLength * (i / _tailSegments);
      final far = headDistance - cometLength * ((i + 1) / _tailSegments);
      final start = far.clamp(0.0, total);
      final end = near.clamp(0.0, total);
      if (end - start <= 0.01) continue;

      // Brightest at the head, fading toward the tail.
      final fade = 1 - (i / _tailSegments);
      canvas.drawPath(
        metric.extractPath(start, end),
        strokePaint(fade * fade * 0.95, stroke * (0.75 + 0.35 * fade)),
      );
    }

    // ── Travelling head ──────────────────────────────────────────────────────
    if (headDistance < 0 || headDistance > total) return;
    final tangent = metric.getTangentForOffset(headDistance);
    if (tangent == null) return;

    final beat = McareEcgPath.beatIntensity(tangent.position.dy, size.height);
    final headRadius = stroke * (0.85 + beat * 0.75);

    // Glow flares as the head rides the QRS spike.
    canvas.drawCircle(
      tangent.position,
      headRadius * (2.4 + beat * 1.6),
      Paint()
        ..color = color.withValues(alpha: 0.10 + beat * 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.6),
    );
    canvas.drawCircle(
      tangent.position,
      headRadius,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant McarePulsePainter old) =>
      old.color != color ||
      old.stroke != stroke ||
      old.isStatic != isStatic ||
      old.compact != compact;
}
