import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';

/// Unified mCare wordmark — indigo **m** + ink **Care**, same for every role.
///
/// [animateHeartbeat] adds the lub-dub pulse + random colour flashes.
/// [showLifeline] adds the ECG lifeline that is pixel-identical to the
/// splash screen animation (same path, same clip-reveal timing, same colours).
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.height = topBarHeight,
    this.onWhite = false,
    this.tappable = true,
    this.animateHeartbeat = true,
    this.showLifeline = true,
    @Deprecated('Use showLifeline') this.splashIntegrated = false,
    @Deprecated('Use wordmark only') this.showMark = false,
  });

  static const double topBarHeight = AppLayout.logoTopBar;
  static const double railHeight = AppLayout.logoRail;
  static const double splashHeight = AppLayout.logoSplash;

  final double height;
  final bool onWhite;
  final bool tappable;
  final bool animateHeartbeat;
  final bool showLifeline;
  // ignore: deprecated_member_use_from_same_package
  final bool splashIntegrated;
  // ignore: deprecated_member_use_from_same_package
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final lifeline = showLifeline || splashIntegrated;
    final mark = animateHeartbeat
        ? _HeartbeatWordmark(
            height: height,
            onWhite: onWhite,
            showLifeline: lifeline,
          )
        : _McareWordmark(height: height, onWhite: onWhite);

    if (!tappable) return mark;

    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) {
        final loggedIn = AuthState.instance.user != null;
        if (loggedIn) return mark;

        return Semantics(
          label: 'mCare — get started',
          button: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil(RouteNames.landing, (_) => false),
              child: mark,
            ),
          ),
        );
      },
    );
  }
}

// ── Beat palette ─────────────────────────────────────────────────────────────

class _BeatPalette {
  _BeatPalette._();

  static const colors = <Color>[
    AppColors.brandIndigo,
    AppColors.heartRed,
    AppColors.doctorGreen,
    AppColors.spo2Blue,
    AppColors.bpPurple,
    AppColors.glucoseAmber,
    AppColors.tempTeal,
    AppColors.adminPurple,
    AppColors.mcareAmber,
    AppColors.success,
    AppColors.critical,
    AppColors.warning,
    AppColors.info,
  ];

  static final _rng = math.Random();

  static Color pick({Color? exclude}) {
    if (colors.length <= 1) return colors.first;
    Color next;
    do {
      next = colors[_rng.nextInt(colors.length)];
    } while (exclude != null && next == exclude);
    return next;
  }
}

// ── Heartbeat rhythm helpers ──────────────────────────────────────────────────

class _HeartbeatRhythm {
  _HeartbeatRhythm._();

  static const cycleMs = 1400;

  static double scale(double t) {
    if (t < 0.12) return 1.0 + (t / 0.12) * 0.085;
    if (t < 0.20) return 1.085 - ((t - 0.12) / 0.08) * 0.055;
    if (t < 0.30) return 1.03 + ((t - 0.20) / 0.10) * 0.055;
    if (t < 0.42) return 1.085 - ((t - 0.30) / 0.12) * 0.085;
    return 1.0;
  }

  static double lubIntensity(double t) {
    final d = ((t - 0.12) / 0.10).abs();
    return d >= 1 ? 0 : (1 - d).clamp(0.0, 1.0);
  }

  static double dubIntensity(double t) {
    final d = ((t - 0.30) / 0.09).abs();
    return d >= 1 ? 0 : (1 - d).clamp(0.0, 1.0);
  }

  static Color mColor({
    required Color base,
    required double lub,
    required double dub,
    required Color lubFlash,
    required Color dubFlash,
    required bool onWhite,
  }) {
    if (onWhite) {
      final peak = lub > dub ? lub : dub;
      return Colors.white.withValues(alpha: 0.88 + peak * 0.12);
    }
    var color = base;
    if (lub > 0) color = Color.lerp(color, lubFlash, lub * 0.95)!;
    if (dub > 0) color = Color.lerp(color, dubFlash, dub * 0.95)!;
    return color;
  }
}

// ── Animated wordmark widget ──────────────────────────────────────────────────

class _HeartbeatWordmark extends StatefulWidget {
  const _HeartbeatWordmark({
    required this.height,
    required this.onWhite,
    required this.showLifeline,
  });

  final double height;
  final bool onWhite;
  final bool showLifeline;

  @override
  State<_HeartbeatWordmark> createState() => _HeartbeatWordmarkState();
}

