import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Backwards-compatible name for the approved v2 application backdrop.
///
/// The previous implementation rendered continuously animated bokeh bubbles.
/// The approved design uses a calm, static clinical surface instead: it is
/// easier to read, cheaper to render on web/mobile, and automatically respects
/// reduced-motion preferences because no ambient animation is created.
class BubbleBackground extends StatelessWidget {
  const BubbleBackground({
    super.key,
    this.bubbleCount = 0,
    this.child,
    this.surfaceColor,
  });

  /// Kept only for source compatibility while old call sites migrate.
  final int bubbleCount;
  final Widget? child;
  final Color? surfaceColor;

  @override
  Widget build(BuildContext context) {
    final isDark = AppPalette.isDark(context);
    final base = surfaceColor ?? AppPalette.scaffoldBg(context);
    final accent = Theme.of(context).colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.035 : 0.025),
              base,
            ),
            base,
            Color.alphaBlend(
              AppColors.info.withValues(alpha: isDark ? 0.025 : 0.018),
              base,
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}
