import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// One filter option for [StaffFilterChipBar].
class StaffFilterOption {
  const StaffFilterOption({
    required this.value,
    required this.label,
    this.color,
  });

  final String value;
  final String label;
  final Color? color;
}

/// Unified horizontal filter chips for staff/admin screens.
class StaffFilterChipBar extends StatelessWidget {
  const StaffFilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.accent,
  });

  final List<StaffFilterOption> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final defaultAccent = accent ?? AppColors.adminPurple;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final opt in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _StaffFilterChip(
                label: opt.label,
                selected: selected == opt.value,
                accent: opt.color ?? defaultAccent,
                onTap: () => onSelected(opt.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _StaffFilterChip extends StatelessWidget {
  const _StaffFilterChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : AppPalette.surfaceAlt(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected ? accent : AppPalette.border(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : AppPalette.textMuted(context),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
