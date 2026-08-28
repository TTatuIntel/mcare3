import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../../core/realtime/session_poller.dart';
import '../../core/realtime/realtime_refresh_mixin.dart';
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
import '../../shared/widgets/staff_directory_controls.dart';
import '../../shared/widgets/loading/loading.dart';

/// Admin entry point for the merged care workspace.
class AdminCareRequestsView extends StatelessWidget {
  const AdminCareRequestsView({super.key, this.initialTab = CareTab.requests});

  final CareTab initialTab;

  @override
  Widget build(BuildContext context) {
    return CareRequestsScreen(
      currentRoute: RouteNames.adminCareRequests,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
      initialTab: initialTab,
    );
  }
}

/// The two halves of the workspace.
enum CareTab { requests, assignments }

enum _Sort {
  newest('Newest first'),
  oldest('Oldest first'),
  patient('Patient A-Z');

  const _Sort(this.label);
  final String label;
}

/// Care requests **and** care assignments in one screen.
///
/// The two used to be separate pages, but they are one workflow: a patient
/// asks for a provider → staff approve, re-route, or decline → an approval is
/// exactly what creates the care assignment. The old `/admin/assignments`
/// route now redirects here.
///
/// The two halves carry their own mCare-assistant grants: [canTriage] mirrors
/// `can_manage_care_requests`, [canAssign] mirrors `can_assign_patients`. An
/// assistant holding only one sees only that half; admins hold both.
class CareRequestsScreen extends StatefulWidget {
  const CareRequestsScreen({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
    this.canAssign = true,
    this.canTriage = true,
    this.initialTab = CareTab.requests,
  });

  final String currentRoute;
  final List destinations;
  final String profileRoute;
  final String notificationsRoute;
  final bool canAssign;
  final bool canTriage;
  final CareTab initialTab;

  @override
  State<CareRequestsScreen> createState() => _CareRequestsScreenState();
}

