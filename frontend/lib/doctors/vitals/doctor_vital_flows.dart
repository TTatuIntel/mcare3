import 'package:flutter/material.dart';

import '../../shared/state/staff_state.dart';
import '../../shared/widgets/app_toast.dart';
import 'doctor_assign_vitals_sheet.dart';

/// Dashboard and cross-screen entry points for doctor vital workflows.
class DoctorVitalFlows {
  DoctorVitalFlows._();

  static Future<void> openAssignVital(BuildContext context) async {
    final patients = StaffState.instance.assignedPatientsForDoctor();
    if (patients.isEmpty) {
      AppToast.show(
        context,
        message: 'No assigned patients yet. Open Patients to manage caseload.',
      );
      return;
    }
    await DoctorAssignVitalsSheet.show(context);
  }
}
