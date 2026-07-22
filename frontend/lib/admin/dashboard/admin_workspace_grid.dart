import 'package:flutter/material.dart';

import '../../shared/dashboard/admin_workspace_catalog.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/state/support_state.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/section_label.dart';

/// Compact quick-launch row — featured workspaces only (no full catalog).
class AdminWorkspaceGrid extends StatelessWidget {
  const AdminWorkspaceGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        StaffState.instance,
        SupportState.instance,
      ]),
      builder: (context, _) {
        final areas = AdminWorkspaceCatalog.featured()
            .where((a) => a.id != 'dashboard')
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel(
              title: 'Quick access',
              icon: AppIcons.home,
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = AppSpacing.sm;
                final cols = constraints.maxWidth >= 900
                    ? 4
                    : constraints.maxWidth >= 520
                        ? 3
                        : 2;
                final w = (constraints.maxWidth - spacing * (cols - 1)) / cols;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: areas
                      .map(
                        (area) => SizedBox(
                          width: w,
                          child: _QuickTile(area: area),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushNamed(RouteNames.adminAnalytics),
                icon: const Icon(AppIcons.analytics, size: 16),
                label: const Text('Analytics & system'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.area});
  final AdminWorkspaceArea area;

  @override
  Widget build(BuildContext context) {
    final badge = AdminWorkspaceCounts.badgeFor(area.badgeKey);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(area.route),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: GlassCard(
          frosted: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: area.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(area.icon, color: area.color, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  area.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: area.color.withValues(alpha: 0.14),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      color: area.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
