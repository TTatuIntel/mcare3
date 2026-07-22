import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// Compact frosted action chip — blends with bubble backgrounds, accent-tinted.
class GlassFloatingButton extends StatefulWidget {
  const GlassFloatingButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.accent = AppColors.brandIndigo,
    this.dynamicColors,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color accent;

  /// When set (≥2 colors), the accent tint gently shifts between them.
  final List<Color>? dynamicColors;

  @override
  State<GlassFloatingButton> createState() => _GlassFloatingButtonState();
}

class _GlassFloatingButtonState extends State<GlassFloatingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _breathe;

  @override
  void initState() {
    super.initState();
    final disable = SchedulerBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    if (!disable) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 0.5;
    }
    _breathe = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _primaryAccent {
    final dynamic = widget.dynamicColors;
    if (dynamic != null && dynamic.isNotEmpty) return dynamic.first;
    return widget.accent;
  }

  Color get _secondaryAccent {
    final dynamic = widget.dynamicColors;
    if (dynamic != null && dynamic.length >= 2) return dynamic[1];
    return Color.lerp(widget.accent, AppColors.brandIndigo, 0.35)!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _breathe,
      builder: (context, _) {
        final t = _breathe.value;
        final accent = Color.lerp(_primaryAccent, _secondaryAccent, t * 0.4)!;
        final lift = t * 2.5;
        final scale = 1.0 + t * 0.028;

        return Transform.translate(
          offset: Offset(0, -lift),
          child: Transform.scale(
            scale: scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.18 + t * 0.08),
                    blurRadius: 20 + t * 10,
                    offset: Offset(0, 9 + t * 4),
                    spreadRadius: -4,
                  ),
                  ...AppShadows.subtle,
                ],
              ),
              child: _FrostedCapsule(
                isDark: isDark,
                accent: accent,
                breathe: t,
                onPressed: widget.onPressed,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 17, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AccentIconWell(
                        icon: widget.icon,
                        accent: accent,
                        isDark: isDark,
                        breathe: t,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color:
                              isDark ? AppColors.darkInk : AppPalette.ink(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          letterSpacing: 0.12,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FrostedCapsule extends StatelessWidget {
  const _FrostedCapsule({
    required this.isDark,
    required this.accent,
    required this.breathe,
    required this.onPressed,
    required this.child,
  });

  final bool isDark;
  final Color accent;
  final double breathe;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSpacing.radiusPill);
    final useBlur = !kIsWeb;

    final fillTop = isDark
        ? AppColors.darkSurface.withOpacity(useBlur ? 0.90 : 0.97)
        : Colors.white.withOpacity(useBlur ? 0.90 : 0.97);
    final tintStrength = (isDark ? 0.20 : 0.12) + breathe * 0.08;
    final fillBottom = Color.lerp(
      fillTop,
      accent.withOpacity(tintStrength),
      0.45 + breathe * 0.25,
    )!;

    final borderColor = isDark
        ? AppColors.darkBorderStrong.withOpacity(0.85)
        : Color.lerp(
            Colors.white,
            accent.withOpacity(0.35 + breathe * 0.15),
            0.25,
          )!;

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fillTop, fillBottom],
        ),
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );

    if (useBlur) {
      body = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: body,
        ),
      );
    } else {
      body = ClipRRect(borderRadius: radius, child: body);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        splashColor: accent.withOpacity(0.12),
        highlightColor: accent.withOpacity(0.06),
        child: body,
      ),
    );
  }
}

class _AccentIconWell extends StatelessWidget {
  const _AccentIconWell({
    required this.icon,
    required this.accent,
    required this.isDark,
    required this.breathe,
  });

  final IconData icon;
  final Color accent;
  final bool isDark;
  final double breathe;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      width: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withOpacity(
          (isDark ? 0.26 : 0.14) + breathe * 0.08,
        ),
        border: Border.all(
          color: accent.withOpacity(
            (isDark ? 0.50 : 0.32) + breathe * 0.12,
          ),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 19,
        color: accent,
      ),
    );
  }
}
