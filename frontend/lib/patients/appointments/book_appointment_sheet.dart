import 'package:flutter/material.dart';

import '../../shared/models/appointment.dart';
import '../../shared/models/care_provider.dart';
import '../../shared/state/appointments_state.dart';
import '../../shared/state/care_state.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

class BookAppointmentSheet {
  BookAppointmentSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Book appointment',
      subtitle: 'Choose a provider, type, and time.',
      child: const _Form(),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  CareProvider? _doctor;
  AppointmentType _type = AppointmentType.virtual;
  DateTime _date = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
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

  Future<void> _book() async {
    final doctor = _doctor;
    if (doctor == null) {
      AppToast.warn(context, 'Select a care provider.');
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
    try {
      await AppointmentsState.instance.bookAppointment(
        Appointment(
          id: 'a_${DateTime.now().millisecondsSinceEpoch}',
          doctorId: doctor.id,
          doctorName: doctor.name,
          doctorSpecialty: doctor.specialty,
          scheduledAt: scheduled,
          type: _type,
          status: AppointmentStatus.scheduled,
          reason: _reason.text.trim(),
          locationOrLink: _type == AppointmentType.virtual
              ? 'https://meet.mcare.app/new'
              : _type == AppointmentType.inPerson
              ? doctor.facility
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not book: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, 'Appointment booked with ${doctor.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final doctors = CareState.instance.assigned;
    if (_doctor == null && doctors.isNotEmpty) _doctor = doctors.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Provider', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<CareProvider>(
          value: _doctor,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: doctors
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Text('${d.name} · ${d.specialty}'),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _doctor = v),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Visit type', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: AppointmentType.values.map((t) {
            final selected = _type == t;
            return ChoiceChip(
              avatar: Icon(t.icon, size: 16),
              label: Text(t.label),
              selected: selected,
              onSelected: (_) => setState(() => _type = t),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(AppIcons.calendar, size: 18),
                label: Text('${_date.month}/${_date.day}/${_date.year}'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(AppIcons.time, size: 18),
                label: Text(_time.format(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Reason for visit',
          hint: 'Brief description',
          controller: _reason,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Book appointment',
          icon: AppIcons.appointment,
          loading: _saving,
          expand: true,
          onPressed: _book,
        ),
      ],
    );
  }
}
