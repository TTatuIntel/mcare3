import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/support_ticket.dart';
import '../models/user_role.dart';
import '../state/staff_state.dart';
import '../state/support_state.dart';
import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';
import 'staff_hub_models.dart';

/// Builds presentation-only summaries from the existing stores.
///
/// This class intentionally performs no writes and owns no cache. A task tap
/// navigates to the existing feature screen, which remains the single owner of
/// validation, authorization and backend mutations.
class StaffHubData {
  StaffHubData._();

  static StaffHubSnapshot build(UserRole role) {
    assert(role == UserRole.admin || role == UserRole.mcareAssistant);
    final staff = StaffState.instance;
    final canViewPeople =
        role == UserRole.admin ||
        _allowed(role, AssistantPermissions.canCreateUsers) ||
        _allowed(role, AssistantPermissions.canApproveHealthworkers) ||
        _allowed(role, AssistantPermissions.canAssignPatients);
    final canManageRequests =
        role == UserRole.admin ||
        _allowed(role, AssistantPermissions.canApproveHealthworkers) ||
        _allowed(role, AssistantPermissions.canManageCareRequests) ||
        _allowed(role, AssistantPermissions.canAssignPatients);

    final activePatients = canViewPeople
        ? staff.users
              .where(
                (user) =>
                    user.role == UserRole.patient && user.status == 'active',
              )
              .length
        : 0;
    final activeStaff = canViewPeople
        ? staff.users
              .where(
                (user) =>
                    (user.role == UserRole.doctor ||
                        user.role == UserRole.admin ||
                        user.role == UserRole.mcareAssistant) &&
                    user.status == 'active',
              )
              .length
        : 0;

    final patientsTotal = canViewPeople
        ? staff.users.where((u) => u.role == UserRole.patient).length
        : 0;
    final doctorsCount = canViewPeople
        ? staff.users.where((u) => u.role == UserRole.doctor).length
        : 0;
    final adminsCount = canViewPeople
        ? staff.users.where((u) => u.role == UserRole.admin).length
        : 0;
    final assistantsCount = canViewPeople
        ? staff.users.where((u) => u.role == UserRole.mcareAssistant).length
        : 0;
    final pendingCareRequests = canManageRequests
        ? staff.careRequests.where((r) => r.status == 'pending').length
        : 0;
    final pendingApprovals = canManageRequests
        ? staff.approvals.where((a) => a.status == 'pending').length
        : 0;

    return StaffHubSnapshot(
      role: role,
      workItems: _workItems(role),
      peopleLinks: _peopleLinks(role),
      moreLinks: _moreLinks(role),
      activePatients: activePatients,
      activeStaff: activeStaff,
      totalUsers: canViewPeople ? staff.users.length : 0,
      canManageRequests: canManageRequests,
      patientsTotal: patientsTotal,
      doctorsCount: doctorsCount,
      adminsCount: adminsCount,
      assistantsCount: assistantsCount,
      pendingCareRequests: pendingCareRequests,
      pendingApprovals: pendingApprovals,
      peopleRoutes: StaffPeopleRoutes(
        patients: _route(
          role,
          RouteNames.adminPatients,
          RouteNames.assistantPatients,
        ),
        users: _route(role, RouteNames.adminUsers, RouteNames.assistantUsers),
        careRequests: canManageRequests
            ? _route(
                role,
                RouteNames.adminCareRequests,
                RouteNames.assistantCareRequests,
              )
            : null,
        approvals: _allowed(role, AssistantPermissions.canApproveHealthworkers)
            ? _route(
                role,
                RouteNames.adminApprovals,
                RouteNames.assistantApprovals,
              )
            : null,
      ),
    );
  }

