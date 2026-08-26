import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'glass_card.dart';

/// A route-backed task exposed by a grouped role hub.
class AppSectionLink {
  const AppSectionLink({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
    this.color,
  });

  final String title;
  final String description;
  final IconData icon;
  final String route;
  final Color? color;
}

class AppSectionGroup {
  const AppSectionGroup({
    required this.title,
    required this.description,
    required this.links,
  });

  final String title;
  final String description;
  final List<AppSectionLink> links;
}

/// Shared responsive composition for Patient and Doctor grouped navigation.
///
/// It owns presentation only. Every tile opens an existing guarded route, so
/// domain state, validation and API mutations remain in their current owner.
class SectionHub extends StatelessWidget {
  const SectionHub({
    super.key,
    required this.title,
    required this.description,
    required this.groups,
  });

  final String title;
  final String description;
  final List<AppSectionGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppPalette.textMuted(context)),
        ),
        const SizedBox(height: AppSpacing.xxl),
        for (var index = 0; index < groups.length; index++) ...[
          _SectionGroupView(group: groups[index]),
          if (index != groups.length - 1)
            const SizedBox(height: AppSpacing.xxl),
        ],
      ],
    );
  }
}

class _SectionGroupView extends StatelessWidget {
  const _SectionGroupView({required this.group});

  final AppSectionGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(group.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          group.description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final scaler = MediaQuery.textScalerOf(context).scale(1);
            final columns = scaler > 1.3
                ? 1
                : constraints.maxWidth >= 980
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final gap = constraints.maxWidth < 520
                ? AppSpacing.md
                : AppSpacing.lg;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: group.links
                  .map(
                    (link) => SizedBox(
                      width: width,
                      child: _SectionLinkCard(link: link),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _SectionLinkCard extends StatelessWidget {
  const _SectionLinkCard({required this.link});

  final AppSectionLink link;

  @override
  Widget build(BuildContext context) {
    final accent = link.color ?? Theme.of(context).colorScheme.primary;
    return GlassCard(
      onTap: () => Navigator.of(context).pushNamed(link.route),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(link.icon, color: accent, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  link.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  link.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            AppIcons.chevronRight,
            size: 20,
            color: AppPalette.textMuted(context),
          ),
        ],
      ),
    );
  }
}
