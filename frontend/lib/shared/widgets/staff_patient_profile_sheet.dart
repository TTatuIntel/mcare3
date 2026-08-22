import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/env/app_env.dart';
import '../../doctors/vitals/doctor_assign_vitals_sheet.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/section_label.dart';
import 'app_button.dart';
import 'glass_sheet.dart';

/// Read-only full patient profile for doctors and admin assistants.
///
/// The sheet opens immediately with whatever cached state exists; the admin
/// profile fetch runs *after* the sheet is on screen, so tapping a row never
/// blocks the UI. The body watches [StaffState] and re-renders as soon as the
/// merge lands.
class StaffPatientProfileSheet {
  StaffPatientProfileSheet._();

  static Future<void> show(
    BuildContext context, {
    required String patientId,
    String? patientName,
    bool loadFromAdmin = false,
  }) {
    final detail = StaffState.instance.patientClinicalDetail(patientId);
    final patient = StaffState.instance.patientById(patientId);
    final name = detail?.name ?? patient?.name ?? patientName ?? 'Patient';

    return GlassSheet.show<void>(
      context,
      title: 'Patient profile',
      subtitle: name,
      child: _ProfileBody(
        patientId: patientId,
        fallbackName: name,
        loadFromAdmin: loadFromAdmin,
      ),
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody({
    required this.patientId,
    required this.fallbackName,
    required this.loadFromAdmin,
  });

  final String patientId;
  final String fallbackName;
  final bool loadFromAdmin;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.loadFromAdmin && AppEnv.backendEnabled) {
      // Fetch after the sheet is on screen so the tap-to-open feels instant.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    }
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await AdminApi.instance.patientProfile(widget.patientId);
      if (data != null) {
        StaffState.instance
            .mergeAdminPatientProfile(widget.patientId, data);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final detail =
            StaffState.instance.patientClinicalDetail(widget.patientId);
        final patient = StaffState.instance.patientById(widget.patientId);
        final assigned =
            StaffState.instance.assignedVitalsForPatient(widget.patientId);
        final health = detail?.health;
        final name = detail?.name ?? patient?.name ?? widget.fallbackName;
        final hasAnyData =
            detail != null || health != null || patient != null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.all(Radius.circular(AppSpacing.radiusPill)),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              ),
            if (_error != null && !hasAnyData)
              _ErrorState(message: _error!, onRetry: _fetch)
            else if (!hasAnyData)
              const EmptyStateView(
                icon: AppIcons.profile,
                title: 'Loading patient profile…',
                message:
                    'Clinical details will appear as soon as the record syncs.',
                compact: true,
              )
            else
              _ProfileContent(
                name: name,
                detail: detail,
                patient: patient,
                assigned: assigned,
                health: health,
                banner: _error == null || hasAnyData
                    ? null
                    : _error,
                onRetry: _error == null ? null : _fetch,
              ),
          ],
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EmptyStateView(
          icon: AppIcons.alert,
          title: 'Could not load profile',
          message: message,
          compact: true,
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Retry',
          icon: AppIcons.refresh,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.name,
    required this.detail,
    required this.patient,
    required this.assigned,
    required this.health,
    required this.banner,
    required this.onRetry,
  });

