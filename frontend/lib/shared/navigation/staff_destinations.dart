import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../navigation/role_nav_destination.dart';
import '../widgets/app_icons.dart';
import '../dashboard/admin_workspace_catalog.dart';

/// Single source of truth for the staff nav rail items, per role.
/// Mirrors the §9 documentation. Assistant items declare `permissionKey`
/// so RoleShell can auto-hide them when a permission isn't granted.
class StaffDestinations {
  StaffDestinations._();

  /// Doctor bottom nav: Home · Patients · Appointments · Chat.
  /// Visits, alerts, reports, etc. live in dashboard quick actions.
  static List<RoleNavDestination> doctor() => const [
        RoleNavDestination(
          icon: AppIcons.home,
          label: 'Home',
          route: RouteNames.doctorDashboard,
        ),
        RoleNavDestination(
          icon: AppIcons.patients,
          label: 'Patients',
          route: RouteNames.doctorPatients,
        ),
        RoleNavDestination(
          icon: AppIcons.calendar,
          label: 'Appointments',
          route: RouteNames.doctorAppointments,
        ),
        RoleNavDestination(
          icon: AppIcons.chat,
          label: 'Chat',
          route: RouteNames.doctorMessages,
        ),
      ];

  /// Admin destinations with live operational badge counts.
  static List<RoleNavDestination> admin() {
    return [
      const RoleNavDestination(
        icon: AppIcons.home,
        label: 'Overview',
        route: RouteNames.adminDashboard,
      ),
      const RoleNavDestination(
        icon: AppIcons.patients,
        label: 'Patients',
        route: RouteNames.adminPatients,
      ),
      const RoleNavDestination(
        icon: AppIcons.users,
        label: 'Users',
        route: RouteNames.adminUsers,
      ),
      RoleNavDestination(
        icon: AppIcons.alert,
        label: 'Alerts',
        route: RouteNames.adminAlerts,
        badgeCount: AdminWorkspaceCounts.openAlerts > 0 ? AdminWorkspaceCounts.openAlerts : null,
      ),
      RoleNavDestination(
        icon: AppIcons.support,
        label: 'Support',
        route: RouteNames.adminSupport,
        badgeCount: AdminWorkspaceCounts.openSupport > 0 ? AdminWorkspaceCounts.openSupport : null,
      ),
      RoleNavDestination(
        icon: AppIcons.approval,
        label: 'Approvals',
        route: RouteNames.adminApprovals,
        showInBottomNav: false,
        badgeCount: AdminWorkspaceCounts.pendingApprovals > 0 ? AdminWorkspaceCounts.pendingApprovals : null,
      ),
      RoleNavDestination(
        icon: AppIcons.careRequest,
        label: 'Care requests',
        route: RouteNames.adminCareRequests,
        showInBottomNav: false,
        badgeCount: AdminWorkspaceCounts.pendingCareRequests > 0 ? AdminWorkspaceCounts.pendingCareRequests : null,
      ),
      const RoleNavDestination(
        icon: AppIcons.assignments,
        label: 'Assignments',
        route: RouteNames.adminAssignments,
        showInBottomNav: false,
      ),
      RoleNavDestination(
        icon: AppIcons.sos,
        label: 'SOS',
        route: RouteNames.adminSos,
        showInBottomNav: false,
        badgeCount: AdminWorkspaceCounts.activeSos > 0 ? AdminWorkspaceCounts.activeSos : null,
      ),
      const RoleNavDestination(
        icon: AppIcons.catalog,
        label: 'Vital catalog',
        route: RouteNames.adminVitalCatalog,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.permissions,
        label: 'Permissions',
        route: RouteNames.adminPermissions,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.audit,
        label: 'Audit',
        route: RouteNames.adminAudit,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.announcements,
        label: 'Announcements',
        route: RouteNames.adminAnnouncements,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.security,
        label: 'Security',
        route: RouteNames.adminSecurity,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.analytics,
        label: 'Analytics',
        route: RouteNames.adminAnalytics,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.system,
        label: 'System',
        route: RouteNames.adminSystem,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.settings,
        label: 'Settings',
        route: RouteNames.adminSettings,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.chat,
        label: 'Messages',
        route: RouteNames.adminMessages,
        showInBottomNav: false,
      ),
      const RoleNavDestination(
        icon: AppIcons.bell,
        label: 'Notifications',
        route: RouteNames.adminNotifications,
        showInBottomNav: false,
      ),
    ];
  }