class _HeartbeatWordmarkState extends State<_HeartbeatWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beatCtrl;
  Color _lubColor = AppColors.heartRed;
  Color _dubColor = AppColors.spo2Blue;
  double _lastBeatT = 0;

  @override
  void initState() {
    super.initState();
    _rollBeatColors();
    final disable = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _beatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _HeartbeatRhythm.cycleMs),
    );
    if (!disable) {
      _beatCtrl.repeat();
    } else {
      _beatCtrl.value = 0.12;
    }
    _beatCtrl.addListener(_onBeatTick);
  }

  void _onBeatTick() {
    final t = _beatCtrl.value;
    if (t < _lastBeatT) _rollBeatColors();
    _lastBeatT = t;
  }

  void _rollBeatColors() {
    final lub = _BeatPalette.pick();
    final dub = _BeatPalette.pick(exclude: lub);
    if (!mounted) return;
    setState(() {
      _lubColor = lub;
      _dubColor = dub;
    });
  }

  @override
  void dispose() {
    _beatCtrl.removeListener(_onBeatTick);
    _beatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _beatCtrl,
      builder: (context, _) {
        final t = _beatCtrl.value;
        return Transform.scale(
          scale: _HeartbeatRhythm.scale(t),
          child: _McareWordmark(
            height: widget.height,
            onWhite: widget.onWhite,
            lubIntensity: _HeartbeatRhythm.lubIntensity(t),
            dubIntensity: _HeartbeatRhythm.dubIntensity(t),
            lubColor: _lubColor,
            dubColor: _dubColor,
            showLifeline: widget.showLifeline,
            beatPhase: t,
          ),
        );
      },
    );
  }
}

// ── Static wordmark (also used as base by _HeartbeatWordmark) ─────────────────

class _McareWordmark extends StatelessWidget {
  const _McareWordmark({
    required this.height,
    required this.onWhite,
    this.lubIntensity = 0,
    this.dubIntensity = 0,
    this.lubColor = AppColors.heartRed,
    this.dubColor = AppColors.spo2Blue,
    this.showLifeline = false,
    this.beatPhase = 0,
  });

  final double height;
  final bool onWhite;
  final double lubIntensity;
  final double dubIntensity;
  final Color lubColor;
  final Color dubColor;
  final bool showLifeline;
  final double beatPhase;

