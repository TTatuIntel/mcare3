import 'package:flutter/material.dart';

import '../shared/widgets/admin_screens/admin_screens.dart';
import '../admin/analytics/admin_analytics_view.dart';
// The shared barrel deliberately re-exports only AssignmentsScreen, so the
// redirect widget has to come from its defining library directly.
import '../admin/assignments/admin_assignments_view.dart';
import '../admin/users/admin_users_view.dart';
import '../admin/patients/admin_patients_view.dart';
import '../shared/vitals/vital_catalog_screen.dart';
import '../shared/auth/auth_state.dart';
import '../shared/constants/route_names.dart';
import '../shared/navigation/staff_destinations.dart';
import '../shared/staff/staff_alerts_screen.dart';
import '../shared/sos/staff_sos_hub_view.dart';
import '../shared/widgets/permission_gate.dart';

// ---------------------------------------------------------------------------
// Assistant view wrappers.
//
// Every assistant screen reuses an admin/shared implementation and adds:
//   • A PermissionGate against the assistant's grant set.
//   • Assistant routing constants (destinations / profile / notifications).
//
// The `_gate` helper collapses that repeated shape so each wrapper below is a
// single expression, and drift between (permissionKey, currentRoute, title)
// is impossible.
// ---------------------------------------------------------------------------

Widget _gate({
  required String permissionKey,
  required String currentRoute,
  required String title,
  required Widget child,
}) => PermissionGate(
  permissionKey: permissionKey,
  currentRoute: currentRoute,
  title: title,
  child: child,
);

class AssistantApprovalsView extends StatelessWidget {
  const AssistantApprovalsView({super.key});
  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canApproveHealthworkers,
    currentRoute: RouteNames.assistantApprovals,
    title: 'Healthworker approvals',
    child: ApprovalsScreen(
      currentRoute: RouteNames.assistantApprovals,
      destinations: StaffDestinations.assistant(),
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
    ),
  );
}

/// The merged care workspace. Each half carries its own grant, so this gates
/// on whichever the assistant holds and hides the other side.
class AssistantCareRequestsView extends StatelessWidget {
  const AssistantCareRequestsView({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AuthState.instance,
    builder: (context, _) {
      final has = AuthState.instance.hasAssistantPermission;
      final canTriage = has(AssistantPermissions.canManageCareRequests);
      final canAssign = has(AssistantPermissions.canAssignPatients);

      return _gate(
        // With only can_assign_patients the assignments tab is still
        // reachable, so gate against the grant they actually hold.
        permissionKey: canTriage
            ? AssistantPermissions.canManageCareRequests
            : AssistantPermissions.canAssignPatients,
        currentRoute: RouteNames.assistantCareRequests,
        title: canTriage ? 'Care requests' : 'Care assignments',
        child: CareRequestsScreen(
          currentRoute: RouteNames.assistantCareRequests,
          destinations: StaffDestinations.assistant(),
          profileRoute: RouteNames.assistantProfile,
          notificationsRoute: RouteNames.assistantNotifications,
          canTriage: canTriage,
          canAssign: canAssign,
        ),
      );
    },
  );
}

/// PAGE REMOVED — assignments now live inside [AssistantCareRequestsView].
/// The route survives only to redirect existing links.
class AssistantAssignmentsView extends StatelessWidget {
  const AssistantAssignmentsView({super.key});
  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canAssignPatients,
    currentRoute: RouteNames.assistantAssignments,
    title: 'Assignments',
    child: MergedAssignmentsRedirect(
      target: RouteNames.assistantCareRequests,
      currentRoute: RouteNames.assistantAssignments,
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
      canTriage: AuthState.instance.hasAssistantPermission(
        AssistantPermissions.canManageCareRequests,
      ),
    ),
  );
}

class AssistantUsersView extends StatelessWidget {
  const AssistantUsersView({super.key});
  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canCreateUsers,
    currentRoute: RouteNames.assistantUsers,
    title: 'Users',
    child: const AdminUsersView(),
  );
}

