import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/env/app_env.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/services/doctor_session_service.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/messages_state.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../alerts/doctor_alert_resolve_sheet.dart';
import '../patients/doctor_patient_section.dart';
import 'doctor_vital_flows.dart';
import '../../shared/vitals/doctor_vital_threshold_form.dart';

/// One vitals control surface: readings, filters, and global defaults on a
/// single scroll — no tab switching.
class DoctorVitalsHubView extends StatelessWidget {
  const DoctorVitalsHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      scrollable: false,
      currentRoute: RouteNames.doctorVitals,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Vitals',
      subtitle: '${DateFormat.MMMEd().format(DateTime.now())} · Caseload',
      body: const _VitalsHubBody(),
    );
  }
}

// ---------------------------------------------------------------------------
// Unified vitals hub
// ---------------------------------------------------------------------------

class _VitalsHubBody extends StatefulWidget {
  const _VitalsHubBody();

  @override
  State<_VitalsHubBody> createState() => _VitalsHubBodyState();
}

/// Alert lifecycle — filter chips only (not duplicate dashboard cards).
enum _AlertStatusFilter { all, newAlert, reviewing, resolved }

/// Quick date presets for the readings feed.
enum _DatePreset { all, today, week, month, custom }

class _VitalsHubBodyState extends State<_VitalsHubBody>
    with WidgetsBindingObserver {
  final TextEditingController _searchCtrl = TextEditingController();
  String _patientQuery = '';
  String? _patientFilterId;
  VitalKey? _vitalFilter;
  RiskLevel? _riskFilter;
  _AlertStatusFilter _statusFilter = _AlertStatusFilter.all;
  bool _overridesOnly = false;
  bool _filtersExpanded = false;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  _DatePreset _datePreset = _DatePreset.all;
  int _visibleCount = 40;
  bool _refreshing = false;
  bool _bootstrapping = true;
  Timer? _liveTimer;

  static const _liveInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StaffState.instance.addListener(_onStaffStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshReadings(silent: true);
    });
    _startLiveSync();
  }

  void _onStaffStateChanged() {
    if (mounted) setState(() {});
  }

  void _startLiveSync() {
    _refreshReadings(silent: true);
    _liveTimer?.cancel();
    if (AppEnv.backendEnabled) {
      _liveTimer = Timer.periodic(_liveInterval, (_) {
        if (mounted) _refreshReadings(silent: true);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshReadings(silent: true);
    }
  }

  Future<void> _refreshReadings({bool silent = false}) async {
    if (_refreshing) return;
    if (!silent) setState(() => _refreshing = true);
    try {
      if (AppEnv.backendEnabled) {
        await DoctorSessionService.instance.syncFromApi(background: true);
      } else {
        StaffState.instance.seedDemo();
      }
    } catch (_) {
      if (!AppEnv.backendEnabled) {
        StaffState.instance.seedDemo();
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _bootstrapping = false;
        });
      }
    }
  }

  void _resetVisibleCount() => _visibleCount = 40;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StaffState.instance.removeListener(_onStaffStateChanged);
    _liveTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  StaffPatient _patientForReading(
    StaffPatientVitalReading reading,
    Map<String, StaffPatient> patientById,
  ) {
    final found = patientById[reading.patientId];
    if (found != null) return found;
    return StaffPatient(
      id: reading.patientId,
      name: reading.patientName ?? 'Patient',
      age: 0,
      sex: '',
      condition: '',
      risk: reading.risk,
      lastReading: reading.recordedAt,
      assignedDoctor: StaffState.currentDoctorDisplayName() ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final assigned = StaffState.instance.assignedPatientsForDoctor();
    final patientById = {for (final p in assigned) p.id: p};
    final assignedIds = patientById.keys.toSet();
    final hasPatients = assigned.isNotEmpty;

    final readings = hasPatients
        ? (StaffState.instance.patientVitalReadings
              .where((r) => assignedIds.contains(r.patientId))
              .toList()
            ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt)))
        : <StaffPatientVitalReading>[];

    final query = _patientQuery.trim().toLowerCase();
    final filtered = readings.where((r) {
      if (_patientFilterId != null && r.patientId != _patientFilterId) {
        return false;
      }
      if (_vitalFilter != null && r.vital != _vitalFilter) return false;
      if (_riskFilter != null && r.risk != _riskFilter) return false;
      if (_dateFrom != null && _dateTo != null) {
        final day = DateTime(
          r.recordedAt.year,
          r.recordedAt.month,
          r.recordedAt.day,
        );
        final from = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
        final to = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day);
        if (day.isBefore(from) || day.isAfter(to)) return false;
      }
      if (query.isNotEmpty) {
        final name = patientById[r.patientId]?.name.toLowerCase() ?? '';
        final value = r.value.toLowerCase();
        if (!name.contains(query) && !value.contains(query)) return false;
      }
      if (_statusFilter != _AlertStatusFilter.all) {
        final alert = _matchingAlertFor(r);
        if (alert == null) return false;
        switch (_statusFilter) {
          case _AlertStatusFilter.newAlert:
            if (alert.acknowledged || alert.resolved) return false;
            break;
          case _AlertStatusFilter.reviewing:
            if (!alert.acknowledged || alert.resolved) return false;
            break;
          case _AlertStatusFilter.resolved:
            if (!alert.resolved) return false;
            break;
          case _AlertStatusFilter.all:
            break;
        }
      }
      if (_overridesOnly) {
        final hasOverride = StaffState.instance.vitalOverrides.any(
          (o) => o.patientId == r.patientId && o.vital == r.vital,
        );
        if (!hasOverride) return false;
      }
      return true;
    }).toList();

    final catalog = StaffState.instance.vitalCatalog;

    // All vital types the caseload monitors
    // plus anything that has actually been recorded. Surfaced as the primary
    // filter row so the doctor can target a vital even before its first
    // reading lands.
    final usedVitals = <VitalKey>{
      for (final r in readings) r.vital,
      for (final entry in catalog.where((e) => e.enabled && e.vital != null))
        entry.vital!,
    }.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    // Alert lifecycle counts across the doctor's caseload.
    final caseloadAlerts = StaffState.instance.alerts
        .where((a) => assignedIds.contains(a.patientId))
        .toList();
    final newAlertCount = caseloadAlerts
        .where((a) => !a.acknowledged && !a.resolved)
        .length;
    final reviewingCount = caseloadAlerts
        .where((a) => a.acknowledged && !a.resolved)
        .length;
    final resolvedCount =
        caseloadAlerts.where((a) => a.resolved).length;

    final overrideCount = StaffState.instance.vitalOverrides
        .where((o) => assignedIds.contains(o.patientId))
        .length;
    final openReadingAlerts =
        readings.where((r) => _openAlertFor(r) != null).length;
    final activeFilterCount = _countActiveFilters();
    final visibleReadings = filtered.take(_visibleCount).toList();
    final hasMore = filtered.length > _visibleCount;

    if (_bootstrapping) {
      return const AppLoadingView(message: 'Loading vitals…');
    }

    return RefreshIndicator(
      onRefresh: () => _refreshReadings(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.zero,
        children: [
        _VitalsSummaryBar(
          readingCount: readings.length,
          filteredCount: filtered.length,
          openAlerts: openReadingAlerts,
          newAlerts: newAlertCount,
          refreshing: _refreshing,
          activeFilters: activeFilterCount,
          filtersOpen: _filtersExpanded,
          onRefresh: () => _refreshReadings(),
          onToggleFilters: () =>
              setState(() => _filtersExpanded = !_filtersExpanded),
          onAssign: () => DoctorVitalFlows.openAssignVital(context),
          onTemplates: () =>
              Navigator.of(context).pushNamed(RouteNames.doctorVitalTemplate),
          onAlertsTap: () {
            if (!hasPatients) return;
            setState(() {
              _statusFilter = _AlertStatusFilter.newAlert;
              _filtersExpanded = false;
              _resetVisibleCount();
            });
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        StaggeredEntry(
          index: 0,
          child: _VitalsFilterStrip(
          searchCtrl: _searchCtrl,
          onQueryChanged: (v) => setState(() {
            _patientQuery = v;
            _resetVisibleCount();
          }),
          expanded: _filtersExpanded,
          activeFilterCount: activeFilterCount,
          datePreset: _datePreset,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          onDatePreset: _applyDatePreset,
          onPickCustomRange: () => _pickDateRange(context),
          vitalFilter: _vitalFilter,
          vitalOptions: usedVitals,
          onVitalChanged: (v) => setState(() {
            _vitalFilter = v;
            _resetVisibleCount();
          }),
          riskFilter: _riskFilter,
          onRiskChanged: (v) => setState(() {
            _riskFilter = v;
            _resetVisibleCount();
          }),
          statusFilter: _statusFilter,
          onStatusChanged: (v) => setState(() {
            _statusFilter = v;
            _resetVisibleCount();
          }),
          newAlertCount: newAlertCount,
          reviewingCount: reviewingCount,
          resolvedCount: resolvedCount,
          overridesOnly: _overridesOnly,
          overrideCount: overrideCount,
          onOverridesOnlyChanged: (v) => setState(() {
            _overridesOnly = v;
            _resetVisibleCount();
          }),
          onClearFilters: _clearAllFilters,
          hasPatients: hasPatients,
          patients: assigned,
          patientFilterId: _patientFilterId,
          onPatientFilterChanged: (id) => setState(() {
            _patientFilterId = id;
            _resetVisibleCount();
          }),
          onQuickToday: () => _applyDatePreset(_DatePreset.today),
          onQuickAlerts: () => setState(() {
            _statusFilter = _AlertStatusFilter.newAlert;
            _resetVisibleCount();
          }),
          onQuickCritical: () => setState(() {
            _riskFilter = RiskLevel.critical;
            _resetVisibleCount();
          }),
          ),
        ),
        if (hasPatients) ...[
          const SizedBox(height: AppSpacing.sm),
          if (filtered.isEmpty)
            GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.vitals,
                title: readings.isEmpty
                    ? 'No readings yet'
                    : 'No vitals match',
                message: readings.isEmpty
                    ? 'Patient vitals appear here as they are recorded.'
                    : 'Adjust filters or tap Refresh.',
                compact: true,
              ),
            )
          else
            StaffListCard(
              children: [
                for (var i = 0; i < visibleReadings.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: AppPalette.border(context),
                    ),
                  _CompactVitalsRow(
                    reading: visibleReadings[i],
                    patient: _patientForReading(
                      visibleReadings[i],
                      patientById,
                    ),
                    openAlert: _openAlertFor(visibleReadings[i]),
                    onOpenPatient: () =>
                        _openPatient(visibleReadings[i].patientId),
                    onMessage: () => _messagePatient(
                      _patientForReading(visibleReadings[i], patientById),
                    ),
                    onAcknowledge: () =>
                        _acknowledgeAlert(visibleReadings[i]),
                    onResolve: () => _resolveAlert(visibleReadings[i]),
                    onEditThreshold: () => _editThreshold(
                      context,
                      _patientForReading(visibleReadings[i], patientById),
                      visibleReadings[i].vital,
                    ),
                  ),
                ],
              ],
            ),
          if (hasMore) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => setState(() => _visibleCount += 40),
              icon: const Icon(AppIcons.expandMore, size: 18),
              label: Text(
                'Load more (${filtered.length - visibleReadings.length})',
              ),
            ),
          ],
        ] else ...[
          const SizedBox(height: AppSpacing.sm),
          GlassCard(
            frosted: true,
            child: const EmptyStateView(
              icon: AppIcons.patients,
              title: 'No assigned patients',
              message: 'Assign patients to review their vitals.',
              compact: true,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  StaffAlert? _openAlertFor(StaffPatientVitalReading r) {
    for (final a in StaffState.instance.alerts) {
      if (a.patientId == r.patientId && a.vital == r.vital && !a.resolved) {
        return a;
      }
    }
    return null;
  }

  /// Most-recent alert for the same patient + vital, regardless of resolved
  /// state. Used by the lifecycle filter (New / Reviewing / Resolved) so the
  /// Resolved chip can surface readings whose alert has been cleared.
  StaffAlert? _matchingAlertFor(StaffPatientVitalReading r) {
    StaffAlert? latest;
    for (final a in StaffState.instance.alerts) {
      if (a.patientId != r.patientId || a.vital != r.vital) continue;
      if (latest == null || a.createdAt.isAfter(latest.createdAt)) {
        latest = a;
      }
    }
    return latest;
  }

  int _countActiveFilters() {
    var n = 0;
    if (_vitalFilter != null) n++;
    if (_riskFilter != null) n++;
    if (_statusFilter != _AlertStatusFilter.all) n++;
    if (_overridesOnly) n++;
    if (_patientFilterId != null) n++;
    if (_datePreset != _DatePreset.all) n++;
    if (_patientQuery.trim().isNotEmpty) n++;
    return n;
  }

  void _applyDatePreset(_DatePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _datePreset = preset;
      _resetVisibleCount();
      switch (preset) {
        case _DatePreset.all:
          _dateFrom = null;
          _dateTo = null;
        case _DatePreset.today:
          _dateFrom = today;
          _dateTo = today;
        case _DatePreset.week:
          _dateFrom = today.subtract(const Duration(days: 6));
          _dateTo = today;
        case _DatePreset.month:
          _dateFrom = today.subtract(const Duration(days: 29));
          _dateTo = today;
        case _DatePreset.custom:
          break;
      }
    });
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 6)),
              end: now,
            ),
      helpText: 'Filter readings by date',
    );
    if (picked == null) return;
    setState(() {
      _dateFrom = picked.start;
      _dateTo = picked.end;
      _datePreset = _DatePreset.custom;
      _resetVisibleCount();
    });
  }

  void _clearAllFilters() {
    setState(() {
      _vitalFilter = null;
      _riskFilter = null;
      _statusFilter = _AlertStatusFilter.all;
      _overridesOnly = false;
      _patientFilterId = null;
      _patientQuery = '';
      _searchCtrl.clear();
      _dateFrom = null;
      _dateTo = null;
      _datePreset = _DatePreset.all;
      _filtersExpanded = false;
      _resetVisibleCount();
    });
  }

  void _openPatient(String patientId) {
    Navigator.of(context).pushNamed(
      RouteNames.doctorPatientChart,
      arguments: {
        'patientId': patientId,
        'section': DoctorPatientSection.vitals.name,
      },
    );
  }

  void _messagePatient(StaffPatient patient) {
    final conv = MessagesState.instance.conversationForPatient(
      patientId: patient.id,
      patientName: patient.name,
    );
    if (conv != null) {
      Navigator.of(context).pushNamed(
        RouteNames.doctorChatThread,
        arguments: conv.id,
      );
      return;
    }
    Navigator.of(context).pushNamed(RouteNames.doctorMessages);
  }

  Future<void> _acknowledgeAlert(StaffPatientVitalReading r) async {
    final alert = _openAlertFor(r);
    if (alert == null || alert.acknowledged) return;
    final ok = await StaffState.instance.acknowledgeAlert(alert.id);
    if (!mounted) return;
    if (ok) {
      AppToast.success(context, '${r.vital.label} alert acknowledged.');
    } else {
      AppToast.show(context, message: 'Could not acknowledge alert.');
    }
  }

  Future<void> _resolveAlert(StaffPatientVitalReading r) async {
    final alert = _openAlertFor(r);
    if (alert == null) return;
    await DoctorAlertResolveFlow.resolve(context, alert);
  }

  Future<void> _editThreshold(
      BuildContext context, StaffPatient patient, VitalKey vital) async {
    final current = StaffState.instance.effectiveThresholdFor(patient.id, vital);
    final result = await GlassSheet.show<VitalThresholdFormResult>(
      context,
      title: 'Thresholds · ${vital.label}',
      subtitle: '${patient.name} · per-patient override',
      child: VitalThresholdForm(
        vital: vital,
        initial: current,
        existingOverride: StaffState.instance
            .overridesForPatient(patient.id)
            .where((o) => o.vital == vital)
            .isNotEmpty,
      ),
    );
    if (result == null) return;
    if (result.clear) {
      StaffState.instance.clearPatientThreshold(patient.id, vital);
      if (mounted) {
        AppToast.show(context,
            message: 'Reverted to default for ${vital.label}.');
      }
      return;
    }
    final actor = AuthState.instance.user;
    StaffState.instance.upsertPatientThreshold(
      patientId: patient.id,
      vital: vital,
      normalMin: result.normalMin,
      normalMax: result.normalMax,
      warningLow: result.warningLow,
      warningHigh: result.warningHigh,
      criticalLow: result.criticalLow,
      criticalHigh: result.criticalHigh,
      setBy: actor == null
          ? 'Clinician'
          : 'Dr. ${actor.firstName} ${actor.lastName}',
      note: result.note,
    );
    if (mounted) {
      AppToast.show(context,
          message: '${vital.label} thresholds updated for ${patient.name}.');
    }
  }
}

