import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/appointment.dart';
import '../../shared/state/appointments_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_label.dart';

class AppointmentDetailView extends StatefulWidget {
  const AppointmentDetailView({super.key, required this.appointmentId});
  final String appointmentId;

  @override
  State<AppointmentDetailView> createState() => _AppointmentDetailViewState();
}

class _AppointmentDetailViewState extends State<AppointmentDetailView> {
  final _cancelReason = TextEditingController();

  @override
  void dispose() {
    _cancelReason.dispose();
    super.dispose();
  }

  Future<void> _cancel(BuildContext context, Appointment a) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Cancel appointment?',
      message: 'This will notify ${a.doctorName}. You can book a new time anytime.',
      confirmLabel: 'Cancel visit',
      danger: true,
      icon: AppIcons.appointment,
    );
    if (confirmed != true || !context.mounted) return;

    await GlassSheet.show(
      context,
      title: 'Cancellation reason',
      subtitle: 'Optional — helps your care team follow up.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Reason',
            hint: 'Why are you cancelling?',
            controller: _cancelReason,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Confirm cancellation',
            variant: AppButtonVariant.danger,
            expand: true,
            onPressed: () async {
              try {
                await AppointmentsState.instance.cancelAppointment(
                  a.id,
                  reason: _cancelReason.text.trim().isEmpty
                      ? null
                      : _cancelReason.text.trim(),
                );
              } catch (e) {
                if (!context.mounted) return;
                AppToast.warn(context, 'Could not cancel: $e');
                return;
              }
              if (!context.mounted) return;
              Navigator.of(context).pop(); // sheet
              AppToast.success(context, 'Appointment cancelled.');
              Navigator.of(context).pop(); // detail
            },
          ),
        ],
      ),
    );
  }

  Future<void> _reschedule(BuildContext context, Appointment a) async {
    var date = a.scheduledAt;
    var time = TimeOfDay.fromDateTime(a.scheduledAt);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (pickedDate == null || !context.mounted) return;
    date = pickedDate;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: time,
    );
    if (pickedTime == null || !context.mounted) return;
    time = pickedTime;
    final newTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    try {
      await AppointmentsState.instance.rescheduleAppointment(a.id, newTime);
    } catch (e) {
      if (!context.mounted) return;
      AppToast.warn(context, 'Could not reschedule: $e');
      return;
    }
    if (!context.mounted) return;
    AppToast.success(context, 'Appointment rescheduled.');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppointmentsState.instance,
      builder: (context, _) {
        final a = AppointmentsState.instance.byId(widget.appointmentId);
        if (a == null) {
          return PatientScaffold(
            currentRoute: '',
            detachedNav: true,
            title: 'Appointment',
            body: EmptyStateView(
              icon: AppIcons.appointment,
              title: 'Not found',
              message: 'This appointment could not be loaded.',
            ),
          );
        }

        final canModify = a.isUpcoming;

        return PatientScaffold(
          currentRoute: '',
          detachedNav: true,
          title: a.doctorName,
          subtitle: a.doctorSpecialty,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Row(
                      icon: AppIcons.calendar,
                      label: DateFormat.yMMMEd().format(a.scheduledAt),
                    ),
                    _Row(
                      icon: AppIcons.time,
                      label:
                          '${DateFormat.jm().format(a.scheduledAt)} · ${a.durationMinutes} min',
                    ),
                    _Row(icon: a.type.icon, label: a.type.label),
                    _Row(
                      icon: AppIcons.info,
                      label: a.status.label,
                      valueColor: a.status.color,
                    ),
                    if (a.locationOrLink != null)
                      _Row(icon: AppIcons.location, label: a.locationOrLink!),
                    if (a.reason != null)
                      _Row(icon: AppIcons.report, label: a.reason!),
                    if (a.cancellationReason != null)
                      _Row(
                        icon: AppIcons.alert,
                        label: 'Cancelled: ${a.cancellationReason}',
                        valueColor: AppColors.critical,
                      ),
                  ],
                ),
              ),
              if (canModify) ...[
                const SizedBox(height: AppSpacing.xl),
                SectionLabel(title: 'Actions', icon: AppIcons.edit),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Reschedule',
                        variant: AppButtonVariant.secondary,
                        icon: AppIcons.calendar,
                        onPressed: () => _reschedule(context, a),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.danger,
                        onPressed: () => _cancel(context, a),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.huge),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
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
