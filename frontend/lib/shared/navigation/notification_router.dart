import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/notification_item.dart';
import '../models/user_role.dart';
import '../models/vital.dart';
import '../state/notification_state.dart';
import 'sos_navigation.dart';

/// Routes notification taps to the correct screen (shared across roles).
class NotificationRouter {
  NotificationRouter._();

  static void handleTap(BuildContext context, AppNotification n) {
    if (!n.resolved) {
      NotificationState.instance.markReadRemote(n.id);
    }
    if (n.kind == NotificationKind.sos) {
      SosNavigation.openFromNotification(context, n);
      return;
    }
    final role = AuthState.instance.user?.role;
    final route = n.actionRoute ?? _defaultRoute(n, role);
    if (route == null) return;
    Navigator.of(context).pushNamed(route, arguments: n.actionArguments);
  }

  static String? _defaultRoute(AppNotification n, UserRole? role) {
    return switch (role) {
      UserRole.doctor => _doctorRoute(n),
      UserRole.admin => _adminRoute(n),
      UserRole.mcareAssistant => _assistantRoute(n),
      UserRole.patient || null => _patientRoute(n),
      UserRole.externalDoctor => RouteNames.externalDoctor,
      UserRole.guest => null,
    };
  }

  static String? _patientRoute(AppNotification n) => switch (n.kind) {
        NotificationKind.vitalAlert =>
          n.linkedVital != null
              ? RouteNames.patientVitalDetail
              : RouteNames.patientVitals,
        NotificationKind.appointment => RouteNames.patientAppointments,
        NotificationKind.medication => RouteNames.patientMedications,
        NotificationKind.message => RouteNames.patientMessages,
        NotificationKind.document => RouteNames.patientDocuments,
        NotificationKind.report => RouteNames.patientDocuments,
        NotificationKind.careRequest => RouteNames.patientCareTeam,
        NotificationKind.sos => RouteNames.patientSos,
        NotificationKind.approval => RouteNames.pendingApproval,
        NotificationKind.assignment => RouteNames.patientCareTeam,
        NotificationKind.profile => RouteNames.patientProfile,
        NotificationKind.consent => RouteNames.patientReportConsents,
        NotificationKind.system => RouteNames.patientNotifications,
      };

  static String? _doctorRoute(AppNotification n) => switch (n.kind) {
        NotificationKind.vitalAlert => RouteNames.doctorAlerts,
        NotificationKind.appointment => RouteNames.doctorAppointments,
        NotificationKind.medication => RouteNames.doctorPrescriptions,
        NotificationKind.message => RouteNames.doctorMessages,
        NotificationKind.document => RouteNames.doctorReports,
        NotificationKind.report => RouteNames.doctorReports,
        NotificationKind.careRequest => RouteNames.doctorPatients,
        NotificationKind.sos => RouteNames.doctorSos,
        NotificationKind.approval => RouteNames.pendingApproval,
        NotificationKind.assignment => RouteNames.doctorPatients,
        NotificationKind.profile => RouteNames.doctorProfile,
        NotificationKind.consent => RouteNames.doctorReports,
        NotificationKind.system => RouteNames.doctorNotifications,
      };

  static String? _adminRoute(AppNotification n) => switch (n.kind) {
        NotificationKind.vitalAlert => RouteNames.adminAnalytics,
        NotificationKind.appointment => RouteNames.adminCareRequests,
        NotificationKind.medication => RouteNames.adminUsers,
        NotificationKind.message => RouteNames.adminMessages,
        NotificationKind.document => RouteNames.adminAudit,
        NotificationKind.report => RouteNames.adminAudit,
        NotificationKind.careRequest => RouteNames.adminCareRequests,
        NotificationKind.sos => RouteNames.adminSos,
        NotificationKind.approval => RouteNames.adminApprovals,
        // Assignments live on the merged care-requests screen.
        NotificationKind.assignment => RouteNames.adminCareRequests,
        NotificationKind.profile => RouteNames.adminProfile,
        NotificationKind.consent => RouteNames.adminPatients,
        NotificationKind.system => RouteNames.adminNotifications,
      };

  static String? _assistantRoute(AppNotification n) => switch (n.kind) {
        NotificationKind.vitalAlert => RouteNames.assistantAlerts,
        NotificationKind.appointment => RouteNames.assistantCareRequests,
        NotificationKind.medication => RouteNames.assistantUsers,
        NotificationKind.message => RouteNames.assistantMessages,
        NotificationKind.document => RouteNames.assistantAudit,
        NotificationKind.report => RouteNames.assistantAudit,
        NotificationKind.careRequest => RouteNames.assistantCareRequests,
        NotificationKind.sos => RouteNames.assistantSos,
        NotificationKind.approval => RouteNames.assistantApprovals,
        NotificationKind.assignment => RouteNames.assistantCareRequests,
        NotificationKind.profile => RouteNames.assistantProfile,
        NotificationKind.consent => RouteNames.assistantPatients,
        NotificationKind.system => RouteNames.assistantNotifications,
      };

  /// Convenience for vital alerts that open a specific vital detail.
  static Object? vitalDetailArgs(VitalKey key) => key;
}
