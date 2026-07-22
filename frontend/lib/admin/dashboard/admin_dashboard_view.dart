import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'admin_activity_feed.dart';
import 'admin_overview_hero.dart';
import 'admin_workspace_grid.dart';
import '../../core/api/admin_api.dart';
import '../../core/env/app_env.dart';
import '../../core/realtime/session_poller.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/dashboard/staff_attention_builder.dart';
import '../../shared/dashboard/staff_attention_section.dart';
import '../../shared/utils/time_greeting.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/state/support_state.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/staff_blocks.dart';

class AdminDashboardView extends StatefulWidget {
  const AdminDashboardView({super.key});

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  List<AnalyticsKpi>? _apiKpis;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SessionPoller.instance.triggerNow();
    });
    _fetchKpis();
  }

  Future<void> _fetchKpis() async {
    if (!AppEnv.backendEnabled) return;
    try {
      final raw = await AdminApi.instance.fetchKpis();
      if (!mounted || raw.isEmpty) return;
      setState(() {
        _apiKpis = [
          AnalyticsKpi(
            label: 'Active patients',
            value: '${raw['active_patients'] ?? raw['patients'] ?? 0}',
            deltaPercent: (raw['active_patients_delta'] as num?)?.toDouble(),
            helper: 'vs. last week',
          ),
          AnalyticsKpi(
            label: 'Open alerts',
            value: '${raw['open_alerts'] ?? 0}',
            deltaPercent: (raw['open_alerts_delta'] as num?)?.toDouble(),
            helper: 'vs. yesterday',
          ),
          AnalyticsKpi(
            label: 'Pending approvals',
            value:
                '${raw['pending_approvals'] ?? StaffState.instance.approvals.where((a) => a.status == 'pending').length}',
            helper: 'healthworker queue',
          ),
          AnalyticsKpi(
            label: 'Avg. response time',
            value: raw['avg_response_seconds'] != null
                ? _formatResponse(raw['avg_response_seconds'])
                : '6m 12s',
            deltaPercent: (raw['avg_response_delta'] as num?)?.toDouble(),
            helper: 'alert acknowledgement',
          ),
        ];
      });
    } catch (_) {
      // Non-fatal — local StaffState KPIs remain visible.
    }
  }

  static String _formatResponse(dynamic seconds) {
    final s = (seconds as num?)?.toInt() ?? 0;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '${m}m' : '${m}m ${r}s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        StaffState.instance,
        SupportState.instance,
      ]),
      builder: (context, _) {
        final attention = StaffAttentionBuilder.build(
          context,
          roleRoutes: AttentionRoleRoutes.admin,
          hasPermission: (_) => true,
        );
        final dashboardKpis = _apiKpis ?? StaffState.instance.adminKpis();

        return RoleShell(
          currentRoute: RouteNames.adminDashboard,
          destinations: StaffDestinations.admin(),
          profileRoute: RouteNames.adminProfile,
          notificationsRoute: RouteNames.adminNotifications,
          title: timeGreeting(firstName: AuthState.instance.user?.firstName),
          subtitle:
              'System overview · ${DateFormat.MMMEd().format(DateTime.now())}',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminOverviewHero(),
              const SizedBox(height: AppSpacing.md),
              StaffKpiGrid(
                tiles: dashboardKpis
                    .map(
                      (k) => StaffKpiTile(
                        label: k.label,
                        value: k.value,
                        helper: k.helper,
                        deltaPercent: k.deltaPercent,
                        icon: _kpiIcon(k.label),
                        onTap: () => _openKpi(context, k.label),
                      ),
                    )
                    .toList(),
              ),
              if (attention.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                StaffAttentionSection(
                  title: 'Needs attention',
                  items: attention,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const AdminWorkspaceGrid(),
              const SizedBox(height: AppSpacing.lg),
              const AdminActivityFeed(limit: 5),
              const SizedBox(height: AppSpacing.huge),
            ],
          ),
        );
      },
    );
  }

  static IconData _kpiIcon(String label) => switch (label) {
        'Active patients' => AppIcons.patients,
        'Open alerts' => AppIcons.alert,
        'Pending approvals' => AppIcons.approval,
        'Avg. response time' => AppIcons.analytics,
        _ => AppIcons.analytics,
      };

  static void _openKpi(BuildContext context, String label) {
    final route = switch (label) {
      'Active patients' => RouteNames.adminPatients,
      'Open alerts' => RouteNames.adminAlerts,
      'Pending approvals' => RouteNames.adminApprovals,
      _ => RouteNames.adminAnalytics,
    };
    Navigator.of(context).pushNamed(route);
  }

}
