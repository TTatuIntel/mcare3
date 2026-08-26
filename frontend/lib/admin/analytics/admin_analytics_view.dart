import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../core/env/app_env.dart';
import '../../core/realtime/session_poller.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/loading/loading.dart';

class AdminAnalyticsView extends StatefulWidget {
  const AdminAnalyticsView({
    super.key,
    this.currentRoute = RouteNames.adminAnalytics,
    this.profileRoute = RouteNames.adminProfile,
    this.notificationsRoute = RouteNames.adminNotifications,
    this.destinations,
  });

  final String currentRoute;
  final String profileRoute;
  final String notificationsRoute;
  final List? destinations;

  @override
  State<AdminAnalyticsView> createState() => _AdminAnalyticsViewState();
}

class _AdminAnalyticsViewState extends State<AdminAnalyticsView> {
  Key _kpiKey = UniqueKey();
  Key _trendKey = UniqueKey();
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    SessionPoller.instance.triggerNow();
    // Small delay so the spinner is visible even on very fast networks.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _kpiKey = UniqueKey();
      _trendKey = UniqueKey();
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations:
          (widget.destinations ?? StaffDestinations.admin()).cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Analytics',
      subtitle: 'Usage, alerting and response metrics',
      headerActions: [
        IconButton(
          tooltip: 'Refresh analytics',
          onPressed: _refreshing ? null : _refresh,
          icon: _refreshing
              ? const McarePulse(
                  size: McarePulseSize.micro,
                  semanticLabel: null,
                )
              : const Icon(Icons.refresh),
        ),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final patients = StaffState.instance.users
              .where((u) => u.role.name == 'patient' && u.status == 'active')
              .length;
          final alerts = StaffState.instance.alerts.length;
          final unack = StaffState.instance.alerts
              .where((a) => !a.acknowledged)
              .length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // KPI tiles — fetches from API when backend is on.
              _KpiSection(key: _kpiKey),
              const SizedBox(height: AppSpacing.lg),

              // Trend charts
              SectionLabel(title: '7-day trends', icon: AppIcons.trend),
              _LiveTrendSection(key: _trendKey),
              const SizedBox(height: AppSpacing.lg),

              // Alert breakdown
              SectionLabel(
                title: 'Alert breakdown',
                icon: AppIcons.alert,
                trailing: '$unack unacknowledged',
              ),
              _AlertBreakdown(
                total: alerts,
                unack: unack,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Highlights
              SectionLabel(title: 'Highlights', icon: AppIcons.analytics),
              GlassCard(
                frosted: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet(context,
                        '$patients patients monitored across ${StaffState.instance.assignments.length} care relationships.'),
                    _bullet(context,
                        '$unack unacknowledged alert${unack == 1 ? '' : 's'} require attention.'),
                    _bullet(context,
                        '${StaffState.instance.approvals.where((a) => a.status == 'pending').length} clinician application${StaffState.instance.approvals.where((a) => a.status == 'pending').length == 1 ? '' : 's'} awaiting approval.'),
                    _bullet(context,
                        '${StaffState.instance.audit.where((e) => e.category == 'security').length} security events recorded in the audit log.'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•'),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child:
                  Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// KPI grid — uses live API data when backend is enabled, local math otherwise.
// ---------------------------------------------------------------------------

class _KpiSection extends StatefulWidget {
  const _KpiSection({super.key});

  @override
  State<_KpiSection> createState() => _KpiSectionState();
}

class _KpiSectionState extends State<_KpiSection> {
  List<AnalyticsKpi>? _apiKpis;

  @override
  void initState() {
    super.initState();
    _fetchFromApi();
  }

  Future<void> _fetchFromApi() async {
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
            value: '${raw['open_alerts'] ?? raw['alerts'] ?? 0}',
            deltaPercent: (raw['open_alerts_delta'] as num?)?.toDouble(),
            helper: 'vs. yesterday',
          ),
          AnalyticsKpi(
            label: 'Pending approvals',
            value: '${raw['pending_approvals'] ?? raw['approvals'] ?? 0}',
            helper: 'healthworker queue',
          ),
          AnalyticsKpi(
            label: 'Avg. response time',
            value: _formatSeconds(raw['avg_response_seconds']),
            deltaPercent: (raw['avg_response_delta'] as num?)?.toDouble(),
            helper: 'alert acknowledgement',
          ),
        ];
      });
    } catch (_) {
      // Non-fatal: local KPIs remain visible.
    }
  }

