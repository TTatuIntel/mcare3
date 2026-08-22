import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'glass_card.dart';

/// Search surface shared by staff directory screens.
///
/// Keeping this as one component prevents Patients, Users and future staff
/// directories from drifting apart while preserving each screen's own query
/// and API logic.
class StaffDirectorySearch extends StatelessWidget {
  const StaffDirectorySearch({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onSubmitted,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 18, color: AppPalette.textMuted(context)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              textField: true,
              label: semanticLabel ?? hintText,
              child: TextField(
                controller: controller,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: InputBorder.none,
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                          icon: const Icon(AppIcons.close, size: 17),
                        ),
                ),
                onChanged: onChanged,
                onSubmitted: onSubmitted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Consistent, horizontally scrollable filter control used below directory
/// search. The visual size mirrors the supplied mobile reference while the
/// semantic node exposes the selected state to assistive technology.
class StaffDirectoryFilterChip extends StatelessWidget {
  const StaffDirectoryFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final resolvedAccent = accent ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label filter',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? resolvedAccent.withValues(alpha: 0.14)
                    : AppPalette.surfaceAlt(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                border: Border.all(
                  color: selected ? resolvedAccent : AppPalette.border(context),
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected
                      ? resolvedAccent
                      : AppPalette.textMuted(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