class AssistantPatientsView extends StatelessWidget {
  const AssistantPatientsView({super.key});
  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canCreateUsers,
    currentRoute: RouteNames.assistantPatients,
    title: 'Patients',
    child: const AdminPatientsView(assistantMode: true),
  );
}

class AssistantUserDetailView extends StatelessWidget {
  const AssistantUserDetailView({super.key, required this.userId});
  final String userId;
  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canCreateUsers,
    currentRoute: RouteNames.assistantUserDetail,
    title: 'User detail',
    child: AdminUserDetailView(userId: userId),
  );
}

class AssistantAuditView extends StatelessWidget {
  const AssistantAuditView({super.key});
  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canViewActivityLogs,
    currentRoute: RouteNames.assistantAudit,
    title: 'Audit log',
    child: AuditScreen(
      currentRoute: RouteNames.assistantAudit,
      destinations: StaffDestinations.assistant(),
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
    ),
  );
}

class AssistantAnnouncementsView extends StatelessWidget {
  const AssistantAnnouncementsView({super.key});
  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canManageAdvertising,
    currentRoute: RouteNames.assistantAnnouncements,
    title: 'Announcements',
    child: AnnouncementsScreen(
      currentRoute: RouteNames.assistantAnnouncements,
      destinations: StaffDestinations.assistant(),
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
    ),
  );
}

class AssistantSecurityView extends StatelessWidget {
  const AssistantSecurityView({super.key});
  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canViewSecurityIncidents,
    currentRoute: RouteNames.assistantSecurity,
    title: 'Security incidents',
    child: SecurityIncidentsScreen(
      currentRoute: RouteNames.assistantSecurity,
      destinations: StaffDestinations.assistant(),
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
    ),
  );
}

class AssistantSupportView extends StatelessWidget {
  const AssistantSupportView({super.key});
  @override
  Widget build(BuildContext context) => SupportQueueScreen(
    currentRoute: RouteNames.assistantSupport,
    destinations: StaffDestinations.assistant(),
    profileRoute: RouteNames.assistantProfile,
    notificationsRoute: RouteNames.assistantNotifications,
  );
}

class AssistantAlertsView extends StatelessWidget {
  const AssistantAlertsView({super.key});
  @override
  Widget build(BuildContext context) => StaffAlertsScreen(
    currentRoute: RouteNames.assistantAlerts,
    destinations: StaffDestinations.assistant(),
    profileRoute: RouteNames.assistantProfile,
    notificationsRoute: RouteNames.assistantNotifications,
  );
}

/// SOS emergency hub — gated by [AssistantPermissions.canAccessEmergencyLocation]
/// because SOS reveals live GPS coordinates.
class AssistantSosView extends StatelessWidget {
  const AssistantSosView({
    super.key,
    this.initialPatientId,
    this.initialEventId,
  });
  final String? initialPatientId;
  final String? initialEventId;

  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canAccessEmergencyLocation,
    currentRoute: RouteNames.assistantSos,
    title: 'Emergency SOS',
    child: StaffSosHubView(
      initialPatientId: initialPatientId,
      initialEventId: initialEventId,
    ),
  );
}

class AssistantVitalCatalogView extends StatelessWidget {
  const AssistantVitalCatalogView({super.key});

  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canManageVitalCatalog,
    currentRoute: RouteNames.assistantVitalCatalog,
    title: 'Vital catalog',
    child: VitalCatalogScreen.assistant(),
  );
}

class AssistantAnalyticsView extends StatelessWidget {
  const AssistantAnalyticsView({super.key});

  @override
  Widget build(BuildContext context) => _gate(
    permissionKey: AssistantPermissions.canViewActivityLogs,
    currentRoute: RouteNames.assistantAnalytics,
    title: 'Analytics',
    child: AdminAnalyticsView(
      currentRoute: RouteNames.assistantAnalytics,
      destinations: StaffDestinations.assistant(),
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
    ),
  );
}