  static List<StaffWorkItem> _workItems(UserRole role) {
    final staff = StaffState.instance;
    final items = <StaffWorkItem>[];

    void add({
      required bool visible,
      required StaffWorkItemType type,
      required StaffWorkUrgency urgency,
      required String title,
      required String description,
      required int count,
      required String route,
      required IconData icon,
      required Color color,
      String actionLabel = 'Review',
    }) {
      if (!visible || count == 0) return;
      items.add(
        StaffWorkItem(
          type: type,
          urgency: urgency,
          title: title,
          description: description,
          count: count,
          route: route,
          icon: icon,
          color: color,
          actionLabel: actionLabel,
        ),
      );
    }

    final canEmergency = _allowed(
      role,
      AssistantPermissions.canAccessEmergencyLocation,
    );
    final canApprove = _allowed(
      role,
      AssistantPermissions.canApproveHealthworkers,
    );
    final canCareRequests = _allowed(
      role,
      AssistantPermissions.canManageCareRequests,
    );
    final canAssignments = _allowed(
      role,
      AssistantPermissions.canAssignPatients,
    );

    add(
      visible: canEmergency,
      type: StaffWorkItemType.emergency,
      urgency: StaffWorkUrgency.critical,
      title: 'Respond to active SOS',
      description: 'Open the secure emergency response hub',
      count: staff.patientSos.where((event) => event.isActive).length,
      route: _route(role, RouteNames.adminSos, RouteNames.assistantSos),
      icon: AppIcons.sos,
      color: AppColors.critical,
      actionLabel: 'Respond',
    );

    final criticalAlerts = staff.alerts
        .where(
          (alert) =>
              !alert.resolved &&
              !alert.acknowledged &&
              alert.severity.name == 'critical',
        )
        .length;
    final attentionAlerts = staff.alerts
        .where(
          (alert) =>
              !alert.resolved &&
              !alert.acknowledged &&
              alert.severity.name != 'critical',
        )
        .length;

    add(
      visible: true,
      type: StaffWorkItemType.clinicalAlert,
      urgency: StaffWorkUrgency.critical,
      title: 'Review critical alerts',
      description: 'Items require secure review in the alert workspace',
      count: criticalAlerts,
      route: _route(role, RouteNames.adminAlerts, RouteNames.assistantAlerts),
      icon: AppIcons.alert,
      color: AppColors.critical,
    );

    add(
      visible: true,
      type: StaffWorkItemType.clinicalAlert,
      urgency: StaffWorkUrgency.attention,
      title: 'Review open alerts',
      description: 'Warning alerts are waiting in the alert workspace',
      count: attentionAlerts,
      route: _route(role, RouteNames.adminAlerts, RouteNames.assistantAlerts),
      icon: AppIcons.alert,
      color: AppColors.warning,
    );

    add(
      visible: canApprove,
      type: StaffWorkItemType.approval,
      urgency: StaffWorkUrgency.attention,
      title: 'Review health workers',
      description: 'New or updated profiles are awaiting verification',
      count: staff.approvals
          .where((approval) => approval.status == 'pending')
          .length,
      route: _route(
        role,
        RouteNames.adminApprovals,
        RouteNames.assistantApprovals,
      ),
      icon: AppIcons.approval,
      color: AppColors.adminPurple,
    );

    // Requests and assignments share one screen — approving a request is what
    // creates the assignment — so they share one work item too.
    add(
      visible: canCareRequests || canAssignments,
      type: StaffWorkItemType.careRequest,
      urgency: StaffWorkUrgency.attention,
      title: canCareRequests
          ? 'Review care requests'
          : 'Manage care assignments',
      description: canCareRequests
          ? 'Approve, re-route or decline — then the assignment is automatic'
          : 'Connect patients with their care providers',
      count: canCareRequests
          ? staff.careRequests
                .where((request) => request.status == 'pending')
                .length
          : staff.assignments.length,
      route: _route(
        role,
        RouteNames.adminCareRequests,
        RouteNames.assistantCareRequests,
      ),
      icon: AppIcons.careRequest,
      color: AppColors.info,
    );

    add(
      visible: true,
      type: StaffWorkItemType.support,
      urgency: StaffWorkUrgency.routine,
      title: 'Reply to support tickets',
      description: 'People are waiting for a staff response',
      count: SupportState.instance.all
          .where(
            (ticket) =>
                ticket.status == TicketStatus.open ||
                ticket.status == TicketStatus.inProgress,
          )
          .length,
      route: _route(role, RouteNames.adminSupport, RouteNames.assistantSupport),
      icon: AppIcons.support,
      color: AppColors.info,
      actionLabel: 'Open',
    );

    items.sort((a, b) {
      final urgency = a.urgency.index.compareTo(b.urgency.index);
      return urgency != 0 ? urgency : b.count.compareTo(a.count);
    });
    return items;
  }

  static List<StaffHubLink> _peopleLinks(UserRole role) {
    final staff = StaffState.instance;
    final canManagePeople = _allowed(role, AssistantPermissions.canCreateUsers);
    final canApprove = _allowed(
      role,
      AssistantPermissions.canApproveHealthworkers,
    );
    final canAssign = _allowed(role, AssistantPermissions.canAssignPatients);

    return [
      if (canManagePeople)
        StaffHubLink(
          id: 'patients',
          title: 'Patients',
          description: 'Find patients and open existing profiles',
          route: _route(
            role,
            RouteNames.adminPatients,
            RouteNames.assistantPatients,
          ),
          icon: AppIcons.patients,
          color: AppColors.brandIndigo,
          count: staff.users.where((u) => u.role == UserRole.patient).length,
        ),
      if (canManagePeople)
        StaffHubLink(
          id: 'users',
          title: 'Users',
          description: 'Accounts, access state and role-aware actions',
          route: _route(role, RouteNames.adminUsers, RouteNames.assistantUsers),
          icon: AppIcons.users,
          color: role.accent,
          count: staff.users.length,
        ),
      if (canApprove)
        StaffHubLink(
          id: 'approvals',
          title: 'Health-worker approvals',
          description: 'Verify pending clinician applications',
          route: _route(
            role,
            RouteNames.adminApprovals,
            RouteNames.assistantApprovals,
          ),
          icon: AppIcons.approval,
          color: AppColors.adminPurple,
          count: staff.approvals.where((a) => a.status == 'pending').length,
        ),
      if (canAssign)
        StaffHubLink(
          id: 'assignments',
          title: 'Care assignments',
          description: 'Connect patients with their care providers',
          // Merged into the care-requests workspace, which opens on the
          // assignments tab for staff who only hold can_assign_patients.
          route: _route(
            role,
            RouteNames.adminCareRequests,
            RouteNames.assistantCareRequests,
          ),
          icon: AppIcons.assignments,
          color: AppColors.info,
          count: staff.assignments.length,
        ),
    ];
  }

