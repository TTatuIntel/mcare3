import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'brand_logo.dart';
import 'responsive.dart';

class PatientNavDestination {
  const PatientNavDestination({
    required this.icon,
    required this.label,
    required this.route,
    this.activeRoutes = const <String>{},
  });
  final IconData icon;
  final String label;
  final String route;
  final Set<String> activeRoutes;

  bool isActive(String currentRoute) =>
      route == currentRoute || activeRoutes.contains(currentRoute);
}

class PatientBottomNav extends StatelessWidget {
  const PatientBottomNav({
    super.key,
    required this.currentRoute,
    this.detached = false,
  });

  /// Used for utility screens — highlights nothing but still navigates home.
  const PatientBottomNav.detached({super.key})
    : currentRoute = '',
      detached = true;

  final String currentRoute;
  final bool detached;

  static const destinations = <PatientNavDestination>[
    PatientNavDestination(
      icon: AppIcons.home,
      label: 'Home',
      route: RouteNames.patientDashboard,
    ),
    PatientNavDestination(
      icon: AppIcons.vitals,
      label: 'Health',
      route: RouteNames.patientHealth,
      activeRoutes: {
        RouteNames.patientHealth,
        RouteNames.patientVitals,
        RouteNames.patientVitalDetail,
        RouteNames.patientVitalHistory,
        RouteNames.patientVital7Day,
        RouteNames.patientMedications,
        RouteNames.patientMedicationDetail,
        RouteNames.patientDocuments,
      },
    ),
    PatientNavDestination(
      icon: AppIcons.careTeam,
      label: 'Care',
      route: RouteNames.patientCare,
      activeRoutes: {
        RouteNames.patientCare,
        RouteNames.patientAppointments,
        RouteNames.patientAppointmentDetail,
        RouteNames.patientMessages,
        RouteNames.patientChatThread,
        RouteNames.patientCareTeam,
        RouteNames.patientSupport,
        RouteNames.patientTicketDetail,
        RouteNames.patientSos,
      },
    ),
    PatientNavDestination(
      icon: AppIcons.more,
      label: 'More',
      route: RouteNames.patientMore,
      activeRoutes: {
        RouteNames.patientMore,
        RouteNames.patientNotifications,
        RouteNames.patientProfile,
        RouteNames.patientSettings,
      },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    if (tier.isDesktop) {
      // Desktop uses a side rail rendered by the page layout — bottom nav hidden.
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        border: Border(top: BorderSide(color: AppPalette.border(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: destinations
                .map(
                  (d) => _NavItem(
                    destination: d,
                    selected: !detached && d.isActive(currentRoute),
                    onTap: () {
                      if (!detached && d.route == currentRoute) return;
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil(d.route, (_) => false);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });
  final PatientNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final color = selected ? accent : AppPalette.textMuted(context);
    return Expanded(
      child: Semantics(
        key: ValueKey('patient-bottom-nav:${destination.route}'),
        button: true,
        selected: selected,
        label: '${destination.label} navigation tab',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.micro,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: AppMotion.micro,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Icon(destination.icon, color: color, size: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop left rail rendered by `PatientScaffold`.
class PatientSideRail extends StatelessWidget {
  const PatientSideRail({
    super.key,
    required this.currentRoute,
    this.compact = false,
  });
  final String currentRoute;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 80 : 232,
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        border: Border(right: BorderSide(color: AppPalette.border(context))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.lg : AppSpacing.xl,
                AppSpacing.xl,
                compact ? AppSpacing.lg : AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: compact
                  ? Icon(
                      AppIcons.heartRate,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                      semanticLabel: 'mCare',
                    )
                  : const BrandLogo(
                      height: BrandLogo.railHeight,
                      tappable: true,
                      animateHeartbeat: false,
                      showLifeline: false,
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...PatientBottomNav.destinations.map(
              (d) => _RailItem(
                destination: d,
                selected: d.isActive(currentRoute),
                compact: compact,
                onTap: () {
                  if (d.route == currentRoute) return;
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil(d.route, (_) => false);
                },
              ),
            ),
            const Spacer(),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.onTap,
  });
  final PatientNavDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final color = selected ? accent : AppPalette.textMuted(context);
    final item = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 2,
      ),
      child: Material(
        color: selected ? accent.withOpacity(0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(destination.icon, color: color, size: 20),
                if (!compact) ...[
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    destination.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? AppPalette.ink(context) : color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final semanticItem = Semantics(
      key: ValueKey('patient-rail-nav:${destination.route}'),
      button: true,
      selected: selected,
      label: '${destination.label} navigation tab',
      child: item,
    );
    if (!compact) return semanticItem;
    return Tooltip(message: destination.label, child: semanticItem);
  }
}
