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
    RouteNames.adminPatients,
    RouteNames.adminUsers,
    RouteNames.adminApprovals,
    RouteNames.adminCareRequests,
    RouteNames.adminAssignments,
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
    RouteNames.assistantPatients,
    RouteNames.assistantApprovals,
    RouteNames.assistantCareRequests,
    RouteNames.assistantAssignments,
    RouteNames.assistantUsers,
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
  static bool shouldShowBack({
    required bool canPop,
    String? currentRoute,
    BuildContext? context,
  }) {
    final route = context != null
        ? resolveRoute(context, currentRoute)
        : _normalize(currentRoute);
    if (isRootRoute(route) || isPrimaryHome(route)) return false;
    return canPop;
  }

  static String? _normalize(String? route) {
    if (route == null || route.isEmpty) return null;
    return route;
  }
}