  final String name;
  final StaffPatientClinicalDetail? detail;
  final StaffPatient? patient;
  final Set<VitalKey> assigned;
  final PatientHealthProfile? health;
  final String? banner;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (banner != null) ...[
          _StaleBanner(message: banner!, onRetry: onRetry),
          const SizedBox(height: AppSpacing.sm),
        ],
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
                        patient!.demographicsLine,
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
          _HealthScoreCard(health: health!),
          const SizedBox(height: AppSpacing.md),
          SectionLabel(
            title: 'Health profile',
            icon: AppIcons.vitals,
            trailing: health!.bmiCategory,
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
                  value: '${health!.ageYears} years',
                ),
                PatientCompactInfoRow(
                  label: 'Gender',
                  value: health!.gender.label,
                ),
                PatientCompactInfoRow(
                  label: 'Blood type',
                  value: health!.bloodType.label,
                ),
                PatientCompactInfoRow(
                  label: 'BMI',
                  value:
                      '${health!.bmi.toStringAsFixed(1)} (${health!.bmiCategory})',
                ),
                PatientCompactInfoRow(
                  label: 'Height / Weight',
                  value:
                      '${health!.heightCm.toStringAsFixed(0)} cm · ${health!.weightKg.toStringAsFixed(0)} kg',
                ),
                if (health!.address != null && health!.address!.isNotEmpty)
                  PatientCompactInfoRow(
                    label: 'Address',
                    value: health!.address!,
                  ),
                PatientCompactInfoRow(
                  label: 'Conditions',
                  value: health!.chronicConditions.isEmpty
                      ? 'None recorded'
                      : health!.chronicConditions.join(', '),
                ),
                PatientCompactInfoRow(
                  label: 'Allergies',
                  value: health!.noKnownAllergies
                      ? 'None known'
                      : health!.allergies.isEmpty
                          ? 'Not recorded'
                          : health!.allergies.join(', '),
                ),
                PatientCompactInfoRow(
                  label: 'Medications',
                  value: health!.noCurrentMedications
                      ? 'None'
                      : health!.currentMedications.isEmpty
                          ? 'Not recorded'
                          : health!.currentMedications.join(', '),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Builder(
          builder: (ctx) {
            final role = AuthState.instance.user?.role;
            final canAssist =
                role == UserRole.admin || role == UserRole.mcareAssistant;
            final patientName =
                detail?.name ?? patient?.name ?? name;
            final patientId = detail?.patientId ?? patient?.id;
            return SectionLabel(
              title: 'Assigned vitals',
              icon: AppIcons.vitals,
              trailing: '${assigned.length}',
              actionLabel:
                  (canAssist && patientId != null) ? 'Assign' : null,
              onAction: (canAssist && patientId != null)
                  ? () => DoctorAssignVitalsSheet.show(
                        ctx,
                        patientId: patientId,
                        patientName: patientName,
                      )
                  : null,
            );
          },
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
              children:
                  assigned.map((v) => _VitalChip(vital: v)).toList(),
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
                for (var i = 0;
                    i < detail!.emergencyContacts.length;
                    i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.xs),
                  _ContactRow(contact: detail!.emergencyContacts[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Showing cached details — could not refresh.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
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

/// Compact wellness snapshot — 0-100 heuristic score, category label,
/// and a small ring so care staff can triage at a glance.
class _HealthScoreCard extends StatelessWidget {
  const _HealthScoreCard({required this.health});
  final PatientHealthProfile health;

  Color _accent(int score) {
    if (score >= 70) return AppColors.success;
    if (score >= 55) return AppColors.info;
    if (score >= 40) return AppColors.warning;
    return AppColors.critical;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = health.healthScore;
    final category = health.healthCategory;
    final accent = _accent(score);

    // Short blurb that surfaces the top-line risk driver.
    final drivers = <String>[];
    if (health.chronicConditions.isNotEmpty) {
      drivers.add(
        '${health.chronicConditions.length} chronic '
        '${health.chronicConditions.length == 1 ? "condition" : "conditions"}',
      );
    }
    final bmi = health.bmi;
    if (bmi == 0) {
      drivers.add('BMI unknown');
    } else if (bmi < 18.5 || bmi >= 25) {
      drivers.add('BMI ${bmi.toStringAsFixed(1)} · ${health.bmiCategory}');
    }
    if (health.ageYears >= 60) {
      drivers.add('Age ${health.ageYears}');
    }
    final blurb = drivers.isEmpty
        ? 'No major risk factors on record.'
        : drivers.take(2).join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ScoreRing(score: score, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Health score',
                      style: theme.textTheme.labelMedium?.copyWith(
                            color: AppPalette.textMuted(context),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusPill),
                      ),
                      child: Text(
                        category.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  blurb,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.ink(context),
                        height: 1.3,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Little circular gauge that shows the numeric score inside the ring.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.color});
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 5,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  height: 1.0,
                ),
              ),
              Text(
                'of 100',
                style: TextStyle(
                  color: color.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w700,
                  fontSize: 7,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
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
        color: vital.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: vital.accent.withValues(alpha: 0.25)),
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
