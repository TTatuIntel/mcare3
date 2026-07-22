import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// The one and only card surface. Use everywhere a panel is needed.
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

  /// Frosted glass — blurs content behind and uses a translucent fill.
  final bool frosted;
  final double blurSigma;

  static double defaultBlurSigma(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? 14 : 10;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ??
        BorderRadius.circular(AppSpacing.radiusLg);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultSurface =
        isDark ? AppColors.darkSurface : AppPalette.surface(context);
    final defaultBorder =
        isDark ? AppColors.darkBorder : AppPalette.border(context);
    final frostedFill = isDark
        ? AppColors.darkSurface.withOpacity(0.82)
        : AppPalette.surface(context).withOpacity(0.22);
    final frostedBorder = isDark
        ? AppColors.darkBorderStrong.withOpacity(0.65)
        : Colors.white.withOpacity(0.45);
    final sigma = blurSigma > 0 ? blurSigma : defaultBlurSigma(context);

    // BackdropFilter is unreliable on Flutter web (blank panels on some
    // mobile browsers). Use an opaque surface there instead.
    final useBackdropBlur = frosted && !kIsWeb;

    final Color? fillColor;
    if (frosted) {
      fillColor = background ??
          (useBackdropBlur
              ? frostedFill
              : (isDark ? AppColors.darkSurface : AppPalette.surfaceAlt(context)));
    } else if (gradient == null) {
      fillColor = background ?? defaultSurface;
    } else {
      fillColor = null;
    }

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fillColor,
        gradient: frosted ? null : gradient,
        borderRadius: radius,
        border: frosted
            ? Border.all(
                color: useBackdropBlur ? frostedBorder : defaultBorder,
                width: 1,
              )
            : (border ?? Border.all(color: defaultBorder, width: 1)),
        boxShadow: useBackdropBlur
            ? AppShadows.none
            : (shadow ?? AppShadows.card(context)),
      ),
      child: child,
    );

    if (useBackdropBlur) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: content,
        ),
      );
    }

    if (constraints != null) {
      content = ConstrainedBox(constraints: constraints!, child: content);
    }

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }
    return content;
  }
}
