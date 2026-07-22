import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';

/// One row in the unified patient vital + alert timeline.
class PatientVitalFeedItem {
  const PatientVitalFeedItem({
    required this.at,
    required this.vital,
    required this.value,
    required this.risk,
    required this.isAlert,
    this.alertId,
    this.resolved = false,
    this.acknowledged = false,
  });

  final DateTime at;
  final VitalKey vital;
  final String value;
  final RiskLevel risk;
  final bool isAlert;
  final String? alertId;
  final bool resolved;
  final bool acknowledged;

  factory PatientVitalFeedItem.fromReading(StaffPatientVitalReading r) =>
      PatientVitalFeedItem(
        at: r.recordedAt,
        vital: r.vital,
        value: r.value,
        risk: r.risk,
        isAlert: false,
      );

  factory PatientVitalFeedItem.fromAlert(StaffAlert a) => PatientVitalFeedItem(
        at: a.createdAt,
        vital: a.vital,
        value: a.value,
        risk: a.severity,
        isAlert: true,
        alertId: a.id,
        resolved: a.resolved,
        acknowledged: a.acknowledged,
      );

  String get pillLabel {
    if (!isAlert) return risk.label;
    if (resolved) return 'Resolved';
    if (acknowledged) return 'Ack';
    return risk.label;
  }

  Color get pillColor {
    if (!isAlert) return risk.color;
    if (resolved) return AppColors.success;
    return risk.color;
  }
}

/// Merges vital readings + vital alerts into one chronological feed.
class PatientVitalFeed {
  PatientVitalFeed._();

  static const maxItems = 6;

  static List<PatientVitalFeedItem> collect(String patientId) {
    final s = StaffState.instance;
    final items = <PatientVitalFeedItem>[
      ...s.vitalsForPatient(patientId).map(PatientVitalFeedItem.fromReading),
      ...s
          .alertsForPatient(patientId)
          .where((a) => a.kind != 'sos')
          .map(PatientVitalFeedItem.fromAlert),
    ];
    items.sort((a, b) => b.at.compareTo(a.at));
    return _dedupe(items).take(maxItems).toList();
  }

  static List<PatientVitalFeedItem> _dedupe(List<PatientVitalFeedItem> sorted) {
    final out = <PatientVitalFeedItem>[];
    for (final item in sorted) {
      final near = out.indexWhere(
        (d) =>
            d.vital == item.vital &&
            d.at.difference(item.at).abs().inHours < 3,
      );
      if (near >= 0) {
        final existing = out[near];
        final preferNew = item.isAlert &&
            !item.resolved &&
            (!existing.isAlert || existing.resolved);
        if (preferNew || (!existing.isAlert && item.at.isAfter(existing.at))) {
          out[near] = item;
        }
        continue;
      }
      out.add(item);
    }
    return out;
  }
}

/// Compact overview block — latest patient vital/alert plus up to five more.
class DoctorPatientVitalFeed extends StatelessWidget {
  const DoctorPatientVitalFeed({
    super.key,
    required this.patientId,
    required this.onOpenVitals,
    required this.onOpenAlerts,
  });

  final String patientId;
  final VoidCallback onOpenVitals;
  final VoidCallback onOpenAlerts;

  void _openItem(BuildContext context, PatientVitalFeedItem item) {
    if (item.isAlert && item.alertId != null) {
      Navigator.of(context).pushNamed(
        RouteNames.doctorAlertDetail,
        arguments: item.alertId,
      );
      return;
    }
    onOpenVitals();
  }

  @override
  Widget build(BuildContext context) {
    final items = PatientVitalFeed.collect(patientId);
    final latest = items.isEmpty ? null : items.first;
    final rest = items.length > 1 ? items.sublist(1) : const <PatientVitalFeedItem>[];
    final openCount =
        items.where((i) => i.isAlert && !i.resolved && !i.acknowledged).length;
    final theme = Theme.of(context);
    final accent =
        openCount > 0 ? AppColors.warning : AppColors.brandIndigo;

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
          InkWell(
            onTap: onOpenVitals,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    height: 28,
                    width: 28,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(AppIcons.vitals, size: 14, color: accent),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Vitals & alerts',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (items.isNotEmpty)
                    Text(
                      '${items.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(AppIcons.chevronRight,
                      size: 14, color: AppPalette.textMuted(context)),
                ],
              ),
            ),
          ),
          if (latest == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No readings or alerts yet',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 11,
                ),
              ),
            )
          else ...[
            const SizedBox(height: AppSpacing.xs),
            _HeroVitalRow(
              item: latest,
              onTap: () => _openItem(context, latest),
            ),
            if (rest.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1, color: AppPalette.border(context)),
              ),
              for (var i = 0; i < rest.length; i++) ...[
                if (i > 0) const SizedBox(height: 2),
                _CompactVitalRow(
                  item: rest[i],
                  onTap: () => _openItem(context, rest[i]),
                ),
              ],
            ],
            if (openCount > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              InkWell(
                onTap: onOpenAlerts,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '$openCount need review · open alerts',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _HeroVitalRow extends StatelessWidget {
  const _HeroVitalRow({required this.item, required this.onTap});

  final PatientVitalFeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: item.risk.softBg(context),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: item.vital.accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(item.vital.icon, color: item.vital.accent, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latest · ${item.vital.label}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      item.value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat.MMMd().add_jm().format(item.at),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              _Pill(label: item.pillLabel, color: item.pillColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactVitalRow extends StatelessWidget {
  const _CompactVitalRow({required this.item, required this.onTap});

  final PatientVitalFeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 5,
        ),
        child: Row(
          children: [
            Icon(item.vital.icon, size: 15, color: item.vital.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.vital.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    '${item.value} · ${DateFormat.MMMd().add_jm().format(item.at)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _Pill(label: item.pillLabel, color: item.pillColor),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
      ),
    );
  }
}
