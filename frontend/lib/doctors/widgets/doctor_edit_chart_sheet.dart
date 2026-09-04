import 'package:flutter/material.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';

String _normSex(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'male':
      return 'Male';
    case 'female':
      return 'Female';
    default:
      return 'Other';
  }
}

/// Clinician chart edit — the doctor/admin counterpart to the patient's
/// own profile editor. Mutates the slim StaffPatient record and emits a
/// notification + audit entry so the patient and care team see who
/// changed what (matches `ProfileService` audit pattern).
void showDoctorEditChartSheet(
  BuildContext context, {
  required String patientId,
}) {
  final patient = StaffState.instance.patientById(patientId);
  if (patient == null) {
    AppToast.error(context, 'Patient not found.');
    return;
  }

  final condition = TextEditingController(text: patient.condition);
  final age = TextEditingController(text: '${patient.age}');
  var sex = _normSex(patient.sex);
  var risk = patient.risk;

  GlassSheet.show(
    context,
    title: 'Edit chart',
    subtitle: patient.name,
    child: Builder(
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Primary condition',
                controller: condition,
                hint: 'e.g. Type 2 diabetes',
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Age',
                      controller: age,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: GlassCard(
                      frosted: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 4,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: sex,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                                value: 'Male', child: Text('Male')),
                            DropdownMenuItem(
                                value: 'Female', child: Text('Female')),
                            DropdownMenuItem(
                                value: 'Other', child: Text('Other')),
                          ],
                          onChanged: (v) {
                            if (v != null) setSheetState(() => sex = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Clinical risk',
                style: Theme.of(sheetCtx)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppPalette.textMuted(context)),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final r in RiskLevel.values)
                    ChoiceChip(
                      label: Text(r.label),
                      selected: risk == r,
                      selectedColor: r.color.withValues(alpha: 0.18),
                      onSelected: (_) => setSheetState(() => risk = r),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Save changes',
                expand: true,
                onPressed: () async {
                  final actor = AuthState.instance.user;
                  if (actor == null) {
                    AppToast.error(sheetCtx, 'Sign in expired.');
                    return;
                  }
                  final ageVal = int.tryParse(age.text.trim());

                  // Translate user-facing inputs into the backend health
                  // schema. `condition` is the patient's primary chronic
                  // condition; the server stores the full array.
                  final healthDelta = <String, dynamic>{};
                  if (condition.text.trim().isNotEmpty &&
                      condition.text.trim() != patient.condition) {
                    healthDelta['chronic_conditions'] = [
                      condition.text.trim(),
                    ];
                  }
                  if (sex != patient.sex) healthDelta['gender'] = sex;

                  final changes =
                      await StaffState.instance.updatePatientChart(
                    patientId: patientId,
                    actor: actor.fullName,
                    condition: condition.text,
                    sex: sex,
                    age: ageVal,
                    risk: risk,
                    healthDelta: healthDelta,
                  );
                  if (!sheetCtx.mounted) return;
                  Navigator.of(sheetCtx).pop();
                  if (changes.isEmpty) {
                    AppToast.show(context,
                        message: 'No changes to save.');
                    return;
                  }
                  // Local notification only in mock mode; with the backend
                  // on, the server creates the notification and the next
                  // sync brings it down.
                  NotificationState.instance.add(
                    AppNotification(
                      id: 'chart_${DateTime.now().millisecondsSinceEpoch}',
                      kind: NotificationKind.profile,
                      title: 'Chart updated by ${actor.fullName}',
                      body:
                          '${actor.role.label} updated ${patient.name}: ${changes.join(', ')}',
                      createdAt: DateTime.now(),
                      read: true,
                    ),
                  );
                  AppToast.success(
                    context,
                    'Updated ${changes.join(', ').toLowerCase()}.',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
