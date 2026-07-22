import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vital.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'glass_card.dart';
import 'responsive.dart';
import 'risk_badge.dart';

/// Compact metric tile reused on every staff dashboard / analytics screen.
class StaffKpiTile extends StatelessWidget {
  const StaffKpiTile({
    super.key,
    required this.label,
    required this.value,
    this.helper,
    this.deltaPercent,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final String? helper;
  final double? deltaPercent;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = AppPalette.textMuted(context);
    final isUp = (deltaPercent ?? 0) >= 0;
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 32,
                    width: 32,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(
                      icon ?? AppIcons.analytics,
                      color: accent,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(value, style: theme.textTheme.headlineSmall),
              if (helper != null || deltaPercent != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (deltaPercent != null) ...[
                      Icon(
                        isUp ? AppIcons.trendUp : AppIcons.trendDown,
                        color: isUp ? AppColors.success : AppColors.critical,
                        size: 14,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${deltaPercent!.abs().toStringAsFixed(1)}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isUp ? AppColors.success : AppColors.critical,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (helper != null) const SizedBox(width: 6),
                    ],
                    if (helper != null)
                      Expanded(
                        child: Text(
                          helper!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive KPI grid — 2 cols on mobile, 4 on desktop. Used on every
/// staff overview screen. Branches layout, never logic.
class StaffKpiGrid extends StatelessWidget {
  const StaffKpiGrid({super.key, required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final cols = tier.isMobile ? 2 : (tier.isTablet ? 3 : 4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = AppSpacing.md;
        final w = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles.map((t) => SizedBox(width: w, child: t)).toList(),
        );
      },
    );
  }
}

/// A row representing one patient — reused in the doctor caseload, admin
/// user list, and assistant assignments view.
class StaffPatientRow extends StatelessWidget {
  const StaffPatientRow({
    super.key,
    required this.name,
    required this.summary,
    required this.risk,
    required this.lastActivity,
    this.unreadAlerts = 0,
    this.onTap,
    this.trailing,
  });

  final String name;
  final String summary;
  final RiskLevel risk;
  final DateTime lastActivity;
  final int unreadAlerts;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppPalette.textMuted(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: risk.color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(name),
                  style: TextStyle(
                    color: risk.color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unreadAlerts > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppPalette.isDark(context)
                                  ? AppColors.darkCriticalSoft
                                  : AppPalette.criticalSoft(context),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusPill),
                            ),
                            child: Text(
                              '$unreadAlerts alert${unreadAlerts == 1 ? '' : 's'}',
                              style: const TextStyle(
                                color: AppColors.critical,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      summary,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        RiskBadge(risk: risk, dense: true),
                        const SizedBox(width: 6),
                        Text(
                          'Last reading ${_relative(lastActivity)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ] else
                Icon(AppIcons.chevronRight,
                    size: 16, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(d);
  }
}

/// One generic data-row in a staff list (approvals, audit, users, etc.) —
/// mirrors the patient ticket-row pattern.
class StaffListRow extends StatelessWidget {
  const StaffListRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.pill,
    this.pillColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? pill;
  final Color? pillColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = iconColor ?? theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: colour.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: colour, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pill != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: (pillColor ?? colour).withOpacity(0.14),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusPill),
                            ),
                            child: Text(
                              pill!,
                              style: TextStyle(
                                color: pillColor ?? colour,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppPalette.textMuted(context)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cards-in-a-card pattern reused across every staff list screen.
class StaffListCard extends StatelessWidget {
  const StaffListCard({super.key, required this.children, this.title});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppPalette.border(context)),
            children[i],
          ],
        ],
      ),
    );
  }
}
