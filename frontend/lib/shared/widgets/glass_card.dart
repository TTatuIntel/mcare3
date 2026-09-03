import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// The canonical application surface.
///
/// The class name is retained to avoid breaking existing feature code, but the
/// approved v2 design no longer uses frosted glass or background blur. Every
/// role now receives the same opaque, bordered, accessible clinical surface.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.borderRadius,
    this.background,
    this.gradient,
    this.border,
    this.shadow,
    this.onTap,
    this.constraints,
    this.frosted = false,
    this.blurSigma = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? background;
  final Gradient? gradient;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;
  final BoxConstraints? constraints;

  /// Deprecated compatibility properties. They no longer enable blur.
  final bool frosted;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppSpacing.radiusLg);

    final defaultSurface = AppPalette.surface(context);
    final defaultBorder = AppPalette.border(context);
    final fillColor = gradient == null ? background ?? defaultSurface : null;

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fillColor,
        gradient: gradient,
        borderRadius: radius,
        border: border ?? Border.all(color: defaultBorder, width: 1),
        boxShadow: shadow ?? AppShadows.card(context),
      ),
      child: child,
    );

    if (constraints != null) {
      content = ConstrainedBox(constraints: constraints!, child: content);
    }

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(onTap: onTap, borderRadius: radius, child: content),
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }
    return content;
  }
}
