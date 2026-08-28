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
            // Emergency + help closes every layout (wide and narrow): it is the
            // last block on the page, inside thumb reach, and the only place
            // home surfaces SOS.
            const SizedBox(height: AppSpacing.xl),
            const StaggeredEntry(index: 6, child: _PatientHelpCard()),
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

/// Home "Record a vital" board.
///
/// Shows every vital the patient tracks (care-team assigned first, then the
/// ones they self-assigned), each carrying its latest reading, status and
/// trend so logging is a decision, not a guess. The board is also the entry
/// point for self-assignment: "Manage" and the trailing add tile both open
/// [VitalPreferencesSheet], where optional vitals can be switched on.
class _PatientVitalShortcuts extends StatelessWidget {
  const _PatientVitalShortcuts();

  /// Keep home scannable — the rest stay one tap away on the Vitals screen.
  static const _maxTiles = 6;

  /// Alerting first, then critical / watch, then most recently updated. The
  /// reading a clinician would look at first is the one nearest the thumb.
  static List<VitalKey> _ordered(List<VitalKey> tracked) {
    int priority(VitalKey key) {
      if (NotificationState.instance.vitalAlertFor(key) != null) return 0;
      return switch (VitalsState.instance.latestOf(key)?.risk) {
        RiskLevel.critical => 1,
        RiskLevel.warning => 2,
        _ => 3,
      };
    }

    return tracked.toList()..sort((a, b) {
      final byPriority = priority(a).compareTo(priority(b));
      if (byPriority != 0) return byPriority;
      final assignedA = VitalsState.instance.isAssigned(a);
      final assignedB = VitalsState.instance.isAssigned(b);
      if (assignedA != assignedB) return assignedA ? -1 : 1;
      final ra = VitalsState.instance.latestOf(a)?.recordedAt;
      final rb = VitalsState.instance.latestOf(b)?.recordedAt;
      if (ra == null && rb == null) return a.index.compareTo(b.index);
      if (ra == null) return 1;
      if (rb == null) return -1;
      return rb.compareTo(ra);
    });
  }

  static int _columnsFor(double width) {
    if (width >= 960) return 4;
    if (width >= 620) return 3;
    return 2;
  }

  static VitalReading? _previousReading(VitalKey vital) {
    final history = VitalsState.instance.forVital(vital);
    return history.length > 1 ? history[1] : null;
  }

