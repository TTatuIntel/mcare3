import 'package:flutter/material.dart';

import '../../shared/models/vital.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/vitals/vital_structure.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';
import 'doctor_patient_vital_threshold_sheet.dart';

/// Doctor-facing sheet to assign vitals a patient must track.
class DoctorAssignVitalsSheet {
  DoctorAssignVitalsSheet._();

  static Future<void> show(
    BuildContext context, {
    String? patientId,
    String? patientName,
  }) {
    final patients = StaffState.instance.assignedPatientsForDoctor();
    String? resolvedPatientId = patientId;
    String? resolvedPatientName = patientName;
    if (resolvedPatientId == null && patients.length == 1) {
      final only = patients.first;
      resolvedPatientId = only.id;
      resolvedPatientName = only.name;
    }

    return GlassSheet.show<void>(
      context,
      title: 'Assign vitals',
      subtitle: resolvedPatientName == null
          ? 'Select a patient, then assign vitals to their dashboard.'
          : 'Required vitals for $resolvedPatientName stay on their dashboard.',
      child: _AssignVitalsBody(
        initialPatientId: resolvedPatientId,
        initialPatientName: resolvedPatientName,
      ),
    );
  }
}

class _AssignVitalsBody extends StatefulWidget {
  const _AssignVitalsBody({this.initialPatientId, this.initialPatientName});

  final String? initialPatientId;
  final String? initialPatientName;

  @override
  State<_AssignVitalsBody> createState() => _AssignVitalsBodyState();
}

class _AssignVitalsBodyState extends State<_AssignVitalsBody> {
  late Set<VitalKey> _selected;
  late final TextEditingController _noteCtrl;
  late final List<StaffPatient> _patients;
  String? _patientId;
  String? _patientName;
  bool _saving = false;
  bool get _hasPatient => _patientId != null && _patientName != null;

  @override
  void initState() {
    super.initState();
    _patients = StaffState.instance.assignedPatientsForDoctor();
    _patientId = widget.initialPatientId;
    _patientName = widget.initialPatientName;
    _selected = <VitalKey>{};
    _noteCtrl = TextEditingController();
    if (_hasPatient) {
      _loadSelectionForPatient(_patientId!);
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_hasPatient) {
      AppToast.warn(context, 'Select a patient first.');
      return;
    }
    if (_selected.isEmpty) {
      AppToast.warn(context, 'Select at least one vital.');
      return;
    }
    setState(() => _saving = true);
    final ok = await StaffState.instance.updateAssignedVitalsForPatient(
      patientId: _patientId!,
      vitals: _selected,
      note: _noteCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
      AppToast.success(context, 'Assigned vitals updated.');
    } else {
      AppToast.error(context, 'Could not update assigned vitals.');
    }
  }

  void _loadSelectionForPatient(String patientId) {
    _selected = Set<VitalKey>.from(
      StaffState.instance.assignedVitalsForPatient(patientId),
    );
    if (_selected.isEmpty) {
      _selected = {VitalKey.bloodPressure, VitalKey.bloodGlucose};
    }
    _noteCtrl.text =
        StaffState.instance.assignedVitalsNoteForPatient(patientId) ?? '';
  }

  void _onPickPatient(String? id) {
    if (id == null) return;
    StaffPatient? picked;
    for (final p in _patients) {
      if (p.id == id) {
        picked = p;
        break;
      }
    }
    if (picked == null) return;
    final patientId = picked.id;
    final patientName = picked.name;
    setState(() {
      _patientId = patientId;
      _patientName = patientName;
      _loadSelectionForPatient(patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canChoosePatient =
        _patients.length > 1 && widget.initialPatientId == null;
    final chosenName = _patientName ?? 'No patient selected';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canChoosePatient) ...[
            DropdownButtonFormField<String>(
              value: _patientId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Patient',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _patients
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(p.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving ? null : _onPickPatient,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            'Patient: $chosenName',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Toggle vitals this patient must log. Assigned vitals appear locked in the patient app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: AnimatedBuilder(
              animation: StaffState.instance,
              builder: (context, _) {
                final catalogVitals = StaffState.instance
                    .enabledBuiltinVitals();
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: catalogVitals.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final v = catalogVitals[index];
                    final isAssigned = _selected.contains(v);
                    return _VitalAssignRow(
                      vital: v,
                      assigned: isAssigned,
                      onChanged: !_hasPatient
                          ? (_) {}
                          : (next) {
                              setState(() {
                                if (next) {
                                  _selected.add(v);
                                } else {
                                  _selected.remove(v);
                                }
                              });
                            },
                      onThreshold: _hasPatient && isAssigned
                          ? () => DoctorPatientVitalThresholdSheet.show(
                              context: context,
                              patientId: _patientId!,
                              patientName: _patientName!,
                              vital: v,
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Clinical instruction (optional)',
            hint: 'e.g. Check morning fasting glucose before breakfast',
            controller: _noteCtrl,
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: _saving ? 'Saving…' : 'Save assignments',
            icon: AppIcons.vitals,
            expand: true,
            onPressed: _saving || !_hasPatient ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _VitalAssignRow extends StatelessWidget {
  const _VitalAssignRow({
    required this.vital,
    required this.assigned,
    required this.onChanged,
    this.onThreshold,
  });

  final VitalKey vital;
  final bool assigned;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onThreshold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = vital.accent;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: assigned
            ? accent.withOpacity(0.06)
            : AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
          color: assigned
              ? accent.withOpacity(0.28)
              : AppPalette.border(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(vital.icon, color: accent, size: 17),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vital.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                Text(
                  vital.unit,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (onThreshold != null) ...[
            IconButton(
              icon: const Icon(AppIcons.filter, size: 18),
              tooltip: 'Thresholds & alert ranges',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: onThreshold,
            ),
            const SizedBox(width: 2),
          ],
          Transform.scale(
            scale: 0.85,
            child: Switch.adaptive(
              value: assigned,
              activeColor: accent,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