  /// Full assistant destination set — each tagged with the permission flag
  /// it requires. RoleShell auto-hides items whose permission isn't granted.
  static List<RoleNavDestination> assistant() {
    final has = AuthState.instance.hasAssistantPermission;
    return [
      const RoleNavDestination(
        icon: AppIcons.home,
        label: 'Overview',
        route: RouteNames.assistantDashboard,
      ),
      RoleNavDestination(
        icon: AppIcons.patients,
        label: 'Patients',
        route: RouteNames.assistantPatients,
        permissionKey: AssistantPermissions.canCreateUsers,
      ),
      RoleNavDestination(
        icon: AppIcons.approval,
        label: 'Approvals',
        route: RouteNames.assistantApprovals,
        permissionKey: AssistantPermissions.canApproveHealthworkers,
        badgeCount: has(AssistantPermissions.canApproveHealthworkers) &&
                AdminWorkspaceCounts.pendingApprovals > 0
            ? AdminWorkspaceCounts.pendingApprovals
            : null,
      ),
      RoleNavDestination(
        icon: AppIcons.careRequest,
        label: 'Care requests',
        route: RouteNames.assistantCareRequests,
        permissionKey: AssistantPermissions.canManageCareRequests,
        badgeCount: has(AssistantPermissions.canManageCareRequests) &&
                AdminWorkspaceCounts.pendingCareRequests > 0
            ? AdminWorkspaceCounts.pendingCareRequests
            : null,
      ),
      RoleNavDestination(
        icon: AppIcons.assignments,
        label: 'Assignments',
        route: RouteNames.assistantAssignments,
        permissionKey: AssistantPermissions.canAssignPatients,
      ),
      RoleNavDestination(
        icon: AppIcons.users,
        label: 'Users',
        route: RouteNames.assistantUsers,
        permissionKey: AssistantPermissions.canCreateUsers,
      ),
      RoleNavDestination(
        icon: AppIcons.catalog,
        label: 'Vital catalog',
        route: RouteNames.assistantVitalCatalog,
        permissionKey: AssistantPermissions.canManageVitalCatalog,
      ),
      RoleNavDestination(
        icon: AppIcons.sos,
        label: 'SOS',
        route: RouteNames.assistantSos,
        permissionKey: AssistantPermissions.canAccessEmergencyLocation,
        badgeCount: has(AssistantPermissions.canAccessEmergencyLocation) &&
                AdminWorkspaceCounts.activeSos > 0
            ? AdminWorkspaceCounts.activeSos
            : null,
      ),
      RoleNavDestination(
        icon: AppIcons.support,
        label: 'Support',
        route: RouteNames.assistantSupport,
        badgeCount: AdminWorkspaceCounts.openSupport > 0 ? AdminWorkspaceCounts.openSupport : null,
      ),
      RoleNavDestination(
        icon: AppIcons.audit,
        label: 'Audit',
        route: RouteNames.assistantAudit,
        permissionKey: AssistantPermissions.canViewActivityLogs,
      ),
      RoleNavDestination(
        icon: AppIcons.analytics,
        label: 'Analytics',
        route: RouteNames.assistantAnalytics,
        permissionKey: AssistantPermissions.canViewActivityLogs,
        showInBottomNav: false,
      ),
      RoleNavDestination(
        icon: AppIcons.announcements,
        label: 'Announcements',
        route: RouteNames.assistantAnnouncements,
        permissionKey: AssistantPermissions.canManageAdvertising,
      ),
      RoleNavDestination(
        icon: AppIcons.security,
        label: 'Security',
        route: RouteNames.assistantSecurity,
        permissionKey: AssistantPermissions.canViewSecurityIncidents,
      ),
      // Alerts is intentionally un-gated: monitoring vitals alerts is the
      // baseline responsibility of every assistant. SOS above stays gated by
      // canAccessEmergencyLocation because SOS reveals live GPS coordinates.
      RoleNavDestination(
        icon: AppIcons.alert,
        label: 'Alerts',
        route: RouteNames.assistantAlerts,
        badgeCount: AdminWorkspaceCounts.openAlerts > 0
            ? AdminWorkspaceCounts.openAlerts
            : null,
      ),
      const RoleNavDestination(
        icon: AppIcons.chat,
        label: 'Messages',
        route: RouteNames.assistantMessages,
      ),
      const RoleNavDestination(
        icon: AppIcons.bell,
        label: 'Notifications',
        route: RouteNames.assistantNotifications,
      ),
    ];
  }
}
