import 'package:flutter/material.dart';

import '../../shared/state/staff_state.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/models/vital.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/vitals/doctor_vital_threshold_form.dart';

/// Patient-scoped threshold editor for a single vital.
class DoctorPatientVitalThresholdSheet {
  DoctorPatientVitalThresholdSheet._();

  static Future<void> show({
    required BuildContext context,
    required String patientId,
    required String patientName,
    required VitalKey vital,
  }) async {
    final s = StaffState.instance;
    final current = s.effectiveThresholdFor(patientId, vital);
    final existingOverride = s
        .overridesForPatient(patientId)
        .any((o) => o.vital == vital);

    final result = await GlassSheet.show<VitalThresholdFormResult>(
      context,
      title: 'Thresholds · ${vital.label}',
      subtitle: '$patientName · per-patient override',
      child: VitalThresholdForm(
        vital: vital,
        initial: current,
        existingOverride: existingOverride,
        allowClear: true,
      ),
    );

    if (result == null || context.mounted == false) return;
    if (result.clear) {
      s.clearPatientThreshold(patientId, vital);
      AppToast.show(
        context,
        message: 'Reverted ${vital.label} to default for $patientName.',
      );
      return;
    }

    final actor = AuthState.instance.user;
    s.upsertPatientThreshold(
      patientId: patientId,
      vital: vital,
      normalMin: result.normalMin,
      normalMax: result.normalMax,
      warningLow: result.warningLow,
      warningHigh: result.warningHigh,
      criticalLow: result.criticalLow,
      criticalHigh: result.criticalHigh,
      setBy: actor == null
          ? 'Clinician'
          : 'Dr. ${actor.firstName} ${actor.lastName}',
      note: result.note,
    );
    AppToast.show(
      context,
      message: '${vital.label} thresholds updated for $patientName.',
    );
  }
}
