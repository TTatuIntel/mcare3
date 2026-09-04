import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/medication.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';
import 'add_medication_sheet.dart';
import 'all_medications_sheet.dart';
import 'dose_detail_sheet.dart';
import 'log_dose_sheet.dart';
import 'medication_detail_sheet.dart';

String _relativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Higher = more urgent, so an expired medication always wins the hero banner.
int _alertUrgency(MedicationAlertKind kind) => switch (kind) {
  MedicationAlertKind.expired => 3,
  MedicationAlertKind.refillLow => 2,
  MedicationAlertKind.expiringSoon => 1,
};

String _alertActionLabel(MedicationAlertKind kind) => switch (kind) {
  MedicationAlertKind.expired => 'Review now',
  MedicationAlertKind.refillLow => 'Request refill',
  MedicationAlertKind.expiringSoon => 'Review',
};

class MedicationsView extends StatelessWidget {
  const MedicationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);

    return PatientScaffold(
      currentRoute: RouteNames.patientMedications,
      title: 'Medications',
      subtitle: 'Today\'s doses, prescriptions and reminders',
      body: AnimatedBuilder(
        animation: MedicationsState.instance,
        builder: (context, _) {
          final state = MedicationsState.instance;
          final today = state.dosesForToday();
          final alerts = state.medicationAlerts();
          final activity = state.recentActivity(limit: 4);
          final takenToday = today
              .where((d) => d.status == DoseStatus.taken)
              .length;
          final pendingToday = today
              .where((d) => d.status == DoseStatus.pending)
              .length;
          final missedToday = today
              .where((d) => d.status == DoseStatus.missed)
              .length;
          final actionableToday = today
              .where((d) => d.status != DoseStatus.taken)
              .toList();

          MedicationDose? nextDose;
          for (final d in today) {
            if (d.status == DoseStatus.pending) {
              nextDose = d;
              break;
            }
          }

          final todayStr = DateFormat('EEE, MMM d').format(DateTime.now());
          final showSchedule = actionableToday.isNotEmpty;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: _MedsHero(
                  dateLabel: todayStr,
                  adherence: state.adherencePercent(),
                  taken: takenToday,
                  total: today.length,
                  pending: pendingToday,
                  missed: missedToday,
                  nextDose: nextDose,
                  alerts: alerts,
                  onAlertTap: (alert) {
                    final med = state.byId(alert.medicationId);
                    if (med != null) MedicationDetailSheet.show(context, med);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _MedsQuickActions(
                  onAdd: () => AddMedicationSheet.show(context),
                  alertCount: alerts.length,
                  medCount: state.active.length,
                ),
              ),
              if (showSchedule) ...[
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(
                  index: 2,
                  child: SectionLabel(
                    title: 'Needs action',
                    icon: AppIcons.time,
                    trailing: '$takenToday/${today.length} taken',
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                StaggeredEntry(
                  index: 3,
                  child: _TodayScheduleCard(doses: actionableToday),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 4,
                child: SectionLabel(
                  title: 'Recent activity',
                  icon: AppIcons.records,
                  trailing: '${activity.length} events',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredEntry(
                index: 5,
                child: _ActivityFeed(activity: activity),
              ),
              SizedBox(
                height: tier.isHandheld ? AppSpacing.xl : AppSpacing.huge,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MedsHero extends StatelessWidget {
  const _MedsHero({
    required this.dateLabel,
    required this.adherence,
    required this.taken,
    required this.total,
    required this.pending,
    required this.missed,
    required this.nextDose,
    required this.alerts,
    required this.onAlertTap,
  });

  final String dateLabel;
  final double adherence;
  final int taken;
  final int total;
  final int pending;
  final int missed;
  final MedicationDose? nextDose;
  final List<MedicationAlert> alerts;
  final void Function(MedicationAlert alert) onAlertTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Surface the most urgent alert first (expired > refill/expiring) so the
    // patient always sees the critical one.
    final sortedAlerts = [...alerts]
      ..sort((a, b) => _alertUrgency(b.kind).compareTo(_alertUrgency(a.kind)));
    final primaryAlert = sortedAlerts.isNotEmpty ? sortedAlerts.first : null;
    final isAlert = primaryAlert != null;
    final isPending = pending > 0;

    // Use the alert's own tint so an EXPIRED med reads as critical (red),
    // not a soft amber warning — this is the signal the patient must notice.
    final accent = isAlert
        ? primaryAlert.tint
        : isPending
        ? AppColors.glucoseAmber
        : AppColors.brandIndigo;
    final iconBg = isAlert
        ? primaryAlert.tint.withValues(alpha: 0.15)
        : isPending
        ? AppColors.glucoseAmber.withValues(alpha: 0.15)
        : AppPalette.infoSoft(context);

    final headline = total == 0
        ? 'Track your medications'
        : pending == 0
        ? 'All doses taken today'
        : '$pending dose${pending == 1 ? '' : 's'} left today';

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + 2,
        AppSpacing.md,
        AppSpacing.sm + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  isAlert ? AppIcons.alert : AppIcons.medication,
                  color: accent,
                  size: 21,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    if (nextDose != null && primaryAlert != null)
                      Text(
                        'Next ${DateFormat.jm().format(nextDose!.scheduledAt)} · ${nextDose!.name}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Text(
                dateLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (primaryAlert != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _HeroAlertBanner(
                alert: primaryAlert,
                extraCount: alerts.length - 1,
                onTap: () => onAlertTap(primaryAlert),
              ),
            )
          else if (nextDose != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: _HeroInsight(
                icon: AppIcons.time,
                color: AppColors.glucoseAmber,
                label: 'Next ${DateFormat.jm().format(nextDose!.scheduledAt)}',
                detail: '${nextDose!.name} ${nextDose!.dosage}',
                onTap: () => DoseDetailSheet.show(context, nextDose!),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _HeroStat(
                label: 'Adherence',
                value: '${adherence.toStringAsFixed(0)}%',
              ),
              _HeroStatDivider(),
              _HeroStat(label: 'Taken', value: '$taken/$total'),
              _HeroStatDivider(),
              _HeroStat(
                label: 'Alerts',
                value: '${alerts.length}',
                accent: primaryAlert?.tint,
                onTap: primaryAlert != null
                    ? () => onAlertTap(primaryAlert)
                    : null,
              ),
              _HeroStatDivider(),
              _HeroStat(
                label: 'Missed',
                value: '$missed',
                accent: missed > 0 ? AppColors.critical : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroInsight extends StatelessWidget {
  const _HeroInsight({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$label · $detail',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.ink(context),
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

/// Prominent, high-visibility medication alert banner shown in the meds hero.
///
/// Unlike the compact [_HeroInsight] strip, this presents the alert on its own
/// two lines with the correct urgency colour (red for expired) and an explicit
/// call-to-action, so a patient cannot miss an expired or refill-due medicine.
class _HeroAlertBanner extends StatelessWidget {
  const _HeroAlertBanner({
    required this.alert,
    required this.extraCount,
    required this.onTap,
  });

  final MedicationAlert alert;
  final int extraCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = alert.tint;
    final isCritical = alert.kind == MedicationAlertKind.expired;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isCritical ? 0.14 : 0.10),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: color.withValues(alpha: isCritical ? 0.55 : 0.35),
              width: isCritical ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(AppIcons.alert, size: 18, color: color),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.title,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (extraCount > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusPill,
                              ),
                            ),
                            child: Text(
                              '+$extraCount more',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _alertActionLabel(alert.kind),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Icon(AppIcons.chevronRight, size: 14, color: color),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                color: accent ?? AppPalette.ink(context),
                fontWeight: FontWeight.w800,
                fontSize: 21,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return Expanded(child: child);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: child,
        ),
      ),
    );
  }
}

class _HeroStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      color: AppPalette.border(context),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}

class _MedsQuickActions extends StatelessWidget {
  const _MedsQuickActions({
    required this.onAdd,
    required this.alertCount,
    required this.medCount,
  });

  final VoidCallback onAdd;
  final int alertCount;
  final int medCount;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: PatientQuickActionsBar(
        children: [
          PatientQuickAction(
            icon: AppIcons.add,
            label: 'Add med',
            horizontal: true,
            onTap: onAdd,
          ),
          PatientQuickAction(
            icon: AppIcons.medication,
            label: 'Log dose',
            horizontal: true,
            onTap: () {
              final pending = MedicationsState.instance
                  .dosesForToday()
                  .where((d) => d.status == DoseStatus.pending)
                  .toList();
              if (pending.isEmpty) {
                AppToast.info(context, 'No pending doses to log right now.');
                return;
              }
              LogDoseSheet.show(context, pending.first);
            },
          ),
          PatientQuickAction(
            icon: AppIcons.alert,
            label: 'Alerts',
            horizontal: true,
            badge: alertCount > 0 ? '$alertCount' : null,
            onTap: () {
              final alerts = MedicationsState.instance.medicationAlerts();
              if (alerts.isEmpty) {
                AppToast.info(context, 'No medication alerts.');
                return;
              }
              final med = MedicationsState.instance.byId(
                alerts.first.medicationId,
              );
              if (med != null) {
                MedicationDetailSheet.show(context, med);
              }
            },
          ),
          PatientQuickAction(
            icon: AppIcons.records,
            label: 'All meds',
            horizontal: true,
            badge: medCount > 0 ? '$medCount' : null,
            badgeColor: AppColors.brandIndigo,
            onTap: () => AllMedicationsSheet.show(context),
          ),
        ],
      ),
    );
  }
}

class _TodayScheduleCard extends StatelessWidget {
  const _TodayScheduleCard({required this.doses});
  final List<MedicationDose> doses;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          for (var i = 0; i < doses.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            _DoseRow(dose: doses[i]),
          ],
        ],
      ),
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose});
  final MedicationDose dose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat.jm().format(dose.scheduledAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => DoseDetailSheet.show(context, dose),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: dose.status.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: dose.status.color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                height: 28,
                width: 28,
                decoration: BoxDecoration(
                  color: AppColors.glucoseAmber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  AppIcons.medication,
                  color: AppColors.glucoseAmber,
                  size: 14,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$time · ${dose.dosage}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: dose.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  dose.status.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: dose.status.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                  ),
                ),
              ),
              const SizedBox(width: 2),
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

class _ActivityFeed extends StatefulWidget {
  const _ActivityFeed({required this.activity});
  final List<MedicationDose> activity;

  @override
  State<_ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<_ActivityFeed> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activity.isEmpty) {
      return GlassCard(
        frosted: true,
        child: EmptyStateView(
          icon: AppIcons.records,
          title: 'No activity yet',
          message: 'Logged doses and reminders show up here.',
          compact: true,
        ),
      );
    }

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.activity.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            _ActivityRow(dose: widget.activity[i]),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.dose});
  final MedicationDose dose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = dose.takenAt ?? dose.scheduledAt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => DoseDetailSheet.show(context, dose),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(dose.status.icon, size: 12, color: dose.status.color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${dose.name} · ${dose.status.label} · ${_relativeTime(when)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on DoseStatus {
  IconData get icon => switch (this) {
    DoseStatus.taken => AppIcons.check,
    DoseStatus.pending => AppIcons.time,
    DoseStatus.skipped => AppIcons.alert,
    DoseStatus.missed => AppIcons.alert,
  };
}
