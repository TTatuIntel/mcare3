import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../../core/realtime/session_poller.dart';
import '../../doctors/alerts/doctor_alert_resolve_sheet.dart';
import '../models/user_role.dart';
import '../models/vital.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_toast.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/patient_three_day_summary.dart';
import '../widgets/risk_badge.dart';
import '../widgets/role_shell.dart';
import '../widgets/section_label.dart';
import '../widgets/staff_blocks.dart';
import '../widgets/staff_filter_chip.dart';
import '../widgets/staff_patient_profile_sheet.dart';

/// System-wide vital alerts — shared by admin and mCare assistant.
///
/// Each row opens a detail sheet where the operator can acknowledge, resolve
/// with a clinical action + note, assign the patient to a health worker
/// (creates a care assignment), or jump to the patient profile.
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
  static const _statusOptions = [
    StaffFilterOption(value: 'open', label: 'Open'),
    StaffFilterOption(
      value: 'critical',
      label: 'Critical',
      color: AppColors.critical,
    ),
    StaffFilterOption(
      value: 'warning',
      label: 'Watch',
      color: AppColors.warning,
    ),
    StaffFilterOption(value: 'acknowledged', label: 'Acknowledged'),
    StaffFilterOption(value: 'resolved', label: 'Resolved'),
    StaffFilterOption(value: 'all', label: 'All'),
  ];

  final _searchCtrl = TextEditingController();
  final Set<String> _busyAlertIds = <String>{};
  String _statusFilter = 'open';
  String _query = '';
  bool _refreshing = false;
  DateTime? _lastSyncedAt;
  Timer? _syncedTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SessionPoller.instance.triggerNow();
      _refresh();
    });
    _syncedTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _lastSyncedAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _syncedTicker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!AppEnv.backendEnabled) {
      setState(() => _lastSyncedAt = DateTime.now());
      return;
    }
    setState(() => _refreshing = true);
    try {
      final rows = await AdminApi.instance.listAlerts();
      final alerts = rows.map((e) => StaffMapper.alertFromApi(e)).toList();
      StaffState.instance.mergeAlerts(alerts);
      if (mounted) setState(() => _lastSyncedAt = DateTime.now());
    } catch (e) {
      if (mounted) AppToast.warn(context, 'Could not refresh alerts.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _setBusy(String id, bool busy) {
    if (!mounted) return;
    setState(() {
      if (busy) {
        _busyAlertIds.add(id);
      } else {
        _busyAlertIds.remove(id);
      }
    });
  }

  Future<void> _acknowledge(BuildContext context, StaffAlert alert) async {
    if (alert.acknowledged || alert.resolved) return;
    _setBusy(alert.id, true);
    try {
      final ok = await StaffState.instance.acknowledgeAlert(alert.id);
      if (!context.mounted) return;
      if (ok) {
        AppToast.success(context, 'Alert acknowledged.');
      } else {
        AppToast.error(context, 'Could not acknowledge — please retry.');
      }
    } finally {
      _setBusy(alert.id, false);
    }
  }

  Future<void> _resolve(BuildContext context, StaffAlert alert) async {
    if (alert.resolved) return;
    _setBusy(alert.id, true);
    try {
      await DoctorAlertResolveFlow.resolve(context, alert);
    } finally {
      _setBusy(alert.id, false);
    }
  }

  List<StaffAlert> _filtered(List<StaffAlert> all) {
    Iterable<StaffAlert> list = all;

    switch (_statusFilter) {
      case 'open':
        list = list.where((a) => !a.resolved);
        break;
      case 'critical':
        list = list.where(
          (a) => !a.resolved && a.severity == RiskLevel.critical,
        );
        break;
      case 'warning':
        list = list.where(
          (a) => !a.resolved && a.severity == RiskLevel.warning,
        );
        break;
      case 'acknowledged':
        list = list.where((a) => a.acknowledged && !a.resolved);
        break;
      case 'resolved':
        list = list.where((a) => a.resolved);
        break;
      case 'all':
      default:
        break;
    }

    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where(
        (a) =>
            a.patientName.toLowerCase().contains(q) ||
            a.vital.label.toLowerCase().contains(q) ||
            a.value.toLowerCase().contains(q),
      );
    }

    final out = list.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  int _openCount(List<StaffAlert> all) => all.where((a) => !a.resolved).length;

  String? _syncedCaption() {
    final synced = _lastSyncedAt;
    if (synced == null) return null;
    final delta = DateTime.now().difference(synced);
    if (delta.inSeconds < 60) return 'Synced just now';
    if (delta.inMinutes < 60) return 'Synced ${delta.inMinutes}m ago';
    if (delta.inHours < 24) return 'Synced ${delta.inHours}h ago';
    return 'Synced ${DateFormat.MMMd().format(synced)}';
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      scrollable: true,
      currentRoute: widget.currentRoute,
      destinations: widget.destinations,
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Alerts',
      subtitle: widget.subtitle,
      headerActions: [
        AppButton(
          label: 'Refresh',
          icon: AppIcons.refresh,
          size: AppButtonSize.sm,
          variant: AppButtonVariant.secondary,
          loading: _refreshing,
          onPressed: _refreshing ? null : _refresh,
        ),
        const SizedBox(width: 8),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final all = StaffState.instance.alerts.toList();
          final filtered = _filtered(all);
          final openCount = _openCount(all);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(index: 0, child: _searchField(context)),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: StaffFilterChipBar(
                  options: _statusOptions,
                  selected: _statusFilter,
                  onSelected: (v) => setState(() => _statusFilter = v),
                ),
              ),
              if (_refreshing) ...[
                const SizedBox(height: AppSpacing.sm),
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 2,
                child: SectionLabel(
                  title: _sectionTitle(),
                  icon: AppIcons.alert,
                  trailing: '${filtered.length}/${all.length}',
                ),
              ),
              if (_syncedCaption() != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.xs,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    '${_syncedCaption()!} · $openCount open',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ),
              StaggeredEntry(
                index: 3,
                child: filtered.isEmpty
                    ? _emptyState(context, all)
                    : StaffListCard(
                        children: filtered
                            .map(
                              (a) => _AlertRow(
                                alert: a,
                                busy: _busyAlertIds.contains(a.id),
                                onTap: () => _openDetail(context, a),
                                onAck: a.resolved || a.acknowledged
                                    ? null
                                    : () => _acknowledge(context, a),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Search patient, vital, or reading…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
        isDense: true,
      ),
    );
  }

  String _sectionTitle() => switch (_statusFilter) {
    'open' => 'Open alerts',
    'critical' => 'Critical alerts',
    'warning' => 'Watch alerts',
    'acknowledged' => 'Acknowledged',
    'resolved' => 'Resolved',
    _ => 'All alerts',
  };

  Widget _emptyState(BuildContext context, List<StaffAlert> all) {
    return GlassCard(
      frosted: true,
      child: EmptyStateView(
        icon: AppIcons.alert,
        title: all.isEmpty ? 'No alerts' : 'No alerts match',
        message: all.isEmpty
            ? 'Patient vital alerts will appear here.'
            : 'Try a different filter or clear the search.',
        compact: true,
      ),
    );
  }

  // ------------------------------------------------------------- detail ----

  Future<void> _openDetail(BuildContext pageContext, StaffAlert alert) {
    return GlassSheet.show<void>(
      pageContext,
      title: '${alert.vital.label} alert',
      subtitle:
          '${alert.patientName} · ${DateFormat.MMMd().add_jm().format(alert.createdAt)}',
      leadingIcon: alert.vital.icon,
      leadingColor: alert.severity.color,
      statusLabel: alert.resolved
          ? 'Resolved'
          : alert.acknowledged
          ? 'Acknowledged'
          : alert.severity.label,
      statusColor: alert.resolved
          ? AppColors.success
          : alert.acknowledged
          ? AppColors.info
          : alert.severity.color,
      child: _AlertDetailBody(
        alertId: alert.id,
        pageContext: pageContext,
        onAcknowledge: (a) => _acknowledge(pageContext, a),
        onResolve: (a) => _resolve(pageContext, a),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.alert,
    required this.busy,
    required this.onTap,
    this.onAck,
  });

  final StaffAlert alert;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onAck;

  @override
  Widget build(BuildContext context) {
    final pillLabel = alert.resolved
        ? 'Resolved'
        : (alert.acknowledged ? 'Acknowledged' : alert.severity.label);
    final pillColor = alert.resolved
        ? AppColors.success
        : (alert.acknowledged ? AppColors.info : alert.severity.color);

    return StaffListRow(
      icon: alert.vital.icon,
      iconColor: alert.resolved
          ? AppPalette.textMuted(context)
          : alert.severity.color,
      title: '${alert.patientName} · ${alert.vital.label}',
      subtitle:
          '${alert.value} · ${DateFormat.MMMd().add_jm().format(alert.createdAt)}',
      pill: pillLabel,
      pillColor: pillColor,
      onTap: onTap,
      trailing: onAck == null
          ? null
          : AppButton(
              label: 'Ack',
              size: AppButtonSize.sm,
              loading: busy,
              onPressed: busy ? null : onAck,
            ),
    );
  }
}

class _AlertDetailBody extends StatefulWidget {
  const _AlertDetailBody({
    required this.alertId,
    required this.pageContext,
    required this.onAcknowledge,
    required this.onResolve,
  });

  final String alertId;
  final BuildContext pageContext;
  final Future<void> Function(StaffAlert alert) onAcknowledge;
  final Future<void> Function(StaffAlert alert) onResolve;

  @override
  State<_AlertDetailBody> createState() => _AlertDetailBodyState();
}

class _AlertDetailBodyState extends State<_AlertDetailBody> {
  bool _busy = false;

  StaffAlert? _find() {
    for (final a in StaffState.instance.alerts) {
      if (a.id == widget.alertId) return a;
    }
    return null;
  }

  /// Split the free-text alert body into a compact numeric reading (e.g.
  /// `168 mg/dL`) and the trailing narrative. Falls back to the whole string
  /// as the reading when no unit-like token is present.
  _ParsedReading _splitReading(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const _ParsedReading('—', null);

    final match = RegExp(
      r'^([-+]?\d+(?:[./]\d+)?(?:\s?[a-zA-Z%°/]+)?(?:\s?/\s?\d+(?:\.\d+)?(?:\s?[a-zA-Z%°/]+)?)?)',
    ).firstMatch(text);

    if (match == null) return _ParsedReading(text, null);

    final reading = match.group(1)!.trim();
    var remainder = text.substring(match.end).trim();
    remainder = remainder.replaceFirst(RegExp(r'^[—–\-·:,\.\s]+'), '').trim();
    return _ParsedReading(reading, remainder.isEmpty ? null : remainder);
  }

  /// Care providers linked to this patient. `CareAssignment` stores names only
  /// so we match on the patient name from the alert; when the API row is
  /// hydrated the merge keeps this in sync.
  List<CareAssignment> _assignmentsFor(String patientName) {
    final target = patientName.trim().toLowerCase();
    return StaffState.instance.assignments
        .where((a) => a.patient.trim().toLowerCase() == target)
        .toList()
      ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final alert = _find();
        if (alert == null) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: EmptyStateView(
              icon: AppIcons.alert,
              title: 'Alert not found',
              message: 'It may have been resolved by another operator.',
              compact: true,
            ),
          );
        }

        final assignees = _assignmentsFor(alert.patientName);
        final parsed = _splitReading(alert.value);
        final isResolved = alert.resolved;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _AlertHeaderCard(alert: alert, parsed: parsed),
            if (isResolved && (alert.resolutionNote?.isNotEmpty ?? false)) ...[
              const SizedBox(height: AppSpacing.sm),
              _ResolutionCard(alert: alert),
            ],
            const SizedBox(height: AppSpacing.md),

            _SectionCaption(
              label: 'CARE TEAM',
              trailing: assignees.isEmpty
                  ? 'Unassigned'
                  : '${assignees.length} assigned',
            ),
            const SizedBox(height: AppSpacing.xs),
            if (assignees.isEmpty)
              _EmptyAssignees()
            else
              for (final a in assignees) _AssigneeChip(assignment: a),

            const SizedBox(height: AppSpacing.md),
            const _SectionCaption(
              label: 'PATIENT CONTEXT',
              trailing: 'Past 3 days',
            ),
            const SizedBox(height: AppSpacing.xs),
            PatientThreeDaySummary(
              patientId: alert.patientId,
              highlightedVital: alert.vital,
            ),

            const SizedBox(height: AppSpacing.md),
            _ActionsPanel(
              busy: _busy,
              isResolved: isResolved,
              acknowledged: alert.acknowledged,
              assigneesCount: assignees.length,
              onAcknowledge: () async {
                setState(() => _busy = true);
                await widget.onAcknowledge(alert);
                if (mounted) setState(() => _busy = false);
              },
              onResolve: () async {
                setState(() => _busy = true);
                await widget.onResolve(alert);
                if (mounted) setState(() => _busy = false);
              },
              onAssign: () => _openAssignSheet(widget.pageContext, alert),
              onProfile: () async {
                Navigator.of(context, rootNavigator: true).pop();
                await StaffPatientProfileSheet.show(
                  widget.pageContext,
                  patientId: alert.patientId,
                  patientName: alert.patientName,
                  loadFromAdmin: true,
                );
              },
              onCopy: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        '${alert.patientName} · ${alert.vital.label} ${alert.value} '
                        'at ${DateFormat.yMd().add_jm().format(alert.createdAt)}',
                  ),
                );
                if (!context.mounted) return;
                AppToast.success(context, 'Copied.');
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAssignSheet(
    BuildContext pageContext,
    StaffAlert alert,
  ) async {
    final doctors =
        StaffState.instance.users
            .where(
              (u) =>
                  (u.role == UserRole.doctor ||
                      u.role == UserRole.externalDoctor) &&
                  u.status == 'active',
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    if (doctors.isEmpty) {
      AppToast.warn(
        pageContext,
        'No active health workers available. Approve or register one first.',
      );
      return;
    }

    DirectoryUser? selected;
    String role = 'Primary';
    var saving = false;

    await GlassSheet.show<void>(
      pageContext,
      title: 'Assign health worker',
      subtitle: alert.patientName,
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Route this patient to a doctor. The assignment grants the '
                'doctor caseload access — future alerts appear in their queue.',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(sheetContext),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _pickerBlock(
                context: sheetContext,
                label: 'Health worker',
                icon: AppIcons.careTeam,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DirectoryUser>(
                    value: selected,
                    isExpanded: true,
                    hint: const Text('Select a doctor'),
                    icon: const Icon(AppIcons.expandMore),
                    onChanged: saving
                        ? null
                        : (v) => setSheetState(() => selected = v),
                    items: [
                      for (final d in doctors)
                        DropdownMenuItem(
                          value: d,
                          child: Text(
                            d.specialty != null && d.specialty!.isNotEmpty
                                ? '${d.name} · ${d.specialty}'
                                : d.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _pickerBlock(
                context: sheetContext,
                label: 'Relationship',
                icon: AppIcons.assignments,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: role,
                    isExpanded: true,
                    icon: const Icon(AppIcons.expandMore),
                    onChanged: saving
                        ? null
                        : (v) => setSheetState(() => role = v ?? 'Primary'),
                    items: const [
                      DropdownMenuItem(
                        value: 'Primary',
                        child: Text('Primary care'),
                      ),
                      DropdownMenuItem(
                        value: 'Consulting',
                        child: Text('Consulting'),
                      ),
                      DropdownMenuItem(
                        value: 'Specialist',
                        child: Text('Specialist'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Create assignment',
                icon: AppIcons.assignments,
                expand: true,
                loading: saving,
                onPressed: saving
                    ? null
                    : () async {
                        if (selected == null) {
                          AppToast.warn(sheetContext, 'Pick a doctor first.');
                          return;
                        }
                        setSheetState(() => saving = true);
                        try {
                          await StaffState.instance.createAssignmentRemote(
                            patientUserId: alert.patientId,
                            providerUserId: selected!.id,
                            role: role,
                          );
                          if (!AppEnv.backendEnabled) {
                            StaffState.instance.addAssignment(
                              CareAssignment(
                                id: 'as_${DateTime.now().millisecondsSinceEpoch}',
                                patient: alert.patientName,
                                provider: selected!.name,
                                assignedAt: DateTime.now(),
                                role: role,
                              ),
                            );
                          }
                          if (sheetContext.mounted) {
                            Navigator.of(
                              sheetContext,
                              rootNavigator: true,
                            ).pop();
                          }
                          if (pageContext.mounted) {
                            AppToast.success(
                              pageContext,
                              '${alert.patientName} assigned to ${selected!.name}.',
                            );
                          }
                        } catch (e) {
                          if (sheetContext.mounted) {
                            setSheetState(() => saving = false);
                            AppToast.error(
                              sheetContext,
                              'Could not assign: ${_readableError(e)}',
                            );
                          }
                        }
                      },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: saving
                    ? null
                    : () =>
                          Navigator.of(sheetContext, rootNavigator: true).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickerBlock({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.brandIndigo),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppPalette.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppPalette.border(context)),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ],
    );
  }

  String _readableError(Object e) {
    final s = e.toString();
    if (s.contains('Assignment already exists')) return 'already assigned';
    if (s.length > 120) return '${s.substring(0, 120)}…';
    return s;
  }
}

/// Compact numeric reading + trailing narrative extracted from an alert body.
class _ParsedReading {
  const _ParsedReading(this.reading, this.detail);
  final String reading;
  final String? detail;
}

/// The distinct action card at the bottom of the alert detail sheet.
/// Wraps the primary + secondary actions in a tinted, bordered surface with
/// a header pill so operators recognise the action zone at a glance.
class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel({
    required this.busy,
    required this.isResolved,
    required this.acknowledged,
    required this.assigneesCount,
    required this.onAcknowledge,
    required this.onResolve,
    required this.onAssign,
    required this.onProfile,
    required this.onCopy,
  });

  final bool busy;
  final bool isResolved;
  final bool acknowledged;
  final int assigneesCount;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;
  final VoidCallback onAssign;
  final VoidCallback onProfile;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandIndigo.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: AppColors.brandIndigo.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandIndigo.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: const Text(
                  'ACTIONS',
                  style: TextStyle(
                    color: AppColors.brandIndigo,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              if (isResolved)
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 13,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Closed',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          if (!isResolved) ...[
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: acknowledged ? 'Acknowledged' : 'Acknowledge',
                    icon: AppIcons.checkMark,
                    size: AppButtonSize.sm,
                    expand: true,
                    variant: AppButtonVariant.secondary,
                    loading: busy && !acknowledged,
                    onPressed: acknowledged || busy ? null : onAcknowledge,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Resolve',
                    icon: AppIcons.check,
                    size: AppButtonSize.sm,
                    expand: true,
                    variant: AppButtonVariant.primary,
                    onPressed: busy ? null : onResolve,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Divider(
              height: 1,
              color: AppColors.brandIndigo.withValues(alpha: 0.15),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: AppIcons.careTeam,
                  label: assigneesCount == 0 ? 'Assign' : 'Reassign',
                  onTap: busy ? null : onAssign,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionTile(
                  icon: AppIcons.profile,
                  label: 'Profile',
                  onTap: busy ? null : onProfile,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionTile(
                  icon: AppIcons.copy,
                  label: 'Copy',
                  onTap: onCopy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small tap target used inside [_ActionsPanel] for the secondary triad.
/// Icon over a short label, tinted background — reads instantly as an action.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled
        ? AppPalette.textMuted(context)
        : AppColors.brandIndigo;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: disabled
                ? AppPalette.surfaceAlt(context)
                : AppColors.brandIndigo.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: disabled
                  ? AppPalette.border(context)
                  : AppColors.brandIndigo.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption({required this.label, this.trailing});
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppPalette.textMuted(context),
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    );
    return Row(
      children: [
        Text(label, style: style),
        if (trailing != null) ...[
          const Spacer(),
          Text(trailing!, style: style),
        ],
      ],
    );
  }
}

class _AlertHeaderCard extends StatelessWidget {
  const _AlertHeaderCard({required this.alert, required this.parsed});
  final StaffAlert alert;
  final _ParsedReading parsed;

  @override
  Widget build(BuildContext context) {
    final accent = alert.severity.color;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(alert.vital.icon, color: accent, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        parsed.reading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: RiskBadge(risk: alert.severity, dense: true),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${alert.vital.label} · ${DateFormat.MMMd().add_jm().format(alert.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (parsed.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    parsed.detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.ink(context),
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolutionCard extends StatelessWidget {
  const _ResolutionCard({required this.alert});
  final StaffAlert alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.successSoft(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resolution',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
          if (alert.resolutionAction != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              formatAlertResolutionAction(alert),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (alert.resolutionNote?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              alert.resolutionNote!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyAssignees extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.careTeam,
            size: 16,
            color: AppPalette.textMuted(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No health worker assigned yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssigneeChip extends StatelessWidget {
  const _AssigneeChip({required this.assignment});
  final CareAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: AppColors.brandIndigo.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: AppColors.brandIndigo.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              AppIcons.careTeam,
              size: 16,
              color: AppColors.brandIndigo,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assignment.provider,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppPalette.ink(context),
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${assignment.role} · since ${DateFormat.MMMd().format(assignment.assignedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