  static List<StaffHubLink> _moreLinks(UserRole role) {
    bool can(String key) => _allowed(role, key);
    final links = <StaffHubLink>[
      StaffHubLink(
        id: 'messages',
        title: 'Messages',
        description: 'Staff conversations and care coordination',
        route: _route(
          role,
          RouteNames.adminMessages,
          RouteNames.assistantMessages,
        ),
        icon: AppIcons.chat,
        color: AppColors.brandIndigo,
      ),
      StaffHubLink(
        id: 'notifications',
        title: 'Notifications',
        description: 'Updates from your current account',
        route: _route(
          role,
          RouteNames.adminNotifications,
          RouteNames.assistantNotifications,
        ),
        icon: AppIcons.bell,
        color: AppColors.info,
      ),
      if (can(AssistantPermissions.canManageAdvertising))
        StaffHubLink(
          id: 'announcements',
          title: 'Announcements',
          description: 'Publish updates through the existing workflow',
          route: _route(
            role,
            RouteNames.adminAnnouncements,
            RouteNames.assistantAnnouncements,
          ),
          icon: AppIcons.announcements,
          color: AppColors.info,
        ),
      if (can(AssistantPermissions.canManageVitalCatalog))
        StaffHubLink(
          id: 'vital_catalog',
          title: 'Vital catalog',
          description: 'Definitions and clinical threshold configuration',
          route: _route(
            role,
            RouteNames.adminVitalCatalog,
            RouteNames.assistantVitalCatalog,
          ),
          icon: AppIcons.catalog,
          color: role.accent,
        ),
      if (can(AssistantPermissions.canViewActivityLogs)) ...[
        StaffHubLink(
          id: 'audit',
          title: 'Audit trail',
          description: 'Review recorded platform activity',
          route: _route(role, RouteNames.adminAudit, RouteNames.assistantAudit),
          icon: AppIcons.audit,
          color: AppColors.textMutedAA,
        ),
        StaffHubLink(
          id: 'analytics',
          title: 'Analytics',
          description: 'Operational counts and established reports',
          route: _route(
            role,
            RouteNames.adminAnalytics,
            RouteNames.assistantAnalytics,
          ),
          icon: AppIcons.analytics,
          color: AppColors.brandIndigo,
        ),
      ],
      if (can(AssistantPermissions.canViewSecurityIncidents))
        StaffHubLink(
          id: 'security',
          title: 'Security',
          description: 'Incidents and existing security review tools',
          route: _route(
            role,
            RouteNames.adminSecurity,
            RouteNames.assistantSecurity,
          ),
          icon: AppIcons.security,
          color: AppColors.critical,
        ),
      if (role == UserRole.admin)
        const StaffHubLink(
          id: 'permissions',
          title: 'Assistant permissions',
          description: 'Delegate approved capabilities',
          route: RouteNames.adminPermissions,
          icon: AppIcons.permissions,
          color: AppColors.adminPurple,
        ),
      if (role == UserRole.admin)
        const StaffHubLink(
          id: 'system',
          title: 'System configuration',
          description: 'Current runtime and platform settings',
          route: RouteNames.adminSystem,
          icon: AppIcons.system,
          color: AppColors.textMutedAA,
        ),
      StaffHubLink(
        id: 'settings',
        title: 'Settings',
        description: 'Appearance, notifications and account preferences',
        route: _route(
          role,
          RouteNames.adminSettings,
          RouteNames.assistantSettings,
        ),
        icon: AppIcons.settings,
        color: role.accent,
      ),
      StaffHubLink(
        id: 'profile',
        title: 'Profile and security',
        description: 'Personal details and password controls',
        route: _route(
          role,
          RouteNames.adminProfile,
          RouteNames.assistantProfile,
        ),
        icon: AppIcons.profile,
        color: role.accent,
      ),
    ];
    return links;
  }

  static bool _allowed(UserRole role, String permission) =>
      role == UserRole.admin ||
      AuthState.instance.hasAssistantPermission(permission);

  static String _route(
    UserRole role,
    String adminRoute,
    String assistantRoute,
  ) => role == UserRole.admin ? adminRoute : assistantRoute;
}
