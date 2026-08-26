import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../dashboard/admin_workspace_catalog.dart';
import '../navigation/role_nav_destination.dart';
import '../widgets/app_icons.dart';

/// Approved task-based navigation for every authenticated staff experience.
///
/// Existing named routes remain valid and are mapped into one of four parent
/// destinations. This keeps bookmarks and feature workflows functional while
/// removing the previous backend-shaped list of peer navigation items.
class StaffDestinations {
  StaffDestinations._();

  static List<RoleNavDestination> doctor() => const [
    RoleNavDestination(
      icon: AppIcons.home,
      label: 'Home',
      route: RouteNames.doctorDashboard,
    ),
    RoleNavDestination(
      icon: AppIcons.assignments,
      label: 'Work',
      route: RouteNames.doctorInbox,
      activeRoutes: {
        RouteNames.doctorInbox,
        RouteNames.doctorAlerts,
        RouteNames.doctorAlertDetail,
        RouteNames.doctorVisits,
        RouteNames.doctorAppointments,
        RouteNames.doctorPrescriptions,
        RouteNames.doctorReports,
        RouteNames.doctorReportEditor,
        RouteNames.doctorMessages,
        RouteNames.doctorChatThread,
        RouteNames.doctorSos,
      },
    ),
    RoleNavDestination(
      icon: AppIcons.patients,
      label: 'Patients',
      route: RouteNames.doctorPatients,
      activeRoutes: {RouteNames.doctorPatients, RouteNames.doctorPatientChart},
    ),
    RoleNavDestination(
      icon: AppIcons.more,
      label: 'More',
      route: RouteNames.doctorMore,
      activeRoutes: {
        RouteNames.doctorMore,
        RouteNames.doctorOverview,
        RouteNames.doctorVitals,
        RouteNames.doctorVitalTemplate,
        RouteNames.doctorNotifications,
        RouteNames.doctorProfile,
        RouteNames.doctorSettings,
      },
    ),
  ];

  static List<RoleNavDestination> admin() {
    final workCount =
        AdminWorkspaceCounts.openAlerts +
        AdminWorkspaceCounts.openSupport +
        AdminWorkspaceCounts.pendingApprovals +
        AdminWorkspaceCounts.pendingCareRequests +
        AdminWorkspaceCounts.activeSos;

    return [
      const RoleNavDestination(
        icon: AppIcons.home,
        label: 'Home',
        route: RouteNames.adminDashboard,
      ),
      RoleNavDestination(
        icon: AppIcons.assignments,
        label: 'Work',
        route: RouteNames.adminWork,
        badgeCount: workCount > 0 ? workCount : null,
        activeRoutes: const {
          RouteNames.adminWork,
          RouteNames.adminSos,
          RouteNames.adminApprovals,
          RouteNames.adminCareRequests,
          RouteNames.adminAssignments,
          RouteNames.adminSupport,
          RouteNames.adminAlerts,
          RouteNames.adminMessages,
          RouteNames.adminChatThread,
        },
      ),
      const RoleNavDestination(
        icon: AppIcons.users,
        label: 'People',
        route: RouteNames.adminPeople,
        activeRoutes: {
          RouteNames.adminPeople,
          RouteNames.adminPatients,
          RouteNames.adminUsers,
          RouteNames.adminUserDetail,
          RouteNames.adminPermissions,
        },
      ),
      const RoleNavDestination(
        icon: AppIcons.more,
        label: 'More',
        route: RouteNames.adminMore,
        activeRoutes: {
          RouteNames.adminMore,
          RouteNames.adminVitalCatalog,
          RouteNames.adminAudit,
          RouteNames.adminAnalytics,
          RouteNames.adminSystem,
          RouteNames.adminAnnouncements,
          RouteNames.adminSecurity,
          RouteNames.adminNotifications,
          RouteNames.adminProfile,
          RouteNames.adminSettings,
        },
      ),
    ];
  }

  static List<RoleNavDestination> assistant() {
    final has = AuthState.instance.hasAssistantPermission;
    final canSeePeople =
        has(AssistantPermissions.canCreateUsers) ||
        has(AssistantPermissions.canAssignPatients);
    final workCount =
        AdminWorkspaceCounts.openAlerts +
        AdminWorkspaceCounts.openSupport +
        (has(AssistantPermissions.canApproveHealthworkers)
            ? AdminWorkspaceCounts.pendingApprovals
            : 0) +
        (has(AssistantPermissions.canManageCareRequests)
            ? AdminWorkspaceCounts.pendingCareRequests
            : 0) +
        (has(AssistantPermissions.canAccessEmergencyLocation)
            ? AdminWorkspaceCounts.activeSos
            : 0);

    return [
      const RoleNavDestination(
        icon: AppIcons.home,
        label: 'Home',
        route: RouteNames.assistantDashboard,
      ),
      RoleNavDestination(
        icon: AppIcons.assignments,
        label: 'Work',
        route: RouteNames.assistantWork,
        badgeCount: workCount > 0 ? workCount : null,
        activeRoutes: const {
          RouteNames.assistantWork,
          RouteNames.assistantApprovals,
          RouteNames.assistantCareRequests,
          RouteNames.assistantAssignments,
          RouteNames.assistantSupport,
          RouteNames.assistantAlerts,
          RouteNames.assistantMessages,
          RouteNames.assistantChatThread,
          RouteNames.assistantSos,
        },
      ),
      if (canSeePeople)
        const RoleNavDestination(
          icon: AppIcons.users,
          label: 'People',
          route: RouteNames.assistantPeople,
          activeRoutes: {
            RouteNames.assistantPeople,
            RouteNames.assistantPatients,
            RouteNames.assistantUsers,
            RouteNames.assistantUserDetail,
          },
        ),
      const RoleNavDestination(
        icon: AppIcons.more,
        label: 'More',
        route: RouteNames.assistantMore,
        activeRoutes: {
          RouteNames.assistantMore,
          RouteNames.assistantVitalCatalog,
          RouteNames.assistantAudit,
          RouteNames.assistantAnalytics,
          RouteNames.assistantAnnouncements,
          RouteNames.assistantSecurity,
          RouteNames.assistantNotifications,
          RouteNames.assistantProfile,
          RouteNames.assistantSettings,
        },
      ),
    ];
  }
}
