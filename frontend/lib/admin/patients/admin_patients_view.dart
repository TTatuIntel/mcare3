import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../../core/realtime/session_poller.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_credential_dialog.dart';
import '../../shared/widgets/staff_filter_chip.dart';
import '../../shared/widgets/dossier/user_dossier_sheet.dart';
import '../reports/patient_report_builder_sheet.dart';
import '../reports/patient_report_status_sheet.dart';

/// Admin / Assistant patient directory. Composition matches the marked People
/// pages (Users, Health-worker approvals, Care assignments):
///   RoleShell → search + status chips → SectionLabel → StaffListCard →
///   StaffListRow whose onTap opens a management GlassSheet.
///
/// Desktop shows Suspend/Reactivate inline as trailing row buttons; handheld
/// exposes the same actions in the detail sheet.
class AdminPatientsView extends StatefulWidget {
  const AdminPatientsView({super.key, this.assistantMode = false});

  final bool assistantMode;

  @override
  State<AdminPatientsView> createState() => _AdminPatientsViewState();
}

class _AdminPatientsViewState extends State<AdminPatientsView>
    with WidgetsBindingObserver {
  static String? _persistedStatus;
  static String _persistedSearchQuery = '';
  static _PatientSort _persistedSort = _PatientSort.nameAsc;
  static _AdvancedFilter _persistedAdvanced = _AdvancedFilter.none;

  /// Cadence for the silent in-page background refresh. This layers on top of
  /// [SessionPoller] (30s all-user sync at perPage: 100) with a fuller
  /// per-page sync so long directories stay complete without operator taps.
  static const Duration _backgroundRefreshCadence = Duration(seconds: 45);

  late final TextEditingController _search = TextEditingController(
    text: _persistedSearchQuery,
  );

  late String? _statusFilter = _persistedStatus;
  late String _searchQuery = _persistedSearchQuery;
  late _PatientSort _sort = _persistedSort;
  late _AdvancedFilter _advanced = _persistedAdvanced;

  final Set<String> _busyPatientIds = <String>{};
  bool _loading = false;
  bool _backgroundInFlight = false;
  String? _error;
  DateTime? _lastSyncedAt;
  int _lastKnownUserCount = 0;
  Timer? _syncedTicker;
  Timer? _backgroundTicker;

  String get _currentRoute => widget.assistantMode
      ? RouteNames.assistantPatients
      : RouteNames.adminPatients;

  String get _profileRoute => widget.assistantMode
      ? RouteNames.assistantProfile
      : RouteNames.adminProfile;

  String get _notificationsRoute => widget.assistantMode
      ? RouteNames.assistantNotifications
      : RouteNames.adminNotifications;

  List<RoleNavDestination> get _destinations => widget.assistantMode
      ? StaffDestinations.assistant()
      : StaffDestinations.admin();

  bool get _canCreate =>
      !widget.assistantMode ||
      AuthState.instance.hasAssistantPermission(
        AssistantPermissions.canCreateUsers,
      );

  int get _advancedFilterCount {
    var count = 0;
    if (_advanced != _AdvancedFilter.none) count++;
    if (_sort != _PatientSort.nameAsc) count++;
    return count;
  }

  String get _statusKey => _statusFilter ?? 'all';

  static const _statusOptions = [
    StaffFilterOption(value: 'all', label: 'All'),
    StaffFilterOption(
      value: 'active',
      label: 'Active',
      color: AppColors.success,
    ),
    StaffFilterOption(
      value: 'pending',
      label: 'Pending',
      color: AppColors.warning,
    ),
    StaffFilterOption(
      value: 'suspended',
      label: 'Suspended',
      color: AppColors.critical,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastKnownUserCount = StaffState.instance.users
        .where((u) => u.role == UserRole.patient)
        .length;
    StaffState.instance.addListener(_onStaffStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SessionPoller.instance.triggerNow();
      _loadPatients();
    });
    _syncedTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _lastSyncedAt != null) setState(() {});
    });
    _backgroundTicker = Timer.periodic(
      _backgroundRefreshCadence,
      (_) => _backgroundRefresh(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StaffState.instance.removeListener(_onStaffStateChanged);
    _backgroundTicker?.cancel();
    _syncedTicker?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    // Coming back to the foreground — the session poller may be sleeping and
    // any cached user data can be stale. Kick both immediately.
    if (state == AppLifecycleState.resumed) {
      SessionPoller.instance.triggerNow();
      _backgroundRefresh();
    }
  }

  /// Fires whenever anything mutates [StaffState] — including merges done by
  /// [AdminSessionService] under [SessionPoller]. Bumping [_lastSyncedAt]
  /// keeps the "Synced X ago" caption honest even when the fresh data arrived
  /// through the shared poll instead of this page's own refresh.
  void _onStaffStateChanged() {
    if (!mounted) return;
    final currentCount = StaffState.instance.users
        .where((u) => u.role == UserRole.patient)
        .length;
    if (currentCount != _lastKnownUserCount) {
      _lastKnownUserCount = currentCount;
      setState(() => _lastSyncedAt = DateTime.now());
    }
  }

  /// Silent, page-scoped background refresh. Does not surface a loader or
  /// clobber the current error banner. Errors are swallowed so a transient
  /// network blip cannot disrupt the operator's flow.
  Future<void> _backgroundRefresh() async {
    if (!mounted || !AppEnv.backendEnabled || _backgroundInFlight || _loading) {
      return;
    }
    _backgroundInFlight = true;
    try {
      final data = await AdminApi.instance.listUsers(
        role: 'patient',
        perPage: 200,
      );
      final raw = data['users'] as List? ?? const [];
      final users = raw
          .map(
            (e) => StaffMapper.directoryUserFromApiFull(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList();
      StaffState.instance.mergeUsers(users);
      if (mounted) setState(() => _lastSyncedAt = DateTime.now());
    } catch (_) {
      // Silent — foreground refresh is still available via the section label.
    } finally {
      _backgroundInFlight = false;
    }
  }

  // -------------------------------------------------------------- data ----

  Future<void> _loadPatients() async {
    if (!AppEnv.backendEnabled) {
      if (mounted) setState(() => _lastSyncedAt = DateTime.now());
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminApi.instance.listUsers(
        role: 'patient',
        perPage: 200,
      );
      final raw = data['users'] as List? ?? const [];
      final users = raw
          .map(
            (e) => StaffMapper.directoryUserFromApiFull(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList();
      StaffState.instance.mergeUsers(users);
      if (mounted) _lastSyncedAt = DateTime.now();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DirectoryUser? _patientById(String id) {
    for (final u in StaffState.instance.users) {
      if (u.id == id) return u;
    }
    return null;
  }

  List<DirectoryUser> _filteredPatients() {
    var list = StaffState.instance.users
        .where((u) => u.role == UserRole.patient)
        .toList();

    if (_statusFilter != null) {
      list = list.where((u) => u.status == _statusFilter).toList();
    }

    switch (_advanced) {
      case _AdvancedFilter.none:
        break;
      case _AdvancedFilter.locked:
        list = list.where((u) => u.isLocked).toList();
        break;
      case _AdvancedFilter.needsSetup:
        list = list.where((u) => u.mustChangePassword).toList();
        break;
      case _AdvancedFilter.newThisWeek:
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        list = list.where((u) => u.joinedAt.isAfter(cutoff)).toList();
        break;
    }

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (u) =>
                u.name.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q) ||
                u.uniqueId.toLowerCase().contains(q),
          )
          .toList();
    }

    switch (_sort) {
      case _PatientSort.nameAsc:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case _PatientSort.nameDesc:
        list.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case _PatientSort.newest:
        list.sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
        break;
      case _PatientSort.oldest:
        list.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
        break;
      case _PatientSort.mcareId:
        list.sort(
          (a, b) =>
              a.uniqueId.toLowerCase().compareTo(b.uniqueId.toLowerCase()),
        );
        break;
    }

    return list;
  }

  // ----------------------------------------------------------- filters ----

  void _setStatus(String value) {
    final status = value == 'all' ? null : value;
    setState(() {
      _statusFilter = status;
      _persistedStatus = status;
    });
  }

  void _onSearchChanged(String value) {
    final next = value.trim();
    if (next == _searchQuery) return;
    setState(() {
      _searchQuery = next;
      _persistedSearchQuery = next;
    });
  }

  void _clearSearch() {
    if (_search.text.isEmpty && _searchQuery.isEmpty) return;
    setState(() {
      _search.clear();
      _searchQuery = '';
      _persistedSearchQuery = '';
    });
  }

  void _clearAdvancedFilters() {
    if (_advanced == _AdvancedFilter.none && _sort == _PatientSort.nameAsc) {
      return;
    }
    setState(() {
      _advanced = _AdvancedFilter.none;
      _sort = _PatientSort.nameAsc;
      _persistedAdvanced = _AdvancedFilter.none;
      _persistedSort = _PatientSort.nameAsc;
    });
  }

  // ------------------------------------------------------------- build ----

  String get _sectionTitle {
    if (_statusFilter == null) return 'All patients';
    final label = _statusFilter!.replaceAll('_', ' ');
    return '${label[0].toUpperCase()}${label.substring(1)} patients';
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      scrollable: true,
      currentRoute: _currentRoute,
      destinations: _destinations,
      profileRoute: _profileRoute,
      notificationsRoute: _notificationsRoute,
      title: 'Patients',
      subtitle:
          'Clinical accounts · ${DateFormat.MMMEd().format(DateTime.now())}',
      headerActions: [
        Tooltip(
          message: _canCreate
              ? 'Register a new patient account'
              : 'You do not have permission to register patients',
          child: AppButton(
            label: 'Register',
            icon: AppIcons.add,
            size: AppButtonSize.sm,
            onPressed: _canCreate
                ? () => _openCreatePatientSheet(context)
                : null,
          ),
        ),
        const SizedBox(width: 8),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final all = StaffState.instance.users
              .where((u) => u.role == UserRole.patient)
              .toList();
          final list = _filteredPatients();

          if (_loading && all.isEmpty) {
            return const SizedBox(
              height: 420,
              child: AppLoadingView(
                message: 'Loading patients…',
                itemCount: 5,
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              ),
            );
          }

          if (_error != null && all.isEmpty) {
            return _errorState(context);
          }

          final handheld = ResponsiveBuilder.of(context).isHandheld;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: _searchAndFilterRow(context, all),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: StaffFilterChipBar(
                  options: _statusOptions,
                  selected: _statusKey,
                  onSelected: _setStatus,
                ),
              ),
              if (_advancedFilterCount > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                _activeAdvancedFilterSummary(context),
              ],
              if (_error != null && all.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _refreshWarning(context),
              ],
              if (_loading && all.isNotEmpty) ...[
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
                  title: _sectionTitle,
                  icon: AppIcons.patients,
                  trailing: '${list.length}/${all.length}',
                  actionLabel: _loading ? null : 'Refresh',
                  onAction: _loading ? null : _loadPatients,
                ),
              ),
              if (_syncedCaption() != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.xs,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    _syncedCaption()!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ),
              StaggeredEntry(
                index: 3,
                child: list.isEmpty
                    ? _emptyDirectory(context, all)
                    : StaffListCard(
                        children: list
                            .map((u) => _patientRow(context, u, handheld))
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

  Widget _errorState(BuildContext context) {
    return GlassCard(
      frosted: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyStateView(
            icon: AppIcons.alert,
            title: 'Failed to load patients',
            message: _error,
            compact: true,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Retry',
            icon: AppIcons.refresh,
            onPressed: _loadPatients,
          ),
        ],
      ),
    );
  }

  Widget _refreshWarning(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not refresh. Showing the last available patient data.',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: _loading ? null : _loadPatients,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _emptyDirectory(BuildContext context, List<DirectoryUser> all) {
    return GlassCard(
      frosted: true,
      child: EmptyStateView(
        icon: AppIcons.patients,
        title: all.isEmpty ? 'No patients yet' : 'No patients match',
        message: all.isEmpty
            ? (_canCreate
                  ? 'Register a patient to get started.'
                  : 'The patient directory is currently empty.')
            : 'Try adjusting your search or filters.',
        actionLabel: all.isEmpty && _canCreate ? 'Register patient' : null,
        onAction: all.isEmpty && _canCreate
            ? () => _openCreatePatientSheet(context)
            : null,
        compact: true,
      ),
    );
  }

  Widget _searchAndFilterRow(BuildContext context, List<DirectoryUser> all) {
    final activeAdvanced = _advancedFilterCount > 0;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'Search name, email or mCare ID…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: activeAdvanced
                      ? 'More filters and sort, $_advancedFilterCount active'
                      : 'More filters and sort',
                  child: IconButton.filledTonal(
                    tooltip: 'More filters & sort',
                    onPressed: () => _openFilterSheet(context, all),
                    icon: const Icon(AppIcons.filter),
                  ),
                ),
              ),
              if (activeAdvanced)
                Positioned(
                  top: -3,
                  right: -3,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.brandIndigo,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_advancedFilterCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _activeAdvancedFilterSummary(BuildContext context) {
    final labels = <String>[
      if (_advanced != _AdvancedFilter.none) _advanced.label,
      if (_sort != _PatientSort.nameAsc) _sort.label,
    ];

    return Row(
      children: [
        const Icon(Icons.tune_rounded, size: 15, color: AppColors.brandIndigo),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            labels.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: _clearAdvancedFilters,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('Clear'),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- row ----

  Widget _patientRow(
    BuildContext context,
    DirectoryUser patient,
    bool handheld,
  ) {
    final pillLabel = patient.isLocked
        ? 'LOCKED'
        : patient.mustChangePassword
        ? 'TEMP PWD'
        : patient.status.replaceAll('_', ' ').toUpperCase();
    final pillColor = patient.isLocked
        ? AppColors.critical
        : patient.mustChangePassword
        ? AppColors.warning
        : switch (patient.status) {
            'active' => AppColors.success,
            'suspended' => AppColors.critical,
            _ => AppColors.warning,
          };

    final busy = _busyPatientIds.contains(patient.id);

    return StaffListRow(
      icon: AppIcons.patients,
      iconColor: patient.role.accent,
      title: patient.name,
      subtitle: '${patient.email} · ${patient.uniqueId}',
      pill: handheld ? pillLabel : null,
      pillColor: pillColor,
      onTap: () => _showPatientDetail(context, patient),
      trailing: handheld
          ? null
          : _RowInlineActions(
              patient: patient,
              busy: busy,
              pillLabel: pillLabel,
              pillColor: pillColor,
              onPrimary: patient.status == 'pending'
                  ? () => _approvePatient(context, patient)
                  : () => _toggleStatus(context, patient),
              primaryLabel: patient.status == 'pending'
                  ? 'Approve'
                  : (patient.status == 'active' ? 'Suspend' : 'Reactivate'),
              primaryDanger: patient.status == 'active',
              primarySuccess:
                  patient.status != 'active' && patient.status != 'pending',
            ),
    );
  }

  // ----------------------------------------------------- detail sheet ----

  Future<void> _showPatientDetail(
    BuildContext pageContext,
    DirectoryUser patient,
  ) {
    return GlassSheet.show<void>(
      pageContext,
      title: patient.name,
      subtitle: 'Patient · ${patient.uniqueId}',
      child: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (sheetContext, _) {
          final current = _patientById(patient.id) ?? patient;
          final busy = _busyPatientIds.contains(current.id);
          final statusColor = switch (current.status) {
            'active' => AppColors.success,
            'suspended' => AppColors.critical,
            _ => AppColors.warning,
          };

          return Padding(
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
                _PatientIdentityCard(patient: current),
                const SizedBox(height: AppSpacing.lg),
                _PatientDetailRow(label: 'Email', value: current.email),
                _PatientDetailRow(label: 'mCare ID', value: current.uniqueId),
                _PatientDetailRow(
                  label: 'Status',
                  value: current.status.replaceAll('_', ' ').toUpperCase(),
                  valueColor: statusColor,
                ),
                _PatientDetailRow(
                  label: 'Joined',
                  value: DateFormat.yMMMd().format(current.joinedAt),
                ),
                if (current.isLocked)
                  _PatientDetailRow(
                    label: 'Locked',
                    value: current.lockedUntil != null
                        ? 'Until ${DateFormat.MMMd().add_jm().format(current.lockedUntil!.toLocal())}'
                        : 'Locked after failed sign-ins',
                    valueColor: AppColors.critical,
                  ),
                if (current.mustChangePassword)
                  const _PatientDetailRow(
                    label: 'Password',
                    value: 'Temporary — must change on next sign-in',
                    valueColor: AppColors.warning,
                  ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Open clinical profile',
                  icon: AppIcons.profile,
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: busy
                      ? null
                      : () async {
                          Navigator.of(sheetContext, rootNavigator: true).pop();
                          await _openClinicalProfile(pageContext, current);
                        },
                ),
                if (current.status == 'pending') ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Approve account',
                    icon: AppIcons.check,
                    expand: true,
                    loading: busy,
                    onPressed: busy
                        ? null
                        : () async {
                            final ok = await _approvePatient(
                              sheetContext,
                              current,
                            );
                            if (ok && sheetContext.mounted) {
                              Navigator.of(
                                sheetContext,
                                rootNavigator: true,
                              ).pop();
                            }
                          },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Reject application',
                    icon: AppIcons.close,
                    variant: AppButtonVariant.danger,
                    expand: true,
                    loading: busy,
                    onPressed: busy
                        ? null
                        : () async {
                            final ok = await _rejectPatient(
                              sheetContext,
                              current,
                            );
                            if (ok && sheetContext.mounted) {
                              Navigator.of(
                                sheetContext,
                                rootNavigator: true,
                              ).pop();
                            }
                          },
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: current.status == 'active'
                        ? 'Suspend account'
                        : 'Reactivate account',
                    icon: current.status == 'active'
                        ? AppIcons.lock
                        : AppIcons.check,
                    variant: current.status == 'active'
                        ? AppButtonVariant.danger
                        : AppButtonVariant.primary,
                    expand: true,
                    loading: busy,
                    onPressed: busy
                        ? null
                        : () => _toggleStatus(sheetContext, current),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Issue temporary password',
                  icon: AppIcons.lock,
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: busy
                      ? null
                      : () => _resetPatientPassword(sheetContext, current),
                ),
                if (current.isLocked) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Unlock account',
                    icon: AppIcons.check,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: busy
                        ? null
                        : () => _unlockPatient(sheetContext, current),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: current.email),
                          );
                          if (!sheetContext.mounted) return;
                          AppToast.success(sheetContext, 'Email copied');
                        },
                        icon: const Icon(Icons.email_outlined, size: 16),
                        label: const Text('Copy email'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: current.uniqueId),
                          );
                          if (!sheetContext.mounted) return;
                          AppToast.success(sheetContext, 'mCare ID copied');
                        },
                        icon: const Icon(Icons.badge_outlined, size: 16),
                        label: const Text('Copy ID'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openClinicalProfile(
    BuildContext context,
    DirectoryUser patient,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      // Admin staff get the complete dossier, not just the clinical sheet —
      // meals, progress, account trail, and login history included.
      await UserDossierSheet.show(
        context,
        userId: patient.id,
        name: patient.name,
        subtitle: 'Patient · ${patient.uniqueId}',
        onIssueReport: () => _issuePatientReport(context, patient),
      );
    } catch (_) {
      if (context.mounted) {
        AppToast.error(
          context,
          'Could not open patient details. Please refresh and try again.',
        );
      }
    }
  }

  /// Tick the sections needed, then track the request through the patient's
  /// consent and the doctor's signature to issue.
  Future<void> _issuePatientReport(
    BuildContext context,
    DirectoryUser patient,
  ) async {
    final request = await PatientReportBuilderSheet.show(
      context,
      patientId: patient.id,
      patientName: patient.name,
    );
    if (request == null || !context.mounted) return;

    await PatientReportStatusSheet.show(context, request: request);
  }

  // --------------------------------------------------- management ops ----

  void _setBusy(String id, bool busy) {
    if (!mounted) return;
    setState(() {
      if (busy) {
        _busyPatientIds.add(id);
      } else {
        _busyPatientIds.remove(id);
      }
    });
  }

  Future<bool> _approvePatient(BuildContext context, DirectoryUser u) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Approve ${u.name}?',
      message: 'They will gain access to the patient app immediately.',
      confirmLabel: 'Approve',
      icon: AppIcons.approval,
    );
    if (ok != true || !mounted) return false;
    _setBusy(u.id, true);
    try {
      await StaffState.instance.approveApplicationRemote(u.id);
      if (!context.mounted) return true;
      AppToast.success(context, '${u.name} approved.');
      return true;
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, 'Could not approve: $e');
      }
      return false;
    } finally {
      _setBusy(u.id, false);
    }
  }

  Future<bool> _rejectPatient(BuildContext context, DirectoryUser u) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Reject application?',
      message: 'This cannot be undone.',
      confirmLabel: 'Reject',
      danger: true,
      icon: AppIcons.close,
    );
    if (ok != true || !mounted) return false;
    _setBusy(u.id, true);
    try {
      await StaffState.instance.rejectApplicationRemote(
        u.id,
        reason: 'Application rejected by staff.',
      );
      if (!context.mounted) return true;
      AppToast.info(context, '${u.name} rejected.');
      return true;
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, 'Could not reject: $e');
      }
      return false;
    } finally {
      _setBusy(u.id, false);
    }
  }

  Future<void> _toggleStatus(BuildContext context, DirectoryUser u) async {
    final next = u.status == 'active' ? 'suspended' : 'active';
    final ok = await AppDialog.confirm(
      context,
      title: u.status == 'active' ? 'Suspend account?' : 'Reactivate?',
      message: u.status == 'active'
          ? 'Patient will lose access immediately.'
          : 'Patient will regain access immediately.',
      danger: u.status == 'active',
    );
    if (ok != true || !mounted) return;
    _setBusy(u.id, true);
    try {
      await StaffState.instance.setUserStatusRemote(u.id, next);
      if (!context.mounted) return;
      AppToast.success(context, 'Status updated.');
    } catch (_) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not update status.');
    } finally {
      _setBusy(u.id, false);
    }
  }

  Future<void> _resetPatientPassword(
    BuildContext context,
    DirectoryUser u,
  ) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Issue temporary password?',
      message:
          'A one-time password will be shown once for ${u.name}. They must change it on next sign-in. Any lockout is cleared and active sessions end immediately.',
      icon: AppIcons.lock,
    );
    if (ok != true || !mounted) return;
    _setBusy(u.id, true);
    try {
      final temp = await AdminApi.instance.resetUserPassword(u.id);
      if (!context.mounted) return;
      u
        ..isLocked = false
        ..lockedUntil = null
        ..mustChangePassword = true;
      StaffState.instance.notifyDirectoryChanged();
      await showStaffCredentialDialog(
        context,
        title: 'Temporary password',
        message:
            'Share this securely with ${u.name}. It is shown only once and must be changed at the next sign-in.',
        values: [
          StaffCredentialValue(label: 'Temporary password', value: temp ?? ''),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not issue temporary password: $e');
    } finally {
      _setBusy(u.id, false);
    }
  }

  Future<void> _unlockPatient(BuildContext context, DirectoryUser u) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Unlock account?',
      message:
          'Clear the login lockout for ${u.name} so they can sign in again.',
      icon: AppIcons.check,
    );
    if (ok != true || !mounted) return;
    _setBusy(u.id, true);
    try {
      await AdminApi.instance.unlockUser(u.id);
      if (!context.mounted) return;
      u
        ..isLocked = false
        ..lockedUntil = null;
      StaffState.instance.notifyDirectoryChanged();
      AppToast.success(context, '${u.name} unlocked.');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not unlock account: $e');
    } finally {
      _setBusy(u.id, false);
    }
  }

  // ---------------------------------------------------- filter sheet ----

  Future<void> _openFilterSheet(
    BuildContext context,
    List<DirectoryUser> all,
  ) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    var draftAdvanced = _advanced;
    var draftSort = _sort;

    var scoped = all.toList();
    if (_statusFilter != null) {
      scoped = scoped.where((u) => u.status == _statusFilter).toList();
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      scoped = scoped
          .where(
            (u) =>
                u.name.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q) ||
                u.uniqueId.toLowerCase().contains(q),
          )
          .toList();
    }

    int advancedCount(_AdvancedFilter filter) => switch (filter) {
      _AdvancedFilter.none => scoped.length,
      _AdvancedFilter.locked => scoped.where((u) => u.isLocked).length,
      _AdvancedFilter.needsSetup =>
        scoped.where((u) => u.mustChangePassword).length,
      _AdvancedFilter.newThisWeek =>
        scoped.where((u) => u.joinedAt.isAfter(cutoff)).length,
    };

    final applied = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget section(String title, List<Widget> children) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textMuted(ctx),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: children,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.md,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'More filters & sort',
                                  style: Theme.of(ctx).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Status stays on the quick chips above the directory.',
                                  style: Theme.of(ctx).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppPalette.textMuted(ctx),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                draftAdvanced = _AdvancedFilter.none;
                                draftSort = _PatientSort.nameAsc;
                              });
                            },
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              section('ACCOUNT', [
                                for (final filter in _AdvancedFilter.values)
                                  _FilterChip(
                                    label:
                                        '${filter.label} · ${advancedCount(filter)}',
                                    selected: draftAdvanced == filter,
                                    accent: AppColors.tempTeal,
                                    onTap: () => setSheetState(
                                      () => draftAdvanced = filter,
                                    ),
                                  ),
                              ]),
                              section('SORT BY', [
                                for (final sort in _PatientSort.values)
                                  _FilterChip(
                                    label: sort.label,
                                    selected: draftSort == sort,
                                    accent: AppColors.doctorGreen,
                                    onTap: () =>
                                        setSheetState(() => draftSort = sort),
                                  ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Apply filters',
                        icon: AppIcons.checkMark,
                        expand: true,
                        onPressed: () => Navigator.of(ctx).pop(true),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        _advanced = draftAdvanced;
        _sort = draftSort;
        _persistedAdvanced = draftAdvanced;
        _persistedSort = draftSort;
      });
    }
  }

  String? _syncedCaption() {
    final synced = _lastSyncedAt;
    if (synced == null) return null;
    final delta = DateTime.now().difference(synced);
    if (delta.inSeconds < 60) return 'Synced just now · ${_sort.label}';
    if (delta.inMinutes < 60) {
      return 'Synced ${delta.inMinutes}m ago · ${_sort.label}';
    }
    if (delta.inHours < 24) {
      return 'Synced ${delta.inHours}h ago · ${_sort.label}';
    }
    return 'Synced ${DateFormat.MMMd().format(synced)} · ${_sort.label}';
  }

  // ---------------------------------------------------------- create ----

  bool _looksLikeEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  Future<void> _openCreatePatientSheet(BuildContext context) async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    var creating = false;

    await GlassSheet.show(
      context,
      title: 'Register patient',
      subtitle: 'Creates an active patient account',
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          final first = firstCtrl.text.trim();
          final last = lastCtrl.text.trim();
          final email = emailCtrl.text.trim();
          final canSubmit =
              first.isNotEmpty &&
              last.isNotEmpty &&
              _looksLikeEmail(email) &&
              !creating;

          Widget field(
            TextEditingController controller,
            String label,
            String hint, {
            TextInputType? keyboardType,
            String? errorText,
          }) {
            return AppTextField(
              controller: controller,
              label: label,
              hint: hint,
              keyboardType: keyboardType,
              errorText: errorText,
              onChanged: (_) => setSheetState(() {}),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        field(firstCtrl, 'First name', 'e.g. Amara'),
                        const SizedBox(height: AppSpacing.sm),
                        field(lastCtrl, 'Last name', 'e.g. Okonkwo'),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: field(firstCtrl, 'First name', 'e.g. Amara'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: field(lastCtrl, 'Last name', 'e.g. Okonkwo'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              field(
                emailCtrl,
                'Email address',
                'patient@example.com',
                keyboardType: TextInputType.emailAddress,
                errorText: email.isEmpty || _looksLikeEmail(email)
                    ? null
                    : 'Enter a valid email address',
              ),
              const SizedBox(height: AppSpacing.sm),
              field(
                phoneCtrl,
                'Phone (optional)',
                '+256 7XX XXX XXX',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Create patient account',
                icon: AppIcons.patients,
                expand: true,
                loading: creating,
                onPressed: !canSubmit
                    ? null
                    : () async {
                        setSheetState(() => creating = true);
                        try {
                          final data = await AdminApi.instance.createUser(
                            firstName: first,
                            lastName: last,
                            email: email,
                            phone: phoneCtrl.text.trim().isEmpty
                                ? null
                                : phoneCtrl.text.trim(),
                            role: 'patient',
                          );
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          if (!mounted) return;
                          final temp = data?['temp_password'] as String?;
                          if (temp != null && temp.isNotEmpty) {
                            await showStaffCredentialDialog(
                              context,
                              title: 'Patient registered',
                              message:
                                  '$first $last is ready. Share the temporary password securely — they must change it on first sign-in.',
                              icon: AppIcons.check,
                              values: [
                                StaffCredentialValue(
                                  label: 'Temporary password',
                                  value: temp,
                                ),
                              ],
                            );
                          } else {
                            AppToast.success(
                              context,
                              'Patient account created.',
                            );
                          }
                          await _loadPatients();
                        } catch (_) {
                          if (ctx.mounted) {
                            AppToast.error(
                              ctx,
                              'Could not create patient — check email is unique.',
                            );
                          }
                        } finally {
                          if (ctx.mounted) {
                            setSheetState(() => creating = false);
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    firstCtrl.dispose();
    lastCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
  }
}

// ---------------------------------------------------------------------------
// Private support widgets
// ---------------------------------------------------------------------------

class _PatientIdentityCard extends StatelessWidget {
  const _PatientIdentityCard({required this.patient});
  final DirectoryUser patient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: patient.role.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: patient.role.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: patient.role.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            alignment: Alignment.center,
            child: Icon(
              AppIcons.patients,
              color: patient.role.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  patient.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientDetailRow extends StatelessWidget {
  const _PatientDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: valueColor ?? AppPalette.ink(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop-only trailing widget on each row: the status pill and a single
/// contextual primary action (Approve / Suspend / Reactivate). Matches the
/// inline-action pattern used by the Approvals directory.
class _RowInlineActions extends StatelessWidget {
  const _RowInlineActions({
    required this.patient,
    required this.busy,
    required this.pillLabel,
    required this.pillColor,
    required this.onPrimary,
    required this.primaryLabel,
    required this.primaryDanger,
    required this.primarySuccess,
  });

  final DirectoryUser patient;
  final bool busy;
  final String pillLabel;
  final Color pillColor;
  final VoidCallback onPrimary;
  final String primaryLabel;
  final bool primaryDanger;
  final bool primarySuccess;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: pillColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: Text(
            pillLabel,
            style: TextStyle(
              color: pillColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppButton(
          label: primaryLabel,
          size: AppButtonSize.sm,
          loading: busy,
          variant: primaryDanger
              ? AppButtonVariant.danger
              : primarySuccess
              ? AppButtonVariant.primary
              : AppButtonVariant.primary,
          onPressed: busy ? null : onPrimary,
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : AppPalette.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(
              color: selected ? accent : AppPalette.border(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accent : AppPalette.textMuted(context),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

enum _PatientSort {
  nameAsc('Name (A → Z)'),
  nameDesc('Name (Z → A)'),
  newest('Recently joined'),
  oldest('Oldest first'),
  mcareId('mCare ID');

  const _PatientSort(this.label);
  final String label;
}

enum _AdvancedFilter {
  none('Any account'),
  locked('Locked'),
  needsSetup('Needs setup'),
  newThisWeek('New this week');

  const _AdvancedFilter(this.label);
  final String label;
}
