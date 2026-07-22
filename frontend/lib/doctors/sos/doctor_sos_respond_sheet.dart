import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/services/doctor_patient_detail_service.dart';
import '../../shared/sos/sos_respond_context.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/patient_sheet.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/app_icons.dart';

/// Full-screen respond sheet — patient contacts, location, and SOS actions.
class DoctorSosRespondSheet {
  DoctorSosRespondSheet._();

  static Future<void> show(
    BuildContext context, {
    required String patientId,
    String? eventId,
  }) async {
    await DoctorPatientDetailService.instance.loadPatient(patientId);
    if (!context.mounted) return;

    return PatientSheet.show<void>(
      context,
      title: 'Respond to SOS',
      subtitle: 'Patient details · contacts · location',
      maxHeightFactor: 0.96,
      child: _DoctorSosRespondBody(
        patientId: patientId,
        eventId: eventId,
      ),
    );
  }
}

class _DoctorSosRespondBody extends StatelessWidget {
  const _DoctorSosRespondBody({
    required this.patientId,
    this.eventId,
  });

  final String patientId;
  final String? eventId;

  StaffPatientSos? _resolveEvent(List<StaffPatientSos> events) {
    if (eventId != null) {
      for (final e in events) {
        if (e.id == eventId) return e;
      }
    }
    final active = events.where((e) => e.isActive).toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    return active.isEmpty ? null : active.first;
  }

  Future<void> _update(
    BuildContext context,
    String id,
    String status,
  ) async {
    final ok = await StaffState.instance.resolveSos(id, status: status);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'SOS updated.');
      if (status == 'resolved' || status == 'falseAlarm') {
        Navigator.of(context).pop();
      }
    } else {
      AppToast.error(context, 'Could not update SOS.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final events = StaffState.instance.sosForPatient(patientId);
        final event = _resolveEvent(events);
        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SosRespondContextCard(patientId: patientId, event: event),
            if (event != null) ...[
              const SizedBox(height: AppSpacing.md),
              SectionLabel(title: 'Active alert', icon: AppIcons.sos),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppPalette.criticalSoft(context),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.critical.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      event.kindLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.critical,
                      ),
                    ),
                    if (event.note != null && event.note!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(event.note!, style: theme.textTheme.bodyMedium),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.MMMd().add_jm().format(event.triggeredAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (event.status == 'active')
                AppButton(
                  label: 'Acknowledge — on my way',
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: () => _update(context, event.id, 'acknowledged'),
                ),
              if (event.status == 'active')
                const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Resolve',
                      variant: AppButtonVariant.danger,
                      onPressed: () => _update(context, event.id, 'resolved'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: 'False alarm',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => _update(context, event.id, 'falseAlarm'),
                    ),
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  'No active SOS for this patient.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
