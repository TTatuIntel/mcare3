part of 'doctor_patient_workspace_view.dart';

class _PatientStatusStrip extends StatelessWidget {
  const _PatientStatusStrip({
    required this.patient,
    required this.patientId,
    required this.onNavigate,
  });

  final StaffPatient patient;
  final String patientId;
  final ValueChanged<DoctorPatientSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = StaffState.instance;
    final sos = s.hasActiveSos(patientId);
    final openAlerts = s.openAlertCountForPatient(patientId);
    final apptCount = s.appointmentsForPatient(patientId).length;
    final primaryAlert =
        s.alertsForPatient(patientId).where((a) => !a.resolved).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final topAlert = primaryAlert.isEmpty ? null : primaryAlert.first;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RiskBadge(risk: patient.risk, dense: true),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (patient.hasCondition)
                      Text(
                        patient.condition,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      'Last reading ${DateFormat.MMMd().add_jm().format(patient.lastReading)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (sos)
                _MiniChip(
                  label: 'SOS',
                  color: AppColors.critical,
                  onTap: () => onNavigate(DoctorPatientSection.sos),
                ),
            ],
          ),
          if (topAlert != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _InsightLine(
              icon: AppIcons.alert,
              color: topAlert.severity.color,
              text:
                  '${topAlert.vital.label} ${topAlert.value} Â· ${topAlert.severity.label}',
              onTap: () => onNavigate(DoctorPatientSection.alerts),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              PatientHeroStat(
                label: 'Alerts',
                value: '$openAlerts',
                accent: openAlerts > 0 ? AppColors.warning : null,
                onTap: () => onNavigate(DoctorPatientSection.alerts),
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Vitals',
                value: '${PatientVitalFeed.collect(patientId).length}',
                onTap: () => onNavigate(DoctorPatientSection.vitals),
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Rx',
                value: '${s.prescriptionsForPatient(patientId).length}',
                onTap: () => onNavigate(DoctorPatientSection.prescriptions),
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Appts',
                value: '$apptCount',
                accent: apptCount > 0 ? AppColors.info : null,
                onTap: () => onNavigate(DoctorPatientSection.appointments),
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Docs',
                value: '${s.documentsForPatient(patientId).length}',
                onTap: () => onNavigate(DoctorPatientSection.documents),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightLine extends StatelessWidget {
  const _InsightLine({
    required this.icon,
    required this.color,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                size: 12,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({
    super.key,
    required this.section,
    required this.patientId,
    required this.patientName,
    required this.onNavigateSection,
  });

  final DoctorPatientSection section;
  final String patientId;
  final String patientName;
  final ValueChanged<DoctorPatientSection> onNavigateSection;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      DoctorPatientSection.overview => _OverviewPanel(
        patientId: patientId,
        patientName: patientName,
        onNavigateSection: onNavigateSection,
      ),
      DoctorPatientSection.vitals => _VitalsPanel(
        patientId: patientId,
        patientName: patientName,
      ),
      DoctorPatientSection.documents => _DocumentsPanel(patientId: patientId),
      DoctorPatientSection.prescriptions => _PrescriptionsPanel(
        patientId: patientId,
        patientName: patientName,
      ),
      DoctorPatientSection.meals => _MealsPanel(
        patientId: patientId,
        patientName: patientName,
      ),
      DoctorPatientSection.medications => _PrescriptionsPanel(
        patientId: patientId,
        patientName: patientName,
        title: 'Medication records',
      ),
      DoctorPatientSection.alerts => _AlertsPanel(patientId: patientId),
      DoctorPatientSection.sos => _SosPanel(patientId: patientId),
      DoctorPatientSection.appointments => _AppointmentsPanel(
        patientId: patientId,
        patientName: patientName,
      ),
      DoctorPatientSection.messages => _MessagesPanel(
        patientId: patientId,
        patientName: patientName,
      ),
      DoctorPatientSection.reports => _ReportsPanel(
        patientId: patientId,
        patientName: patientName,
      ),
      DoctorPatientSection.timeline => _TimelinePanel(patientId: patientId),
      DoctorPatientSection.trends => _TrendsPanel(patientId: patientId),
    };
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({
    required this.patientId,
    required this.patientName,
    required this.onNavigateSection,
  });

  final String patientId;
  final String patientName;
  final ValueChanged<DoctorPatientSection> onNavigateSection;

  @override
  Widget build(BuildContext context) {
    final s = StaffState.instance;
    final rx = s.prescriptionsForPatient(patientId);
    final rxPreview = rx.take(3).toList();
    final appts = s.appointmentsForPatient(patientId)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final apptPreview = appts.take(2).toList();
    final sosActive = s.hasActiveSos(patientId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sosActive) ...[
          StaggeredEntry(
            index: 0,
            child: GlassCard(
              frosted: true,
              onTap: () =>
                  DoctorSosRespondSheet.show(context, patientId: patientId),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(AppIcons.sos, size: 18, color: AppColors.critical),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Active SOS â€” respond now',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.critical,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    AppIcons.chevronRight,
                    size: 14,
                    color: AppPalette.textMuted(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        StaggeredEntry(
          index: 2,
          child: DoctorPatientVitalFeed(
            patientId: patientId,
            onOpenVitals: () => onNavigateSection(DoctorPatientSection.vitals),
            onOpenAlerts: () => onNavigateSection(DoctorPatientSection.alerts),
          ),
        ),
        if (rxPreview.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          StaggeredEntry(
            index: 5,
            child: _OverviewFeedCard(
              title: 'Active prescriptions',
              icon: AppIcons.prescription,
              trailing: '${rx.length}',
              onTap: () =>
                  onNavigateSection(DoctorPatientSection.prescriptions),
              child: StaffListCard(
                children: rxPreview
                    .map(
                      (p) => StaffListRow(
                        icon: AppIcons.prescription,
                        iconColor: AppColors.brandIndigo,
                        title: '${p.drug} ${p.dosage}',
                        subtitle: '${p.frequency} Â· ${p.duration}',
                        pill: p.status,
                        pillColor: AppColors.success,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        StaggeredEntry(
          index: 5,
          child: _OverviewFeedCard(
            title: 'Appointments',
            icon: AppIcons.appointment,
            trailing: appts.isEmpty ? null : '${appts.length}',
            onTap: () => DoctorAppointmentFlows.openSchedule(
              context,
              patientId: patientId,
              patientName: patientName,
            ),
            emptyHint: 'No visits scheduled â€” schedule appointment',
            child: apptPreview.isEmpty
                ? null
                : StaffListCard(
                    children: apptPreview
                        .map(
                          (a) => StaffListRow(
                            icon: a.type.icon,
                            iconColor: AppColors.info,
                            title: DateFormat.MMMd().add_jm().format(a.startAt),
                            subtitle:
                                '${a.type.label}${a.reason != null ? ' Â· ${a.reason}' : ''}',
                            onTap: () => DoctorAppointmentFlows.openDetail(
                              context,
                              a.id,
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Compact, tappable overview block â€” header navigates; avoids duplicate
/// stat grids and redundant section labels.
class _OverviewFeedCard extends StatelessWidget {
  const _OverviewFeedCard({
    required this.title,
    required this.icon,
    required this.onTap,
    this.trailing,
    this.emptyHint,
    this.child,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final String? trailing;
  final String? emptyHint;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = AppColors.brandIndigo;

    return GlassCard(
      frosted: true,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 28,
                width: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                AppIcons.chevronRight,
                size: 14,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: AppSpacing.xs),
            child!,
          ] else if (emptyHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                emptyHint!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _openPatientChat(
  BuildContext context,
  String patientId,
  String patientName,
) {
  final conv = MessagesState.instance.conversationForPatient(
    patientId: patientId,
    patientName: patientName,
  );
  if (conv != null) {
    Navigator.of(
      context,
    ).pushNamed(RouteNames.doctorChatThread, arguments: conv.id);
    return;
  }
  Navigator.of(context).pushNamed(RouteNames.doctorMessages);
}

class _VitalsPanel extends StatelessWidget {
  const _VitalsPanel({required this.patientId, required this.patientName});
  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final s = StaffState.instance;
    final vitals = s.vitalsForPatient(patientId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DoctorAssignedVitalsPeek(
          patientId: patientId,
          patientName: patientName,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'New vitals report',
          icon: AppIcons.report,
          variant: AppButtonVariant.secondary,
          expand: true,
          size: AppButtonSize.sm,
          onPressed: () => Navigator.of(
            context,
          ).pushNamed(RouteNames.doctorReportEditor, arguments: patientName),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionLabel(
          title: 'Vital signs',
          icon: AppIcons.vitals,
          trailing: '${vitals.length}',
        ),
        const SizedBox(height: AppSpacing.xs),
        _VitalsList(vitals: vitals, emptyLabel: 'No vitals recorded yet.'),
      ],
    );
  }
}

String _patientInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return parts.isEmpty ? '?' : parts.first[0].toUpperCase();
}

class _VitalsList extends StatelessWidget {
  const _VitalsList({required this.vitals, required this.emptyLabel});
  final List<StaffPatientVitalReading> vitals;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (vitals.isEmpty) {
      return GlassCard(
        frosted: true,
        child: Text(emptyLabel, style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return StaffListCard(
      children: vitals
          .map(
            (v) => StaffListRow(
              icon: v.vital.icon,
              iconColor: v.risk.color,
              title: v.vital.label,
              subtitle:
                  '${v.value} Â· ${DateFormat.MMMd().add_jm().format(v.recordedAt)}',
              pill: v.risk.label,
              pillColor: v.risk.color,
            ),
          )
          .toList(),
    );
  }
}

class _DocumentsPanel extends StatelessWidget {
  const _DocumentsPanel({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final docs = StaffState.instance.documentsForPatient(patientId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Medical documents',
          icon: AppIcons.document,
          trailing: '${docs.length}',
        ),
        if (docs.isEmpty)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.document,
              title: 'No documents',
              message: 'Uploads from the patient will appear here.',
              compact: true,
            ),
          )
        else
          StaffListCard(
            children: docs
                .map(
                  (d) => StaffListRow(
                    icon: AppIcons.document,
                    iconColor: AppColors.weightSlate,
                    title: d.title,
                    subtitle:
                        '${d.category} Â· ${DateFormat.MMMd().format(d.uploadedAt)}',
                    pill: 'View',
                    pillColor: AppColors.info,
                    onTap: () => _showDocumentSheet(context, d),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Upload document',
          icon: AppIcons.upload,
          variant: AppButtonVariant.secondary,
          onPressed: () {
            final patient = StaffState.instance.patientById(patientId);
            DoctorUploadDocumentSheet.show(
              context,
              patientId: patientId,
              patientName: patient?.name ?? 'Patient',
            );
          },
        ),
      ],
    );
  }
}

class _PrescriptionsPanel extends StatelessWidget {
  const _PrescriptionsPanel({
    required this.patientId,
    required this.patientName,
    this.title = 'Prescriptions',
  });

  final String patientId;
  final String patientName;
  final String title;

  @override
  Widget build(BuildContext context) {
    final rx = StaffState.instance.prescriptionsForPatient(patientId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: title,
          icon: AppIcons.prescription,
          trailing: '${rx.length}',
          actionLabel: 'New',
          onAction: () => showDoctorPrescriptionSheet(
            context,
            patientId: patientId,
            patientName: patientName,
          ),
        ),
        if (rx.isEmpty)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.prescription,
              title: 'No prescriptions',
              actionLabel: 'Issue prescription',
              onAction: () => showDoctorPrescriptionSheet(
                context,
                patientId: patientId,
                patientName: patientName,
              ),
              compact: true,
            ),
          )
        else
          StaffListCard(
            children: rx
                .map(
                  (p) => StaffListRow(
                    icon: AppIcons.prescription,
                    iconColor: AppColors.brandIndigo,
                    title: '${p.drug} ${p.dosage}',
                    subtitle:
                        '${p.frequency} Â· ${DateFormat.MMMd().format(p.issuedAt)}',
                    pill: p.status,
                    pillColor: AppColors.success,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final alerts = StaffState.instance.alertsForPatient(patientId)
      ..sort((a, b) {
        if (a.resolved != b.resolved) return a.resolved ? 1 : -1;
        if (a.acknowledged != b.acknowledged) {
          return a.acknowledged ? 1 : -1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Patient alerts',
          icon: AppIcons.alert,
          trailing: '${alerts.length}',
        ),
        _AlertsList(alerts: alerts, compact: false),
      ],
    );
  }
}

class _AlertsList extends StatelessWidget {
  const _AlertsList({required this.alerts, required this.compact});
  final List<StaffAlert> alerts;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return GlassCard(
        frosted: true,
        child: Text(
          'No alerts for this patient.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return StaffListCard(
      children: alerts
          .map(
            (a) => StaffListRow(
              icon: a.vital.icon,
              iconColor: a.severity.color,
              title: a.vital.label,
              subtitle:
                  '${a.value} Â· ${DateFormat.MMMd().add_jm().format(a.createdAt)}'
                  '${a.resolved && a.resolutionAction != null ? ' Â· ${formatAlertResolutionAction(a)}' : ''}',
              pill: a.resolved
                  ? 'Resolved'
                  : (a.acknowledged ? 'Ack' : a.severity.label),
              pillColor: a.resolved ? AppColors.success : a.severity.color,
              onTap: compact
                  ? () => Navigator.of(
                      context,
                    ).pushNamed(RouteNames.doctorAlertDetail, arguments: a.id)
                  : null,
              trailing: compact
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!a.acknowledged)
                          TextButton(
                            onPressed: () async {
                              final ok = await StaffState.instance
                                  .acknowledgeAlert(a.id);
                              if (!context.mounted) return;
                              if (ok) {
                                if (AppEnv.backendEnabled) {
                                  await DoctorSessionService.instance
                                      .syncFromApi();
                                }
                                if (!context.mounted) return;
                                AppToast.success(context, 'Acknowledged.');
                              } else {
                                AppToast.error(
                                  context,
                                  'Could not acknowledge alert.',
                                );
                              }
                            },
                            child: const Text('Ack'),
                          ),
                        if (!a.resolved)
                          TextButton(
                            onPressed: () => DoctorAlertResolveFlow.resolve(
                              context,
                              a,
                              successMessage: 'Alert resolved.',
                            ),
                            child: const Text('Resolve'),
                          ),
                      ],
                    ),
            ),
          )
          .toList(),
    );
  }
}

class _SosPanel extends StatelessWidget {
  const _SosPanel({required this.patientId});
  final String patientId;

  Future<void> _update(BuildContext context, String id, String status) async {
    final ok = await StaffState.instance.resolveSos(id, status: status);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'SOS updated.');
    } else {
      AppToast.error(context, 'Could not update SOS.');
    }
  }

  StaffPatientSos? _primaryActive(List<StaffPatientSos> active) {
    if (active.isEmpty) return null;
    active.sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    return active.first;
  }

  @override
  Widget build(BuildContext context) {
    final events = StaffState.instance.sosForPatient(patientId);
    final theme = Theme.of(context);
    final active = events.where((e) => e.isActive).toList();
    final lead = _primaryActive(active);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'Emergency / SOS', icon: AppIcons.sos),
        if (lead != null) ...[
          const SizedBox(height: AppSpacing.sm),
          SosRespondContextCard(patientId: patientId, event: lead),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Open full respond view',
            icon: AppIcons.sos,
            variant: AppButtonVariant.danger,
            expand: true,
            onPressed: () => DoctorSosRespondSheet.show(
              context,
              patientId: patientId,
              eventId: lead.id,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            frosted: true,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.criticalSoft(context),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusPill,
                        ),
                      ),
                      child: Text(
                        'ACTIVE SOS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.critical,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final e in active) ...[
                  Text(
                    e.kindLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.critical,
                    ),
                  ),
                  if (e.note != null && e.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(e.note!, style: theme.textTheme.bodyMedium),
                    ),
                  Text(
                    DateFormat.MMMd().add_jm().format(e.triggeredAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (e.status == 'active')
                    AppButton(
                      label: 'Acknowledge â€” on my way',
                      variant: AppButtonVariant.secondary,
                      expand: true,
                      onPressed: () => _update(context, e.id, 'acknowledged'),
                    ),
                  if (e.status == 'active')
                    const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (e.mapsUrl != null) ...[
                        Expanded(
                          child: AppButton(
                            label: 'Map',
                            variant: AppButtonVariant.secondary,
                            icon: AppIcons.map,
                            onPressed: () => SosContactActions.map(e.mapsUrl!),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Expanded(
                        child: AppButton(
                          label: 'Resolve',
                          variant: AppButtonVariant.danger,
                          onPressed: () => _update(context, e.id, 'resolved'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppButton(
                          label: 'False alarm',
                          variant: AppButtonVariant.secondary,
                          onPressed: () => _update(context, e.id, 'falseAlarm'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (events.isEmpty)
          GlassCard(
            frosted: true,
            child: Text(
              'No SOS events on record.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          StaffListCard(
            children: events
                .map(
                  (e) => StaffListRow(
                    icon: AppIcons.sos,
                    iconColor: e.isActive
                        ? AppColors.critical
                        : AppPalette.textMuted(context),
                    title: e.kindLabel,
                    subtitle:
                        '${DateFormat.MMMd().add_jm().format(e.triggeredAt)}${e.locationLabel != null ? ' Â· ${e.locationLabel}' : ''}${e.respondedBy != null ? ' Â· ${e.respondedBy}' : ''}',
                    pill: e.status,
                    pillColor: e.isActive
                        ? AppColors.critical
                        : AppColors.success,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _AppointmentsPanel extends StatelessWidget {
  const _AppointmentsPanel({
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final appts = StaffState.instance.appointmentsForPatient(patientId)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final now = DateTime.now();
    final upcoming = appts.where((a) => a.isUpcoming).toList();
    final past =
        appts
            .where(
              (a) => !a.isUpcoming && a.status != AppointmentStatus.cancelled,
            )
            .toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt));
    final cancelled = appts
        .where((a) => a.status == AppointmentStatus.cancelled)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Appointments',
          icon: AppIcons.appointment,
          trailing: '${appts.length}',
          actionLabel: 'Schedule',
          onAction: () => DoctorAppointmentFlows.openSchedule(
            context,
            patientId: patientId,
            patientName: patientName,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        GlassCard(
          frosted: true,
          onTap: () => DoctorAppointmentFlows.openSchedule(
            context,
            patientId: patientId,
            patientName: patientName,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(AppIcons.add, size: 18, color: AppColors.brandIndigo),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Schedule visit with $patientName',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                size: 14,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (appts.isEmpty)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.appointment,
              title: 'No appointments',
              message: 'Schedule a visit for $patientName.',
              compact: true,
              actionLabel: 'Schedule visit',
              onAction: () => DoctorAppointmentFlows.openSchedule(
                context,
                patientId: patientId,
                patientName: patientName,
              ),
            ),
          )
        else ...[
          if (upcoming.isNotEmpty) ...[
            SectionLabel(
              title: 'Upcoming',
              icon: AppIcons.calendar,
              trailing: '${upcoming.length}',
            ),
            const SizedBox(height: AppSpacing.xs),
            StaffListCard(
              children: upcoming
                  .map((a) => _appointmentRow(context, a, now))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (past.isNotEmpty) ...[
            SectionLabel(
              title: 'Past visits',
              icon: AppIcons.audit,
              trailing: '${past.length}',
            ),
            const SizedBox(height: AppSpacing.xs),
            StaffListCard(
              children: past
                  .map((a) => _appointmentRow(context, a, now))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (cancelled.isNotEmpty) ...[
            SectionLabel(
              title: 'Cancelled',
              icon: AppIcons.alert,
              trailing: '${cancelled.length}',
            ),
            const SizedBox(height: AppSpacing.xs),
            StaffListCard(
              children: cancelled
                  .map((a) => _appointmentRow(context, a, now))
                  .toList(),
            ),
          ],
        ],
      ],
    );
  }

  Widget _appointmentRow(
    BuildContext context,
    StaffAppointment a,
    DateTime now,
  ) {
    return StaffListRow(
      icon: a.type.icon,
      iconColor: a.status.color,
      title: DateFormat.MMMEd().add_jm().format(a.startAt),
      subtitle: '${a.type.label}${a.reason != null ? ' Â· ${a.reason}' : ''}',
      pill: a.isUpcoming ? _appointmentPill(a.startAt, now) : a.status.label,
      pillColor: a.isUpcoming ? AppColors.success : a.status.color,
      onTap: () => DoctorAppointmentFlows.openDetail(context, a.id),
    );
  }

  static String _appointmentPill(DateTime start, DateTime now) {
    final diff = start.difference(now);
    if (diff.inMinutes < 60 && !diff.isNegative) return 'Soon';
    if (start.year == now.year &&
        start.month == now.month &&
        start.day == now.day) {
      return 'Today';
    }
    return 'Upcoming';
  }
}
