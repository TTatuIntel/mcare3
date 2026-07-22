import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/vitals/vital_structure.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_stat_cards.dart';

/// Full caseload analytics for a doctor — vital trends, alert frequency,
/// condition mix, adherence and workload. Every tile and chart drills into
/// the matching working surface (patients, alerts, vitals, visits, reports).
class DoctorOverviewView extends StatefulWidget {
  const DoctorOverviewView({super.key});

  @override
  State<DoctorOverviewView> createState() => _DoctorOverviewViewState();
}

class _DoctorOverviewViewState extends State<DoctorOverviewView> {
  int _alertWindowDays = 7;

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorOverview,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Overview',
      subtitle: 'Caseload analytics · ${DateFormat.MMMEd().format(DateTime.now())}',
      headerActions: [
        AppButton(
          label: 'Report',
          icon: AppIcons.report,
          size: AppButtonSize.sm,
          onPressed: () => _startCaseloadReport(context),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final assigned = StaffState.instance.assignedPatientsForDoctor();
          final ids = assigned.map((p) => p.id).toSet();

          if (assigned.isEmpty) {
            return const EmptyStateView(
              icon: AppIcons.patients,
              title: 'No assigned patients yet',
              message:
                  'When patients are assigned to you, their analytics show up here.',
            );
          }

          final alerts = StaffState.instance.alerts
              .where((a) => ids.contains(a.patientId))
              .toList();
          final alertSummary =
              StaffState.instance.caseloadAlertSummary(patientIds: ids);
          final critical = alertSummary.criticalCount;
          final readings = StaffState.instance.patientVitalReadings
              .where((r) => ids.contains(r.patientId))
              .toList();
          final appts = StaffState.instance.appointments
              .where((a) => a.patientId != null && ids.contains(a.patientId))
              .toList();
          final reports = StaffState.instance.reports
              .where((r) => assigned.any((p) => p.name == r.patientName))
              .toList();

          final attention = assigned
              .where((p) =>
                  p.risk == RiskLevel.critical ||
                  p.risk == RiskLevel.warning ||
                  p.unreadAlerts > 0)
              .length;
          final stable = assigned.length - attention;

          final adherence = _adherenceFor(assigned, readings);
          final accent = Theme.of(context).colorScheme.primary;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: StaffStatCardsGrid(
                  cards: [
                    StaffStatCardData(
                      value: '${assigned.length}',
                      label: 'Assigned',
                      detail: attention > 0
                          ? '$attention need monitoring'
                          : '$stable stable',
                      icon: AppIcons.patients,
                      accent: accent,
                      onTap: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorPatients),
                    ),
                    StaffStatCardData(
                      value: '$attention',
                      label: 'Need attention',
                      detail:
                          critical > 0 ? '$critical critical' : 'No critical',
                      icon: AppIcons.alert,
                      accent: critical > 0
                          ? AppColors.critical
                          : (attention > 0
                              ? AppColors.warning
                              : AppPalette.textMuted(context)),
                      onTap: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorPatients),
                    ),
                    StaffStatCardData(
                      value: '${alertSummary.openCount}',
                      label: 'Open alerts',
                      detail: alertSummary.kpiDetail,
                      icon: AppIcons.bell,
                      accent: alertSummary.kpiAccent(),
                      pulse: alertSummary.shouldPulse,
                      cardKey: ValueKey(
                        'overview-alerts-${alertSummary.openCount}-${alertSummary.kpiDetail}',
                      ),
                      onTap: () =>
                          openCaseloadAlertPrimary(context, alertSummary),
                    ),
                    StaffStatCardData(
                      value: '${adherence.toStringAsFixed(0)}%',
                      label: 'Adherence',
                      detail: 'Readings in last 7d',
                      icon: AppIcons.check,
                      accent: adherence >= 70
                          ? AppColors.success
                          : (adherence >= 40
                              ? AppColors.warning
                              : AppPalette.textMuted(context)),
                      onTap: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorVitals),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 1,
                child: SectionLabel(
                  title: 'Alert frequency · last $_alertWindowDays days',
                  icon: AppIcons.trend,
                  actionLabel: 'View alerts',
                  onAction: () => Navigator.of(context)
                      .pushNamed(RouteNames.doctorAlerts),
                ),
              ),
              StaggeredEntry(
                index: 2,
                child: _AlertFrequencyCard(
                  alerts: alerts,
                  windowDays: _alertWindowDays,
                  onWindowChanged: (d) =>
                      setState(() => _alertWindowDays = d),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: 'Condition distribution',
                  icon: AppIcons.chart,
                  actionLabel: 'Patients',
                  onAction: () => Navigator.of(context)
                      .pushNamed(RouteNames.doctorPatients),
                ),
              ),
              StaggeredEntry(
                index: 4,
                child: _ConditionBreakdownCard(patients: assigned),
              ),
              const SizedBox(height: AppSpacing.lg),
              StaggeredEntry(
                index: 5,
                child: const SectionLabel(
                  title: 'Workload · visits and reports',
                  icon: AppIcons.appointment,
                ),
              ),
              StaggeredEntry(
                index: 6,
                child: _WorkloadCard(
                  appointments: appts.length,
                  reports: reports.length,
                  prescriptions: StaffState.instance.prescriptions
                      .where((p) => ids.contains(p.patientId))
                      .length,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              StaggeredEntry(
                index: 7,
                child: SectionLabel(
                  title: 'Risk by patient',
                  icon: AppIcons.patients,
                  actionLabel: 'Open caseload',
                  onAction: () => Navigator.of(context)
                      .pushNamed(RouteNames.doctorPatients),
                ),
              ),
              StaggeredEntry(
                index: 8,
                child: _RiskDistributionCard(patients: assigned),
              ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  static void _startCaseloadReport(BuildContext context) {
    final assigned = StaffState.instance.assignedPatientsForDoctor();
    Navigator.of(context).pushNamed(
      RouteNames.doctorReportEditor,
      arguments: 'Caseload (${assigned.length} patients)',
    );
  }

  double _adherenceFor(
      List<StaffPatient> patients, List<StaffPatientVitalReading> readings) {
    if (patients.isEmpty) return 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final active = readings
        .where((r) => r.recordedAt.isAfter(cutoff))
        .map((r) => r.patientId)
        .toSet()
        .length;
    return (active / patients.length) * 100;
  }
}

class _AlertFrequencyCard extends StatelessWidget {
  const _AlertFrequencyCard({
    required this.alerts,
    required this.windowDays,
    required this.onWindowChanged,
  });

  final List<StaffAlert> alerts;
  final int windowDays;
  final ValueChanged<int> onWindowChanged;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: windowDays - 1));
    final counts = List<int>.filled(windowDays, 0);
    for (final a in alerts) {
      final d = a.createdAt;
      final day = DateTime(d.year, d.month, d.day);
      final delta = day.difference(start).inDays;
      if (delta >= 0 && delta < windowDays) counts[delta]++;
    }
    final total = counts.fold<int>(0, (s, v) => s + v);
    final peak = counts.fold<int>(0, (m, v) => v > m ? v : m);
    final avg = windowDays == 0 ? 0.0 : total / windowDays;
    final maxY = (peak + 1).toDouble();
    final accent = Theme.of(context).colorScheme.primary;

    // Sparser X-axis labels for longer windows so the chart stays legible.
    final labelStep = windowDays <= 7
        ? 1
        : windowDays <= 14
            ? 2
            : 5;
    final barWidth =
        windowDays <= 7 ? 14.0 : (windowDays <= 14 ? 10.0 : 6.0);

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MetricChip(label: 'Total', value: '$total'),
                    _MetricChip(label: 'Peak', value: '$peak / day'),
                    _MetricChip(
                        label: 'Avg', value: avg.toStringAsFixed(1)),
                  ],
                ),
              ),
              _WindowSelector(
                value: windowDays,
                onChanged: onWindowChanged,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        AppPalette.textMuted(context).withOpacity(0.95),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 6,
                    ),
                    getTooltipItem: (group, _, rod, __) {
                      final d =
                          start.add(Duration(days: group.x.toInt()));
                      final n = rod.toY.toInt();
                      return BarTooltipItem(
                        '${DateFormat.MMMd().format(d)}\n$n ${n == 1 ? 'alert' : 'alerts'}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval:
                      maxY <= 2 ? 1 : (maxY / 4).ceilToDouble(),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppPalette.textMuted(context).withOpacity(0.15),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: maxY <= 2 ? 1 : (maxY / 4).ceilToDouble(),
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          color: AppPalette.textMuted(context),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx % labelStep != 0 &&
                            idx != windowDays - 1) {
                          return const SizedBox.shrink();
                        }
                        final d = start.add(Duration(days: idx));
                        final label = windowDays <= 7
                            ? DateFormat.E().format(d).substring(0, 1)
                            : DateFormat.Md().format(d);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: AppPalette.textMuted(context),
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < counts.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: counts[i].toDouble(),
                          width: barWidth,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                          color: counts[i] >= 4
                              ? AppColors.critical
                              : counts[i] >= 2
                                  ? AppColors.warning
                                  : accent,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowSelector extends StatelessWidget {
  const _WindowSelector({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [7, 14, 30];
    final accent = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 4,
      children: [
        for (final opt in options)
          InkWell(
            onTap: () => onChanged(opt),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: opt == value
                    ? accent
                    : accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                '${opt}d',
                style: TextStyle(
                  color: opt == value ? Colors.white : accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ConditionBreakdownCard extends StatelessWidget {
  const _ConditionBreakdownCard({required this.patients});
  final List<StaffPatient> patients;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = <String, int>{};
    for (final p in patients) {
      buckets.update(p.condition, (v) => v + 1, ifAbsent: () => 1);
    }
    final entries = buckets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = patients.length;
    final colors = [
      Theme.of(context).colorScheme.primary,
      AppColors.bpPurple,
      AppColors.spo2Blue,
      AppColors.glucoseAmber,
      AppColors.respGreen,
      AppColors.heartRed,
      AppColors.tempTeal,
    ];

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            InkWell(
              onTap: () => Navigator.of(context)
                  .pushNamed(RouteNames.doctorPatients),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 10,
                          width: 10,
                          decoration: BoxDecoration(
                            color: colors[i % colors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            entries[i].key,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${entries[i].value} · ${((entries[i].value / total) * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.labelSmall?.copyWith(
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
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: entries[i].value / total,
                        minHeight: 6,
                        backgroundColor: AppPalette.surfaceMuted(context),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors[i % colors.length],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < entries.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _WorkloadCard extends StatelessWidget {
  const _WorkloadCard({
    required this.appointments,
    required this.reports,
    required this.prescriptions,
  });
  final int appointments;
  final int reports;
  final int prescriptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: _WorkloadStat(
              label: 'Appointments',
              value: '$appointments',
              icon: AppIcons.appointment,
              accent: theme.colorScheme.primary,
              onTap: () => Navigator.of(context)
                  .pushNamed(RouteNames.doctorVisits),
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: AppPalette.textMuted(context).withOpacity(0.15),
          ),
          Expanded(
            child: _WorkloadStat(
              label: 'Reports',
              value: '$reports',
              icon: AppIcons.report,
              accent: AppColors.spo2Blue,
              onTap: () => Navigator.of(context)
                  .pushNamed(RouteNames.doctorReports),
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: AppPalette.textMuted(context).withOpacity(0.15),
          ),
          Expanded(
            child: _WorkloadStat(
              label: 'Rx active',
              value: '$prescriptions',
              icon: AppIcons.prescription,
              accent: AppColors.glucoseAmber,
              onTap: () => Navigator.of(context)
                  .pushNamed(RouteNames.doctorPrescriptions),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkloadStat extends StatelessWidget {
  const _WorkloadStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskDistributionCard extends StatelessWidget {
  const _RiskDistributionCard({required this.patients});
  final List<StaffPatient> patients;

  @override
  Widget build(BuildContext context) {
    final critical =
        patients.where((p) => p.risk == RiskLevel.critical).length;
    final warning =
        patients.where((p) => p.risk == RiskLevel.warning).length;
    final normal =
        patients.where((p) => p.risk == RiskLevel.normal).length;
    final unknown =
        patients.where((p) => p.risk == RiskLevel.unknown).length;
    final total = patients.length.toDouble();
    if (total == 0) return const SizedBox.shrink();

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          InkWell(
            onTap: () => Navigator.of(context)
                .pushNamed(RouteNames.doctorPatients),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: SizedBox(
              height: 160,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 38,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(enabled: true),
                  sections: [
                    if (critical > 0)
                      PieChartSectionData(
                        value: critical / total * 100,
                        color: AppColors.critical,
                        title: '$critical',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        radius: 46,
                      ),
                    if (warning > 0)
                      PieChartSectionData(
                        value: warning / total * 100,
                        color: AppColors.warning,
                        title: '$warning',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        radius: 46,
                      ),
                    if (normal > 0)
                      PieChartSectionData(
                        value: normal / total * 100,
                        color: AppColors.success,
                        title: '$normal',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        radius: 46,
                      ),
                    if (unknown > 0)
                      PieChartSectionData(
                        value: unknown / total * 100,
                        color: AppPalette.textMuted(context),
                        title: '$unknown',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        radius: 46,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              if (critical > 0)
                InkWell(
                  onTap: () => Navigator.of(context)
                      .pushNamed(RouteNames.doctorPatients),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusPill),
                  child: const RiskBadge(risk: RiskLevel.critical),
                ),
              if (warning > 0)
                InkWell(
                  onTap: () => Navigator.of(context)
                      .pushNamed(RouteNames.doctorPatients),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusPill),
                  child: const RiskBadge(risk: RiskLevel.warning),
                ),
              if (normal > 0)
                InkWell(
                  onTap: () => Navigator.of(context)
                      .pushNamed(RouteNames.doctorPatients),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusPill),
                  child: const RiskBadge(risk: RiskLevel.normal),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
