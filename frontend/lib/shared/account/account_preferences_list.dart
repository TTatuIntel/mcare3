import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import '../models/user_role.dart';
import '../navigation/profile_navigation.dart';
import '../widgets/staff_blocks.dart';

/// Settings · Notifications · Support rows — same destinations as the account sheet.
class AccountPreferencesList extends StatelessWidget {
  const AccountPreferencesList({
    super.key,
    required this.role,
    this.excludeRoutes = const {},
    this.sectionTitle = 'Account & preferences',
  });

  final UserRole role;
  final Set<String> excludeRoutes;
  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    final profileRoute = ProfileNavigation.profileRouteFor(role);
    final items = ProfileNavigation.menuFor(role)
        .where((e) =>
            e.route != profileRoute && !excludeRoutes.contains(e.route))
        .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StaffListCard(
          children: items
              .map(
                (item) => StaffListRow(
                  icon: item.icon,
                  title: item.label,
                  subtitle: _subtitleFor(item.route, role),
                  onTap: () => Navigator.of(context).pushNamed(item.route),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  static String _subtitleFor(String route, UserRole role) => switch (route) {
        RouteNames.adminSettings ||
        RouteNames.doctorSettings ||
        RouteNames.assistantSettings ||
        RouteNames.patientSettings =>
          'Theme, language and alert preferences',
        RouteNames.adminNotifications ||
        RouteNames.doctorNotifications ||
        RouteNames.assistantNotifications ||
        RouteNames.patientNotifications =>
          'Unified inbox — alerts and updates',
        RouteNames.adminSupport ||
        RouteNames.assistantSupport ||
        RouteNames.patientSupport =>
          role == UserRole.admin || role == UserRole.mcareAssistant
              ? 'Patient and staff help requests'
              : 'Support tickets and replies',
        RouteNames.adminUsers || RouteNames.assistantUsers =>
          'Temp passwords, unlocks and invites',
        RouteNames.adminAudit || RouteNames.assistantAudit =>
          'Recent workspace actions',
        RouteNames.adminSystem => 'Runtime, data, access',
        RouteNames.patientCareTeam => 'Doctors and care coordinators',
        RouteNames.patientSos => 'Emergency contacts and SOS',
        _ => 'Open',
      };
}

/// Compact shortcuts row for notifications / settings footers.
class AccountHubQuickLinks extends StatelessWidget {
  const AccountHubQuickLinks({
    super.key,
    required this.role,
    this.currentRoute,
  });

  final UserRole role;
  final String? currentRoute;

  @override
  Widget build(BuildContext context) {
    final profileRoute = ProfileNavigation.profileRouteFor(role);
    final items = ProfileNavigation.menuFor(role)
        .where((e) =>
            e.route != profileRoute &&
            e.route != currentRoute &&
            !e.danger)
        .take(3)
        .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return StaffListCard(
      children: items
          .map(
            (item) => StaffListRow(
              icon: item.icon,
              title: item.label,
              subtitle: AccountPreferencesList._subtitleFor(item.route, role),
              onTap: () => Navigator.of(context).pushNamed(item.route),
            ),
          )
          .toList(),
    );
  }
}
