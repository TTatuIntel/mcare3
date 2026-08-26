import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../../core/realtime/session_poller.dart';
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
import '../../shared/widgets/staff_filter_chip.dart';
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

enum _Sort { newest, oldest, patient }

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

class _CareRequestsScreenState extends State<CareRequestsScreen> {
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
      _Sort.patient => (a, b) =>
          a.patient.toLowerCase().compareTo(b.patient.toLowerCase()),
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
      _Sort.patient => (a, b) =>
          a.patient.toLowerCase().compareTo(b.patient.toLowerCase()),
    });
    return list;
  }

  static String _normaliseRole(String role) => switch (role.trim().toLowerCase()) {
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
              (u.role == UserRole.doctor || u.role == UserRole.externalDoctor) &&
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
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final visibleProviders = providers.where((p) {
            final q = providerSearch.text.trim().toLowerCase();
            if (q.isEmpty) return true;
            return p.user.name.toLowerCase().contains(q) ||
                (p.user.specialty ?? '').toLowerCase().contains(q);
          }).toList();

          final needsReason = decision == _Decision.decline ||
              (decision == _Decision.reassign && chosen != null);
          final reasonFilled = reasonCtrl.text.trim().length >= 4;

          final canSubmit = !submitting &&
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

                _FieldLabel(
                  label: 'Decision',
                  icon: AppIcons.careRequest,
                ),
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
                      value: visibleProviders.any((p) => p.user.id == chosen?.id)
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
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
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
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
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
                  errorText: needsReason &&
                          reasonCtrl.text.isNotEmpty &&
                          !reasonFilled
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
                    style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(sheetContext),
                        ),
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
                    style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                          color: AppPalette.textMuted(sheetContext),
                        ),
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
                    style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                          color: AppPalette.textMuted(sheetContext),
                        ),
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
              _DetailRow(label: 'Assigned by', value: assignment.assignedByName!),
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

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(index: 0, child: _buildKpis(staff)),
              const SizedBox(height: AppSpacing.md),
              if (_showTabs) ...[
                StaggeredEntry(
                  index: 1,
                  child: _TabSwitcher(
                    value: _tab,
                    requestCount:
                        staff.careRequests.where((r) => r.isPending).length,
                    assignmentCount: staff.assignments.length,
                    onChanged: (tab) => setState(() => _tab = tab),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              StaggeredEntry(index: 2, child: _buildToolbar(context)),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(index: 3, child: _buildFilters()),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 4,
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

  Widget _buildKpis(StaffState staff) {
    final pending = staff.careRequests.where((r) => r.isPending).length;
    final approved =
        staff.careRequests.where((r) => r.status == 'approved').length;
    final declined =
        staff.careRequests.where((r) => r.status == 'rejected').length;
    final reassigned = staff.careRequests.where((r) => r.reassigned).length;

    return StaffKpiGrid(
      tiles: [
        if (widget.canTriage) ...[
          StaffKpiTile(
            label: 'Awaiting decision',
            value: '$pending',
            helper: pending == 0 ? 'Queue clear' : 'Needs triage',
            icon: AppIcons.careRequest,
            onTap: () => setState(() {
              _tab = CareTab.requests;
              _statusFilter = 'pending';
            }),
          ),
          StaffKpiTile(
            label: 'Approved',
            value: '$approved',
            helper: reassigned == 0 ? 'As requested' : '$reassigned re-routed',
            icon: AppIcons.check,
            onTap: () => setState(() {
              _tab = CareTab.requests;
              _statusFilter = 'approved';
            }),
          ),
          StaffKpiTile(
            label: 'Declined',
            value: '$declined',
            helper: 'With a reason',
            icon: AppIcons.close,
            onTap: () => setState(() {
              _tab = CareTab.requests;
              _statusFilter = 'rejected';
            }),
          ),
        ],
        if (widget.canAssign)
          StaffKpiTile(
            label: 'Active assignments',
            value: '${staff.assignments.length}',
            helper: 'Patient ↔ provider',
            icon: AppIcons.assignments,
            onTap: () => setState(() => _tab = CareTab.assignments),
          ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final handheld = ResponsiveBuilder.of(context).isHandheld;
    final search = AppTextField(
      controller: _search,
      hint: _tab == CareTab.requests
          ? 'Search patient, provider or reason…'
          : 'Search patient, provider or specialty…',
      prefixIcon: AppIcons.search,
      suffixIcon: _search.text.isEmpty ? null : AppIcons.close,
      onSuffixTap: () {
        _search.clear();
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
    );

    final sort = _SortMenu(
      value: _sort,
      onChanged: (value) => setState(() => _sort = value),
    );

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: handheld
          ? Column(
              children: [
                search,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: sort),
              ],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: AppSpacing.sm),
                sort,
              ],
            ),
    );
  }

  Widget _buildFilters() {
    if (_tab == CareTab.requests) {
      return StaffFilterChipBar(
        accent: AppColors.info,
        selected: _statusFilter,
        onSelected: (value) => setState(() => _statusFilter = value),
        options: const [
          StaffFilterOption(value: 'all', label: 'All'),
          StaffFilterOption(
            value: 'pending',
            label: 'Pending',
            color: AppColors.warning,
          ),
          StaffFilterOption(
            value: 'approved',
            label: 'Approved',
            color: AppColors.success,
          ),
          StaffFilterOption(
            value: 'rejected',
            label: 'Declined',
            color: AppColors.critical,
          ),
        ],
      );
    }
    return StaffFilterChipBar(
      accent: AppColors.brandIndigo,
      selected: _roleFilter,
      onSelected: (value) => setState(() => _roleFilter = value),
      options: const [
        StaffFilterOption(value: 'all', label: 'All'),
        StaffFilterOption(
          value: 'Primary',
          label: 'Primary',
          color: AppColors.brandIndigo,
        ),
        StaffFilterOption(
          value: 'Consulting',
          label: 'Consulting',
          color: AppColors.info,
        ),
        StaffFilterOption(
          value: 'Specialist',
          label: 'Specialist',
          color: AppColors.warning,
        ),
      ],
    );
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
              actionLabel: all.isEmpty ? null : 'Clear filters',
              onAction: all.isEmpty
                  ? null
                  : () => setState(() {
                        _statusFilter = 'all';
                        _search.clear();
                      }),
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
                                  onPressed: () =>
                                      _openReviewSheet(context, request),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppButton(
                                      label: 'Approve',
                                      size: AppButtonSize.sm,
                                      onPressed: () =>
                                          _quickApprove(context, request),
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
      final reason = request.reason.isEmpty ? 'No reason given' : request.reason;
      return '$reason\n$when';
    }
    final note = (request.decisionNote ?? '').isEmpty
        ? (request.reason.isEmpty ? 'No reason given' : request.reason)
        : request.decisionNote!;
    final decided = request.decidedAt == null
        ? when
        : DateFormat.MMMd().add_jm().format(request.decidedAt!);
    final who = request.decidedByName == null ? '' : ' · ${request.decidedByName}';
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
              actionLabel: all.isEmpty ? 'Create assignment' : 'Clear filters',
              onAction: all.isEmpty
                  ? () => _openAssignmentSheet(context)
                  : () => setState(() {
                        _roleFilter = 'all';
                        _search.clear();
                      }),
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
    final specialty = (user.specialty ?? '').isEmpty ? '' : ' · ${user.specialty}';
    return '${user.name}$specialty · $caseload patient${caseload == 1 ? '' : 's'}';
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({
    required this.value,
    required this.requestCount,
    required this.assignmentCount,
    required this.onChanged,
  });

  final CareTab value;
  final int requestCount;
  final int assignmentCount;
  final ValueChanged<CareTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Requests',
              icon: AppIcons.careRequest,
              badge: requestCount,
              accent: AppColors.info,
              selected: value == CareTab.requests,
              onTap: () => onChanged(CareTab.requests),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _TabButton(
              label: 'Assignments',
              icon: AppIcons.assignments,
              badge: assignmentCount,
              accent: AppColors.brandIndigo,
              selected: value == CareTab.assignments,
              onTap: () => onChanged(CareTab.assignments),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.badge,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int badge;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : AppPalette.textMuted(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.value, required this.onChanged});

  final _Sort value;
  final ValueChanged<_Sort> onChanged;

  static String _label(_Sort sort) => switch (sort) {
        _Sort.newest => 'Newest first',
        _Sort.oldest => 'Oldest first',
        _Sort.patient => 'Patient A–Z',
      };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Sort>(
      tooltip: 'Sort',
      initialValue: value,
      onSelected: onChanged,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      itemBuilder: (context) => [
        for (final sort in _Sort.values)
          PopupMenuItem(value: sort, child: Text(_label(sort))),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppPalette.surfaceAlt(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.filter,
              size: 16,
              color: AppPalette.textMuted(context),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              _label(value),
              style: TextStyle(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              AppIcons.expandMore,
              size: 16,
              color: AppPalette.textMuted(context),
            ),
          ],
        ),
      ),
    );
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
          if (entry.$1 != entries.last.$1) const SizedBox(height: AppSpacing.xs),
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
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
