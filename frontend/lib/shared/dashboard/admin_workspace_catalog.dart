import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/support_ticket.dart';
import '../models/user_role.dart';
import '../state/staff_state.dart';
import '../state/support_state.dart';
import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';

/// Single source of truth for every admin workspace area — routes, icons,
/// categories, and live badge counts. Used by dashboard, profile, and settings.
enum AdminWorkspaceCategory {
  people('People & access'),
  operations('Operations'),
  communication('Communication'),
  platform('Platform');

  const AdminWorkspaceCategory(this.label);
  final String label;
}

class AdminWorkspaceArea {
  const AdminWorkspaceArea({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.color,
    required this.category,
    this.featured = false,
    this.badgeKey,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final String route;
  final Color color;
  final AdminWorkspaceCategory category;
  final bool featured;
  final String? badgeKey;
}

class AdminWorkspaceCatalog {
  AdminWorkspaceCatalog._();

  static const areas = <AdminWorkspaceArea>[
    AdminWorkspaceArea(
      id: 'dashboard',
      label: 'Overview',
      subtitle: 'KPIs, activity feed and system snapshot',
      icon: AppIcons.home,
      route: RouteNames.adminDashboard,
      color: AppColors.adminPurple,
      category: AdminWorkspaceCategory.platform,
      featured: true,
    ),
    AdminWorkspaceArea(
      id: 'patients',
      label: 'Patients',
      subtitle: 'Directory and clinical read-only profiles',
      icon: AppIcons.patients,
      route: RouteNames.adminPatients,
      color: AppColors.brandIndigo,
      category: AdminWorkspaceCategory.people,
      featured: true,
    ),
    AdminWorkspaceArea(
      id: 'users',
      label: 'Users',
      subtitle: 'Create accounts, roles, suspend and reset passwords',
      icon: AppIcons.users,
      route: RouteNames.adminUsers,
      color: AppColors.adminPurple,
      category: AdminWorkspaceCategory.people,
      featured: true,
    ),
    AdminWorkspaceArea(
      id: 'approvals',
      label: 'Approvals',
      subtitle: 'Verify healthworkers and activate staff accounts',
      icon: AppIcons.approval,
      route: RouteNames.adminApprovals,
      color: AppColors.adminPurple,
      category: AdminWorkspaceCategory.people,
      featured: true,
      badgeKey: 'approvals',
    ),
    AdminWorkspaceArea(
      id: 'permissions',
      label: 'Permissions',
      subtitle: 'Delegate capabilities to mCare assistants',
      icon: AppIcons.permissions,
      route: RouteNames.adminPermissions,
      color: AppColors.adminPurple,
      category: AdminWorkspaceCategory.people,
    ),
    // Requests and assignments are one workflow on one screen — approving a
    // request is what creates the assignment. The former 'assignments' area
    // was folded in here; `/admin/assignments` redirects to this route.
    AdminWorkspaceArea(
      id: 'care_requests',
      label: 'Care requests',
      subtitle: 'Approve, re-route or decline — and manage assignments',
      icon: AppIcons.careRequest,
      route: RouteNames.adminCareRequests,
      color: AppColors.info,
      category: AdminWorkspaceCategory.operations,
      badgeKey: 'care_requests',
      featured: true,
    ),
    AdminWorkspaceArea(
      id: 'alerts',
      label: 'Alerts',
      subtitle: 'Platform-wide vital and escalation alerts',
      icon: AppIcons.alert,
      route: RouteNames.adminAlerts,
      color: AppColors.warning,
      category: AdminWorkspaceCategory.operations,
      featured: true,
      badgeKey: 'alerts',
    ),
    // Reachable from the Work hub as well as from a patient's row. A signed
    // report waiting to be issued has no patient in mind — the admin is
    // working a queue, not a person — so it needs a door of its own.
    AdminWorkspaceArea(
      id: 'patient_reports',
      label: 'Patient reports',
      subtitle: 'Review, issue or send back what doctors have signed',
      icon: AppIcons.report,
      route: RouteNames.adminReports,
      color: AppColors.adminPurple,
      category: AdminWorkspaceCategory.operations,
      featured: true,
    ),
    AdminWorkspaceArea(
      id: 'sos',
      label: 'SOS',
      subtitle: 'Emergency events and responder hub',
      icon: AppIcons.sos,
      route: RouteNames.adminSos,
      color: AppColors.critical,
      category: AdminWorkspaceCategory.operations,
      badgeKey: 'sos',
    ),
    AdminWorkspaceArea(
      id: 'support',
      label: 'Ticket inbox',
      subtitle: 'Reply to tickets and close help requests',
      icon: AppIcons.support,
      route: RouteNames.adminSupport,
      color: AppColors.info,
      category: AdminWorkspaceCategory.communication,
      featured: true,
      badgeKey: 'support',
    ),
    AdminWorkspaceArea(
      id: 'messages',
      label: 'Messages',
      subtitle: 'Staff conversations and care coordination',
      icon: AppIcons.chat,
      route: RouteNames.adminMessages,
      color: AppColors.brandIndigo,
      category: AdminWorkspaceCategory.communication,
    ),
    AdminWorkspaceArea(
      id: 'announcements',
      label: 'Announcements',
      subtitle: 'Broadcast updates to patients and staff',
      icon: AppIcons.announcements,
      route: RouteNames.adminAnnouncements,
      color: AppColors.info,
      category: AdminWorkspaceCategory.communication,
    ),
    AdminWorkspaceArea(
      id: 'vital_catalog',
      label: 'Vital catalog',
      subtitle: 'Global thresholds and vital definitions',
      icon: AppIcons.catalog,
      route: RouteNames.adminVitalCatalog,
      color: AppColors.adminPurple,
      category: AdminWorkspaceCategory.platform,
    ),
    AdminWorkspaceArea(
      id: 'security',
      label: 'Security',
      subtitle: 'Incidents, SOS history and escalations',
      icon: AppIcons.security,
      route: RouteNames.adminSecurity,
      color: AppColors.critical,
      category: AdminWorkspaceCategory.platform,
    ),
    AdminWorkspaceArea(
      id: 'audit',
      label: 'Audit',
      subtitle: 'Activity trail across all accounts',
      icon: AppIcons.audit,
      route: RouteNames.adminAudit,
      color: AppColors.textMutedAA,
      category: AdminWorkspaceCategory.platform,
    ),
    AdminWorkspaceArea(
      id: 'analytics',
      label: 'Analytics',
      subtitle: 'KPIs, trends and operational metrics',
      icon: AppIcons.analytics,
      route: RouteNames.adminAnalytics,
      color: AppColors.brandIndigo,
      category: AdminWorkspaceCategory.platform,
    ),
    AdminWorkspaceArea(
      id: 'system',
      label: 'System',
      subtitle: 'Signup, SMS, retention and runtime flags',
      icon: AppIcons.system,
      route: RouteNames.adminSystem,
      color: AppColors.textMutedAA,
      category: AdminWorkspaceCategory.platform,
    ),
    AdminWorkspaceArea(
      id: 'settings',
      label: 'Settings',
      subtitle: 'Personal preferences and admin shortcuts',
      icon: AppIcons.settings,
      route: RouteNames.adminSettings,
      color: AppColors.adminPurple,
      category: AdminWorkspaceCategory.platform,
    ),
    AdminWorkspaceArea(
      id: 'notifications',
      label: 'Notifications',
      subtitle: 'Unified inbox for alerts and updates',
      icon: AppIcons.bell,
      route: RouteNames.adminNotifications,
      color: AppColors.brandIndigo,
      category: AdminWorkspaceCategory.communication,
    ),
    AdminWorkspaceArea(
      id: 'profile',
      label: 'Profile',
      subtitle: 'Your account, password and workspace hub',
      icon: AppIcons.profile,
      route: RouteNames.adminProfile,
      color: AppColors.adminPurple,
      category: AdminWorkspaceCategory.platform,
    ),
  ];

  static List<AdminWorkspaceArea> featured() =>
      areas.where((a) => a.featured).toList();

  static List<AdminWorkspaceArea> byCategory(AdminWorkspaceCategory cat) =>
      areas.where((a) => a.category == cat && !a.featured).toList();

  static List<AdminWorkspaceArea> operationsHub() => [
    areaById('users')!,
    areaById('approvals')!,
    areaById('permissions')!,
    areaById('care_requests')!,
    areaById('support')!,
  ];

  static AdminWorkspaceArea? areaById(String id) {
    for (final a in areas) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Map admin workspace ids to assistant routes for delegated staff.
  static String assistantRouteFor(String areaId) => switch (areaId) {
    'users' => RouteNames.assistantUsers,
    'patients' => RouteNames.assistantPatients,
    'approvals' => RouteNames.assistantApprovals,
    'care_requests' => RouteNames.assistantCareRequests,
    // Retired id — still mapped so stored shortcuts land on the merged page.
    'assignments' => RouteNames.assistantCareRequests,
    'support' => RouteNames.assistantSupport,
    'alerts' => RouteNames.assistantAlerts,
    'sos' => RouteNames.assistantSos,
    'audit' => RouteNames.assistantAudit,
    'announcements' => RouteNames.assistantAnnouncements,
    'security' => RouteNames.assistantSecurity,
    'vital_catalog' => RouteNames.assistantVitalCatalog,
    _ => RouteNames.assistantDashboard,
  };

  /// Areas an assistant can open given their current permission grants.
  static List<AdminWorkspaceArea> forAssistantGrants(
    bool Function(String key) hasPermission,
  ) {
    bool allowed(AdminWorkspaceArea area) => switch (area.id) {
      'users' ||
      'patients' => hasPermission(AssistantPermissions.canCreateUsers),
      'approvals' => hasPermission(
        AssistantPermissions.canApproveHealthworkers,
      ),
      // The merged screen serves both grants: request triage needs
      // can_manage_care_requests, the assignments tab needs
      // can_assign_patients. Either one earns the entry.
      'care_requests' =>
        hasPermission(AssistantPermissions.canManageCareRequests) ||
            hasPermission(AssistantPermissions.canAssignPatients),
      'audit' => hasPermission(AssistantPermissions.canViewActivityLogs),
      'announcements' => hasPermission(
        AssistantPermissions.canManageAdvertising,
      ),
      'security' => hasPermission(
        AssistantPermissions.canViewSecurityIncidents,
      ),
      'sos' => hasPermission(AssistantPermissions.canAccessEmergencyLocation),
      'vital_catalog' => hasPermission(
        AssistantPermissions.canManageVitalCatalog,
      ),
      'support' || 'alerts' || 'messages' || 'notifications' => true,
      _ => false,
    };

    return areas.where(allowed).toList();
  }
}

/// Live operational counts for admin badge chips.
///
/// Always use static getters, e.g. `AdminWorkspaceCounts.pendingApprovals`.
/// Do **not** write `final c = AdminWorkspaceCounts` — that stores the [Type],
/// not a counts snapshot.
class AdminWorkspaceCounts {
  AdminWorkspaceCounts._();

  static int badgeFor(String? key) {
    if (key == null) return 0;
    return switch (key) {
      'approvals' =>
        StaffState.instance.approvals
            .where((a) => a.status == 'pending')
            .length,
      'care_requests' =>
        StaffState.instance.careRequests
            .where((r) => r.status == 'pending')
            .length,
      'alerts' =>
        StaffState.instance.alerts
            .where((a) => !a.acknowledged && !a.resolved)
            .length,
      'sos' => StaffState.instance.patientSos.where((e) => e.isActive).length,
      'support' =>
        SupportState.instance.all
            .where(
              (t) =>
                  t.status == TicketStatus.open ||
                  t.status == TicketStatus.inProgress,
            )
            .length,
      _ => 0,
    };
  }

  static int get pendingApprovals => badgeFor('approvals');
  static int get pendingCareRequests => badgeFor('care_requests');
  static int get openAlerts => badgeFor('alerts');
  static int get activeSos => badgeFor('sos');
  static int get openSupport => badgeFor('support');

  static int get totalAttention =>
      pendingApprovals +
      pendingCareRequests +
      openAlerts +
      activeSos +
      openSupport;

  static int activePatients() => StaffState.instance.users
      .where((u) => u.role == UserRole.patient && u.status == 'active')
      .length;
}
