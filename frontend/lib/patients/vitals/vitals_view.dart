import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/notifications_filter.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_floating_button.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/vital_tile.dart';
import 'request_vital_report_sheet.dart';
import 'submit_vital_sheet.dart';
import 'vital_reading_sheet.dart';
import 'vital_preferences_sheet.dart';

List<Color> _vitalsFabColors() {
  var hasCritical = false;
  var hasWarning = false;
  for (final key in VitalsState.instance.tracked) {
    final risk = VitalsState.instance.latestOf(key)?.risk;
    if (risk == RiskLevel.critical) hasCritical = true;
    if (risk == RiskLevel.warning) hasWarning = true;
  }
  if (hasCritical) return [AppColors.critical, AppColors.warning];
  if (hasWarning) return [AppColors.warning, AppColors.brandIndigo];
  return [AppColors.brandIndigo, const Color(0xFF8B5CF6)];
}

List<VitalKey> _sortedTracked(List<VitalKey> tracked) {
  int priority(VitalKey key) {
    final alert = NotificationState.instance.vitalAlertFor(key);
    if (alert != null) return 0;
    final risk = VitalsState.instance.latestOf(key)?.risk;
    if (risk == RiskLevel.critical) return 1;
    if (risk == RiskLevel.warning) return 2;
    return 3;
  }

  final sorted = tracked.toList()
    ..sort((a, b) {
      final byPriority = priority(a).compareTo(priority(b));
      if (byPriority != 0) return byPriority;
      final ra = VitalsState.instance.latestOf(a)?.recordedAt;
      final rb = VitalsState.instance.latestOf(b)?.recordedAt;
      if (ra == null && rb == null) return 0;
      if (ra == null) return 1;
      if (rb == null) return -1;
      return rb.compareTo(ra);
    });
  return sorted;
}

String _relativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

int _resolvedCount(List<VitalKey> tracked) {
  var count = 0;
  for (final v in tracked) {
    if (NotificationState.instance.vitalAlertFor(v) != null) continue;
    if (NotificationState.instance.resolvedVitalAlertFor(v) != null &&
        VitalsState.instance.latestOf(v)?.risk == RiskLevel.normal) {
      count++;
    }
  }
  return count;
}

/// Most recent individual readings the patient logged (newest first).
List<VitalReading> _lastProvidedReadings(
  Iterable<VitalKey> tracked, {
  int limit = 6,
}) {
  final keys = tracked.toSet();
  return VitalsState.instance.all
      .where((r) => keys.contains(r.vital))
      .take(limit)
      .toList();
}

