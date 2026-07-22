import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';

/// Heart indicator showing profile completion (0–100%).
class ProfileCompletionHeart extends StatelessWidget {
  const ProfileCompletionHeart({
    super.key,
    required this.percent,
    this.size = 52,
    this.onTap,
    this.showLabel = true,
  });

  final int percent;
  final double size;
  final VoidCallback? onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = percent.clamp(0, 100);
    final fill = clamped / 100.0;
    final isFull = clamped >= 100;
    final color = isFull ? AppColors.critical : AppColors.brandIndigo;

    final heart = Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          AppIcons.heartRate,
          size: size,
          color: AppPalette.borderStrong(context),
        ),
        ClipRect(
          clipper: _BottomFillClipper(fill),
          child: Icon(
            AppIcons.heartRate,
            size: size,
            color: color,
          ),
        ),
        if (showLabel)
          Text(
            '$clamped%',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: size < 44 ? 9 : 10,
              fontWeight: FontWeight.w800,
              color: isFull ? AppColors.critical : AppPalette.ink(context),
            ),
          ),
      ],
    );

    if (onTap == null) return heart;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: heart,
        ),
      ),
    );
  }
}

class _BottomFillClipper extends CustomClipper<Rect> {
  _BottomFillClipper(this.fill);
  final double fill;

  @override
  Rect getClip(Size size) {
    final top = size.height * (1 - fill);
    return Rect.fromLTWH(0, top, size.width, size.height - top);
  }

  @override
  bool shouldReclip(_BottomFillClipper old) => old.fill != fill;
}

/// Compact completion card with heart and missing fields hint.
class ProfileCompletionCard extends StatelessWidget {
  const ProfileCompletionCard({
    super.key,
    required this.percent,
    required this.incompleteLabels,
    this.onTap,
  });

  final int percent;
  final List<String> incompleteLabels;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFull = percent >= 100;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              ProfileCompletionHeart(
                percent: percent,
                size: 48,
                showLabel: true,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFull
                          ? 'Profile complete'
                          : 'Complete your profile',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFull
                          ? 'All health details are on file.'
                          : incompleteLabels.isEmpty
                              ? '$percent% complete — keep going!'
                              : 'Missing: ${incompleteLabels.take(3).join(', ')}${incompleteLabels.length > 3 ? '…' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isFull)
                Icon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: AppPalette.textMuted(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
