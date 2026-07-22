import 'package:flutter/material.dart';

import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

/// Issue a prescription — optionally pre-filled for a patient workspace.
void showDoctorPrescriptionSheet(
  BuildContext context, {
  String? patientId,
  String? patientName,
}) {
  GlassSheet.show(
    context,
    title: 'New prescription',
    child: _RxSheetBody(
      initialPatientId: patientId,
      initialPatientName: patientName,
    ),
  );
}

class _RxSheetBody extends StatefulWidget {
  const _RxSheetBody({
    this.initialPatientId,
    this.initialPatientName,
  });

  final String? initialPatientId;
  final String? initialPatientName;

  @override
  State<_RxSheetBody> createState() => _RxSheetBodyState();
}

class _RxSheetBodyState extends State<_RxSheetBody> {
  late final TextEditingController _drug;
  late final TextEditingController _dosage;
  late final TextEditingController _freq;
  late final TextEditingController _dur;
  late final List<StaffPatient> _patients;

  String? _patientId;
  String? _patientName;

  bool get _locked => widget.initialPatientId != null;

  @override
  void initState() {
    super.initState();
    _drug = TextEditingController();
    _dosage = TextEditingController();
    _freq = TextEditingController();
    _dur = TextEditingController();
    _patients = StaffState.instance.assignedPatientsForDoctor();
    _patientId = widget.initialPatientId;
    _patientName = widget.initialPatientName;
  }

  @override
  void dispose() {
    _drug.dispose();
    _dosage.dispose();
    _freq.dispose();
    _dur.dispose();
    super.dispose();
  }

  void _submit(BuildContext ctx) {
    if (_patientId == null || _patientName == null) {
      AppToast.warn(ctx, 'Select a patient first.');
      return;
    }
    if (_drug.text.trim().isEmpty) {
      AppToast.warn(ctx, 'Drug name is required.');
      return;
    }
    StaffState.instance.addPrescription(
      StaffPrescription(
        id: 'rx_${DateTime.now().millisecondsSinceEpoch}',
        patientId: _patientId!,
        patientName: _patientName!,
        drug: _drug.text.trim(),
        dosage: _dosage.text.trim(),
        frequency: _freq.text.trim(),
        duration: _dur.text.trim(),
        issuedAt: DateTime.now(),
      ),
    );
    Navigator.of(ctx).pop();
    AppToast.success(context, 'Prescription issued.');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_locked)
              AppTextField(
                controller: TextEditingController(text: _patientName ?? ''),
                label: 'Patient',
                enabled: false,
              )
            else
              DropdownButtonFormField<String>(
                value: _patientId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Patient',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                hint: const Text('Select a patient'),
                items: _patients
                    .map((p) => DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(p.name),
                        ))
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  final p = _patients.firstWhere((x) => x.id == id);
                  setState(() {
                    _patientId = id;
                    _patientName = p.name;
                  });
                },
              ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _drug,
              label: 'Drug',
              hint: 'e.g. Metformin',
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _dosage,
                    label: 'Dosage',
                    hint: '500 mg',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppTextField(
                    controller: _freq,
                    label: 'Frequency',
                    hint: 'Twice daily',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _dur,
              label: 'Duration',
              hint: '90 days',
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Issue prescription',
              icon: AppIcons.check,
              expand: true,
              onPressed: () => _submit(ctx),
            ),
          ],
        ),
      ),
    );
  }
}
