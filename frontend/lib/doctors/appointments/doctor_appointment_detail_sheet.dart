import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/appointment.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/section_label.dart';
import '../patients/doctor_patient_section.dart';

/// Appointment detail + doctor actions (confirm, complete, reschedule, cancel).
class DoctorAppointmentDetailSheet {
  DoctorAppointmentDetailSheet._();

  static Future<void> show(BuildContext context, String appointmentId) {
    return GlassSheet.show<void>(
      context,
      title: 'Appointment details',
      subtitle: 'Manage visit · open patient chart',
      child: _DetailBody(appointmentId: appointmentId),
    );
  }
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({required this.appointmentId});

  final String appointmentId;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  final _cancelReason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cancelReason.dispose();
    super.dispose();
  }

  StaffAppointment? get _appt =>
      StaffState.instance.appointmentById(widget.appointmentId);

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final ok =
        await StaffState.instance.confirmAppointment(widget.appointmentId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      AppToast.success(context, 'Appointment confirmed.');
    } else {
      AppToast.error(context, 'Could not confirm appointment.');
    }
  }

  Future<void> _complete() async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Mark visit complete?',
      message: 'This will close the appointment on the schedule.',
      confirmLabel: 'Complete visit',
      icon: AppIcons.check,
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final done =
        await StaffState.instance.completeAppointment(widget.appointmentId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) {
      AppToast.success(context, 'Visit marked complete.');
    } else {
      AppToast.error(context, 'Could not complete appointment.');
    }
  }

  Future<void> _reschedule(StaffAppointment a) async {
    var date = a.startAt;
    var time = TimeOfDay.fromDateTime(a.startAt);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (pickedDate == null || !mounted) return;
    date = pickedDate;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: time,
    );
    if (pickedTime == null || !mounted) return;
    time = pickedTime;
    final newTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() => _busy = true);
    final ok = await StaffState.instance.rescheduleAppointment(
      widget.appointmentId,
      newTime,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      AppToast.success(context, 'Appointment rescheduled.');
    } else {
      AppToast.error(context, 'Could not reschedule.');
    }
  }

  Future<void> _cancel(StaffAppointment a) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Cancel appointment?',
      message:
          'This will notify ${a.patientName} that the visit is cancelled.',
      confirmLabel: 'Cancel visit',
      danger: true,
      icon: AppIcons.appointment,
    );
    if (confirmed != true || !mounted) return;

    await GlassSheet.show(
      context,
      title: 'Cancellation reason',
      subtitle: 'Optional — shared with the patient.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Reason',
              hint: 'Why is this visit being cancelled?',
              controller: _cancelReason,
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Confirm cancellation',
              variant: AppButtonVariant.danger,
              expand: true,
              onPressed: () async {
                setState(() => _busy = true);
                final ok = await StaffState.instance.cancelAppointment(
                  widget.appointmentId,
                  reason: _cancelReason.text.trim().isEmpty
                      ? null
                      : _cancelReason.text.trim(),
                );
                if (!context.mounted) return;
                setState(() => _busy = false);
                if (ok) {
                  Navigator.of(context).pop();
                  AppToast.success(context, 'Appointment cancelled.');
                } else {
                  AppToast.error(context, 'Could not cancel appointment.');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPatientChart(StaffAppointment a) async {
    final pid = a.patientId;
    if (pid == null) {
      AppToast.warn(context, 'Patient record not linked.');
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
    await Future<void>.delayed(Duration.zero);
    if (!nav.mounted) return;
    await nav.pushNamed(
      RouteNames.doctorPatientChart,
      arguments: {
        'patientId': pid,
        'section': DoctorPatientSection.overview.name,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final a = _appt;
        if (a == null) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Appointment not found.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        final patient = a.patientId == null
            ? null
            : StaffState.instance.patientById(a.patientId!);
        final canModify = a.isUpcoming;

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
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.doctorGreen.withOpacity(0.15),
                        child: Text(
                          _initials(a.patientName),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.doctorGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.patientName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: a.status.softBg(context),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Text(
                          a.status.label,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: a.status.color,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const SectionLabel(
                  title: 'Visit information',
                  icon: AppIcons.info,
                ),
                const SizedBox(height: AppSpacing.xs),
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: AppIcons.calendar,
                        label: DateFormat.yMMMEd().format(a.startAt),
                      ),
                      _InfoRow(
                        icon: AppIcons.time,
                        label:
                            '${DateFormat.jm().format(a.startAt)} · ${a.durationMinutes} min',
                      ),
                      _InfoRow(icon: a.type.icon, label: a.type.label),
                      if (a.reason != null)
                        _InfoRow(icon: AppIcons.report, label: a.reason!),
                      if (a.locationOrLink != null)
                        _InfoRow(
                          icon: AppIcons.location,
                          label: a.locationOrLink!,
                        ),
                      if (a.cancellationReason != null)
                        _InfoRow(
                          icon: AppIcons.alert,
                          label: 'Cancelled: ${a.cancellationReason}',
                          valueColor: AppColors.critical,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Open patient chart',
                  icon: AppIcons.chart,
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: _busy ? null : () => _openPatientChart(a),
                ),
                if (canModify) ...[
                  const SizedBox(height: AppSpacing.md),
                  const SectionLabel(title: 'Actions', icon: AppIcons.edit),
                  const SizedBox(height: AppSpacing.xs),
                  if (a.status == AppointmentStatus.scheduled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppButton(
                        label: 'Confirm appointment',
                        icon: AppIcons.check,
                        expand: true,
                        onPressed: _busy ? null : _confirm,
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Reschedule',
                          variant: AppButtonVariant.secondary,
                          icon: AppIcons.calendar,
                          onPressed: _busy ? null : () => _reschedule(a),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppButton(
                          label: 'Cancel',
                          variant: AppButtonVariant.danger,
                          onPressed: _busy ? null : () => _cancel(a),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Mark complete',
                    icon: AppIcons.check,
                    variant: AppButtonVariant.ghost,
                    expand: true,
                    onPressed: _busy ? null : _complete,
                  ),
                ],
              ],
            ),
        );
      },
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppPalette.textMuted(context)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
