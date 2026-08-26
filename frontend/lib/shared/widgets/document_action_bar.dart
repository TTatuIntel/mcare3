import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'glass_card.dart';
import 'loading/loading.dart';

/// Compact row of document actions — View, Download, Delete on one line.
class DocumentActionBar extends StatelessWidget {
  const DocumentActionBar({
    super.key,
    required this.onView,
    required this.onDownload,
    this.onEdit,
    this.onDelete,
    this.viewLoading = false,
    this.downloadLoading = false,
    this.deleteLoading = false,
  });

  final VoidCallback? onView;
  final VoidCallback? onDownload;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool viewLoading;
  final bool downloadLoading;
  final bool deleteLoading;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.visibility_outlined,
                label: 'View',
                onTap: viewLoading ? null : onView,
                loading: viewLoading,
              ),
            ),
            const _ActionDivider(),
            Expanded(
              child: _ActionTile(
                icon: AppIcons.document,
                label: 'Download',
                onTap: downloadLoading ? null : onDownload,
                loading: downloadLoading,
              ),
            ),
            if (onEdit != null) ...[
              const _ActionDivider(),
              Expanded(
                child: _ActionTile(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
            ],
            if (onDelete != null) ...[
              const _ActionDivider(),
              Expanded(
                child: _ActionTile(
                  icon: AppIcons.delete,
                  label: 'Delete',
                  danger: true,
                  onTap: deleteLoading ? null : onDelete,
                  loading: deleteLoading,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  const _ActionDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return VerticalDivider(
      width: 1,
      thickness: 1,
      color: isDark ? AppColors.darkBorder : AppPalette.border(context),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.loading = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = danger
        ? AppColors.critical
        : theme.colorScheme.primary;
    final fg = danger
        ? accent
        : (isDark ? AppColors.darkInk : AppPalette.ink(context));
    final muted = danger
        ? accent.withOpacity(0.75)
        : AppPalette.textMuted(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        splashColor: accent.withOpacity(0.1),
        highlightColor: accent.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                McarePulse(
                  size: McarePulseSize.micro,
                  color: accent,
                  semanticLabel: null,
                )
              else
                Icon(icon, size: 20, color: fg),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: danger ? muted : AppPalette.textMuted(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
