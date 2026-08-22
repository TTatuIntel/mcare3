import 'package:flutter/material.dart';

import '../models/user_role.dart';

/// The four stable destinations in the Guided Operations Hub.
///
/// These are presentation destinations, not replacements for the existing
/// named routes. Every task still opens the established route that owns the
/// workflow and its API behaviour.
enum StaffHubSection {
  home('Home', Icons.home_rounded),
  work('Work', Icons.assignment_turned_in_rounded),
  people('People', Icons.groups_2_rounded),
  more('More', Icons.more_horiz_rounded);

  const StaffHubSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum StaffWorkItemType {
  emergency,
  clinicalAlert,
  approval,
  careRequest,
  assignment,
  support,
}

enum StaffWorkUrgency { critical, attention, routine }

class StaffWorkItem {
  const StaffWorkItem({
    required this.type,
    required this.urgency,
    required this.title,
    required this.description,
    required this.count,
    required this.route,
    required this.icon,
    required this.color,
    this.actionLabel = 'Review',
  });

  final StaffWorkItemType type;
  final StaffWorkUrgency urgency;
  final String title;
  final String description;
  final int count;
  final String route;
  final IconData icon;
  final Color color;
  final String actionLabel;
}

class StaffHubLink {
  const StaffHubLink({
    required this.id,
    required this.title,
    required this.description,
    required this.route,
    required this.icon,
    required this.color,
    this.count,
  });

  final String id;
  final String title;
  final String description;
  final String route;
  final IconData icon;
  final Color color;
  final int? count;
}

/// Route destinations used by the tappable analytics tiles on the People page.
///
/// Routes are computed once (by [StaffHubData.build]) so the view layer can
/// stay role-agnostic when wiring tap handlers.
class StaffPeopleRoutes {
  const StaffPeopleRoutes({
    this.patients,
    this.users,
    this.careRequests,
    this.approvals,
  });

  final String? patients;
  final String? users;
  final String? careRequests;
  final String? approvals;
}

class StaffHubSnapshot {
  const StaffHubSnapshot({
    required this.role,
    required this.workItems,
    required this.peopleLinks,
    required this.moreLinks,
    required this.activePatients,
    required this.activeStaff,
    required this.totalUsers,
    required this.canManageRequests,
    this.patientsTotal = 0,
    this.doctorsCount = 0,
    this.adminsCount = 0,
    this.assistantsCount = 0,
    this.pendingCareRequests = 0,
    this.pendingApprovals = 0,
    this.peopleRoutes = const StaffPeopleRoutes(),
  });

  final UserRole role;
  final List<StaffWorkItem> workItems;
  final List<StaffHubLink> peopleLinks;
  final List<StaffHubLink> moreLinks;
  final int activePatients;
  final int activeStaff;
  final int totalUsers;
  final bool canManageRequests;

  final int patientsTotal;
  final int doctorsCount;
  final int adminsCount;
  final int assistantsCount;
  final int pendingCareRequests;
  final int pendingApprovals;
  final StaffPeopleRoutes peopleRoutes;

  int get urgentCount => workItems
      .where((item) => item.urgency == StaffWorkUrgency.critical)
      .fold(0, (sum, item) => sum + item.count);

  int get openWorkCount => workItems.fold(0, (sum, item) => sum + item.count);
}
