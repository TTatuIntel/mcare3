import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import 'root_navigator.dart';

/// Routes that act as app "homes" — no back affordance after correct navigation.
///
/// Intentionally depends only on [RouteNames] (no staff/patient widget imports)
/// to avoid circular imports on web release builds.
class NavigationRoots {
  NavigationRoots._();

  /// Primary tab dashboards — avatar header only (no back, no drill-down chrome).
  static const Set<String> primaryHomeRoutes = {
    RouteNames.patientDashboard,
    RouteNames.doctorDashboard,
    RouteNames.adminDashboard,
    RouteNames.assistantDashboard,
  };

  static const Set<String> _patient = {
    RouteNames.patientDashboard,
    // Bottom-nav hubs — tab peers of the dashboard, like the admin rail's
    // Work/People/More, so they carry no back chip.
    RouteNames.patientHealth,
    RouteNames.patientCare,
    RouteNames.patientMore,
    RouteNames.patientVitals,
    RouteNames.patientMedications,
    RouteNames.patientAppointments,
    RouteNames.patientMessages,
    RouteNames.patientDocuments,
    RouteNames.patientCareTeam,
    RouteNames.patientNotifications,
    RouteNames.patientProfile,
    RouteNames.patientSettings,
    RouteNames.patientSupport,
    RouteNames.patientSos,
  };

  static const Set<String> _staff = {
    // Doctor bottom nav + common staff roots
    RouteNames.doctorDashboard,
    RouteNames.doctorPatients,
    RouteNames.doctorAppointments,
    RouteNames.doctorMessages,
    RouteNames.doctorOverview,
    RouteNames.doctorVitals,
    RouteNames.doctorInbox,
    RouteNames.doctorAlerts,
    RouteNames.doctorVisits,
    RouteNames.doctorPrescriptions,
    RouteNames.doctorReports,
    RouteNames.doctorNotifications,
    RouteNames.doctorProfile,
    RouteNames.doctorSettings,
    RouteNames.doctorSos,
    // Admin rail
    RouteNames.adminDashboard,
    RouteNames.adminWork,
    RouteNames.adminPeople,
    RouteNames.adminMore,
    // People-tab drill-downs (Patients / Users / Approvals / CareRequests /
    // Assignments) are intentionally NOT root routes — they're pushed from the
    // Guided Operations Hub's People tab and must show a back chip so the user
    // can return to that hub instead of being stranded on a directory screen.
    RouteNames.adminVitalCatalog,
    RouteNames.adminPermissions,
    RouteNames.adminSupport,
    RouteNames.adminAudit,
    RouteNames.adminAnalytics,
    RouteNames.adminSystem,
    RouteNames.adminMessages,
    RouteNames.adminAnnouncements,
    RouteNames.adminSecurity,
    RouteNames.adminSos,
    RouteNames.adminProfile,
    RouteNames.adminSettings,
    RouteNames.adminNotifications,
    RouteNames.adminAlerts,
    RouteNames.adminCompleteProfile,
    // Assistant rail
    RouteNames.assistantDashboard,
    RouteNames.assistantWork,
    RouteNames.assistantPeople,
    RouteNames.assistantMore,
    // People-tab drill-downs — same reason as the admin equivalents above.
    RouteNames.assistantSupport,
    RouteNames.assistantAudit,
    RouteNames.assistantAnalytics,
    RouteNames.assistantAlerts,
    RouteNames.assistantMessages,
    RouteNames.assistantNotifications,
    RouteNames.assistantSettings,
    RouteNames.assistantProfile,
    RouteNames.assistantCompleteProfile,
    RouteNames.assistantForcePassword,
    RouteNames.assistantSos,
    RouteNames.assistantVitalCatalog,
    RouteNames.assistantAnnouncements,
    RouteNames.assistantSecurity,
    // Staff force-password / complete-profile (doctor + admin)
    RouteNames.doctorCompleteProfile,
    RouteNames.doctorForcePassword,
    RouteNames.adminForcePassword,
    // Auth / onboarding roots
    RouteNames.patientOnboarding,
    RouteNames.patientForcePassword,
    RouteNames.pendingApproval,
    RouteNames.home,
    RouteNames.landing,
    RouteNames.login,
  };

  static bool isRootRoute(String? route) {
    final name = _normalize(route);
    if (name == null) return false;
    return _patient.contains(name) || _staff.contains(name);
  }

