import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/vitals_api.dart';
import '../models/vital.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/risk_badge.dart';

/// Lets a doctor or admin record a reading on a patient's behalf.
///
/// Readings taken at the desk or read back over the phone had nowhere to go:
/// writing vitals was the patient's own endpoint alone, so staff either asked
/// the patient to enter it later — which often meant never — or left it in a
/// note that nothing grades and nothing alerts on.
///
/// Deliberately one reading at a time, unlike the patient's own sheet. A
/// patient logs a morning round of three; staff enter a reading as they take
/// it, and a form that invites four at once mostly invites mistakes in the
/// three nobody measured.
class StaffLogVitalSheet {
  StaffLogVitalSheet._();

  static Future<bool?> show(
    BuildContext context, {
    required String patientId,
    required String patientName,
    VitalKey? initial,
  }) {
    return GlassSheet.show<bool>(
      context,
      title: 'Log a vital',
      subtitle: 'Recording for $patientName',
      maxHeightFactor: 0.8,
      child: _Form(
        patientId: patientId,
        patientName: patientName,
        initial: initial,
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({
    required this.patientId,
    required this.patientName,
    this.initial,
  });

  final String patientId;
  final String patientName;
  final VitalKey? initial;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late VitalKey _vital = widget.initial ?? _tracked.first;
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  /// The vitals this patient is actually tracking, falling back to the full
  /// catalogue so a reading can still be filed for someone with none assigned.
  List<VitalKey> get _tracked {
    final assigned = StaffState.instance.assignedVitalsForPatient(
      widget.patientId,
    );

    return assigned.isEmpty
        ? VitalKey.values
        : (assigned.toList()..sort((a, b) => a.index.compareTo(b.index)));
  }

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_primary.text.trim());
  double? get _second => double.tryParse(_secondary.text.trim());

  RiskLevel get _risk {
    final v = _value;
    if (v == null) return RiskLevel.unknown;

    return VitalRanges.defaults[_vital]!.assess(v);
  }

  Future<void> _save() async {
    final value = _value;
    if (value == null) {
      AppToast.warn(context, 'Enter a value.');
      return;
    }
    if (_vital.hasSecondaryValue && _second == null) {
      AppToast.warn(context, 'Enter both systolic and diastolic.');
      return;
    }

    setState(() => _saving = true);
    try {
      await VitalsApi.instance.recordForPatient(
        patientUserId: widget.patientId,
        vital: _vital,
        value: value,
        secondaryValue: _second,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppToast.success(
        context,
        '${_vital.shortLabel} recorded for ${widget.patientName}.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracked = _tracked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your tracked vitals',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.ink(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: tracked
              .map(
                (v) => _VitalChoice(
                  vital: v,
                  selected: v == _vital,
                  onTap: () => setState(() {
                    _vital = v;
                    _primary.clear();
                    _secondary.clear();
                  }),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: AppLayout.fieldGap),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: _vital.accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: _vital.accent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(_vital.icon, color: _vital.accent, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _vital.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              RiskBadge(risk: _risk),
            ],
          ),
        ),
        const SizedBox(height: AppLayout.fieldGap),
        if (_vital.hasSecondaryValue)
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Systolic',
                  hint: '120',
                  controller: _primary,
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  label: 'Diastolic',
                  hint: '80',
                  controller: _secondary,
                  onChanged: () => setState(() {}),
                ),
              ),
            ],
          )
        else
          _NumberField(
            label: 'Value (${_vital.unit})',
            hint: 'e.g. 72',
            controller: _primary,
            onChanged: () => setState(() {}),
          ),
        const SizedBox(height: AppLayout.fieldGap),
        AppTextField(
          label: 'Note (optional)',
          hint: 'e.g. taken at the desk',
          controller: _note,
          maxLines: 2,
          minLines: 2,
          dense: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This is filed as a reading you took. It grades and alerts exactly '
          'as one the patient logs themselves.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppLayout.sectionGap),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.ghost,
                expand: true,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppButton(
                label: 'Save reading',
                icon: AppIcons.check,
                expand: true,
                size: AppButtonSize.md,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      hint: hint,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\.]'))],
      dense: true,
      onChanged: (_) => onChanged(),
    );
  }
}

class _VitalChoice extends StatelessWidget {
  const _VitalChoice({
    required this.vital,
    required this.selected,
    required this.onTap,
  });

  final VitalKey vital;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = vital.accent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: selected ? c : c.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(vital.icon, color: selected ? Colors.white : c, size: 14),
            const SizedBox(width: 5),
            Text(
              vital.shortLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? Colors.white : c,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