class _CareRequestsScreenState extends State<CareRequestsScreen>
    with RealtimeRefreshMixin<CareRequestsScreen> {
  static const _roles = ['Primary', 'Consulting', 'Specialist'];

  final _search = TextEditingController();

  late CareTab _tab = _initialTab();

  /// Falls back to whichever half this staff member is allowed to open.
  CareTab _initialTab() {
    if (!widget.canAssign) return CareTab.requests;
    if (!widget.canTriage) return CareTab.assignments;
    return widget.initialTab;
  }

  /// Both halves visible ⇒ the tab switcher is worth rendering.
  bool get _showTabs => widget.canAssign && widget.canTriage;
  String _statusFilter = 'all';
  String _roleFilter = 'all';
  _Sort _sort = _Sort.newest;

  bool _loading = false;
  bool _creating = false;
  String? _error;
  final Set<String> _busyRequests = <String>{};
  final Set<String> _busyAssignments = <String>{};

  @override
  void initState() {
    super.initState();
    watchRealtime(const {'care'}, _load);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SessionPoller.instance.triggerNow();
      _load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  /// Pulls both halves. In mock mode the seeded rows are the source of truth,
  /// so an empty API response must not wipe them.
  Future<void> _load() async {
    if (!AppEnv.backendEnabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.canTriage) {
        final requests = await AdminApi.instance.listCareRequests();
        StaffState.instance.mergeCareRequests(
          requests.map(StaffMapper.careRequestFromApi).toList(),
        );
      }
      if (widget.canAssign) {
        final rows = await AdminApi.instance.listAssignments();
        StaffState.instance.mergeAssignments(
          rows.map(StaffMapper.assignmentFromApi).toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _query => _search.text.trim().toLowerCase();

  List<CareRequestItem> get _filteredRequests {
    var list = List<CareRequestItem>.from(StaffState.instance.careRequests);
    if (_statusFilter != 'all') {
      list = list.where((r) => r.status == _statusFilter).toList();
    }
    if (_query.isNotEmpty) {
      list = list
          .where(
            (r) =>
                r.patient.toLowerCase().contains(_query) ||
                r.providerRequested.toLowerCase().contains(_query) ||
                r.effectiveProvider.toLowerCase().contains(_query) ||
                r.reason.toLowerCase().contains(_query),
          )
          .toList();
    }
    list.sort(switch (_sort) {
      _Sort.newest => (a, b) => b.createdAt.compareTo(a.createdAt),
      _Sort.oldest => (a, b) => a.createdAt.compareTo(b.createdAt),
      _Sort.patient => (a, b) => a.patient.toLowerCase().compareTo(
        b.patient.toLowerCase(),
      ),
    });
    // Pending work always floats to the top of whatever ordering is chosen.
    list.sort((a, b) {
      if (a.isPending == b.isPending) return 0;
      return a.isPending ? -1 : 1;
    });
    return list;
  }

  List<CareAssignment> get _filteredAssignments {
    var list = List<CareAssignment>.from(StaffState.instance.assignments);
    if (_roleFilter != 'all') {
      list = list.where((a) => _normaliseRole(a.role) == _roleFilter).toList();
    }
    if (_query.isNotEmpty) {
      list = list
          .where(
            (a) =>
                a.patient.toLowerCase().contains(_query) ||
                a.provider.toLowerCase().contains(_query) ||
                (a.providerSpecialty ?? '').toLowerCase().contains(_query),
          )
          .toList();
    }
    list.sort(switch (_sort) {
      _Sort.newest => (a, b) => b.assignedAt.compareTo(a.assignedAt),
      _Sort.oldest => (a, b) => a.assignedAt.compareTo(b.assignedAt),
      _Sort.patient => (a, b) => a.patient.toLowerCase().compareTo(
        b.patient.toLowerCase(),
      ),
    });
    return list;
  }

  static String _normaliseRole(String role) =>
      switch (role.trim().toLowerCase()) {
        'consulting' => 'Consulting',
        'specialist' => 'Specialist',
        _ => 'Primary',
      };

  static Color _statusColor(String status) => switch (status) {
    'approved' => AppColors.success,
    'rejected' => AppColors.critical,
    _ => AppColors.warning,
  };

  static Color _roleColor(String role) => switch (role) {
    'Consulting' => AppColors.info,
    'Specialist' => AppColors.warning,
    _ => AppColors.brandIndigo,
  };

  List<DirectoryUser> get _activePatients =>
      StaffState.instance.users
          .where((u) => u.role == UserRole.patient && u.status == 'active')
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Care providers ranked by current caseload — the lightest load first, so
  /// "assign a suitable doctor" starts from a sensible suggestion.
  List<_ProviderOption> get _providerOptions {
    final assignments = StaffState.instance.assignments;
    final options = StaffState.instance.users
        .where(
          (u) =>
              (u.role == UserRole.doctor ||
                  u.role == UserRole.externalDoctor) &&
              u.status == 'active',
        )
        .map((u) {
          final caseload = assignments
              .where(
                (a) => a.providerUserId != null
                    ? a.providerUserId == u.id
                    : a.provider.trim().toLowerCase() ==
                          u.name.trim().toLowerCase(),
              )
              .length;
          return _ProviderOption(user: u, caseload: caseload);
        })
        .toList();
    options.sort((a, b) {
      final byLoad = a.caseload.compareTo(b.caseload);
      return byLoad != 0 ? byLoad : a.user.name.compareTo(b.user.name);
    });
    return options;
  }

  // ---------------------------------------------------------------------------
  // Request decisions
  // ---------------------------------------------------------------------------

  Future<void> _approve(
    CareRequestItem request, {
    DirectoryUser? provider,
    required String role,
    String? note,
  }) async {
    setState(() => _busyRequests.add(request.id));
    try {
      await StaffState.instance.approveCareRequestAdminRemote(
        request.id,
        providerUserId: provider?.id,
        providerName: provider?.name,
        role: role,
        note: note,
      );
      if (!mounted) return;
      final assigned = provider?.name ?? request.providerRequested;
      AppToast.success(
        context,
        '${request.patient} is now assigned to $assigned.',
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.error(context, 'Could not approve: $error');
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  Future<void> _decline(CareRequestItem request, String reason) async {
    setState(() => _busyRequests.add(request.id));
    try {
      await StaffState.instance.rejectCareRequestAdminRemote(
        request.id,
        reason: reason,
      );
      if (!mounted) return;
      AppToast.info(context, 'Request declined — ${request.patient} notified.');
    } catch (error) {
      if (!mounted) return;
      AppToast.error(context, 'Could not decline: $error');
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  /// One sheet covering every decision: approve as requested, approve with a
  /// different provider (reason required), or decline (reason required).
  Future<void> _openReviewSheet(
    BuildContext pageContext,
    CareRequestItem request, {
    _Decision initial = _Decision.approve,
  }) async {
    final providers = _providerOptions;
    final reasonCtrl = TextEditingController();
    final providerSearch = TextEditingController();

    var decision = initial;
    DirectoryUser? chosen;
    var role = _normaliseRole(request.assignmentRole ?? 'Primary');
    var submitting = false;

    await GlassSheet.show<void>(
      pageContext,
      title: 'Review care request',
      subtitle: '${request.patient} → ${request.providerRequested}',
      leadingIcon: AppIcons.careRequest,
      leadingColor: _statusColor(request.status),
      statusLabel: request.status.toUpperCase(),
      statusColor: _statusColor(request.status),
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final visibleProviders = providers.where((p) {
            final q = providerSearch.text.trim().toLowerCase();
            if (q.isEmpty) return true;
            return p.user.name.toLowerCase().contains(q) ||
                (p.user.specialty ?? '').toLowerCase().contains(q);
          }).toList();

          final needsReason =
              decision == _Decision.decline ||
              (decision == _Decision.reassign && chosen != null);
          final reasonFilled = reasonCtrl.text.trim().length >= 4;

          final canSubmit =
              !submitting &&
              switch (decision) {
                _Decision.approve => true,
                _Decision.reassign => chosen != null && reasonFilled,
                _Decision.decline => reasonFilled,
              };

          Future<void> submit() async {
            setSheet(() => submitting = true);
            Navigator.of(sheetContext, rootNavigator: true).pop();
            final note = reasonCtrl.text.trim();
            switch (decision) {
              case _Decision.approve:
                await _approve(
                  request,
                  role: role,
                  note: note.isEmpty ? null : note,
                );
              case _Decision.reassign:
                await _approve(
                  request,
                  provider: chosen,
                  role: role,
                  note: note,
                );
              case _Decision.decline:
                await _decline(request, note);
            }
          }

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
                _RequestSummaryCard(request: request),
                const SizedBox(height: AppSpacing.md),

                _FieldLabel(label: 'Decision', icon: AppIcons.careRequest),
                const SizedBox(height: AppSpacing.sm),
                _DecisionSelector(
                  value: decision,
                  requestedProvider: request.providerRequested,
                  onChanged: submitting
                      ? null
                      : (value) => setSheet(() => decision = value),
                ),
                const SizedBox(height: AppSpacing.md),

                if (decision == _Decision.reassign) ...[
                  _FieldLabel(
                    label: 'Suitable provider',
                    icon: AppIcons.careTeam,
                    helper: 'Sorted by lightest current caseload',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    controller: providerSearch,
                    hint: 'Filter by name or specialty…',
                    prefixIcon: AppIcons.search,
                    enabled: !submitting,
                    onChanged: (_) => setSheet(() {}),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _PickerShell(
                    child: DropdownButton<DirectoryUser>(
                      value:
                          visibleProviders.any((p) => p.user.id == chosen?.id)
                          ? chosen
                          : null,
                      hint: Text(
                        visibleProviders.isEmpty
                            ? 'No matching providers'
                            : 'Select a provider',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(sheetContext).textTheme.bodyMedium
                            ?.copyWith(
                              color: AppPalette.textMuted(sheetContext),
                            ),
                      ),
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      icon: const Icon(AppIcons.expandMore),
                      onChanged: submitting || visibleProviders.isEmpty
                          ? null
                          : (value) => setSheet(() => chosen = value),
                      items: [
                        for (final option in visibleProviders)
                          DropdownMenuItem(
                            value: option.user,
                            child: Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                if (decision != _Decision.decline) ...[
                  _FieldLabel(
                    label: 'Relationship type',
                    icon: AppIcons.assignments,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _PickerShell(
                    child: DropdownButton<String>(
                      value: role,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      icon: const Icon(AppIcons.expandMore),
                      onChanged: submitting
                          ? null
                          : (value) =>
                                setSheet(() => role = value ?? 'Primary'),
                      items: [
                        for (final r in _roles)
                          DropdownMenuItem(value: r, child: Text(r)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                AppTextField(
                  controller: reasonCtrl,
                  label: needsReason ? 'Reason (required)' : 'Note (optional)',
                  hint: switch (decision) {
                    _Decision.decline =>
                      'e.g. Provider is not accepting new patients',
                    _Decision.reassign =>
                      'e.g. Closer facility and matching specialty',
                    _Decision.approve => 'Add context for the audit trail',
                  },
                  maxLines: 3,
                  maxLength: 280,
                  enabled: !submitting,
                  errorText:
                      needsReason && reasonCtrl.text.isNotEmpty && !reasonFilled
                      ? 'Give at least 4 characters'
                      : null,
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: AppSpacing.md),

                AppButton(
                  label: switch (decision) {
                    _Decision.approve => 'Approve & assign',
                    _Decision.reassign => 'Assign this provider',
                    _Decision.decline => 'Decline request',
                  },
                  icon: decision == _Decision.decline
                      ? AppIcons.close
                      : AppIcons.check,
                  variant: decision == _Decision.decline
                      ? AppButtonVariant.danger
                      : AppButtonVariant.primary,
                  expand: true,
                  loading: submitting,
                  onPressed: canSubmit ? submit : null,
                ),
                if (needsReason && !reasonFilled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'The patient sees this reason, so it is required.',
                    textAlign: TextAlign.center,
                    style: Theme.of(sheetContext).textTheme.labelSmall
                        ?.copyWith(color: AppPalette.textMuted(sheetContext)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    reasonCtrl.dispose();
    providerSearch.dispose();
  }

  /// Fast path for the common case — approve exactly what the patient asked.
  Future<void> _quickApprove(
    BuildContext context,
    CareRequestItem request,
  ) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Approve as requested?',
      message:
          '${request.patient} will be assigned to ${request.providerRequested} '
          'as their primary provider, and both sides are notified.',
      confirmLabel: 'Approve & assign',
      icon: AppIcons.check,
    );
    if (ok != true || !mounted) return;
    await _approve(request, role: 'Primary');
  }

  // ---------------------------------------------------------------------------
  // Assignments
  // ---------------------------------------------------------------------------

  Future<void> _openAssignmentSheet(BuildContext pageContext) async {
    final patients = _activePatients;
    final providers = _providerOptions;
    final reasonCtrl = TextEditingController();

    DirectoryUser? patient;
    DirectoryUser? provider;
    var role = 'Primary';
    var creating = false;

    await GlassSheet.show<void>(
      pageContext,
      title: 'New care assignment',
      subtitle: 'Pair a patient with a provider directly',
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
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
              const _AssignmentFormIntro(),
              const SizedBox(height: AppSpacing.md),

              _FieldLabel(label: 'Patient', icon: AppIcons.patients),
              const SizedBox(height: AppSpacing.sm),
              _PickerShell(
                child: DropdownButton<DirectoryUser>(
                  value: patient,
                  hint: Text(
                    patients.isEmpty
                        ? 'No active patients available'
                        : 'Select a patient',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(color: AppPalette.textMuted(sheetContext)),
                  ),
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  icon: const Icon(AppIcons.expandMore),
                  onChanged: patients.isEmpty || creating
                      ? null
                      : (value) => setSheet(() => patient = value),
                  items: [
                    for (final p in patients)
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          '${p.name} · ${p.uniqueId}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              _FieldLabel(
                label: 'Care provider',
                icon: AppIcons.careTeam,
                helper: 'Sorted by lightest current caseload',
              ),
              const SizedBox(height: AppSpacing.sm),
              _PickerShell(
                child: DropdownButton<DirectoryUser>(
                  value: provider,
                  hint: Text(
                    providers.isEmpty
                        ? 'No active care providers available'
                        : 'Select a care provider',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(color: AppPalette.textMuted(sheetContext)),
                  ),
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  icon: const Icon(AppIcons.expandMore),
                  onChanged: providers.isEmpty || creating
                      ? null
                      : (value) => setSheet(() => provider = value),
                  items: [
                    for (final option in providers)
                      DropdownMenuItem(
                        value: option.user,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              _FieldLabel(
                label: 'Relationship type',
                icon: AppIcons.assignments,
              ),
              const SizedBox(height: AppSpacing.sm),
              _PickerShell(
                child: DropdownButton<String>(
                  value: role,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  icon: const Icon(AppIcons.expandMore),
                  onChanged: creating
                      ? null
                      : (value) => setSheet(() => role = value ?? 'Primary'),
                  items: [
                    for (final r in _roles)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              AppTextField(
                controller: reasonCtrl,
                label: 'Reason (optional)',
                hint: 'Why this pairing — kept in the audit trail',
                maxLines: 2,
                maxLength: 280,
                enabled: !creating,
              ),
              const SizedBox(height: AppSpacing.md),

              AppButton(
                label: 'Create assignment',
                icon: AppIcons.assignments,
                expand: true,
                loading: creating,
                onPressed: () async {
                  if (patient == null || provider == null) {
                    AppToast.warn(
                      sheetContext,
                      'Select both a patient and a care provider.',
                    );
                    return;
                  }
                  setSheet(() => creating = true);
                  if (mounted) setState(() => _creating = true);
                  final reason = reasonCtrl.text.trim();
                  var completed = false;
                  try {
                    await StaffState.instance.createAssignmentRemote(
                      patientUserId: patient!.id,
                      providerUserId: provider!.id,
                      role: role,
                      reason: reason.isEmpty ? null : reason,
                    );
                    if (!AppEnv.backendEnabled) {
                      StaffState.instance.addAssignment(
                        CareAssignment(
                          id: 'as_${DateTime.now().millisecondsSinceEpoch}',
                          patient: patient!.name,
                          provider: provider!.name,
                          assignedAt: DateTime.now(),
                          role: role,
                          patientId: patient!.id,
                          providerUserId: provider!.id,
                          providerSpecialty: provider!.specialty,
                          assignedReason: reason.isEmpty ? null : reason,
                        ),
                      );
                    }
                    completed = true;
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext, rootNavigator: true).pop();
                    }
                    if (pageContext.mounted) {
                      AppToast.success(
                        pageContext,
                        '${patient!.name} is now connected to ${provider!.name}.',
                      );
                    }
                  } catch (error) {
                    if (sheetContext.mounted) {
                      AppToast.error(
                        sheetContext,
                        'Could not create assignment: $error',
                      );
                    }
                  } finally {
                    if (!completed && sheetContext.mounted) {
                      setSheet(() => creating = false);
                    }
                    if (mounted) setState(() => _creating = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    reasonCtrl.dispose();
  }

  Future<void> _endAssignment(
    BuildContext pageContext,
    CareAssignment assignment,
  ) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await GlassSheet.show<bool>(
      pageContext,
      title: 'End care assignment',
      subtitle: '${assignment.patient} ↔ ${assignment.provider}',
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
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
              _NoticeCard(
                icon: AppIcons.alert,
                color: AppColors.critical,
                title: 'Access is revoked immediately',
                message:
                    '${assignment.provider} will lose assigned-care access to '
                    '${assignment.patient}. The change is recorded in the audit trail.',
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: reasonCtrl,
                label: 'Reason (optional)',
                hint: 'e.g. Patient transferred to another facility',
                maxLines: 2,
                maxLength: 280,
                onChanged: (_) => setSheet(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'End assignment',
                icon: AppIcons.close,
                variant: AppButtonVariant.danger,
                expand: true,
                onPressed: () =>
                    Navigator.of(sheetContext, rootNavigator: true).pop(true),
              ),
            ],
          ),
        ),
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _busyAssignments.add(assignment.id));
    try {
      await StaffState.instance.removeAssignmentRemote(
        assignment.id,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      AppToast.info(
        context,
        '${assignment.patient} and ${assignment.provider} are no longer assigned.',
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.error(context, 'Could not end assignment: $error');
    } finally {
      if (mounted) setState(() => _busyAssignments.remove(assignment.id));
    }
  }

  // ---------------------------------------------------------------------------
  // Detail sheets
  // ---------------------------------------------------------------------------

  Future<void> _showRequestDetail(
    BuildContext pageContext,
    CareRequestItem request,
  ) async {
    await GlassSheet.show<void>(
      pageContext,
      title: 'Care request',
      subtitle: '${request.patient} → ${request.providerRequested}',
      leadingIcon: AppIcons.careRequest,
      leadingColor: _statusColor(request.status),
      statusLabel: request.status.toUpperCase(),
      statusColor: _statusColor(request.status),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RequestSummaryCard(request: request),
          const SizedBox(height: AppSpacing.md),
          _DetailRow(label: 'Status', value: request.status.toUpperCase()),
          _DetailRow(
            label: 'Patient reason',
            value: request.reason.isEmpty ? '—' : request.reason,
          ),
          _DetailRow(
            label: 'Submitted',
            value: DateFormat.MMMd().add_jm().format(request.createdAt),
          ),
          if (request.assignedProviderName != null)
            _DetailRow(
              label: request.reassigned
                  ? 'Assigned instead'
                  : 'Assigned provider',
              value: request.assignedProviderName!,
            ),
          if (request.assignmentRole != null)
            _DetailRow(
              label: 'Relationship',
              value: _normaliseRole(request.assignmentRole!),
            ),
          if ((request.decisionNote ?? '').isNotEmpty)
            _DetailRow(label: 'Staff reason', value: request.decisionNote!),
          if (request.decidedAt != null)
            _DetailRow(
              label: 'Decided',
              value:
                  '${DateFormat.MMMd().add_jm().format(request.decidedAt!)}'
                  '${request.decidedByName == null ? '' : ' · ${request.decidedByName}'}',
            ),
          if (request.isPending) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Review & decide',
              icon: AppIcons.careRequest,
              expand: true,
              onPressed: () {
                Navigator.of(pageContext, rootNavigator: true).pop();
                _openReviewSheet(pageContext, request);
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAssignmentDetail(
    BuildContext pageContext,
    CareAssignment assignment,
  ) async {
    await GlassSheet.show<void>(
      pageContext,
      title: 'Care assignment',
      subtitle: '${assignment.patient} ↔ ${assignment.provider}',
      child: Padding(
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
            _DetailRow(
              label: 'Relationship',
              value: _normaliseRole(assignment.role),
            ),
            if ((assignment.providerSpecialty ?? '').isNotEmpty)
              _DetailRow(
                label: 'Specialty',
                value: assignment.providerSpecialty!,
              ),
            _DetailRow(
              label: 'Assigned',
              value: DateFormat.yMMMd().format(assignment.assignedAt),
            ),
            if ((assignment.assignedReason ?? '').isNotEmpty)
              _DetailRow(label: 'Reason', value: assignment.assignedReason!),
            if ((assignment.assignedByName ?? '').isNotEmpty)
              _DetailRow(
                label: 'Assigned by',
                value: assignment.assignedByName!,
              ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'End assignment',
              icon: AppIcons.close,
              variant: AppButtonVariant.danger,
              expand: true,
              onPressed: () {
                Navigator.of(pageContext, rootNavigator: true).pop();
                _endAssignment(pageContext, assignment);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      scrollable: true,
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: widget.canTriage ? 'Care requests' : 'Care assignments',
      subtitle: _showTabs
          ? 'Triage requests and manage care assignments'
          : widget.canTriage
          ? 'Patient ↔ provider matchmaking queue'
          : 'Patient ↔ provider care team pairings',
      headerActions: [
        if (widget.canAssign)
          AppButton(
            label: 'Assign',
            icon: AppIcons.add,
            size: AppButtonSize.sm,
            loading: _creating,
            onPressed: _creating ? null : () => _openAssignmentSheet(context),
          ),
        const SizedBox(width: 8),
      ],
      headerMenuActions: [
        if (widget.canAssign)
          RoleHeaderAction(
            label: 'New assignment',
            icon: AppIcons.add,
            onPressed: _creating ? null : () => _openAssignmentSheet(context),
          ),
        RoleHeaderAction(
          label: 'Refresh',
          icon: AppIcons.refresh,
          onPressed: _loading ? null : _load,
        ),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final staff = StaffState.instance;
          final hasNothing =
              staff.careRequests.isEmpty && staff.assignments.isEmpty;

          if (_loading && hasNothing) {
            return const SizedBox(
              height: 420,
              child: AppLoadingView(
                message: 'Loading care workspace…',
                itemCount: 5,
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              ),
            );
          }

          if (_error != null && hasNothing) {
            return GlassCard(
              frosted: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyStateView(
                    icon: AppIcons.alert,
                    title: 'Failed to load care workspace',
                    message: _error,
                    compact: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Retry',
                    icon: AppIcons.refresh,
                    onPressed: _load,
                  ),
                ],
              ),
            );
          }

          final caption = _stripCaption(staff);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(index: 0, child: _buildStatStrip(staff)),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    left: AppSpacing.xs,
                  ),
                  child: Text(
                    caption,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(index: 1, child: _buildSearchRow(context)),
              if (_activeFilterPills().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(index: 2, child: _activeFilterStrip()),
              ],
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: _tab == CareTab.requests
                    ? _buildRequestList(context, staff)
                    : _buildAssignmentList(context, staff),
              ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filtering - one integrated surface
  //
  // Every filter value lives in exactly one control: the stat strip owns scope
  // and status (its counts double as the selector), search owns free text, and
  // the filter sheet owns what has no stat chip - relationship type and sort.
  // The old KPI grid, tab switcher, status chip bar and standalone sort menu
  // offered three overlapping ways to set the same two values; they are gone.
  // ---------------------------------------------------------------------------

  bool get _hasActiveFilters =>
      _statusFilter != 'all' ||
      _roleFilter != 'all' ||
      _sort != _Sort.newest ||
      _search.text.trim().isNotEmpty;

  /// Only counts what the sheet owns - scope and status are already legible in
  /// the stat strip, so badging them here would double-report the same state.
  int get _activeFilterCount {
    var n = 0;
    if (_sort != _Sort.newest) n++;
    if (_tab == CareTab.assignments && _roleFilter != 'all') n++;
    return n;
  }

  void _clearAllFilters() {
    setState(() {
      _statusFilter = 'all';
      _roleFilter = 'all';
      _sort = _Sort.newest;
      _search.clear();
    });
  }

  /// Scope + status as one control. Icon, label and count sit on a single line
  /// so nothing truncates at mobile widths, and tapping a chip both opens the
  /// half of the workspace it belongs to and applies its status filter - the
  /// counts people read are the counts they can act on.
  Widget _buildStatStrip(StaffState staff) {
    final requests = staff.careRequests;
    final pending = requests.where((r) => r.isPending).length;
    final approved = requests.where((r) => r.status == 'approved').length;
    final declined = requests.where((r) => r.status == 'rejected').length;

    void selectRequests(String status) => setState(() {
      _tab = CareTab.requests;
      _statusFilter = status;
    });

    bool requestChipOn(String status) =>
        _tab == CareTab.requests && _statusFilter == status;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (widget.canTriage) ...[
          _CareStatChip(
            icon: AppIcons.careRequest,
            label: 'All requests',
            value: requests.length,
            accent: AppColors.info,
            selected: requestChipOn('all'),
            onTap: () => selectRequests('all'),
          ),
          _CareStatChip(
            icon: AppIcons.time,
            label: 'Awaiting decision',
            value: pending,
            accent: AppColors.warning,
            selected: requestChipOn('pending'),
            onTap: () => selectRequests('pending'),
          ),
          _CareStatChip(
            icon: AppIcons.check,
            label: 'Approved',
            value: approved,
            accent: AppColors.success,
            selected: requestChipOn('approved'),
            onTap: () => selectRequests('approved'),
          ),
          _CareStatChip(
            icon: AppIcons.close,
            label: 'Declined',
            value: declined,
            accent: AppColors.critical,
            selected: requestChipOn('rejected'),
            onTap: () => selectRequests('rejected'),
          ),
        ],
        if (widget.canAssign)
          _CareStatChip(
            icon: AppIcons.assignments,
            label: 'Active assignments',
            value: staff.assignments.length,
            accent: AppColors.brandIndigo,
            selected: _tab == CareTab.assignments,
            onTap: () => setState(() => _tab = CareTab.assignments),
          ),
      ],
    );
  }

  /// Carries the helper text the old KPI tiles showed beneath each number.
  String? _stripCaption(StaffState staff) {
    if (!widget.canTriage) return null;
    final pending = staff.careRequests.where((r) => r.isPending).length;
    final reassigned = staff.careRequests.where((r) => r.reassigned).length;
    final parts = <String>[
      if (pending == 0) 'Triage queue clear' else '$pending needs triage',
      if (reassigned > 0) '$reassigned re-routed',
    ];
    return parts.join(' \u00b7 ');
  }

  Widget _buildSearchRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StaffDirectorySearch(
            controller: _search,
            hintText: _tab == CareTab.requests
                ? 'Search patient, provider or reason\u2026'
                : 'Search patient, provider or specialty\u2026',
            semanticLabel: 'Search the care workspace',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _filterIconButton(context),
      ],
    );
  }

  Widget _filterIconButton(BuildContext context) {
    final active = _activeFilterCount;
    return Semantics(
      button: true,
      label: active == 0 ? 'Open filters' : '$active filters active',
      child: InkWell(
        onTap: () => _openFilterSheet(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 44,
              width: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active > 0
                    ? AppColors.brandIndigo.withValues(alpha: 0.12)
                    : AppPalette.surfaceAlt(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                border: Border.all(color: AppPalette.border(context)),
              ),
              child: Icon(
                AppIcons.filter,
                size: 20,
                color: active > 0
                    ? AppColors.brandIndigo
                    : AppPalette.textMuted(context),
              ),
            ),
            if (active > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandIndigo,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$active',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<({String label, VoidCallback onRemove})> _activeFilterPills() {
    final pills = <({String label, VoidCallback onRemove})>[];
    if (_sort != _Sort.newest) {
      pills.add((
        label: _sort.label,
        onRemove: () => setState(() => _sort = _Sort.newest),
      ));
    }
    if (_tab == CareTab.assignments && _roleFilter != 'all') {
      pills.add((
        label: _roleFilter,
        onRemove: () => setState(() => _roleFilter = 'all'),
      ));
    }
    return pills;
  }

  Widget _activeFilterStrip() {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final pill in _activeFilterPills())
          _CareRemovablePill(label: pill.label, onRemove: pill.onRemove),
        TextButton.icon(
          onPressed: _clearAllFilters,
          icon: const Icon(AppIcons.close, size: 14),
          label: const Text('Clear all'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: AppColors.critical,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ],
    );
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    var draftSort = _sort;
    var draftRole = _roleFilter;
    final showRoles = _tab == CareTab.assignments;

    int roleCount(String role) => role == 'all'
        ? StaffState.instance.assignments.length
        : StaffState.instance.assignments
              .where((a) => _normaliseRole(a.role) == role)
              .length;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            Widget section(String title, List<Widget> children) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.xs,
                      bottom: AppSpacing.sm,
                    ),
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textMuted(ctx),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Wrap(runSpacing: AppSpacing.xs, children: children),
                  const SizedBox(height: AppSpacing.lg),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Row(
                        children: [
                          Text(
                            showRoles
                                ? 'Filter assignments'
                                : 'Filter care requests',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setSt(() {
                              draftSort = _Sort.newest;
                              draftRole = 'all';
                            }),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    ),
                    if (showRoles)
                      section('RELATIONSHIP TYPE', [
                        StaffDirectoryFilterChip(
                          label: 'All \u00b7 ${roleCount('all')}',
                          selected: draftRole == 'all',
                          accent: AppColors.brandIndigo,
                          onTap: () => setSt(() => draftRole = 'all'),
                        ),
                        for (final role in _roles)
                          StaffDirectoryFilterChip(
                            label: '$role \u00b7 ${roleCount(role)}',
                            selected: draftRole == role,
                            accent: _roleColor(role),
                            onTap: () => setSt(() => draftRole = role),
                          ),
                      ]),
                    section('SORT BY', [
                      for (final s in _Sort.values)
                        StaffDirectoryFilterChip(
                          label: s.label,
                          selected: draftSort == s,
                          accent: AppColors.doctorGreen,
                          onTap: () => setSt(() => draftSort = s),
                        ),
                    ]),
                    AppButton(
                      label: 'Apply filters',
                      icon: AppIcons.check,
                      expand: true,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        _sort = draftSort;
        _roleFilter = draftRole;
      });
    }
  }

  Widget _buildRequestList(BuildContext context, StaffState staff) {
    final all = staff.careRequests;
    final list = _filteredRequests;
    final handheld = ResponsiveBuilder.of(context).isHandheld;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Care requests',
          icon: AppIcons.careRequest,
          trailing: '${list.length}/${all.length}',
          actionLabel: _loading ? null : 'Refresh',
          onAction: _loading ? null : _load,
        ),
        if (list.isEmpty)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.careRequest,
              title: all.isEmpty
                  ? 'No care requests yet'
                  : 'No requests match your filters',
              message: all.isEmpty
                  ? 'Requests appear here as soon as a patient asks for a provider.'
                  : 'Try a different status, or clear the search.',
              actionLabel: _hasActiveFilters ? 'Clear filters' : null,
              onAction: _hasActiveFilters ? _clearAllFilters : null,
              compact: true,
            ),
          )
        else
          StaffListCard(
            children: [
              for (final request in list)
                StaffListRow(
                  icon: AppIcons.careRequest,
                  iconColor: _statusColor(request.status),
                  title: '${request.patient} → ${request.effectiveProvider}',
                  subtitle: _requestSubtitle(request),
                  pill: request.reassigned
                      ? 'RE-ROUTED'
                      : request.status.toUpperCase(),
                  pillColor: _statusColor(request.status),
                  onTap: () => _showRequestDetail(context, request),
                  trailing: !request.isPending
                      ? null
                      : _busyRequests.contains(request.id)
                      ? const McarePulse(
                          size: McarePulseSize.micro,
                          semanticLabel: null,
                        )
                      : handheld
                      ? AppButton(
                          label: 'Review',
                          size: AppButtonSize.sm,
                          onPressed: () => _openReviewSheet(context, request),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppButton(
                              label: 'Approve',
                              size: AppButtonSize.sm,
                              onPressed: () => _quickApprove(context, request),
                            ),
                            const SizedBox(width: 6),
                            AppButton(
                              label: 'Assign…',
                              size: AppButtonSize.sm,
                              variant: AppButtonVariant.secondary,
                              onPressed: () => _openReviewSheet(
                                context,
                                request,
                                initial: _Decision.reassign,
                              ),
                            ),
                            const SizedBox(width: 6),
                            AppButton(
                              label: 'Decline',
                              size: AppButtonSize.sm,
                              variant: AppButtonVariant.danger,
                              onPressed: () => _openReviewSheet(
                                context,
                                request,
                                initial: _Decision.decline,
                              ),
                            ),
                          ],
                        ),
                ),
            ],
          ),
      ],
    );
  }

  String _requestSubtitle(CareRequestItem request) {
    final when = DateFormat.MMMd().add_jm().format(request.createdAt);
    if (request.isPending) {
      final reason = request.reason.isEmpty
          ? 'No reason given'
          : request.reason;
      return '$reason\n$when';
    }
    final note = (request.decisionNote ?? '').isEmpty
        ? (request.reason.isEmpty ? 'No reason given' : request.reason)
        : request.decisionNote!;
    final decided = request.decidedAt == null
        ? when
        : DateFormat.MMMd().add_jm().format(request.decidedAt!);
    final who = request.decidedByName == null
        ? ''
        : ' · ${request.decidedByName}';
    return '$note\n$decided$who';
  }

  Widget _buildAssignmentList(BuildContext context, StaffState staff) {
    final all = staff.assignments;
    final list = _filteredAssignments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Care assignments',
          icon: AppIcons.assignments,
          trailing: '${list.length}/${all.length}',
          actionLabel: _loading ? null : 'Refresh',
          onAction: _loading ? null : _load,
        ),
        if (list.isEmpty)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.assignments,
              title: all.isEmpty
                  ? 'No assignments yet'
                  : 'No assignments match your filters',
              message: all.isEmpty
                  ? 'Approve a care request, or create the first patient ↔ provider link.'
                  : 'Try a different relationship type, or clear the search.',
              actionLabel: all.isEmpty
                  ? 'Create assignment'
                  : (_hasActiveFilters ? 'Clear filters' : null),
              onAction: all.isEmpty
                  ? () => _openAssignmentSheet(context)
                  : (_hasActiveFilters ? _clearAllFilters : null),
              compact: true,
            ),
          )
        else
          StaffListCard(
            children: [
              for (final assignment in list)
                StaffListRow(
                  icon: AppIcons.assignments,
                  iconColor: _roleColor(_normaliseRole(assignment.role)),
                  title: '${assignment.patient} → ${assignment.provider}',
                  subtitle: _assignmentSubtitle(assignment),
                  pill: _normaliseRole(assignment.role).toUpperCase(),
                  pillColor: _roleColor(_normaliseRole(assignment.role)),
                  onTap: () => _showAssignmentDetail(context, assignment),
                  trailing: AppButton(
                    label: 'End',
                    size: AppButtonSize.sm,
                    variant: AppButtonVariant.danger,
                    loading: _busyAssignments.contains(assignment.id),
                    onPressed: _busyAssignments.contains(assignment.id)
                        ? null
                        : () => _endAssignment(context, assignment),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _assignmentSubtitle(CareAssignment assignment) {
    final since = 'Since ${DateFormat.MMMd().format(assignment.assignedAt)}';
    final specialty = (assignment.providerSpecialty ?? '').isEmpty
        ? ''
        : ' · ${assignment.providerSpecialty}';
    final reason = (assignment.assignedReason ?? '').isEmpty
        ? ''
        : '\n${assignment.assignedReason}';
    return '$since$specialty$reason';
  }
}

// ---------------------------------------------------------------------------
// Support types and private widgets
// ---------------------------------------------------------------------------

enum _Decision { approve, reassign, decline }

/// A selectable care provider plus their live caseload.
class _ProviderOption {
  const _ProviderOption({required this.user, required this.caseload});

  final DirectoryUser user;
  final int caseload;

  String get label {
    final specialty = (user.specialty ?? '').isEmpty
        ? ''
        : ' · ${user.specialty}';
    return '${user.name}$specialty · $caseload patient${caseload == 1 ? '' : 's'}';
  }
}

class _DecisionSelector extends StatelessWidget {
  const _DecisionSelector({
    required this.value,
    required this.requestedProvider,
    required this.onChanged,
  });

  final _Decision value;
  final String requestedProvider;
  final ValueChanged<_Decision>? onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = <(_Decision, String, String, IconData, Color)>[
      (
        _Decision.approve,
        'Approve as requested',
        'Assign $requestedProvider to this patient',
        AppIcons.check,
        AppColors.success,
      ),
      (
        _Decision.reassign,
        'Assign a different provider',
        'Route the patient to a more suitable doctor',
        AppIcons.careTeam,
        AppColors.brandIndigo,
      ),
      (
        _Decision.decline,
        'Decline the request',
        'No assignment is created; the patient sees your reason',
        AppIcons.close,
        AppColors.critical,
      ),
    ];

    return Column(
      children: [
        for (final entry in entries) ...[
          _DecisionTile(
            title: entry.$2,
            subtitle: entry.$3,
            icon: entry.$4,
            accent: entry.$5,
            selected: value == entry.$1,
            onTap: onChanged == null ? null : () => onChanged!(entry.$1),
          ),
          if (entry.$1 != entries.last.$1)
            const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _DecisionTile extends StatelessWidget {
  const _DecisionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : AppPalette.surfaceAlt(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: selected ? accent : AppPalette.border(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? accent : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? accent : AppPalette.textMuted(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestSummaryCard extends StatelessWidget {
  const _RequestSummaryCard({required this.request});

  final CareRequestItem request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (request.status) {
      'approved' => AppColors.success,
      'rejected' => AppColors.critical,
      _ => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.patients, size: 16, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  request.patient,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                request.status.toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Requested ${request.providerRequested}'
            '${(request.providerSpecialty ?? '').isEmpty ? '' : ' · ${request.providerSpecialty}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          if (request.reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '“${request.reason}”',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
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

class _AssignmentFormIntro extends StatelessWidget {
  const _AssignmentFormIntro();

  @override
  Widget build(BuildContext context) {
    return const _NoticeCard(
      icon: AppIcons.link,
      color: AppColors.brandIndigo,
      title: 'Create a care relationship',
      message:
          'The provider receives access only to the selected patient and assigned relationship.',
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.icon, this.helper});

  final String label;
  final IconData icon;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.brandIndigo),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (helper != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              helper!,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The bordered container every dropdown in this screen sits inside.
class _PickerShell extends StatelessWidget {
  const _PickerShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppPalette.border(context)),
      ),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(child: child),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// One line: icon, label, count. Replaces the two-line KPI tile whose label
/// truncated inside a half-width mobile card, and doubles as the scope/status
/// selector so the workspace has a single filtering surface.
class _CareStatChip extends StatelessWidget {
  const _CareStatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : AppPalette.textMuted(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $value',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 7,
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.20)
                        : AppPalette.border(context).withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    '$value',
                    style: TextStyle(
                      color: selected ? accent : AppPalette.textMuted(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrors the removable filter pill on the Users directory.
class _CareRemovablePill extends StatelessWidget {
  const _CareRemovablePill({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onRemove,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.sm,
            top: 6,
            bottom: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.brandIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(
              color: AppColors.brandIndigo.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandIndigo,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                AppIcons.close,
                size: 14,
                color: AppColors.brandIndigo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
