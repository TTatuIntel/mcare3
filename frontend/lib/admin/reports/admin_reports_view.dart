import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../core/realtime/realtime_refresh_mixin.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/patient_report_request.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/dossier/dossier_blocks.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import 'patient_report_status_sheet.dart';

/// Every patient report in one place, opening on the ones waiting for a
/// decision.
///
/// A doctor signing a report ended the workflow in mid-air. The notification
/// pointed at `/admin/reports`, which did not exist, and the report itself was
/// reachable only by remembering which patient it belonged to and reopening
/// their row — so a signed report waited on someone happening to go looking for
/// it. This screen is the desk that notification lands on.
///
/// The tabs are stages of one pipeline rather than filters over a list: what an
/// admin needs to know first is whether anything is waiting on *them*, which is
/// a different question from what is merely open.
class AdminReportsView extends StatelessWidget {
  const AdminReportsView({super.key, this.initialTab = ReportQueueTab.signed});

  final ReportQueueTab initialTab;

  @override
  Widget build(BuildContext context) => AdminReportsScreen(
    currentRoute: RouteNames.adminReports,
    destinations: StaffDestinations.admin(),
    profileRoute: RouteNames.adminProfile,
    notificationsRoute: RouteNames.adminNotifications,
    initialTab: initialTab,
  );
}

/// Stages of the report pipeline, in the order an admin cares about them.
enum ReportQueueTab {
  /// Signed by a doctor, not yet issued — the admin's own queue.
  signed('Awaiting you', AppIcons.approval),

  /// Waiting on the patient or the doctor. Nothing for the admin to do yet.
  inProgress('In progress', AppIcons.time),

  /// Issued. The patient has their copy.
  issued('Issued', AppIcons.check),

  /// Declined, expired, revoked, or removed.
  closed('Closed', AppIcons.close);

  const ReportQueueTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
    this.initialTab = ReportQueueTab.signed,
  });

  final String currentRoute;
  final List<dynamic> destinations;
  final String profileRoute;
  final String notificationsRoute;
  final ReportQueueTab initialTab;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with RealtimeRefreshMixin<AdminReportsScreen> {
  List<PatientReportRequestItem> _all = const [];
  late ReportQueueTab _tab = widget.initialTab;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    watchRealtime(const {'reports'}, _load);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminApi.instance.listReportRequests();
      if (!mounted) return;
      setState(() {
        _all = rows.map(PatientReportRequestItem.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// One classification, used by both the tab counts and the list, so a badge
  /// can never promise a row the list does not show.
  ReportQueueTab _stageOf(PatientReportRequestItem r) {
    if (r.awaitingIssueDecision) return ReportQueueTab.signed;
    if (r.isIssued) return ReportQueueTab.issued;
    if (r.isClosed) return ReportQueueTab.closed;
    return ReportQueueTab.inProgress;
  }

  List<PatientReportRequestItem> _rowsFor(ReportQueueTab tab) =>
      _all.where((r) => _stageOf(r) == tab).toList();

  Future<void> _open(PatientReportRequestItem request) async {
    await PatientReportStatusSheet.show(
      context,
      request: request,
      onChanged: _load,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rowsFor(_tab);

    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Patient reports',
      subtitle: 'Review, issue, or send back what doctors have signed',
      scrollable: false,
      body: _loading
          ? const AppLoadingView()
          : _error != null
          ? EmptyStateView(
              icon: AppIcons.alert,
              title: 'Could not load reports',
              message: _error,
              actionLabel: 'Retry',
              onAction: _load,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TabBar(
                  selected: _tab,
                  countFor: (t) => _rowsFor(t).length,
                  onSelect: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: rows.isEmpty
                      ? EmptyStateView(
                          icon: _tab.icon,
                          title: _emptyTitle(_tab),
                          message: _emptyMessage(_tab),
                          actionLabel: 'Refresh',
                          onAction: _load,
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xl,
                            ),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (_, i) => _ReportRow(
                              request: rows[i],
                              onTap: () => _open(rows[i]),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  String _emptyTitle(ReportQueueTab tab) => switch (tab) {
    ReportQueueTab.signed => 'Nothing waiting on you',
    ReportQueueTab.inProgress => 'Nothing in progress',
    ReportQueueTab.issued => 'No reports issued yet',
    ReportQueueTab.closed => 'Nothing closed',
  };

  String _emptyMessage(ReportQueueTab tab) => switch (tab) {
    ReportQueueTab.signed =>
      'Signed reports land here for you to read and issue. You will be '
          'notified the moment a doctor signs one.',
    ReportQueueTab.inProgress =>
      'Reports waiting on a patient approval or a doctor signature appear '
          'here.',
    ReportQueueTab.issued =>
      'Once you issue a report it appears here, and a copy goes straight into '
          'the patient’s documents.',
    ReportQueueTab.closed =>
      'Declined, expired and revoked requests are kept here rather than '
          'deleted.',
  };
}

/// Pipeline stages with live counts. The counts are the point — an admin
/// should be able to tell at a glance whether anything is waiting on them.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.selected,
    required this.countFor,
    required this.onSelect,
  });

  final ReportQueueTab selected;
  final int Function(ReportQueueTab) countFor;
  final ValueChanged<ReportQueueTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in ReportQueueTab.values) ...[
            _TabChip(
              tab: tab,
              count: countFor(tab),
              active: tab == selected,
              onTap: () => onSelect(tab),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final ReportQueueTab tab;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only the admin's own queue gets an urgent colour. Colouring every count
    // would make the one that means "act now" indistinguishable from the rest.
    final urgent = tab == ReportQueueTab.signed && count > 0;
    final accent = urgent ? AppColors.warning : AppColors.adminPurple;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: active
                  ? accent.withValues(alpha: 0.42)
                  : AppPalette.textMuted(context).withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tab.icon,
                size: 15,
                color: active ? accent : AppPalette.textMuted(context),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                tab.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? accent : AppPalette.textMuted(context),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: active ? 0.24 : 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One report in the queue.
///
/// Leads with the patient rather than the report title: an admin scanning this
/// list is looking for a person's paperwork, not a document name they chose
/// themselves days ago.
class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.request, required this.onTap});

  final PatientReportRequestItem request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final color = switch (r.status) {
      'issued' => AppColors.success,
      'declined' || 'revoked' || 'expired' => AppColors.critical,
      'signed' => AppColors.warning,
      _ => AppColors.brandIndigo,
    };

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(AppIcons.report, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.patientName ?? 'Patient',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Pill(label: r.statusLabel, color: color),
                    if (r.awaitingIssueDecision)
                      _Pill(
                        label: 'Signed by ${r.signatureName ?? r.doctorName}',
                        color: AppColors.doctorGreen,
                      ),
                    // Surfaced in the list, not just the sheet: a report on its
                    // third trip back is a conversation that has stopped
                    // working, and that is only visible by comparing rows.
                    if (r.returnCount > 0)
                      _Pill(
                        label: r.returnCount == 1
                            ? 'Returned once'
                            : 'Returned ${r.returnCount}×',
                        color: AppColors.warning,
                      ),
                    if (r.recipient != null)
                      _Pill(
                        label: 'For ${r.recipient}',
                        color: AppColors.brandIndigo,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                dossierDate(r.signedAt ?? r.issuedAt ?? r.createdAt) ?? '',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
        ],
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
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
