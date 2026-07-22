import 'package:flutter/material.dart';

import '../../shared/theme/app_layout.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';

/// Google Identity palette
abstract final class _GoogleColors {
  static const blue = Color(0xFF4285F4);
  static const red = Color(0xFFEA4335);
  static const yellow = Color(0xFFFBBC05);
  static const green = Color(0xFF34A853);
  static const text = Color(0xFF1F1F1F);
  static const border = Color(0xFFDADCE0);
}

/// Side-by-side social provider chips — the pattern used by Notion, Linear,
/// Airbnb and most modern auth flows. Always shows **Google** and **Apple**
/// labels for clarity.
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({
    super.key,
    this.onGoogle,
    this.onApple,
    this.compact = false,
  });

  final VoidCallback? onGoogle;
  final VoidCallback? onApple;

  /// Smaller height and type for registration sheets.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? AppSpacing.sm : AppSpacing.md;

    return Row(
      children: [
        Expanded(
          child: _GoogleChip(compact: compact, onTap: onGoogle),
        ),
        SizedBox(width: gap),
        Expanded(
          child: _AppleChip(compact: compact, onTap: onApple),
        ),
      ],
    );
  }
}

/// Google chip — white surface, Google border, multicolor G + "Google".
class _GoogleChip extends StatelessWidget {
  const _GoogleChip({required this.compact, this.onTap});

  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final height = compact ? AppLayout.controlHeight : 44.0;
    final iconSize = compact ? AppLayout.controlIconSize : 19.0;
    final fontSize = compact ? AppLayout.body : 14.0;

    return Semantics(
      button: true,
      label: 'Continue with Google',
      child: Material(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: _GoogleColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GoogleLogo(size: iconSize),
                const SizedBox(width: 8),
                Text(
                  'Google',
                  style: TextStyle(
                    color: _GoogleColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: fontSize,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple chip — white surface, neutral border, Apple mark + "Apple".
class _AppleChip extends StatelessWidget {
  const _AppleChip({required this.compact, this.onTap});

  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final height = compact ? AppLayout.controlHeight : 44.0;
    final iconSize = compact ? 18.0 : 20.0;
    final fontSize = compact ? AppLayout.body : 14.0;

    return Semantics(
      button: true,
      label: 'Continue with Apple',
      child: Material(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.apple, size: iconSize, color: AppPalette.ink(context)),
                const SizedBox(width: 8),
                Text(
                  'Apple',
                  style: TextStyle(
                    color: AppPalette.ink(context),
                    fontWeight: FontWeight.w600,
                    fontSize: fontSize,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Filled multicolour Google "G" — uses Google's official CDN asset with a
/// local vector fallback when offline.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});
  final double size;

  static const _officialAsset =
      'https://www.gstatic.com/images/branding/product/1x/googleg_48dp.png';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        _officialAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => CustomPaint(
          painter: _GoogleLogoPainter(),
        ),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w * 0.44;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Blue — top-right arc + horizontal bar into centre.
    final blue = Paint()
      ..color = _GoogleColors.blue
      ..style = PaintingStyle.fill;
    canvas.drawArc(rect, -0.52, 1.55, true, blue);
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.02, cy - h * 0.07, w * 0.52, h * 0.14),
      blue,
    );

    // Green — left arc.
    canvas.drawArc(
      rect,
      1.95,
      1.25,
      true,
      Paint()
        ..color = _GoogleColors.green
        ..style = PaintingStyle.fill,
    );

    // Yellow — bottom-left arc.
    canvas.drawArc(
      rect,
      3.20,
      0.95,
      true,
      Paint()
        ..color = _GoogleColors.yellow
        ..style = PaintingStyle.fill,
    );

    // Red — right arc.
    canvas.drawArc(
      rect,
      4.15,
      1.10,
      true,
      Paint()
        ..color = _GoogleColors.red
        ..style = PaintingStyle.fill,
    );

    // Hollow centre so segments read as a "G".
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.56,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Blue bar closing the G opening on the right.
    canvas.drawRect(
      Rect.fromLTWH(cx + r * 0.02, cy - h * 0.07, r * 0.62, h * 0.14),
      blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label = 'or continue with'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppPalette.border(context))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
          ),
        ),
        Expanded(child: Divider(color: AppPalette.border(context))),
      ],
    );
  }
}
