import 'package:flutter/material.dart';

import '../../doctors/alerts/doctor_alert_resolve_sheet.dart';
import '../navigation/sos_navigation.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_card.dart';
import 'alert_center.dart';
import 'urgent_alert_dialog.dart';
import '../widgets/loading/loading.dart';

/// The urgent queue rendered inline on the dashboard.
///
/// The popup is for interruption; this is for the standing picture. It groups
/// the queue by severity so an admin can see at a glance what is outstanding,
/// and every row can be acted on without navigating away — which is what
/// "work on them" needs to mean if the popup is ever going to be dismissable.
class UrgentAlertsCard extends StatelessWidget {
  const UrgentAlertsCard({super.key, this.maxRows = 4});

  /// Rows shown before collapsing into a "review all" affordance.
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AlertCenter.instance,
      builder: (context, _) {
        final queue = AlertCenter.instance.openQueue;
        if (queue.isEmpty) return const _AllClearCard();

        final unattended = AlertCenter.instance.unattendedCount;
        final sos = queue.where((i) => i.isSos).length;
        final critical = queue
            .where((i) => i.kind == UrgentKind.criticalVital)
            .length;
        final warning = queue
            .where((i) => i.kind == UrgentKind.warningVital)
            .length;

        final accent = sos > 0 || critical > 0
            ? AppColors.critical
            : AppColors.warning;
        final shown = queue.take(maxRows).toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: GlassCard(
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 1.4,
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  accent: accent,
                  total: queue.length,
                  unattended: unattended,
                  sos: sos,
                  critical: critical,
                  warning: warning,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final item in shown) _UrgentRow(item: item),
                if (queue.length > shown.length)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '+${queue.length - shown.length} more outstanding',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: unattended > 0
                      ? 'Work through $unattended unattended'
                      : 'Review queue',
                  icon: AppIcons.alert,
                  variant: unattended > 0
                      ? AppButtonVariant.danger
                      : AppButtonVariant.secondary,
                  expand: true,
                  onPressed: () => _reviewAll(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Force the queue to surface now, even for items currently snoozed.
  void _reviewAll(BuildContext context) {
    final center = AlertCenter.instance;
    final pending = center.popQueue;
    if (pending.isEmpty) {
      AppToast.info(context, 'Nothing unattended — all items are owned.');
      return;
    }
    // Clearing snoozes makes "review all" mean exactly that.
    center.snoozeAll(pending.map((i) => i.id), Duration.zero);
    UrgentAlertDialog.maybeShow(context);
  }
}

class _AllClearCard extends StatelessWidget {
  const _AllClearCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.24)),
        ),
        child: Row(
          children: [
            const Icon(AppIcons.check, size: 18, color: AppColors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'No urgent items outstanding in your scope.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.accent,
    required this.total,
    required this.unattended,
    required this.sos,
    required this.critical,
    required this.warning,
  });

  final Color accent;
  final int total;
  final int unattended;
  final int sos;
  final int critical;
  final int warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(AppIcons.alert, size: 18, color: accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Urgent · $total outstanding',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              Text(
                [
                  if (sos > 0) '$sos emergency',
                  if (critical > 0) '$critical critical',
                  if (warning > 0) '$warning warning',
                  if (unattended > 0)
                    '$unattended not yet owned'
                  else
                    'all owned',
                ].join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UrgentRow extends StatefulWidget {
  const _UrgentRow({required this.item});
  final UrgentItem item;

  @override
  State<_UrgentRow> createState() => _UrgentRowState();
}

class _UrgentRowState extends State<_UrgentRow> {
  bool _busy = false;

  Future<void> _acknowledge() async {
    final item = widget.item;
    setState(() => _busy = true);
    try {
      final ok = item.alert != null
          ? await StaffState.instance.acknowledgeAlert(item.alert!.id)
          : await StaffState.instance.updateSosForCurrentRole(
              item.sos!.id,
              status: 'acknowledged',
            );
      if (!mounted) return;
      if (ok) {
        AppToast.success(
          context,
          'Acknowledged — this stays open until resolved.',
        );
      } else {
        AppToast.error(context, 'Could not acknowledge — try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    final item = widget.item;
    setState(() => _busy = true);
    try {
      if (item.alert != null) {
        await DoctorAlertResolveFlow.resolve(context, item.alert!);
      } else {
        await SosNavigation.openRespond(
          context,
          patientId: item.patientId,
          eventId: item.sos!.id,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final accent = switch (item.kind) {
      UrgentKind.sos || UrgentKind.criticalVital => AppColors.critical,
      UrgentKind.warningVital => AppColors.warning,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (item.acknowledged) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusPill,
                          ),
                        ),
                        child: const Text(
                          'OWNED',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${item.title}${item.detail.isEmpty ? '' : ' · ${item.detail}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (_busy)
            const McarePulse(size: McarePulseSize.micro, semanticLabel: null)
          else ...[
            if (!item.acknowledged)
              IconButton(
                tooltip: 'Acknowledge',
                onPressed: _acknowledge,
                visualDensity: VisualDensity.compact,
                icon: const Icon(AppIcons.checkMark, size: 17),
              ),
            IconButton(
              tooltip: item.isSos ? 'Respond to SOS' : 'Resolve',
              onPressed: _resolve,
              visualDensity: VisualDensity.compact,
              icon: Icon(AppIcons.check, size: 17, color: accent),
            ),
          ],
        ],
      ),
    );
  }
}