  @override
  Widget build(BuildContext context) {
    final state = VitalsState.instance;
    final tracked = _ordered(state.tracked.toList());
    final shown = tracked.take(_maxTiles).toList();
    final hidden = tracked.length - shown.length;
    final canAddMore = state.selectableVitals.any(
      (v) => !state.tracked.contains(v),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Record a vital',
          icon: AppIcons.vitals,
          trailing: tracked.isEmpty ? null : '${tracked.length} tracked',
          actionLabel: canAddMore ? 'Manage' : null,
          onAction: canAddMore
              ? () => VitalPreferencesSheet.show(context)
              : null,
        ),
        if (tracked.isEmpty)
          GlassCard(
            child: EmptyStateView(
              icon: AppIcons.vitals,
              title: 'Nothing tracked yet',
              message:
                  'Choose the vitals you want to record. Anything your care '
                  'team assigns is added here automatically.',
              actionLabel: 'Choose vitals',
              onAction: () => VitalPreferencesSheet.show(context),
              compact: true,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = _columnsFor(constraints.maxWidth);
              const gap = AppSpacing.sm;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              final tiles = <Widget>[
                for (final vital in shown)
                  _PatientVitalCard(
                    vital: vital,
                    reading: state.latestOf(vital),
                    previous: _previousReading(vital),
                    alert: NotificationState.instance.vitalAlertFor(vital),
                    assigned: state.isAssigned(vital),
                    onLog: () => SubmitVitalSheet.show(context, initial: vital),
                    onOpen: () => openVitalDetail(context, vital),
                  ),
                if (canAddMore || hidden > 0)
                  _PatientAddVitalCard(
                    label: canAddMore ? 'Add a vital' : 'See all vitals',
                    detail: hidden > 0
                        ? '$hidden more tracked · tap to review'
                        : 'Track what matters to you',
                    onTap: canAddMore
                        ? () => VitalPreferencesSheet.show(context)
                        : () => Navigator.of(
                            context,
                          ).pushNamed(RouteNames.patientVitals),
                  ),
              ];

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tile in tiles)
                    SizedBox(width: tileWidth, child: tile),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// One vital on the home board: latest value, status, trend and a log action.
class _PatientVitalCard extends StatelessWidget {
  const _PatientVitalCard({
    required this.vital,
    required this.reading,
    required this.previous,
    required this.alert,
    required this.assigned,
    required this.onLog,
    required this.onOpen,
  });

  final VitalKey vital;
  final VitalReading? reading;
  final VitalReading? previous;
  final AppNotification? alert;
  final bool assigned;
  final VoidCallback onLog;
  final VoidCallback onOpen;

  /// Signed change against the previous reading, or null when there is no
  /// comparison to make. Blood pressure trends on its systolic value.
  double? get _delta {
    final current = reading;
    final before = previous;
    if (current == null || before == null) return null;
    final diff = current.value - before.value;
    return diff.abs() < 0.05 ? 0 : diff;
  }

  String _formatDelta(double delta) {
    final magnitude = delta.abs();
    final text = (vital == VitalKey.temperature || vital == VitalKey.weight)
        ? magnitude.toStringAsFixed(1)
        : magnitude.toStringAsFixed(0);
    return '${delta > 0 ? '+' : '-'}$text';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = vital.accent;
    final risk = reading?.risk ?? RiskLevel.unknown;
    final delta = _delta;
    final statusColor = alert != null ? alert!.kind.tint : risk.color;
    final calm = risk == RiskLevel.normal || risk == RiskLevel.unknown;

    return GlassCard(
      onTap: onLog,
      padding: const EdgeInsets.all(AppSpacing.md),
      background: accent.withValues(alpha: 0.055),
      border: Border.all(
        color: calm && alert == null
            ? accent.withValues(alpha: 0.18)
            : statusColor.withValues(alpha: 0.38),
        width: risk == RiskLevel.critical ? 1.4 : 1,
      ),
      child: Semantics(
        button: true,
        label:
            '${vital.label}, '
            '${reading == null ? 'no reading yet' : '${reading!.formatValue()} ${vital.unit}, ${risk.label}'}. '
            'Log a reading.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _PatientIconDisc(icon: vital.icon, color: accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vital.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        assigned ? 'Care team' : 'Self-tracked',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: assigned
                              ? accent
                              : AppPalette.textFaint(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (delta != null && delta != 0) ...[
                  const SizedBox(width: 2),
                  Icon(
                    delta > 0 ? AppIcons.trendUp : AppIcons.trendDown,
                    size: 14,
                    color: AppPalette.textMuted(context),
                  ),
                  const SizedBox(width: 1),
                  Text(
                    _formatDelta(delta),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: reading?.formatValue() ?? '—',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: reading == null
                            ? AppPalette.textFaint(context)
                            : accent,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    TextSpan(
                      text: ' ${vital.unit}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: RiskBadge(
                risk: risk,
                dense: true,
                label: alert != null ? 'Alert' : null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: reading == null ? onLog : onOpen,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      reading == null
                          ? 'Not logged yet'
                          : _relativeTime(reading!.recordedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.add, size: 13, color: accent),
                      const SizedBox(width: 2),
                      Text(
                        'Log',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Trailing tile on the vitals board — patient self-assignment lives here.
class _PatientAddVitalCard extends StatelessWidget {
  const _PatientAddVitalCard({
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = AppColors.brandIndigo;

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      background: AppPalette.surfaceAlt(context),
      border: Border.all(color: accent.withValues(alpha: 0.30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _PatientIconDisc(icon: AppIcons.add, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              height: 1.3,
              color: AppPalette.textMuted(context),
            ),
          ),
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

/// End-of-page emergency + help block.
///
/// It is the LAST card on the patient home page on purpose: the fastest place
/// to reach with a thumb, and the single home-screen entry point for SOS. The
/// account sheet deliberately no longer repeats an "Emergency SOS" row (see
/// `ProfileNavigation.menuFor`) so the action lives in exactly one place per
/// surface — here, and on the Care tab.
///
/// Everything shown is derived from existing stores ([SosState],
/// [ProfileState]); the card never invents emergency state.
class _PatientHelpCard extends StatelessWidget {
  const _PatientHelpCard();

  void _open(BuildContext context, String route) =>
      Navigator.of(context).pushNamed(route);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([SosState.instance, ProfileState.instance]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final active = SosState.instance.hasActiveSos;
        final contacts = SosState.instance.contacts.length;
        final shareLocation =
            ProfileState.instance.health?.locationConsent ?? false;
        final accent = active ? AppColors.critical : AppColors.brandIndigo;

        return GlassCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          background: accent.withValues(alpha: 0.04),
          border: Border.all(
            color: accent.withValues(alpha: active ? 0.38 : 0.16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PatientIconDisc(icon: AppIcons.sos, color: accent),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active ? 'SOS is active' : 'Need help now?',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          active
                              ? 'Your care team has been alerted and is responding.'
                              : 'Emergency help and your care team, one tap away.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: active ? 'View SOS status' : 'Emergency SOS',
                icon: AppIcons.sos,
                trailingIcon: AppIcons.chevronRight,
                variant: active
                    ? AppButtonVariant.secondary
                    : AppButtonVariant.danger,
                size: AppButtonSize.lg,
                expand: true,
                onPressed: () => _open(context, RouteNames.patientSos),
              ),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth >= 420;
                  final care = AppButton(
                    label: 'Contact care team',
                    icon: AppIcons.careTeam,
                    trailingIcon: horizontal ? null : AppIcons.chevronRight,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: () => _open(context, RouteNames.patientCareTeam),
                  );
                  final support = AppButton(
                    label: 'Support',
                    icon: AppIcons.support,
                    trailingIcon: horizontal ? null : AppIcons.chevronRight,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: () => _open(context, RouteNames.patientSupport),
                  );
                  if (horizontal) {
                    return Row(
                      children: [
                        Expanded(child: care),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: support),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      care,
                      const SizedBox(height: AppSpacing.sm),
                      support,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _PatientHelpMeta(
                contacts: contacts,
                shareLocation: shareLocation,
                onManage: () => _open(context, RouteNames.patientSos),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Readiness line under the help actions — what actually happens on SOS.
class _PatientHelpMeta extends StatelessWidget {
  const _PatientHelpMeta({
    required this.contacts,
    required this.shareLocation,
    required this.onManage,
  });

  final int contacts;
  final bool shareLocation;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final muted = AppPalette.textMuted(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: muted);

    // Flexible, not a bare Text: a Wrap hands each child the full line width,
    // so a label that measures wider than the card (longer contact counts, a
    // wider font, a narrow phone) overflows the row instead of wrapping.
    Widget chip(IconData icon, String text, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip(
          contacts > 0 ? AppIcons.check : AppIcons.alert,
          contacts > 0
              ? '$contacts emergency contact${contacts == 1 ? '' : 's'}'
              : 'No emergency contacts yet',
          contacts > 0 ? AppColors.success : AppColors.warning,
        ),
        chip(
          AppIcons.location,
          shareLocation ? 'Location shared on SOS' : 'Location sharing off',
          shareLocation ? AppColors.success : muted,
        ),
        InkWell(
          onTap: onManage,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(
              'Manage',
              style: style?.copyWith(
                color: AppColors.brandIndigo,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
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