// ---------------------------------------------------------------------------
// Compact summary toolbar
// ---------------------------------------------------------------------------

class _VitalsSummaryBar extends StatelessWidget {
  const _VitalsSummaryBar({
    required this.readingCount,
    required this.filteredCount,
    required this.openAlerts,
    required this.newAlerts,
    required this.refreshing,
    required this.activeFilters,
    required this.filtersOpen,
    required this.onRefresh,
    required this.onToggleFilters,
    required this.onAssign,
    required this.onTemplates,
    required this.onAlertsTap,
  });

  final int readingCount;
  final int filteredCount;
  final int openAlerts;
  final int newAlerts;
  final bool refreshing;
  final int activeFilters;
  final bool filtersOpen;
  final VoidCallback onRefresh;
  final VoidCallback onToggleFilters;
  final VoidCallback onAssign;
  final VoidCallback onTemplates;
  final VoidCallback onAlertsTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final countLabel = filteredCount != readingCount
        ? '$filteredCount / $readingCount'
        : '$readingCount';

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          _SummaryChip(
            icon: AppIcons.vitals,
            label: countLabel,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.xs),
          InkWell(
            onTap: openAlerts > 0 ? onAlertsTap : null,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: _SummaryChip(
              icon: AppIcons.alert,
              label: openAlerts > 0 ? '$openAlerts' : 'OK',
              color: openAlerts > 0 ? AppColors.critical : AppColors.success,
              pulse: newAlerts > 0,
            ),
          ),
          const Spacer(),
          if (refreshing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _ToolbarIcon(
              icon: AppIcons.refresh,
              tooltip: 'Refresh',
              onTap: onRefresh,
            ),
          _ToolbarIcon(
            icon: AppIcons.filter,
            tooltip: 'Filters',
            selected: filtersOpen || activeFilters > 0,
            badge: activeFilters > 0 ? '$activeFilters' : null,
            onTap: onToggleFilters,
          ),
          _ToolbarIcon(
            icon: AppIcons.patients,
            tooltip: 'Assign vitals',
            onTap: onAssign,
          ),
          _ToolbarIcon(
            icon: AppIcons.catalog,
            tooltip: 'Templates',
            onTap: onTemplates,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withOpacity(pulse ? 0.55 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  const _ToolbarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final color = selected ? accent : AppPalette.textMuted(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              if (badge != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.critical,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      badge!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search + quick filters + advanced panel
// ---------------------------------------------------------------------------

class _VitalsFilterStrip extends StatelessWidget {
  const _VitalsFilterStrip({
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.expanded,
    required this.activeFilterCount,
    required this.datePreset,
    required this.dateFrom,
    required this.dateTo,
    required this.onDatePreset,
    required this.onPickCustomRange,
    required this.vitalFilter,
    required this.vitalOptions,
    required this.onVitalChanged,
    required this.riskFilter,
    required this.onRiskChanged,
    required this.statusFilter,
    required this.onStatusChanged,
    required this.newAlertCount,
    required this.reviewingCount,
    required this.resolvedCount,
    required this.overridesOnly,
    required this.overrideCount,
    required this.onOverridesOnlyChanged,
    required this.onClearFilters,
    required this.hasPatients,
    required this.patients,
    required this.patientFilterId,
    required this.onPatientFilterChanged,
    required this.onQuickToday,
    required this.onQuickAlerts,
    required this.onQuickCritical,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final bool expanded;
  final int activeFilterCount;
  final _DatePreset datePreset;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final ValueChanged<_DatePreset> onDatePreset;
  final VoidCallback onPickCustomRange;
  final VitalKey? vitalFilter;
  final List<VitalKey> vitalOptions;
  final ValueChanged<VitalKey?> onVitalChanged;
  final RiskLevel? riskFilter;
  final ValueChanged<RiskLevel?> onRiskChanged;
  final _AlertStatusFilter statusFilter;
  final ValueChanged<_AlertStatusFilter> onStatusChanged;
  final int newAlertCount;
  final int reviewingCount;
  final int resolvedCount;
  final bool overridesOnly;
  final int overrideCount;
  final ValueChanged<bool> onOverridesOnlyChanged;
  final VoidCallback onClearFilters;
  final bool hasPatients;
  final List<StaffPatient> patients;
  final String? patientFilterId;
  final ValueChanged<String?> onPatientFilterChanged;
  final VoidCallback onQuickToday;
  final VoidCallback onQuickAlerts;
  final VoidCallback onQuickCritical;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: searchCtrl,
                hint: hasPatients ? 'Search patient or value' : 'No patients',
                prefixIcon: AppIcons.search,
                enabled: hasPatients,
                dense: true,
                onChanged: hasPatients ? onQueryChanged : null,
              ),
              if (hasPatients) ...[
                const SizedBox(height: AppSpacing.xs),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: datePreset == _DatePreset.all &&
                            statusFilter == _AlertStatusFilter.all &&
                            riskFilter == null &&
                            vitalFilter == null,
                        onTap: onClearFilters,
                      ),
                      const SizedBox(width: 6),
                      _FilterChip(
                        label: 'Today',
                        selected: datePreset == _DatePreset.today,
                        onTap: onQuickToday,
                      ),
                      const SizedBox(width: 6),
                      _FilterChip(
                        label: '7 days',
                        selected: datePreset == _DatePreset.week,
                        onTap: () => onDatePreset(_DatePreset.week),
                      ),
                      const SizedBox(width: 6),
                      if (newAlertCount > 0)
                        _FilterChip(
                          label: 'Alerts ($newAlertCount)',
                          color: AppColors.critical,
                          selected:
                              statusFilter == _AlertStatusFilter.newAlert,
                          onTap: onQuickAlerts,
                        ),
                      if (newAlertCount > 0) const SizedBox(width: 6),
                      _FilterChip(
                        label: 'Critical',
                        color: AppColors.critical,
                        selected: riskFilter == RiskLevel.critical,
                        onTap: onQuickCritical,
                      ),
                      for (final v in vitalOptions.take(6)) ...[
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: v.shortLabel,
                          color: v.accent,
                          selected: vitalFilter == v,
                          onTap: () => onVitalChanged(
                            vitalFilter == v ? null : v,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: _VitalsAdvancedFilterPanel(
              activeFilterCount: activeFilterCount,
              datePreset: datePreset,
              dateFrom: dateFrom,
              dateTo: dateTo,
              onDatePreset: onDatePreset,
              onPickCustomRange: onPickCustomRange,
              vitalFilter: vitalFilter,
              vitalOptions: vitalOptions,
              onVitalChanged: onVitalChanged,
              riskFilter: riskFilter,
              onRiskChanged: onRiskChanged,
              statusFilter: statusFilter,
              onStatusChanged: onStatusChanged,
              newAlertCount: newAlertCount,
              reviewingCount: reviewingCount,
              resolvedCount: resolvedCount,
              overridesOnly: overridesOnly,
              overrideCount: overrideCount,
              onOverridesOnlyChanged: onOverridesOnlyChanged,
              onClearFilters: onClearFilters,
              hasPatients: hasPatients,
              patients: patients,
              patientFilterId: patientFilterId,
              onPatientFilterChanged: onPatientFilterChanged,
            ),
          ),
      ],
    );
  }
}

class _VitalsAdvancedFilterPanel extends StatelessWidget {
  const _VitalsAdvancedFilterPanel({
    required this.activeFilterCount,
    required this.datePreset,
    required this.dateFrom,
    required this.dateTo,
    required this.onDatePreset,
    required this.onPickCustomRange,
    required this.vitalFilter,
    required this.vitalOptions,
    required this.onVitalChanged,
    required this.riskFilter,
    required this.onRiskChanged,
    required this.statusFilter,
    required this.onStatusChanged,
    required this.newAlertCount,
    required this.reviewingCount,
    required this.resolvedCount,
    required this.overridesOnly,
    required this.overrideCount,
    required this.onOverridesOnlyChanged,
    required this.onClearFilters,
    required this.hasPatients,
    required this.patients,
    required this.patientFilterId,
    required this.onPatientFilterChanged,
  });

  final int activeFilterCount;
  final _DatePreset datePreset;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final ValueChanged<_DatePreset> onDatePreset;
  final VoidCallback onPickCustomRange;
  final VitalKey? vitalFilter;
  final List<VitalKey> vitalOptions;
  final ValueChanged<VitalKey?> onVitalChanged;
  final RiskLevel? riskFilter;
  final ValueChanged<RiskLevel?> onRiskChanged;
  final _AlertStatusFilter statusFilter;
  final ValueChanged<_AlertStatusFilter> onStatusChanged;
  final int newAlertCount;
  final int reviewingCount;
  final int resolvedCount;
  final bool overridesOnly;
  final int overrideCount;
  final ValueChanged<bool> onOverridesOnlyChanged;
  final VoidCallback onClearFilters;
  final bool hasPatients;
  final List<StaffPatient> patients;
  final String? patientFilterId;
  final ValueChanged<String?> onPatientFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!hasPatients) return const SizedBox.shrink();

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Advanced filters',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (activeFilterCount > 0)
                TextButton(
                  onPressed: onClearFilters,
                  child: const Text('Clear all'),
                ),
            ],
          ),
          if (patients.length > 1) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _FilterChip(
                  label: 'All patients',
                  selected: patientFilterId == null,
                  onTap: () => onPatientFilterChanged(null),
                ),
                for (final p in patients)
                  _FilterChip(
                    label: p.name.split(' ').first,
                    selected: patientFilterId == p.id,
                    onTap: () => onPatientFilterChanged(
                      patientFilterId == p.id ? null : p.id,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _FilterChip(
                label: 'Custom dates',
                icon: AppIcons.appointment,
                selected: datePreset == _DatePreset.custom,
                onTap: onPickCustomRange,
              ),
              _FilterChip(
                label: '30 days',
                selected: datePreset == _DatePreset.month,
                onTap: () => onDatePreset(_DatePreset.month),
              ),
              _FilterChip(
                label: 'Reviewing',
                selected: statusFilter == _AlertStatusFilter.reviewing,
                onTap: () => onStatusChanged(
                  statusFilter == _AlertStatusFilter.reviewing
                      ? _AlertStatusFilter.all
                      : _AlertStatusFilter.reviewing,
                ),
              ),
              _FilterChip(
                label: 'Resolved',
                selected: statusFilter == _AlertStatusFilter.resolved,
                onTap: () => onStatusChanged(
                  statusFilter == _AlertStatusFilter.resolved
                      ? _AlertStatusFilter.all
                      : _AlertStatusFilter.resolved,
                ),
              ),
              if (overrideCount > 0)
                _FilterChip(
                  label: 'Overrides',
                  selected: overridesOnly,
                  onTap: () => onOverridesOnlyChanged(!overridesOnly),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    final bg = selected ? accent : accent.withOpacity(0.10);
    final fg = selected ? Colors.white : accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: accent.withOpacity(selected ? 0 : 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact reading row
// ---------------------------------------------------------------------------

class _CompactVitalsRow extends StatelessWidget {
  const _CompactVitalsRow({
    required this.reading,
    required this.patient,
    required this.openAlert,
    required this.onOpenPatient,
    required this.onMessage,
    required this.onAcknowledge,
    required this.onResolve,
    required this.onEditThreshold,
  });

  final StaffPatientVitalReading reading;
  final StaffPatient patient;
  final StaffAlert? openAlert;
  final VoidCallback onOpenPatient;
  final VoidCallback onMessage;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;
  final VoidCallback onEditThreshold;

  @override
  Widget build(BuildContext context) {
    final hasAlert = openAlert != null && !openAlert!.resolved;
    final value = _formatReadingValue(reading.value, reading.vital);
    final pill = hasAlert
        ? (openAlert!.acknowledged ? 'Ack' : 'Alert')
        : reading.risk.label;
    final pillColor = hasAlert
        ? AppColors.critical
        : reading.risk.color;

    final displayName = patient.name.trim().isNotEmpty
        ? patient.name
        : (reading.patientName?.trim().isNotEmpty == true
            ? reading.patientName!
            : 'Patient');

    return StaffListRow(
      icon: reading.vital.icon,
      iconColor: reading.vital.accent,
      title: displayName,
      subtitle:
          '${reading.vital.label} · $value · ${_relativeTime(reading.recordedAt)}',
      pill: pill,
      pillColor: pillColor,
      onTap: onOpenPatient,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAlert && !openAlert!.acknowledged)
            _RowIcon(
              icon: AppIcons.check,
              tooltip: 'Acknowledge',
              color: AppColors.warning,
              onTap: onAcknowledge,
            ),
          if (hasAlert)
            _RowIcon(
              icon: AppIcons.check,
              tooltip: 'Resolve',
              color: AppColors.success,
              onTap: onResolve,
            ),
          _RowIcon(
            icon: AppIcons.more,
            tooltip: 'More',
            onTap: null,
            menuActions: [
              _RowMenuAction(
                icon: AppIcons.chart,
                label: 'Chart',
                onTap: onOpenPatient,
              ),
              _RowMenuAction(
                icon: AppIcons.chat,
                label: 'Message',
                onTap: onMessage,
              ),
              _RowMenuAction(
                icon: AppIcons.edit,
                label: 'Threshold',
                onTap: onEditThreshold,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RowMenuAction {
  const _RowMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.menuActions,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final List<_RowMenuAction>? menuActions;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppPalette.textMuted(context);
    if (menuActions != null) {
      return PopupMenuButton<int>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: fg),
        itemBuilder: (ctx) => [
          for (var i = 0; i < menuActions!.length; i++)
            PopupMenuItem(
              value: i,
              child: Row(
                children: [
                  Icon(menuActions![i].icon, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Text(menuActions![i].label),
                ],
              ),
            ),
        ],
        onSelected: (i) => menuActions![i].onTap(),
      );
    }
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(icon, size: 18, color: fg),
      onPressed: onTap,
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.MMMd().format(t);
}

String _formatReadingValue(String value, VitalKey vital) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '—';
  final unit = vital.unit;
  if (trimmed.toLowerCase().contains(unit.toLowerCase())) return trimmed;
  const knownUnits = ['mmHg', 'bpm', 'mg/dL', '/min', 'kg'];
  for (final u in knownUnits) {
    if (trimmed.contains(u)) return trimmed;
  }
  if (trimmed.contains('%') && unit == '%') return trimmed;
  if (trimmed.contains('°') && unit.contains('°')) return trimmed;
  return '$trimmed $unit';
}