class VitalsView extends StatelessWidget {
  const VitalsView({super.key});

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);

    return PatientScaffold(
      currentRoute: RouteNames.patientVitals,
      title: 'Vitals',
      subtitle: 'Your readings, trends and alerts in one place',
      floatingActionButton: tier.isHandheld
          ? GlassFloatingButton(
              icon: AppIcons.add,
              label: 'Log vital',
              dynamicColors: _vitalsFabColors(),
              onPressed: () => SubmitVitalSheet.show(context),
            )
          : null,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          VitalsState.instance,
          NotificationState.instance,
        ]),
        builder: (context, _) {
          final tracked = _sortedTracked(VitalsState.instance.tracked.toList());
          final totalTypes = VitalKey.values.length;
          final alertCount = tracked
              .where((v) => NotificationState.instance.vitalAlertFor(v) != null)
              .length;
          final resolvedCount = _resolvedCount(tracked);
          final watchCount = tracked.where((v) {
            if (NotificationState.instance.vitalAlertFor(v) != null) {
              return false;
            }
            final r = VitalsState.instance.latestOf(v)?.risk;
            return r == RiskLevel.warning || r == RiskLevel.critical;
          }).length;

          final latestProvided = _lastProvidedReadings(tracked, limit: 1);
          final latest = latestProvided.isNotEmpty
              ? latestProvided.first
              : null;

          final today = DateFormat('EEEE, MMM d').format(DateTime.now());

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: Text(
                  today,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _VitalsHero(
                  totalTypes: totalTypes,
                  trackedCount: tracked.length,
                  alertCount: alertCount,
                  resolvedCount: resolvedCount,
                  watchCount: watchCount,
                  latestReading: latest,
                  onManage: () => VitalPreferencesSheet.show(context),
                  onViewAlerts: () => Navigator.of(context).pushNamed(
                      RouteNames.patientNotifications),
                  onViewResolved: () => Navigator.of(context).pushNamed(
                      RouteNames.patientNotifications,
                      arguments: const NotificationsFilter(showResolved: true)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 2,
                child: _VitalsQuickActions(
                  resolvedCount:
                      NotificationState.instance.resolvedVitalAlertCount,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: 'Your vitals',
                  icon: AppIcons.vitals,
                  trailing: tracked.isEmpty
                      ? null
                      : 'Last 6 · ${tracked.length} tracked',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (tracked.isEmpty)
                StaggeredEntry(
                  index: 4,
                  child: GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.vitals,
                      title: 'No vitals tracked yet',
                      message:
                          'Tap Tracked below to choose vitals, then log your first reading.',
                      actionLabel: 'Choose vitals',
                      onAction: () => VitalPreferencesSheet.show(context),
                      compact: true,
                    ),
                  ),
                )
              else
                StaggeredEntry(
                  index: 4,
                  child: _LastSixReadingsPanel(tracked: tracked),
                ),
              SizedBox(height: tier.isHandheld ? 88 : AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

class _LastSixReadingsPanel extends StatefulWidget {
  const _LastSixReadingsPanel({required this.tracked});

  final List<VitalKey> tracked;

  @override
  State<_LastSixReadingsPanel> createState() => _LastSixReadingsPanelState();
}

class _LastSixReadingsPanelState extends State<_LastSixReadingsPanel> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readings = _lastProvidedReadings(widget.tracked, limit: 6);
    final newest = readings.isNotEmpty ? readings.first : null;

    if (readings.isEmpty) {
      return GlassCard(
        frosted: true,
        child: EmptyStateView(
          icon: AppIcons.vitals,
          title: 'No readings yet',
          message: 'Log a vital and your last 6 readings appear here automatically.',
          actionLabel: 'Log vital',
          onAction: () => SubmitVitalSheet.show(context),
          compact: true,
        ),
      );
    }

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 8,
                width: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  newest == null
                      ? 'Waiting for readings'
                      : 'Updated ${_relativeTime(newest.recordedAt)} · showing ${readings.length} of last 6',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < readings.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            VitalTile(
              vital: readings[i].vital,
              reading: readings[i],
              alert: NotificationState.instance
                  .vitalAlertFor(readings[i].vital),
              resolvedAlert: NotificationState.instance
                  .resolvedVitalAlertFor(readings[i].vital),
              assigned: VitalsState.instance.isAssigned(readings[i].vital),
              variant: VitalTileVariant.compact,
              onTap: () =>
                  VitalReadingSheet.show(context, reading: readings[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _VitalsHero extends StatelessWidget {
  const _VitalsHero({
    required this.totalTypes,
    required this.trackedCount,
    required this.alertCount,
    required this.resolvedCount,
    required this.watchCount,
    required this.latestReading,
    required this.onManage,
    required this.onViewAlerts,
    required this.onViewResolved,
  });

  final int totalTypes;
  final int trackedCount;
  final int alertCount;
  final int resolvedCount;
  final int watchCount;
  final VitalReading? latestReading;
  final VoidCallback onManage;
  final VoidCallback onViewAlerts;
  final VoidCallback onViewResolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCritical = alertCount > 0;
    final isWatch = !isCritical && watchCount > 0;

    final accent = isCritical
        ? AppColors.critical
        : isWatch
            ? AppColors.warning
            : AppColors.brandIndigo;
    final iconBg = isCritical
        ? AppPalette.criticalSoft(context)
        : isWatch
            ? AppPalette.warningSoft(context)
            : AppPalette.infoSoft(context);

    final headline = trackedCount == 0
        ? 'Start tracking today'
        : isCritical
            ? '$alertCount active alert${alertCount == 1 ? '' : 's'}'
            : isWatch
                ? '$watchCount reading${watchCount == 1 ? '' : 's'} to watch'
                : 'Everything looks stable';

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  isCritical || isWatch ? AppIcons.alert : AppIcons.vitals,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppPalette.ink(context),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (trackedCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _LastUpdatedStrip(reading: latestReading),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _HeroStatAction(
                label: 'Total',
                value: totalTypes.toString(),
                hint: 'Types',
              ),
              _HeroStatDivider(),
              _HeroStatAction(
                label: 'Tracked',
                value: trackedCount.toString(),
                hint: 'Manage',
                onTap: onManage,
              ),
              _HeroStatDivider(),
              _HeroStatAction(
                label: 'Alerts',
                value: alertCount.toString(),
                hint: alertCount > 0 ? 'View' : 'None',
                accent: alertCount > 0 ? AppColors.critical : null,
                onTap: onViewAlerts,
              ),
              _HeroStatDivider(),
              _HeroStatAction(
                label: 'Resolved',
                value: resolvedCount.toString(),
                hint: resolvedCount > 0 ? 'Cleared' : '—',
                accent: resolvedCount > 0 ? AppColors.success : null,
                onTap: onViewResolved,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VitalsQuickActions extends StatelessWidget {
  const _VitalsQuickActions({required this.resolvedCount});

  final int resolvedCount;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: AppIcons.time,
              label: 'Past 7 days',
              onTap: () =>
                  Navigator.of(context).pushNamed(RouteNames.patientVital7Day),
            ),
          ),
          Container(height: 28, width: 1, color: AppPalette.border(context)),
          Expanded(
            child: _QuickAction(
              icon: AppIcons.report,
              label: 'Request report',
              onTap: () => RequestVitalReportSheet.show(context),
            ),
          ),
          Container(height: 28, width: 1, color: AppPalette.border(context)),
          Expanded(
            child: _QuickAction(
              icon: AppIcons.check,
              label: 'Resolved',
              badge: resolvedCount > 0 ? '$resolvedCount' : null,
              onTap: () => Navigator.of(context).pushNamed(
                RouteNames.patientNotifications,
                arguments: const NotificationsFilter(showResolved: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 18, color: AppColors.brandIndigo),
                  if (badge != null)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Text(
                          badge!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.ink(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LastUpdatedStrip extends StatelessWidget {
  const _LastUpdatedStrip({required this.reading});

  final VitalReading? reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (reading == null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: AppPalette.surfaceMuted(context).withOpacity(0.5),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          children: [
            Icon(AppIcons.time, size: 14, color: AppPalette.textMuted(context)),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'No readings logged yet',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final vital = reading!.vital;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => VitalReadingSheet.show(context, reading: reading!),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: vital.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: vital.accent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(AppIcons.time, size: 14, color: vital.accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Last updated ${_relativeTime(reading!.recordedAt)} · ',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: vital.shortLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.ink(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' ${reading!.formatValue()} ${vital.unit}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: vital.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                size: 14,
                color: vital.accent.withOpacity(0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStatAction extends StatelessWidget {
  const _HeroStatAction({
    required this.label,
    required this.value,
    required this.hint,
    this.onTap,
    this.accent,
  });

  final String label;
  final String value;
  final String hint;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? AppPalette.ink(context);

    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
          Text(
            hint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent ?? (onTap != null ? AppColors.brandIndigo : AppPalette.textFaint(context)),
              fontWeight: FontWeight.w700,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Expanded(child: child);
    }

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
