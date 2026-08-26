import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/async/app_busy.dart';
import '../../theme/app_motion.dart';

/// Slim indeterminate bar pinned to the top of the app.
///
/// Driven by [AppBusy], which [ApiClient] feeds automatically. It only becomes
/// visible once a request has been in flight for [delay] — so the ordinary
/// fast call is silent, and the bar is a genuine signal that the app is
/// waiting on the network rather than frozen.
///
/// Mount once, around the app's `child` in `MaterialApp.builder`.
class AppBusyBar extends StatefulWidget {
  const AppBusyBar({
    super.key,
    required this.child,
    this.delay = AppMotion.loaderDelay,
    this.minVisible = AppMotion.loaderMinVisible,
    this.thickness = 2.5,
  });

  final Widget child;
  final Duration delay;
  final Duration minVisible;
  final double thickness;

  @override
  State<AppBusyBar> createState() => _AppBusyBarState();
}

class _AppBusyBarState extends State<AppBusyBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  Timer? _showTimer;
  Timer? _hideTimer;
  bool _visible = false;
  DateTime? _shownAt;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _sweep = AnimationController(
      vsync: this,
      duration: AppMotion.busySweep,
    );
    AppBusy.instance.addListener(_onBusyChanged);
    if (AppBusy.instance.isBusy) _scheduleShow();
  }

  @override
  void dispose() {
    AppBusy.instance.removeListener(_onBusyChanged);
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  void _onBusyChanged() {
    if (!mounted) return;
    if (AppBusy.instance.isBusy) {
      _scheduleShow();
    } else {
      _scheduleHide();
    }
  }

  void _scheduleShow() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_visible) return;
    _showTimer?.cancel();
    _showTimer = Timer(widget.delay, () {
      if (!mounted || !AppBusy.instance.isBusy) return;
      if (!_reduceMotion && !_sweep.isAnimating) _sweep.repeat();
      setState(() {
        _visible = true;
        _shownAt = DateTime.now();
      });
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _showTimer = null;
    if (!_visible) return;

    final shownAt = _shownAt;
    final elapsed =
        shownAt == null ? widget.minVisible : DateTime.now().difference(shownAt);
    final remaining = widget.minVisible - elapsed;

    void hide() {
      if (!mounted || AppBusy.instance.isBusy) return;
      _sweep.stop();
      setState(() => _visible = false);
    }

    if (remaining <= Duration.zero) {
      hide();
      return;
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(remaining, hide);
  }

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
                child: _visible
                    ? AnimatedBuilder(
                        animation: _sweep,
                        builder: (_, __) => CustomPaint(
                          painter: _BusySweepPainter(
                            progress: _reduceMotion ? 0.5 : _sweep.value,
                            color: accent,
                            isStatic: _reduceMotion,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
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
