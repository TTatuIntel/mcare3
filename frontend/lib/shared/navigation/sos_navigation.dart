import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/notification_item.dart';
import '../models/user_role.dart';
import '../../shared/services/doctor_patient_detail_service.dart';

/// Single source of truth for SOS / emergency navigation across all roles.
class SosNavigation {
  SosNavigation._();

  /// Emergency command-center route for the signed-in staff role.
  static String hubRouteFor(UserRole role) => switch (role) {
        UserRole.doctor => RouteNames.doctorSos,
        UserRole.admin => RouteNames.adminSos,
        UserRole.mcareAssistant => RouteNames.assistantSos,
        UserRole.patient => RouteNames.patientSos,
        _ => RouteNames.patientSos,
      };

  static Map<String, String> hubArgs({
    String? patientId,
    String? eventId,
  }) =>
      {
        if (patientId != null) 'patientId': patientId,
        if (eventId != null) 'eventId': eventId,
      };

  static Map<String, dynamic> doctorChartArgs(
    String patientId, {
    bool respond = false,
    String? eventId,
  }) =>
      {
        'patientId': patientId,
        // Matches DoctorPatientSection.sos.name; kept as a literal so shared
        // navigation does not depend on the doctor module's enum.
        'section': 'sos',
        if (respond) 'sosRespond': true,
        if (eventId != null) 'eventId': eventId,
      };

  /// Opens the role-appropriate SOS hub (list + respond controls).
  static void openHub(
    BuildContext context, {
    String? patientId,
    String? eventId,
    UserRole? role,
  }) {
    final r = role ?? AuthState.instance.user?.role;
    if (r == null) return;
    if (r == UserRole.patient) {
      Navigator.of(context).pushNamed(RouteNames.patientSos);
      return;
    }
    Navigator.of(context).pushNamed(
      hubRouteFor(r),
      arguments: hubArgs(patientId: patientId, eventId: eventId),
    );
  }

  /// Opens the best screen to **respond** to a specific patient's SOS.
  static Future<void> openRespond(
    BuildContext context, {
    required String patientId,
    String? eventId,
    UserRole? role,
  }) async {
    final r = role ?? AuthState.instance.user?.role;
    if (r == null || patientId.isEmpty) return;

    switch (r) {
      case UserRole.doctor:
        await DoctorPatientDetailService.instance.loadPatient(patientId);
        if (!context.mounted) return;
        await Navigator.of(context).pushNamed(
          RouteNames.doctorPatientChart,
          arguments: doctorChartArgs(
            patientId,
            respond: true,
            eventId: eventId,
          ),
        );
      case UserRole.admin:
      case UserRole.mcareAssistant:
        openHub(context, patientId: patientId, eventId: eventId, role: r);
      case UserRole.patient:
        Navigator.of(context).pushNamed(RouteNames.patientSos);
      default:
        break;
    }
  }

  /// Notification bell / inbox tap for SOS items.
  static void openFromNotification(BuildContext context, AppNotification n) {
    if (!n.read && !n.resolved) {
      // read handled by caller when needed
    }
    final args = n.actionArguments;
    if (args is Map) {
      final map = Map<String, dynamic>.from(args);
      final patientId = (map['patientId'] ?? '') as String;
      final eventId = map['eventId'] as String?;
      final role = AuthState.instance.user?.role;
      if (role == UserRole.doctor && patientId.isNotEmpty) {
        openRespond(context, patientId: patientId, eventId: eventId, role: role);
      } else if (patientId.isNotEmpty || eventId != null) {
        openHub(context, patientId: patientId, eventId: eventId, role: role);
      } else {
        openHub(context, role: role);
      }
      return;
    }
    if (args is String && args.isNotEmpty) {
      openRespond(context, patientId: args);
      return;
    }
    openHub(context);
  }

  /// Parses route arguments from [Navigator.pushNamed].
  static ({String? patientId, String? eventId}) parseArgs(Object? arguments) {
    if (arguments is Map) {
      return (
        patientId: arguments['patientId'] as String?,
        eventId: arguments['eventId'] as String?,
      );
    }
    if (arguments is String && arguments.isNotEmpty) {
      return (patientId: arguments, eventId: null);
    }
    return (patientId: null, eventId: null);
  }
}
