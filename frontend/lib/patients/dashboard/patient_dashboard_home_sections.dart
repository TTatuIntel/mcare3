part of 'patient_dashboard_view.dart';

/// PDF-approved patient home composition. It deliberately derives every
/// message and count from the existing stores; the home screen never invents
/// adherence, risk, or scheduling data.
class _PatientHomeLayout extends StatelessWidget {
  const _PatientHomeLayout({
    required this.appointments,
    required this.doses,
    required this.unreadNotifications,
  });

  final List<Appointment> appointments;
  final List<MedicationDose> doses;
  final int unreadNotifications;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        final primary = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StaggeredEntry(index: 0, child: PatientDateHeader()),
            const SizedBox(height: AppSpacing.md),
            StaggeredEntry(
              index: 1,
              child: _PatientDailyPlanCard(
                appointments: appointments,
                doses: doses,
                unreadNotifications: unreadNotifications,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const StaggeredEntry(index: 2, child: _PatientVitalShortcuts()),
            const SizedBox(height: AppSpacing.lg),
            StaggeredEntry(index: 3, child: _PatientNextDoseCard(doses: doses)),
            const SizedBox(height: AppSpacing.md),
            StaggeredEntry(
              index: 4,
              child: _PatientNextVisitCard(appointments: appointments),
            ),
            const SizedBox(height: AppSpacing.lg),
            const StaggeredEntry(index: 5, child: _PatientHelpCard()),
          ],
        );

        final secondary = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _RecentVitalsPanel(),
            const SizedBox(height: AppSpacing.xl),
            SectionLabel(
              title: 'Recent activity',
              icon: AppIcons.trend,
              actionLabel: unreadNotifications > 0 ? 'Updates' : null,
              onAction: unreadNotifications > 0
                  ? () => Navigator.of(
                      context,
                    ).pushNamed(RouteNames.patientNotifications)
                  : null,
            ),
            const _CareActivityFeed(),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: primary),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 5, child: secondary),
                ],
              )
            else ...[
              primary,
              const SizedBox(height: AppSpacing.xl),
              secondary,
            ],
            const SizedBox(height: AppSpacing.huge),
          ],
        );
      },
    );
  }
}

