import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_icons.dart';

/// One section header style across all screens.
class SectionLabel extends StatelessWidget {
  const SectionLabel({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        right: AppSpacing.xs,
        bottom: AppSpacing.md,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          if (trailing != null) ...[
            Text(
              trailing!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (actionLabel != null && onAction != null)
              const SizedBox(width: AppSpacing.sm),
          ],
          if (actionLabel != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Text(
                      actionLabel!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Icon(
                      AppIcons.chevronRight,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