  @override
  Widget build(BuildContext context) {
    final fontSize = height * 0.72;
    final inkColor = onWhite ? Colors.white : AppColors.brandInk;
    final mBase = onWhite ? Colors.white : AppColors.brandIndigo;
    final mColor = _HeartbeatRhythm.mColor(
      base: mBase,
      lub: lubIntensity,
      dub: dubIntensity,
      lubFlash: lubColor,
      dubFlash: dubColor,
      onWhite: onWhite,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.outfit(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: -fontSize * 0.02,
              height: 1.0,
            ),
            children: [
              TextSpan(text: 'm', style: TextStyle(color: mColor)),
              TextSpan(text: 'Care', style: TextStyle(color: inkColor)),
            ],
          ),
        ),
        if (showLifeline)
          Padding(
            padding: EdgeInsets.only(top: height * 0.05),
            child: SizedBox(
              width: height * 1.15,
              height: height * 0.24,
              child: CustomPaint(
                painter: _EcgRevealPainter(
                  beatPhase: beatPhase,
                  lubColor: lubColor,
                  dubColor: dubColor,
                  onWhite: onWhite,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── ECG path — identical to splash SVG ───────────────────────────────────────
//
// SVG source: M0 14 H19 L21 13 L23 14 H29 L30 17 L33 1 L37 23 L38 14 H44 H108
// in a 118×24 viewBox. Scaled proportionally to the painter [size].

class _SplashEcgPath {
  _SplashEcgPath._();

  static Path build(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, 14 / 24 * h)
      ..lineTo(19 / 118 * w, 14 / 24 * h)
      ..lineTo(21 / 118 * w, 13 / 24 * h)
      ..lineTo(23 / 118 * w, 14 / 24 * h)
      ..lineTo(29 / 118 * w, 14 / 24 * h)
      ..lineTo(30 / 118 * w, 17 / 24 * h)
      ..lineTo(33 / 118 * w, 1 / 24 * h)
      ..lineTo(37 / 118 * w, 23 / 24 * h)
      ..lineTo(38 / 118 * w, 14 / 24 * h)
      ..lineTo(44 / 118 * w, 14 / 24 * h)
      ..lineTo(108 / 118 * w, 14 / 24 * h);
  }
}

// ── ECG reveal painter — mirrors splash CSS keyframes exactly ─────────────────

class _EcgRevealPainter extends CustomPainter {
  const _EcgRevealPainter({
    required this.beatPhase,
    required this.lubColor,
    required this.dubColor,
    required this.onWhite,
  });

  final double beatPhase;
  final Color lubColor;
  final Color dubColor;
  final bool onWhite;

  // Global opacity: fade in 6→11%, hold, fade out 83→95%  (mcare-ecg-clip)
  static double _opacity(double t) {
    if (t < 0.06) return 0;
    if (t < 0.11) return (t - 0.06) / 0.05;
    if (t < 0.83) return 1;
    if (t < 0.95) return 1.0 - (t - 0.83) / 0.12;
    return 0;
  }

  // Clip reveal 0→1, ease-in-out cubic, 11→83%  (mcare-ecg-clip)
  static double _reveal(double t) {
    if (t <= 0.11) return 0;
    if (t >= 0.83) return 1;
    final x = (t - 0.11) / 0.72;
    return x < 0.5
        ? 4 * x * x * x
        : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  // Pulse travel sweep 0→1 over 8→88%  (mcare-pulse-travel)
  static double _sweep(double t) {
    if (t < 0.08) return 0;
    if (t > 0.88) return 1;
    return (t - 0.08) / 0.80;
  }

  static double _sweepOpacity(double t) {
    if (t < 0.05) return 0;
    if (t < 0.08) return (t - 0.05) / 0.03;
    if (t < 0.88) return 0.85;
    if (t < 0.92) return 0.85 * (1.0 - (t - 0.88) / 0.04);
    return 0;
  }

  // Stroke colour: same transitions as mcare-ecg-color keyframes
  Color _traceColor(double t) {
    if (onWhite) return Colors.white;
    const base = AppColors.brandIndigo;
    if (t <= 0.10) return base;
    if (t <= 0.14) return Color.lerp(base, lubColor, (t - 0.10) / 0.04)!;
    if (t <= 0.32) return Color.lerp(lubColor, dubColor, (t - 0.14) / 0.18)!;
    if (t <= 0.83) return Color.lerp(dubColor, base, (t - 0.32) / 0.51)!;
    return base;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = beatPhase;
    final alpha = _opacity(t);
    if (alpha <= 0.01) return;

    final base = onWhite ? Colors.white : AppColors.brandIndigo;
    // Baseline y matches the SVG path's "M0 14" in a 24-unit viewBox
    final midY = size.height * (14 / 24);

    // ── Pulse bed  (mcare-pulse-bed) ─────────────────────────────────────────
    final bedScale = 0.78 + 0.11 * (1 - math.cos(2 * math.pi * t));
    final bedW = size.width * 0.75 * bedScale;
    final bedH = size.height * 0.18;
    final bedAlpha =
        (0.10 + 0.08 * (1 - math.cos(2 * math.pi * t))) * alpha;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH((size.width - bedW) / 2, midY - bedH / 2, bedW, bedH),
        Radius.circular(bedH),
      ),
      Paint()..color = base.withValues(alpha: bedAlpha.clamp(0.0, 1.0)),
    );

    // ── Pulse travel  (mcare-pulse-travel) ───────────────────────────────────
    final sweepX = _sweep(t) * size.width * (78 / 118);
    final sweepAlpha = _sweepOpacity(t) * alpha;
    if (sweepAlpha > 0.01) {
      final pulseW = size.width * 0.34;
      final pillH = size.height * 0.35;
      final left = (sweepX - pulseW / 2).clamp(0.0, size.width - pulseW);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, midY - pillH / 2, pulseW, pillH),
        Radius.circular(pillH),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              base.withValues(alpha: 0),
              base.withValues(alpha: 0.35 * sweepAlpha),
              base.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(rect.outerRect),
      );
    }

    // ── ECG trace with left-to-right clip reveal ──────────────────────────────
    final revealFraction = _reveal(t);
    if (revealFraction <= 0.001) return;

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, size.width * revealFraction, size.height),
    );
    canvas.drawPath(
      _SplashEcgPath.build(size),
      Paint()
        ..color = _traceColor(t).withValues(alpha: alpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.height * 0.11).clamp(1.0, 3.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EcgRevealPainter old) =>
      old.beatPhase != beatPhase ||
      old.lubColor != lubColor ||
      old.dubColor != dubColor ||
      old.onWhite != onWhite;
}