class _PatientPlanAction {
  const _PatientPlanAction({
    required this.icon,
    required this.accent,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String detail;
  final VoidCallback onTap;
}

class _PatientDailyPlanCard extends StatelessWidget {
  const _PatientDailyPlanCard({
    required this.appointments,
    required this.doses,
    required this.unreadNotifications,
  });

  final List<Appointment> appointments;
  final List<MedicationDose> doses;
  final int unreadNotifications;

  List<_PatientPlanAction> _actions(BuildContext context) {
    final actions = <_PatientPlanAction>[];
    VitalKey? highestRiskVital;
    for (final vital in VitalsState.instance.tracked) {
      final risk = VitalsState.instance.latestOf(vital)?.risk;
      if (risk == RiskLevel.critical) {
        highestRiskVital = vital;
        break;
      }
      if (risk == RiskLevel.warning) highestRiskVital ??= vital;
    }

    if (highestRiskVital != null) {
      final reading = VitalsState.instance.latestOf(highestRiskVital);
      actions.add(
        _PatientPlanAction(
          icon: highestRiskVital.icon,
          accent: reading?.risk == RiskLevel.critical
              ? AppColors.critical
              : AppColors.warning,
          title: 'Review ${highestRiskVital.label.toLowerCase()}',
          detail: reading == null
              ? 'Open your latest reading'
              : '${reading.formatValue()} ${highestRiskVital.unit} · ${reading.risk.label}',
          onTap: () => openVitalDetail(context, highestRiskVital!),
        ),
      );
    } else {
      final tracked = VitalsState.instance.tracked.toList();
      actions.add(
        _PatientPlanAction(
          icon: AppIcons.vitals,
          accent: AppColors.brandIndigo,
          title: 'Record your vitals',
          detail: tracked.isEmpty
              ? 'Choose a vital and add today\'s reading'
              : 'Keep your care team up to date',
          onTap: () => SubmitVitalSheet.show(
            context,
            initial: tracked.isEmpty ? null : tracked.first,
          ),
        ),
      );
    }

    final pending = doses.where((d) => d.status == DoseStatus.pending).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    if (pending.isNotEmpty) {
      final dose = pending.first;
      actions.add(
        _PatientPlanAction(
          icon: AppIcons.medication,
          accent: AppColors.success,
          title: 'Take your medication',
          detail: '${dose.name} · ${DateFormat.jm().format(dose.scheduledAt)}',
          onTap: () => LogDoseSheet.show(context, dose),
        ),
      );
    }

    if (appointments.isNotEmpty) {
      final appointment = appointments.first;
      actions.add(
        _PatientPlanAction(
          icon: AppIcons.appointment,
          accent: AppColors.bpPurple,
          title: 'Prepare for your next visit',
          detail: _patientVisitTime(appointment.scheduledAt),
          onTap: () => Navigator.of(context).pushNamed(
            RouteNames.patientAppointmentDetail,
            arguments: appointment.id,
          ),
        ),
      );
    }

    if (unreadNotifications > 0) {
      actions.add(
        _PatientPlanAction(
          icon: AppIcons.bell,
          accent: AppColors.info,
          title: 'Review care updates',
          detail:
              '$unreadNotifications unread update${unreadNotifications == 1 ? '' : 's'}',
          onTap: () =>
              Navigator.of(context).pushNamed(RouteNames.patientNotifications),
        ),
      );
    }
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context);
    final visible = actions.take(3).toList();

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.brandIndigo.withValues(alpha: 0.10),
          AppPalette.surface(context),
        ],
      ),
      border: Border.all(color: AppColors.brandIndigo.withValues(alpha: 0.18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PatientIconDisc(
                icon: AppIcons.catalog,
                color: AppColors.brandIndigo,
                size: 52,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your care plan today',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${visible.length} priority step${visible.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.brandIndigo,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var index = 0; index < visible.length; index++) ...[
            _PatientPlanActionRow(action: visible[index]),
            if (index != visible.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _PatientPlanActionRow extends StatelessWidget {
  const _PatientPlanActionRow({required this.action});

  final _PatientPlanAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.surface(context),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            children: [
              _PatientIconDisc(icon: action.icon, color: action.accent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(AppIcons.chevronRight, color: action.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientVitalShortcuts extends StatelessWidget {
  const _PatientVitalShortcuts();

  @override
  Widget build(BuildContext context) {
    final tracked = VitalsState.instance.tracked.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final choices = tracked.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Record a vital', icon: AppIcons.vitals),
        LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 480;
            final tiles = choices.isEmpty
                ? <Widget>[
                    _PatientVitalShortcut(
                      label: 'Choose a vital',
                      icon: AppIcons.vitals,
                      color: AppColors.brandIndigo,
                      onTap: () => SubmitVitalSheet.show(context),
                    ),
                  ]
                : choices
                      .map(
                        (vital) => _PatientVitalShortcut(
                          label: vital.shortLabel,
                          icon: vital.icon,
                          color: vital.accent,
                          onTap: () =>
                              SubmitVitalSheet.show(context, initial: vital),
                        ),
                      )
                      .toList();
            if (horizontal && tiles.length > 1) {
              return Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: tiles[1]),
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  tiles[i],
                  if (i != tiles.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PatientVitalShortcut extends StatelessWidget {
  const _PatientVitalShortcut({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      background: color.withValues(alpha: 0.055),
      border: Border.all(color: color.withValues(alpha: 0.18)),
      child: Row(
        children: [
          _PatientIconDisc(icon: icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Icon(AppIcons.add, color: color, size: 20),
        ],
      ),
    );
  }
}

class _PatientNextDoseCard extends StatelessWidget {
  const _PatientNextDoseCard({required this.doses});

  final List<MedicationDose> doses;

  @override
  Widget build(BuildContext context) {
    final pending = doses.where((d) => d.status == DoseStatus.pending).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final dose = pending.isEmpty ? null : pending.first;

    return _PatientNextCard(
      eyebrow: dose == null ? 'Medication plan' : 'Next medication',
      title:
          dose?.name ??
          (doses.isEmpty
              ? 'No doses scheduled today'
              : 'Today\'s doses logged'),
      detail: dose == null
          ? 'Open medications to review your plan'
          : '${dose.dosage} · ${DateFormat.jm().format(dose.scheduledAt)}',
      icon: AppIcons.medication,
      color: AppColors.success,
      actionLabel: dose == null ? 'View plan' : 'Log dose',
      onTap: () {
        if (dose != null) {
          LogDoseSheet.show(context, dose);
        } else {
          Navigator.of(context).pushNamed(RouteNames.patientMedications);
        }
      },
    );
  }
}

class _PatientNextVisitCard extends StatelessWidget {
  const _PatientNextVisitCard({required this.appointments});

  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    final visit = appointments.isEmpty ? null : appointments.first;
    return _PatientNextCard(
      eyebrow: 'Next appointment',
      title: visit?.doctorName ?? 'No upcoming appointment',
      detail: visit == null
          ? 'Book or review your visits'
          : _patientVisitTime(visit.scheduledAt),
      icon: AppIcons.appointment,
      color: AppColors.bpPurple,
      actionLabel: visit == null ? 'Appointments' : 'View details',
      onTap: () => Navigator.of(context).pushNamed(
        visit == null
            ? RouteNames.patientAppointments
            : RouteNames.patientAppointmentDetail,
        arguments: visit?.id,
      ),
    );
  }
}

class _PatientNextCard extends StatelessWidget {
  const _PatientNextCard({
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.actionLabel,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          final content = Row(
            children: [
              _PatientIconDisc(icon: icon, color: color, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: AppSpacing.md),
                AppButton(
                  label: actionLabel,
                  onPressed: onTap,
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.secondary,
                  trailingIcon: AppIcons.chevronRight,
                ),
              ],
            ],
          );
          if (!compact) return content;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: actionLabel,
                onPressed: onTap,
                size: AppButtonSize.sm,
                variant: AppButtonVariant.secondary,
                trailingIcon: AppIcons.chevronRight,
                expand: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PatientHelpCard extends StatelessWidget {
  const _PatientHelpCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      background: AppColors.brandIndigo.withValues(alpha: 0.04),
      border: Border.all(color: AppColors.brandIndigo.withValues(alpha: 0.16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Need help now?',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = constraints.maxWidth >= 480;
              final care = AppButton(
                label: 'Contact care team',
                icon: AppIcons.support,
                trailingIcon: AppIcons.chevronRight,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: () =>
                    Navigator.of(context).pushNamed(RouteNames.patientCareTeam),
              );
              final sos = AppButton(
                label: 'SOS',
                icon: AppIcons.sos,
                trailingIcon: AppIcons.chevronRight,
                variant: AppButtonVariant.danger,
                expand: true,
                onPressed: () =>
                    Navigator.of(context).pushNamed(RouteNames.patientSos),
              );
              if (horizontal) {
                return Row(
                  children: [
                    Expanded(child: care),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: sos),
                  ],
                );
              }
              return Column(
                children: [
                  care,
                  const SizedBox(height: AppSpacing.sm),
                  sos,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PatientIconDisc extends StatelessWidget {
  const _PatientIconDisc({
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.45),
    );
  }
}

String _patientVisitTime(DateTime scheduledAt) {
  final now = DateTime.now();
  final day = DateUtils.isSameDay(scheduledAt, now)
      ? 'Today'
      : DateUtils.isSameDay(scheduledAt, now.add(const Duration(days: 1)))
      ? 'Tomorrow'
      : DateFormat.MMMEd().format(scheduledAt);
  return '$day · ${DateFormat.jm().format(scheduledAt)}';
}
