import 'package:flutter/material.dart';

import '../../../core/async/app_busy.dart';
import '../../theme/app_motion.dart';

/// Slim indeterminate bar pinned to the top of the app.
///
/// Driven directly by [AppBusy], which [ApiClient] feeds automatically. The
/// fade mirrors the real request edge; no show or minimum-visible timer can
/// outlive the work it represents. It stays hidden while the primary blocking
/// overlay is active so the app never presents two global loaders at once.
///
/// Mount once, around the app's `child` in `MaterialApp.builder`.
class AppBusyBar extends StatefulWidget {
  const AppBusyBar({super.key, required this.child, this.thickness = 2.5});

  final Widget child;
  final double thickness;

  @override
  State<AppBusyBar> createState() => _AppBusyBarState();
}

class _AppBusyBarState extends State<AppBusyBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  bool _visible = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _sweep = AnimationController(vsync: this, duration: AppMotion.busySweep);
    AppBusy.instance.addListener(_onBusyChanged);
    _visible = _shouldShow;
    if (_visible && !_reduceMotion) _sweep.repeat();
  }

  @override
  void dispose() {
    AppBusy.instance.removeListener(_onBusyChanged);
    _sweep.dispose();
    super.dispose();
  }

  void _onBusyChanged() {
    if (!mounted) return;
    final next = _shouldShow;
    if (next == _visible) return;
    if (next) {
      if (!_reduceMotion) _sweep.repeat();
    } else {
      _sweep.stop();
    }
    setState(() => _visible = next);
  }

  bool get _shouldShow =>
      AppBusy.instance.isBusy && !AppBusy.instance.isBlocking;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: AppMotion.crossFade,
              curve: AppMotion.easeOut,
              child: SizedBox(
                height: widget.thickness,
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (_, __) => CustomPaint(
                    painter: _BusySweepPainter(
                      progress: _reduceMotion ? 0.5 : _sweep.value,
                      color: accent,
                      isStatic: _reduceMotion,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BusySweepPainter extends CustomPainter {
  const _BusySweepPainter({
    required this.progress,
    required this.color,
    required this.isStatic,
  });

  final double progress;
  final Color color;
  final bool isStatic;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Track.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.14),
    );

    if (isStatic) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * 0.35, size.height),
        Paint()..color = color.withValues(alpha: 0.85),
      );
      return;
    }

    // Comet travelling left to right, entering and exiting off-canvas.
    final bandWidth = size.width * 0.32;
    final travel = size.width + bandWidth * 2;
    final headX = progress * travel - bandWidth;
    final rect = Rect.fromLTWH(headX, 0, bandWidth, size.height);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _BusySweepPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.isStatic != isStatic;
}
