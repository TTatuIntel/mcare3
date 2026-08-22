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
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';

class AdminAssignmentsView extends StatelessWidget {
  const AdminAssignmentsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AssignmentsScreen(
      currentRoute: RouteNames.adminAssignments,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
    );
  }
}

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
  });
  final String currentRoute;
  final List destinations;
  final String profileRoute;
  final String notificationsRoute;

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  final _search = TextEditingController();
  final Set<String> _endingAssignmentIds = <String>{};
  String? _roleFilter;
  bool _creating = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SessionPoller.instance.triggerNow();
      _loadAssignments();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAssignments() async {
    // Demo assignments are seeded by StaffState. The API intentionally
    // returns an empty list when disabled, which must not wipe those rows.
    if (!AppEnv.backendEnabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminApi.instance.listAssignments();
      final items = rows.map((e) => StaffMapper.assignmentFromApi(e)).toList();
      StaffState.instance.mergeAssignments(items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CareAssignment> _filteredAssignments() {
    var list = List<CareAssignment>.from(StaffState.instance.assignments);
    if (_roleFilter != null) {
      list = list.where((a) => _normaliseRole(a.role) == _roleFilter).toList();
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (a) =>
                a.patient.toLowerCase().contains(q) ||
                a.provider.toLowerCase().contains(q),
          )
          .toList();
    }
    list.sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
    return list;
  }

  static String _normaliseRole(String role) {
    final value = role.trim().toLowerCase();
    return switch (value) {
      'consulting' => 'Consulting',
      'specialist' => 'Specialist',
      _ => 'Primary',
    };
  }

  Future<void> _openSheet(BuildContext pageContext) async {
    final patients =
        StaffState.instance.users
            .where((u) => u.role == UserRole.patient && u.status == 'active')
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final providers =
        StaffState.instance.users
            .where(
              (u) =>
                  (u.role == UserRole.doctor ||
                      u.role == UserRole.externalDoctor) &&
                  u.status == 'active',
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    DirectoryUser? selectedPatient;
    DirectoryUser? selectedProvider;
    String selectedRole = 'Primary';
    var creating = false;

    await GlassSheet.show<void>(
      pageContext,
      title: 'New care assignment',
      subtitle: 'Connect a patient with a trusted care provider',
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
              const _AssignmentFormIntro(),
              const SizedBox(height: AppSpacing.md),
              _AssignmentPicker<DirectoryUser>(
                label: 'Patient',
                icon: AppIcons.patients,
                value: selectedPatient,
                hint: patients.isEmpty
                    ? 'No active patients available'
                    : 'Select a patient',
                enabled: patients.isNotEmpty && !creating,
                items: patients
                    .map(
                      (patient) => DropdownMenuItem(
                        value: patient,
                        child: Text(
                          '${patient.name} · ${patient.uniqueId}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (patient) =>
                    setSheetState(() => selectedPatient = patient),
              ),
              const SizedBox(height: AppSpacing.md),

              _AssignmentPicker<DirectoryUser>(
                label: 'Care provider',
                icon: AppIcons.careTeam,
                value: selectedProvider,
                hint: providers.isEmpty
                    ? 'No active care providers available'
                    : 'Select a care provider',
                enabled: providers.isNotEmpty && !creating,
                items: providers
                    .map(
                      (provider) => DropdownMenuItem(
                        value: provider,
                        child: Text(
                          '${provider.name} · ${provider.uniqueId}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (provider) =>
                    setSheetState(() => selectedProvider = provider),
              ),
              const SizedBox(height: AppSpacing.md),

              _AssignmentPicker<String>(
                label: 'Relationship type',
                icon: AppIcons.assignments,
                value: selectedRole,
                hint: 'Select a relationship type',
                enabled: !creating,
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
                onChanged: (role) =>
                    setSheetState(() => selectedRole = role ?? 'Primary'),
              ),
              const SizedBox(height: AppSpacing.lg),

              AppButton(
                label: 'Create assignment',
                icon: AppIcons.assignments,
                expand: true,
                loading: creating,
                onPressed: () async {
                  if (selectedPatient == null || selectedProvider == null) {
                    AppToast.warn(
                      sheetContext,
                      'Select both a patient and a care provider.',
                    );
                    return;
                  }
                  setSheetState(() => creating = true);
                  if (mounted) setState(() => _creating = true);
                  var completed = false;
                  try {
                    await StaffState.instance.createAssignmentRemote(
                      patientUserId: selectedPatient!.id,
                      providerId: selectedProvider!.id,
                      role: selectedRole,
                    );
                    if (!AppEnv.backendEnabled) {
                      StaffState.instance.addAssignment(
                        CareAssignment(
                          id: 'as_${DateTime.now().millisecondsSinceEpoch}',
                          patient: selectedPatient!.name,
                          provider: selectedProvider!.name,
                          assignedAt: DateTime.now(),
                          role: selectedRole,
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
                        '${selectedPatient!.name} is now connected to ${selectedProvider!.name}.',
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
                      setSheetState(() => creating = false);
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
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      scrollable: true,
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Assignments',
      subtitle:
          'Care relationships · ${DateFormat.MMMEd().format(DateTime.now())}',
      headerActions: [
        AppButton(
          label: 'New',
          icon: AppIcons.add,
          size: AppButtonSize.sm,
          loading: _creating,
          onPressed: _creating ? null : () => _openSheet(context),
        ),
        const SizedBox(width: 8),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          if (_loading && StaffState.instance.assignments.isEmpty) {
            return const SizedBox(
              height: 420,
              child: AppLoadingView(
                message: 'Loading care assignments…',
                itemCount: 5,
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              ),
            );
          }

          if (_error != null && StaffState.instance.assignments.isEmpty) {
            return GlassCard(
              frosted: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyStateView(
                    icon: AppIcons.alert,
                    title: 'Failed to load assignments',
                    message: _error,
                    compact: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Retry',
                    icon: AppIcons.refresh,
                    onPressed: _loadAssignments,
                  ),
                ],
              ),
            );
          }

          final all = StaffState.instance.assignments;
          final list = _filteredAssignments();
          final accent = AppColors.brandIndigo;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: _AssignmentSearchCard(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _roleChip(null, 'All'),
                      _roleChip('Primary', 'Primary'),
                      _roleChip('Consulting', 'Consulting'),
                      _roleChip('Specialist', 'Specialist'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 2,
                child: SectionLabel(
                  title: 'Care assignments',
                  icon: AppIcons.assignments,
                  trailing: '${list.length}/${all.length}',
                  actionLabel: _loading ? null : 'Refresh',
                  onAction: _loading ? null : _loadAssignments,
                ),
              ),
              StaggeredEntry(
                index: 3,
                child: list.isEmpty
                    ? GlassCard(
                        frosted: true,
                        child: EmptyStateView(
                          icon: AppIcons.assignments,
                          title: all.isEmpty
                              ? 'No assignments yet'
                              : 'No assignments match',
                          message: all.isEmpty
                              ? 'Create the first patient ↔ provider link.'
                              : 'Try adjusting your search or filters.',
                          actionLabel: all.isEmpty ? 'Create assignment' : null,
                          onAction: all.isEmpty
                              ? () => _openSheet(context)
                              : null,
                          compact: true,
                        ),
                      )
                    : StaffListCard(
                        children: list
                            .map(
                              (assignment) => StaffListRow(
                                icon: AppIcons.assignments,
                                iconColor: accent,
                                title:
                                    '${assignment.patient} → ${assignment.provider}',
                                subtitle:
                                    'Since ${DateFormat.MMMd().format(assignment.assignedAt)}',
                                pill: _normaliseRole(
                                  assignment.role,
                                ).toUpperCase(),
                                pillColor: switch (_normaliseRole(
                                  assignment.role,
                                )) {
                                  'Primary' => AppColors.brandIndigo,
                                  'Consulting' => AppColors.info,
                                  'Specialist' => AppColors.warning,
                                  _ => accent,
                                },
                                trailing: AppButton(
                                  label: 'End',
                                  size: AppButtonSize.sm,
                                  variant: AppButtonVariant.danger,
                                  loading: _endingAssignmentIds.contains(
                                    assignment.id,
                                  ),
                                  onPressed:
                                      _endingAssignmentIds.contains(
                                        assignment.id,
                                      )
                                      ? null
                                      : () =>
                                            _endAssignment(context, assignment),
                                ),
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

  Future<void> _endAssignment(
    BuildContext context,
    CareAssignment assignment,
  ) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'End assignment?',
      message:
          '${assignment.provider} will no longer have assigned-care access to ${assignment.patient}. This change is recorded in the audit trail.',
      confirmLabel: 'End assignment',
      danger: true,
      icon: AppIcons.close,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _endingAssignmentIds.add(assignment.id));
    try {
      await StaffState.instance.removeAssignmentRemote(assignment.id);
      if (!context.mounted) return;
      AppToast.info(
        context,
        '${assignment.patient} and ${assignment.provider} are no longer assigned.',
      );
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not end assignment: $error');
    } finally {
      if (mounted) {
        setState(() => _endingAssignmentIds.remove(assignment.id));
      }
    }
  }

  Widget _roleChip(String? role, String label) {
    final selected = _roleFilter == role;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: () => setState(() => _roleFilter = role),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppPalette.surface(context)
                : AppPalette.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(
              color: selected
                  ? AppColors.brandIndigo
                  : AppPalette.border(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? AppColors.brandIndigo
                  : AppPalette.textMuted(context),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssignmentSearchCard extends StatelessWidget {
  const _AssignmentSearchCard({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Icon(
              AppIcons.search,
              size: 18,
              color: AppPalette.textMuted(context),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppPalette.surfaceAlt(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppPalette.border(context)),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search patient or provider…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                          icon: const Icon(AppIcons.close, size: 18),
                        ),
                ),
                onChanged: onChanged,
              ),
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandIndigo.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: AppColors.brandIndigo.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.brandIndigo.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            alignment: Alignment.center,
            child: const Icon(
              AppIcons.link,
              color: AppColors.brandIndigo,
              size: 21,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create a care relationship',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The provider receives access only to the selected patient and assigned relationship.',
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

class _AssignmentPicker<T> extends StatelessWidget {
  const _AssignmentPicker({
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.enabled,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final T? value;
  final String hint;
  final bool enabled;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
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
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: Text(
                hint,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
              isExpanded: true,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              icon: const Icon(AppIcons.expandMore),
              onChanged: enabled ? onChanged : null,
              items: items,
            ),
          ),
        ),
      ],
    );
  }
}
