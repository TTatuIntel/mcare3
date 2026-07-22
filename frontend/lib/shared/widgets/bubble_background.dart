import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';

/// Ambient backdrop: soft pastel bokeh circles that drift gently upward.
///
/// Matches the landing-page reference — large blurred colour washes on a
/// white surface, not glossy 3D bubbles. Respects OS "reduce motion".
class BubbleBackground extends StatefulWidget {
  const BubbleBackground({
    super.key,
    this.bubbleCount = 14,
    this.child,
    this.surfaceColor,
  });

  /// How many bokeh circles drift in the background at once.
  final int bubbleCount;

  /// Foreground content placed above the bokeh.
  final Widget? child;

  /// Optional base colour. Defaults to white.
  final Color? surfaceColor;

  @override
  State<BubbleBackground> createState() => _BubbleBackgroundState();
}

class _BubbleBackgroundState extends State<BubbleBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late List<_Bubble> _bubbles;
  final math.Random _rng = math.Random();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  double _lastT = 0;
  Size _size = Size.zero;

  static const _paletteLight = <Color>[
    Color(0xFFB8C5FF), // soft indigo
    Color(0xFFD4B8FF), // soft violet
    Color(0xFFFFC1E3), // soft pink
    Color(0xFFB8E6FF), // soft sky
    Color(0xFFB8FFE0), // soft mint
    Color(0xFFFFE0B8), // soft peach
    Color(0xFFC7D2FE), // periwinkle
    Color(0xFFFDE68A), // pale yellow
  ];

  // Deeper, low-saturation hues so the bokeh reads as ambient glow on
  // dark surfaces without washing out card text.
  static const _paletteDark = <Color>[
    Color(0xFF3B3F7A), // muted indigo
    Color(0xFF4A2F73), // muted violet
    Color(0xFF6B2C52), // muted rose
    Color(0xFF1F4C6B), // muted teal-blue
    Color(0xFF1F5C4A), // muted mint
    Color(0xFF6B4A1F), // muted amber
    Color(0xFF2E3A6B), // muted periwinkle
    Color(0xFF5C5226), // muted ochre
  ];

  List<Color> _palette(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _paletteDark
          : _paletteLight;

  @override
  void initState() {
    super.initState();
    _bubbles = List.generate(
      widget.bubbleCount,
      (_) => _spawn(seedY: true, palette: _paletteLight),
    );
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didChangeDependencies() {

    super.didChangeDependencies();
    // Re-tint existing bubbles when brightness flips so the previous
    // palette doesn't linger after a theme switch.
    final palette = _palette(context);
    for (final b in _bubbles) {
      if (!palette.contains(b.color)) {
        b.color = palette[_rng.nextInt(palette.length)];
      }
    }
  }

  @override
  void dispose() {
    _ticker.stop();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  _Bubble _spawn({bool seedY = false, List<Color>? palette}) {
    final pal = palette ??
        (mounted ? _palette(context) : _paletteLight);
    final radius = 56.0 + _rng.nextDouble() * 110.0;
    return _Bubble(
      x: _rng.nextDouble(),
      y: seedY ? _rng.nextDouble() : 1.05 + _rng.nextDouble() * 0.2,
      radius: radius,
      color: pal[_rng.nextInt(pal.length)],
      drift: -0.008 - _rng.nextDouble() * 0.018,
      sway: 0.02 + _rng.nextDouble() * 0.04,
      swayPhase: _rng.nextDouble() * math.pi * 2,
      swaySpeed: 0.25 + _rng.nextDouble() * 0.45,
      lifespan: 14.0 + _rng.nextDouble() * 12.0,
      age: 0,
      opacity: 0.18 + _rng.nextDouble() * 0.16,
    );
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = (_lastT == 0) ? 0.016 : (t - _lastT).clamp(0.0, 0.05);
    _lastT = t;

    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;

    for (var i = 0; i < _bubbles.length; i++) {
      final b = _bubbles[i];
      b.age += dt;
      b.y += b.drift * dt;
      b.swayPhase += b.swaySpeed * dt;

      final offscreen = b.y < -0.15;
      final expired = b.age > b.lifespan;

      if (offscreen || expired) {
        _bubbles[i] = _spawn();
      }
    }

    if (mounted) _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.surfaceColor ??
        (isDark ? AppColors.darkScaffoldBg : Colors.white);
    // Dark mode uses very faint tints; bright washes hide card text.
    final wash1 = isDark ? const Color(0x12A5B4FC) : const Color(0x10A5B4FC);
    final wash2 = isDark ? const Color(0x0EF472B6) : const Color(0x0CFBCFE8);
    final wash3 = isDark ? const Color(0x0AC4B5FD) : const Color(0x08C4B5FD);
    final fade = isDark ? const Color(0x000B1120) : const Color(0x00FFFFFF);

    return LayoutBuilder(
      builder: (context, c) {
        _size = Size(c.maxWidth, c.maxHeight);
        return Stack(
          alignment: Alignment.topLeft,
          textDirection: TextDirection.ltr,
          fit: StackFit.expand,
          children: [
            Container(color: base),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.2, -0.5),
                  radius: 1.0,
                  colors: [wash1, fade],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.6, 0.7),
                  radius: 1.0,
                  colors: [wash2, fade],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.1, 0.35),
                  radius: 0.9,
                  colors: [wash3, fade],
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                size: _size,
                painter: _BokehPainter(
                  _bubbles,
                  opacityScale: isDark ? 0.55 : 1.0,
                  repaint: _repaint,
                ),
              ),
            ),
            if (widget.child != null) RepaintBoundary(child: widget.child!),
          ],
        );
      },
    );
  }
}

class _Bubble {
  _Bubble({
    required this.x,
    required this.y,
    required this.radius,
    required this.color,
    required this.drift,
    required this.sway,
    required this.swayPhase,
    required this.swaySpeed,
    required this.lifespan,
    required this.age,
    required this.opacity,
  });
  double x;
  double y;
  double radius;
  Color color;
  double drift;
  double sway;
  double swayPhase;
  double swaySpeed;
  double lifespan;
  double age;
  double opacity;
}

class _BokehPainter extends CustomPainter {
  _BokehPainter(this.bubbles, {this.opacityScale = 1.0, super.repaint});
  final List<_Bubble> bubbles;
  final double opacityScale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      final swayX = math.sin(b.swayPhase) * b.sway;
      final cx = (b.x + swayX) * size.width;
      final cy = b.y * size.height;
      final r = b.radius;
      final op = b.opacity * opacityScale;

      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = b.color.withValues(alpha: op.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BokehPainter oldDelegate) => false;
}