  String _formatSeconds(dynamic raw) {
    final secs = (raw as num?)?.toInt();
    if (secs == null) return '—';
    final m = secs ~/ 60;
    final s = secs % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final kpis = _apiKpis ?? StaffState.instance.kpis();
        return StaffKpiGrid(
          tiles: kpis
              .map((k) => StaffKpiTile(
                    label: k.label,
                    value: k.value,
                    helper: k.helper,
                    deltaPercent: k.deltaPercent,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _LiveTrendSection extends StatefulWidget {
  const _LiveTrendSection({super.key});

  @override
  State<_LiveTrendSection> createState() => _LiveTrendSectionState();
}

class _LiveTrendSectionState extends State<_LiveTrendSection> {
  List<double> _signups = const [];
  List<double> _sos = const [];
  List<double> _tickets = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppEnv.backendEnabled) {
      setState(() => _loading = false);
      return;
    }
    final to = DateTime.now();
    final from = to.subtract(const Duration(days: 6));
    try {
      final results = await Future.wait([
        AdminApi.instance.fetchTimeseries(metric: 'signups', from: from, to: to),
        AdminApi.instance.fetchTimeseries(metric: 'sos', from: from, to: to),
        AdminApi.instance.fetchTimeseries(metric: 'tickets', from: from, to: to),
      ]);
      if (!mounted) return;
      setState(() {
        _signups = _seriesToPoints(results[0]);
        _sos = _seriesToPoints(results[1]);
        _tickets = _seriesToPoints(results[2]);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<double> _seriesToPoints(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return List.filled(7, 0);
    return rows.map((r) => (r['value'] as num?)?.toDouble() ?? 0).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: McareLoadingMark(size: McareMarkSize.small)),
      );
    }

    final signupPts = _signups;
    final sosPts = _sos;
    final ticketPts = _tickets;

    return _TrendRow(
      charts: [
        _TrendCard(
          label: 'New signups',
          value: signupPts.isEmpty ? 0 : signupPts.last.round(),
          color: AppColors.brandIndigo,
          points: signupPts,
        ),
        _TrendCard(
          label: 'SOS events',
          value: sosPts.isEmpty ? 0 : sosPts.last.round(),
          color: AppColors.warning,
          points: sosPts,
        ),
        _TrendCard(
          label: 'Support tickets',
          value: ticketPts.isEmpty ? 0 : ticketPts.last.round(),
          color: AppColors.info,
          points: ticketPts,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Trend row (responsive: horizontal scroll on narrow, row on wide)
// ---------------------------------------------------------------------------

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.charts});
  final List<Widget> charts;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 800) {
      return Row(
        children: charts
            .map((c) => Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: c,
                )))
            .toList(),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: charts
            .map((c) => SizedBox(
                  width: 200,
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: c,
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single trend card with sparkline
// ---------------------------------------------------------------------------

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.label,
    required this.value,
    required this.color,
    required this.points,
  });

  final String label;
  final int value;
  final Color color;
  final List<double> points;

  @override
  Widget build(BuildContext context) {
    final spots = points.isEmpty
        ? [const FlSpot(0, 0)]
        : [
            for (var i = 0; i < points.length; i++)
              FlSpot(i.toDouble(), points[i]),
          ];

    final maxY = points.isEmpty
        ? 1.0
        : (points.reduce((a, b) => a > b ? a : b) * 1.2).ceilToDouble();

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 60,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: 0.12),
                    ),
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

// ---------------------------------------------------------------------------
// Alert breakdown bar
// ---------------------------------------------------------------------------

class _AlertBreakdown extends StatelessWidget {
  const _AlertBreakdown({required this.total, required this.unack});
  final int total;
  final int unack;

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return GlassCard(
        frosted: true,
        child: Text(
          'No alerts recorded.',
          style: TextStyle(color: AppPalette.textMuted(context)),
        ),
      );
    }
    final ackFrac = (total - unack) / total;

    return GlassCard(
      frosted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(label: 'Total', value: '$total',
                  color: AppColors.brandIndigo),
              _Stat(label: 'Acknowledged', value: '${total - unack}',
                  color: AppColors.success),
              _Stat(label: 'Pending', value: '$unack',
                  color: AppColors.warning),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: LinearProgressIndicator(
              value: ackFrac,
              minHeight: 8,
              backgroundColor: AppColors.warning.withValues(alpha: 0.2),
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${(ackFrac * 100).round()}% acknowledged',
            style: TextStyle(
              color: AppPalette.textMuted(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: color,
              ),
        ),
        Text(
          label,
          style: TextStyle(color: AppPalette.textMuted(context), fontSize: 11),
        ),
      ],
    );
  }
}
