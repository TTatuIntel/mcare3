import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/realtime/session_poller.dart';
import '../navigation/role_nav_destination.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_toast.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/role_shell.dart';
import '../widgets/section_label.dart';
import '../widgets/staff_blocks.dart';

/// System-wide vital alerts — shared by admin and mCare assistant.
class StaffAlertsScreen extends StatefulWidget {
  const StaffAlertsScreen({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
    this.subtitle = 'System-wide vital alerts across all patients',
  });

  final String currentRoute;
  final List<RoleNavDestination> destinations;
  final String profileRoute;
  final String notificationsRoute;
  final String subtitle;

  @override
  State<StaffAlertsScreen> createState() => _StaffAlertsScreenState();
}

class _StaffAlertsScreenState extends State<StaffAlertsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SessionPoller.instance.triggerNow();
    });
  }

  Future<void> _acknowledge(StaffAlert alert) async {
    final ok = await StaffState.instance.acknowledgeAlert(alert.id);
    if (!mounted) return;
    if (ok) {
      AppToast.success(context, 'Alert acknowledged.');
    } else {
      AppToast.error(context, 'Could not acknowledge — please retry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations,
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Alerts',
      subtitle: widget.subtitle,
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final all = StaffState.instance.alerts.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final open =
              all.where((a) => !a.resolved).toList(growable: false);
          final resolved =
              all.where((a) => a.resolved).toList(growable: false);

          if (all.isEmpty) {
            return const EmptyStateView(
              icon: AppIcons.alert,
              title: 'No alerts',
              message: 'Patient vital alerts will appear here.',
            );
          }

          final children = <Widget>[];

          if (open.isNotEmpty) {
            children.add(SectionLabel(
              title: 'Open',
              icon: AppIcons.alert,
              trailing: '${open.length} need attention',
            ));
            children.add(const SizedBox(height: AppSpacing.sm));
            for (var i = 0; i < open.length; i++) {
              final alert = open[i];
              children.add(StaggeredEntry(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _StaffAlertRow(
                    alert: alert,
                    onAcknowledge: () => _acknowledge(alert),
                  ),
                ),
              ));
            }
          }

          if (resolved.isNotEmpty) {
            children.add(const SizedBox(height: AppSpacing.md));
            children.add(SectionLabel(
              title: 'Resolved',
              icon: AppIcons.check,
              trailing: '${resolved.length} recently closed',
            ));
            children.add(const SizedBox(height: AppSpacing.sm));
            final recent = resolved.take(20).toList();
            for (var i = 0; i < recent.length; i++) {
              children.add(StaggeredEntry(
                index: i + open.length,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _StaffAlertRow(alert: recent[i], dimmed: true),
                ),
              ));
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        },
      ),
    );
  }
}

class _StaffAlertRow extends StatelessWidget {
  const _StaffAlertRow({
    required this.alert,
    this.dimmed = false,
    this.onAcknowledge,
  });

  final StaffAlert alert;
  final bool dimmed;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: EdgeInsets.zero,
      child: StaffListRow(
        icon: alert.vital.icon,
        iconColor: dimmed ? AppPalette.textMuted(context) : alert.severity.color,
        title: '${alert.patientName} · ${alert.vital.label}',
        subtitle:
            '${alert.value} · ${DateFormat.MMMd().add_jm().format(alert.createdAt)}',
        pill: alert.resolved
            ? 'Resolved'
            : (alert.acknowledged ? 'Acknowledged' : alert.severity.label),
        pillColor: alert.resolved
            ? AppColors.success
            : (alert.acknowledged ? AppColors.info : alert.severity.color),
        trailing: (!alert.resolved && !alert.acknowledged && onAcknowledge != null)
            ? AppButton(
                label: 'Ack',
                size: AppButtonSize.sm,
                onPressed: onAcknowledge,
              )
            : null,
      ),
    );
  }
}
