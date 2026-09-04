import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/appointment.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/section_label.dart';

/// Doctor schedules a visit with an assigned patient.
class DoctorScheduleAppointmentSheet {
  DoctorScheduleAppointmentSheet._();

  static Future<void> show(
    BuildContext context, {
    String? patientId,
    String? patientName,
  }) {
    final patients = StaffState.instance.assignedPatientsForDoctor();
    if (patients.isEmpty) {
      AppToast.show(
        context,
        message: 'No assigned patients yet. Open Patients to manage caseload.',
      );
      return Future.value();
    }

    String? resolvedId = patientId;
    String? resolvedName = patientName;
    if (resolvedId == null && patients.length == 1) {
      resolvedId = patients.first.id;
      resolvedName = patients.first.name;
    }

    return GlassSheet.show<void>(
      context,
      title: 'Schedule appointment',
      subtitle: 'Book a visit with your patient',
      child: _ScheduleBody(
        initialPatientId: resolvedId,
        initialPatientName: resolvedName,
      ),
    );
  }
}

class _ScheduleBody extends StatefulWidget {
  const _ScheduleBody({
    this.initialPatientId,
    this.initialPatientName,
  });

  final String? initialPatientId;
  final String? initialPatientName;

  @override
  State<_ScheduleBody> createState() => _ScheduleBodyState();
}

class _ScheduleBodyState extends State<_ScheduleBody> {
  final _reason = TextEditingController();
  final _location = TextEditingController();

  late final List<StaffPatient> _patients;
  String? _patientId;
  String? _patientName;
  AppointmentType _type = AppointmentType.virtual;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  int _duration = 30;
  bool _saving = false;

  bool get _hasPatient => _patientId != null && _patientName != null;

  @override
  void initState() {
    super.initState();
    _patients = StaffState.instance.assignedPatientsForDoctor();
    _patientId = widget.initialPatientId;
    _patientName = widget.initialPatientName;
  }

  @override
  void dispose() {
    _reason.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _onPatientChanged(String? id) {
    if (id == null) return;
    final p = StaffState.instance.patientById(id);
    if (p == null) return;
    setState(() {
      _patientId = p.id;
      _patientName = p.name;
    });
  }

  Future<void> _schedule() async {
    if (!_hasPatient) {
      AppToast.warn(context, 'Select a patient.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      AppToast.warn(context, 'Add a reason for the visit.');
      return;
    }

    setState(() => _saving = true);
    final scheduled = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );

    final location = _location.text.trim();
    final ok = await StaffState.instance.scheduleAppointment(
      patientId: _patientId!,
      patientName: _patientName!,
      scheduledAt: scheduled,
      type: _type,
      reason: _reason.text.trim(),
      durationMinutes: _duration,
      locationOrLink: location.isEmpty
          ? null
          : (_type == AppointmentType.virtual && !location.startsWith('http')
              ? 'https://meet.mcare.app/$location'
              : location),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.of(context).pop();
      AppToast.success(
        context,
        'Appointment scheduled with ${_patientName!}.',
      );
    } else {
      AppToast.error(context, 'Could not schedule appointment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = _patientId == null
        ? null
        : StaffState.instance.patientById(_patientId!);
    final canChoosePatient =
        _patients.length > 1 && widget.initialPatientId == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel(title: 'Patient', icon: AppIcons.patients),
            const SizedBox(height: AppSpacing.xs),
            if (canChoosePatient)
              DropdownButtonFormField<String>(
                value: _patientId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select patient',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _patients
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name),
                      ),
                    )
                    .toList(),
                onChanged: _saving ? null : _onPatientChanged,
              )
            else
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(AppIcons.patients,
                        size: 18, color: AppColors.brandIndigo),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _patientName ?? 'No patient',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (patient != null)
                            Text(
                              patient.demographicsLine,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: AppPalette.textMuted(context)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            const SectionLabel(title: 'Visit details', icon: AppIcons.appointment),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Visit type',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: AppointmentType.values.map((t) {
                final selected = _type == t;
                return ChoiceChip(
                  avatar: Icon(t.icon, size: 16),
                  label: Text(t.label),
                  selected: selected,
                  onSelected: _saving ? null : (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(AppIcons.calendar, size: 18),
                    label: Text(DateFormat.yMMMd().format(_date)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickTime,
                    icon: const Icon(AppIcons.time, size: 18),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              value: _duration,
              decoration: const InputDecoration(
                labelText: 'Duration',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [15, 30, 45, 60]
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text('$m minutes'),
                    ),
                  )
                  .toList(),
              onChanged: _saving ? null : (v) => setState(() => _duration = v!),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Reason for visit',
              hint: 'e.g. Quarterly diabetes review',
              controller: _reason,
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: _type == AppointmentType.virtual
                  ? 'Meeting link (optional)'
                  : _type == AppointmentType.inPerson
                      ? 'Location (optional)'
                      : 'Phone notes (optional)',
              hint: _type == AppointmentType.virtual
                  ? 'Auto-generated if left blank'
                  : 'Clinic room or address',
              controller: _location,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: _saving ? 'Scheduling…' : 'Schedule appointment',
              icon: AppIcons.appointment,
              expand: true,
              onPressed: _saving || !_hasPatient ? null : _schedule,
            ),
          ],
        ),
    );
  }
}
