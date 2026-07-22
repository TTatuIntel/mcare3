import 'package:flutter/material.dart';

import '../../shared/state/staff_state.dart';
import '../../shared/widgets/app_toast.dart';
import 'doctor_appointment_detail_sheet.dart';
import 'doctor_schedule_appointment_sheet.dart';

/// Entry points for doctor appointment workflows.
class DoctorAppointmentFlows {
  DoctorAppointmentFlows._();

  static Future<void> openSchedule(
    BuildContext context, {
    String? patientId,
    String? patientName,
  }) async {
    final patients = StaffState.instance.assignedPatientsForDoctor();
    if (patients.isEmpty) {
      AppToast.show(
        context,
        message: 'No assigned patients yet. Open Patients to manage caseload.',
      );
      return;
    }
    await DoctorScheduleAppointmentSheet.show(
      context,
      patientId: patientId,
      patientName: patientName,
    );
  }

  static Future<void> openDetail(BuildContext context, String appointmentId) {
    return DoctorAppointmentDetailSheet.show(context, appointmentId);
  }
}
