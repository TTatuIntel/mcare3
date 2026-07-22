import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/env/app_env.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/section_label.dart';

/// Read-only full patient profile for doctors and admin assistants.
class StaffPatientProfileSheet {
  StaffPatientProfileSheet._();

  static Future<void> show(
    BuildContext context, {
    required String patientId,
    String? patientName,
    bool loadFromAdmin = false,
  }) async {
    if (loadFromAdmin && AppEnv.backendEnabled) {
      final data = await AdminApi.instance.patientProfile(patientId);
      if (data != null) {
        StaffState.instance.mergeAdminPatientProfile(patientId, data);
      }
    }

    if (!context.mounted) return;

    final detail = StaffState.instance.patientClinicalDetail(patientId);
    final name = detail?.name ?? patientName ?? 'Patient';

    return GlassSheet.show<void>(
      context,
      title: 'Patient profile',
      subtitle: name,
      child: _ProfileBody(
        patientId: patientId,
        fallbackName: name,
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.patientId,
    required this.fallbackName,
  });

  final String patientId;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final detail = StaffState.instance.patientClinicalDetail(patientId);
        final patient = StaffState.instance.patientById(patientId);
        final assigned = StaffState.instance.assignedVitalsForPatient(patientId);
        final health = detail?.health;
        final name = detail?.name ?? patient?.name ?? fallbackName;

        if (detail == null && health == null && patient == null) {
          return const EmptyStateView(
            icon: AppIcons.profile,
            title: 'Profile not loaded',
            message: 'Clinical details will appear after the patient record syncs.',
            compact: true,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    _PatientAvatar(name: name),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          if (detail?.uniqueId != null)
                            Text(
                              detail!.uniqueId!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (patient != null)
                            Text(
                              patient.demographicsLine,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppPalette.textMuted(context),
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (detail?.email != null || detail?.phone != null) ...[
                const SizedBox(height: AppSpacing.md),
                const SectionLabel(title: 'Contact', icon: AppIcons.phone),
                const SizedBox(height: AppSpacing.xs),
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    children: [
                      if (detail?.email != null)
                        PatientCompactInfoRow(
                          label: 'Email',
                          value: detail!.email!,
                        ),
                      if (detail?.phone != null)
                        PatientCompactInfoRow(
                          label: 'Phone',
                          value: detail!.phone!,
                        ),
                      if (detail?.joinedAt != null)
                        PatientCompactInfoRow(
                          label: 'Joined',
                          value: DateFormat.yMMMd().format(detail!.joinedAt!),
                        ),
                      if (detail?.approvalStatus != null)
                        PatientCompactInfoRow(
                          label: 'Status',
                          value: detail!.approvalStatus!,
                        ),
                    ],
                  ),
                ),
              ],
              if (health != null) ...[
                const SizedBox(height: AppSpacing.md),
                SectionLabel(
                  title: 'Health profile',
                  icon: AppIcons.vitals,
                  trailing: health.bmiCategory,
                ),
                const SizedBox(height: AppSpacing.xs),
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    children: [
                      PatientCompactInfoRow(
                        label: 'Age',
                        value: '${health.ageYears} years',
                      ),
                      PatientCompactInfoRow(
                        label: 'Gender',
                        value: health.gender.label,
                      ),
                      PatientCompactInfoRow(
                        label: 'Blood type',
                        value: health.bloodType.label,
                      ),
                      PatientCompactInfoRow(
                        label: 'BMI',
                        value:
                            '${health.bmi.toStringAsFixed(1)} (${health.bmiCategory})',
                      ),
                      PatientCompactInfoRow(
                        label: 'Height / Weight',
                        value:
                            '${health.heightCm.toStringAsFixed(0)} cm · ${health.weightKg.toStringAsFixed(0)} kg',
                      ),
                      if (health.address != null && health.address!.isNotEmpty)
                        PatientCompactInfoRow(
                          label: 'Address',
                          value: health.address!,
                        ),
                      PatientCompactInfoRow(
                        label: 'Conditions',
                        value: health.chronicConditions.isEmpty
                            ? 'None recorded'
                            : health.chronicConditions.join(', '),
                      ),
                      PatientCompactInfoRow(
                        label: 'Allergies',
                        value: health.noKnownAllergies
                            ? 'None known'
                            : health.allergies.isEmpty
                                ? 'Not recorded'
                                : health.allergies.join(', '),
                      ),
                      PatientCompactInfoRow(
                        label: 'Medications',
                        value: health.noCurrentMedications
                            ? 'None'
                            : health.currentMedications.isEmpty
                                ? 'Not recorded'
                                : health.currentMedications.join(', '),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              SectionLabel(
                title: 'Assigned vitals',
                icon: AppIcons.vitals,
                trailing: '${assigned.length}',
              ),
              const SizedBox(height: AppSpacing.xs),
              if (assigned.isEmpty)
                GlassCard(
                  frosted: true,
                  child: Text(
                    'No vitals assigned yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: assigned
                        .map((v) => _VitalChip(vital: v))
                        .toList(),
                  ),
                ),
              if (detail?.emergencyContacts.isNotEmpty == true) ...[
                const SizedBox(height: AppSpacing.md),
                SectionLabel(
                  title: 'Emergency contacts',
                  icon: AppIcons.sos,
                  trailing: '${detail!.emergencyContacts.length}',
                ),
                const SizedBox(height: AppSpacing.xs),
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < detail.emergencyContacts.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.xs),
                        _ContactRow(contact: detail.emergencyContacts[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ],
        );
      },
    );
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : (parts.isEmpty ? '?' : parts.first[0].toUpperCase());

    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.doctorGreen, Color(0xFF1B5E3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _VitalChip extends StatelessWidget {
  const _VitalChip({required this.vital});
  final VitalKey vital;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: vital.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: vital.accent.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vital.icon, size: 14, color: vital.accent),
          const SizedBox(width: 6),
          Text(
            vital.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: vital.accent,
                ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});
  final EmergencyContact contact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(AppIcons.phone, size: 16, color: AppPalette.textMuted(context)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contact.name,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                '${contact.relationship} · ${contact.phone}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 10,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