  static bool isPrimaryHome(String? route) {
    final name = _normalize(route);
    return name != null && primaryHomeRoutes.contains(name);
  }

  /// Resolve the active route from explicit param, navigator, or tracker.
  static String? resolveRoute(BuildContext context, String? currentRoute) {
    return _normalize(currentRoute) ??
        _normalize(ModalRoute.of(context)?.settings.name) ??
        _normalize(AppRouteTracker.currentRouteName);
  }

  /// After landing on a root tab, collapse leftover stack so back never appears.
  ///
  /// IMPORTANT: this removes the routes *below* the current root tab, making it
  /// the sole entry (a tab switch). It must NOT pop the current route.
  ///
  /// The previous implementation called `popUntil((r) => r.isFirst)`, which
  /// popped the freshly-pushed root route and kept the dashboard underneath —
  /// so every `pushNamed(rootRoute)` (profile menu, dashboard quick actions,
  /// and all cross-links) bounced straight back to the dashboard. That is the
  /// "the page opens then instantly closes / never shows" bug.
  static void ensureCleanRootStack(BuildContext context, String route) {
    if (!isRootRoute(route)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final navigator = Navigator.of(context);
      final current = ModalRoute.of(context);
      if (current == null) return;
      // Strip every route beneath the current root tab. Guard the loop on both
      // `isFirst` (nothing left below) and `canPop` (defensive) so we never
      // touch the current route itself.
      while (!current.isFirst && navigator.canPop()) {
        navigator.removeRouteBelow(current);
      }
    });
  }

  /// Back is for drill-down screens only — never on tab/home roots.
  ///
  /// Also returns true for drill-down routes that have a known parent even
  /// when [canPop] is false (e.g. the user landed here from a deep-link or a
  /// hard page refresh) — the smart back handler will fall back to
  /// [parentFor] in that case.
  static bool shouldShowBack({
    required bool canPop,
    String? currentRoute,
    BuildContext? context,
  }) {
    final route = context != null
        ? resolveRoute(context, currentRoute)
        : _normalize(currentRoute);
    if (isRootRoute(route) || isPrimaryHome(route)) return false;
    if (canPop) return true;
    return parentFor(route) != null;
  }

  /// Parent hub route for a drill-down. Used as a fallback when the pop
  /// stack is empty (deep link / refresh) so back always has somewhere to go.
  static String? parentFor(String? route) {
    final name = _normalize(route);
    if (name == null) return null;
    return _parentMap[name];
  }

  /// Pop when possible, otherwise navigate to the drill-down's parent hub.
  /// If neither is available, falls back to the role's primary home so the
  /// user is never stranded.
  static void smartBack(BuildContext context, {String? currentRoute}) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
      return;
    }
    final route = resolveRoute(context, currentRoute);
    final parent = parentFor(route) ?? _homeFallbackFor(route);
    if (parent == null) return;
    navigator.pushReplacementNamed(parent);
  }

  static String? _homeFallbackFor(String? route) {
    final name = _normalize(route);
    if (name == null) return null;
    if (name.startsWith('/admin')) return RouteNames.adminDashboard;
    if (name.startsWith('/assistant')) return RouteNames.assistantDashboard;
    if (name.startsWith('/doctor')) return RouteNames.doctorDashboard;
    if (name.startsWith('/patient')) return RouteNames.patientDashboard;
    return null;
  }

  /// Static map of drill-down → parent tab / hub route. Kept close to the
  /// [StaffDestinations] `activeRoutes` groupings so back always lands on the
  /// tab that originally exposed the screen.
  static const Map<String, String> _parentMap = {
    // ----- Admin People tab -----
    RouteNames.adminPatients: RouteNames.adminPeople,
    RouteNames.adminUsers: RouteNames.adminPeople,
    RouteNames.adminUserDetail: RouteNames.adminUsers,
    RouteNames.adminPermissions: RouteNames.adminPeople,
    RouteNames.adminApprovals: RouteNames.adminWork,
    RouteNames.adminCareRequests: RouteNames.adminWork,
    RouteNames.adminAssignments: RouteNames.adminWork,
    // ----- Admin Work tab -----
    RouteNames.adminSos: RouteNames.adminWork,
    RouteNames.adminSupport: RouteNames.adminWork,
    RouteNames.adminAlerts: RouteNames.adminWork,
    RouteNames.adminMessages: RouteNames.adminWork,
    RouteNames.adminChatThread: RouteNames.adminMessages,
    // ----- Admin More tab -----
    RouteNames.adminVitalCatalog: RouteNames.adminMore,
    RouteNames.adminAudit: RouteNames.adminMore,
    RouteNames.adminAnalytics: RouteNames.adminMore,
    RouteNames.adminSystem: RouteNames.adminMore,
    RouteNames.adminAnnouncements: RouteNames.adminMore,
    RouteNames.adminSecurity: RouteNames.adminMore,
    RouteNames.adminNotifications: RouteNames.adminMore,
    RouteNames.adminProfile: RouteNames.adminMore,
    RouteNames.adminSettings: RouteNames.adminMore,

    // ----- Assistant People tab -----
    RouteNames.assistantPatients: RouteNames.assistantPeople,
    RouteNames.assistantUsers: RouteNames.assistantPeople,
    RouteNames.assistantUserDetail: RouteNames.assistantUsers,
    // ----- Assistant Work tab -----
    RouteNames.assistantApprovals: RouteNames.assistantWork,
    RouteNames.assistantCareRequests: RouteNames.assistantWork,
    RouteNames.assistantAssignments: RouteNames.assistantWork,
    RouteNames.assistantSupport: RouteNames.assistantWork,
    RouteNames.assistantAlerts: RouteNames.assistantWork,
    RouteNames.assistantMessages: RouteNames.assistantWork,
    RouteNames.assistantChatThread: RouteNames.assistantMessages,
    RouteNames.assistantSos: RouteNames.assistantWork,
    // ----- Assistant More tab -----
    RouteNames.assistantVitalCatalog: RouteNames.assistantMore,
    RouteNames.assistantAudit: RouteNames.assistantMore,
    RouteNames.assistantAnalytics: RouteNames.assistantMore,
    RouteNames.assistantAnnouncements: RouteNames.assistantMore,
    RouteNames.assistantSecurity: RouteNames.assistantMore,
    RouteNames.assistantNotifications: RouteNames.assistantMore,
    RouteNames.assistantProfile: RouteNames.assistantMore,
    RouteNames.assistantSettings: RouteNames.assistantMore,

    // ----- Patient drill-downs -----
    // Reached by pushing from a list, so back normally just pops. These only
    // matter on a deep link or a web refresh, where the stack is empty: they
    // send back to the list the row came from instead of the dashboard.
    RouteNames.patientVitalDetail: RouteNames.patientVitals,
    RouteNames.patientVitalHistory: RouteNames.patientVitals,
    RouteNames.patientVital7Day: RouteNames.patientVitals,
    RouteNames.patientMedicationDetail: RouteNames.patientMedications,
    RouteNames.patientAppointmentDetail: RouteNames.patientAppointments,
    RouteNames.patientChatThread: RouteNames.patientMessages,
    RouteNames.patientTicketDetail: RouteNames.patientSupport,

    // ----- Doctor drill-downs -----
    RouteNames.doctorAlerts: RouteNames.doctorInbox,
    RouteNames.doctorAlertDetail: RouteNames.doctorAlerts,
    RouteNames.doctorVisits: RouteNames.doctorInbox,
    RouteNames.doctorAppointments: RouteNames.doctorInbox,
    RouteNames.doctorPrescriptions: RouteNames.doctorInbox,
    RouteNames.doctorReports: RouteNames.doctorInbox,
    RouteNames.doctorReportEditor: RouteNames.doctorReports,
    RouteNames.doctorMessages: RouteNames.doctorInbox,
    RouteNames.doctorChatThread: RouteNames.doctorMessages,
    RouteNames.doctorSos: RouteNames.doctorInbox,
    RouteNames.doctorPatientChart: RouteNames.doctorPatients,
    RouteNames.doctorOverview: RouteNames.doctorMore,
    RouteNames.doctorVitals: RouteNames.doctorMore,
    RouteNames.doctorVitalTemplate: RouteNames.doctorVitals,
    RouteNames.doctorNotifications: RouteNames.doctorMore,
    RouteNames.doctorProfile: RouteNames.doctorMore,
    RouteNames.doctorSettings: RouteNames.doctorMore,
  };

  static String? _normalize(String? route) {
    if (route == null || route.isEmpty) return null;
    return route;
  }
}
