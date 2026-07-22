import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/realtime/session_poller.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_patient_profile_sheet.dart';
import '../../shared/widgets/staff_stat_cards.dart';
import '../../shared/widgets/app_page_route.dart';

/// Admin / assistant patient directory — clinical accounts only.
/// Reads from `StaffState` (hydrated via `/admin/session` or `listUsers`).
class AdminPatientsView extends StatefulWidget {
  const AdminPatientsView({super.key, this.assistantMode = false});

  /// When true, uses assistant nav routes and permission gate is applied upstream.
  final bool assistantMode;

  @override
  State<AdminPatientsView> createState() => _AdminPatientsViewState();
}

class _AdminPatientsViewState extends State<AdminPatientsView> {
  final _search = TextEditingController();
  String? _statusFilter;
  bool _loading = false;
  String? _error;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SessionPoller.instance.triggerNow();
      _loadPatients();
    });
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await AdminApi.instance.listUsers(role: 'patient', perPage: 200);
      final rawList = data['users'] as List? ?? const [];
      final users = rawList
          .map((e) => StaffMapper.directoryUserFromApiFull(
                (e as Map).cast<String, dynamic>(),
              ))
          .toList();
      StaffState.instance.mergeUsers(users);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreatePatientSheet(BuildContext context) async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool creating = false;

    await GlassSheet.show(
      context,
      title: 'Register patient',
      subtitle: 'Creates an active patient account',
      child: StatefulBuilder(
        builder: (ctx, setSt) => Padding(
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
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: firstCtrl,
                      label: 'First name',
                      hint: 'e.g. Amara',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppTextField(
                      controller: lastCtrl,
                      label: 'Last name',
                      hint: 'e.g. Okonkwo',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: emailCtrl,
                label: 'Email address',
                hint: 'patient@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: phoneCtrl,
                label: 'Phone (optional)',
                hint: '+254 7XX XXX XXX',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Create patient account',
                icon: AppIcons.patients,
                expand: true,
                loading: creating,
                onPressed: () async {
                  final first = firstCtrl.text.trim();
                  final last = lastCtrl.text.trim();
                  final email = emailCtrl.text.trim();
                  if (first.isEmpty || last.isEmpty || email.isEmpty) {
                    AppToast.warn(
                      ctx,
                      'First name, last name and email are required.',
                    );
                    return;
                  }
                  setSt(() => creating = true);
                  try {
                    await AdminApi.instance.createUser(
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
                    AppToast.success(ctx, 'Patient account created.');
                    await _loadPatients();
                  } catch (_) {
                    if (ctx.mounted) {
                      AppToast.error(
                        ctx,
                        'Could not create patient — check email is unique.',
                      );
                    }
                  } finally {
                    if (ctx.mounted) setSt(() => creating = false);
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
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DirectoryUser> _filteredPatients() {
    var list = StaffState.instance.users
        .where((u) => u.role == UserRole.patient)
        .toList();
    if (_statusFilter != null) {
      list = list.where((u) => u.status == _statusFilter).toList();
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((u) =>
              u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              u.uniqueId.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = !widget.assistantMode ||
        AuthState.instance.hasAssistantPermission('can_create_users');

    return RoleShell(
      scrollable: true,
      currentRoute: _currentRoute,
      destinations: _destinations,
      profileRoute: _profileRoute,
      notificationsRoute: _notificationsRoute,
      title: 'Patients',
      subtitle: 'Clinical accounts · ${DateFormat.MMMEd().format(DateTime.now())}',
      headerActions: canCreate
          ? [
              AppButton(
                label: 'Register',
                icon: AppIcons.add,
                size: AppButtonSize.sm,
                onPressed: () => _openCreatePatientSheet(context),
              ),
              const SizedBox(width: 8),
            ]
          : null,
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          if (_loading && StaffState.instance.users.isEmpty) {
            return const AppLoadingView();
          }

          if (_error != null && StaffState.instance.users.isEmpty) {
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

          final all = StaffState.instance.users
              .where((u) => u.role == UserRole.patient)
              .toList();
          final list = _filteredPatients();
          final activeCount =
              all.where((u) => u.status == 'active').length;
          final accent = AppColors.brandIndigo;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: StaffStatCardsGrid(
                  cards: [
                    StaffStatCardData(
                      value: '$activeCount',
                      label: 'Active',
                      detail: '${all.length} total patient accounts',
                      icon: AppIcons.patients,
                      accent: accent,
                      onTap: () => setState(() => _statusFilter = 'active'),
                    ),
                    StaffStatCardData(
                      value: '${list.length}',
                      label: 'Showing',
                      detail: _search.text.trim().isEmpty
                          ? 'All patients'
                          : 'Search results',
                      icon: AppIcons.search,
                      accent: accent,
                      onTap: _search.text.trim().isNotEmpty
                          ? () {
                              _search.clear();
                              setState(() {});
                            }
                          : () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 1,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(AppIcons.search,
                          size: 18, color: AppPalette.textMuted(context)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                            hintText: 'Search name, email or mCare ID…',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 2,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statusChip(null, 'All'),
                      _statusChip('active', 'Active'),
                      _statusChip('pending', 'Pending'),
                      _statusChip('suspended', 'Suspended'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: 'Patient directory',
                  icon: AppIcons.patients,
                  trailing: '${list.length}/${all.length}',
                  actionLabel: _loading ? null : 'Refresh',
                  onAction: _loading ? null : _loadPatients,
                ),
              ),
              StaggeredEntry(
                index: 4,
                child: list.isEmpty
                    ? GlassCard(
                        frosted: true,
                        child: EmptyStateView(
                          icon: AppIcons.patients,
                          title: 'No patients found',
                          message: canCreate
                              ? 'Register a patient or adjust your filters.'
                              : 'Try adjusting your search or filters.',
                          compact: true,
                        ),
                      )
                    : StaffListCard(
                        children: list
                            .map(
                              (u) => StaffListRow(
                                icon: AppIcons.patients,
                                iconColor: u.role.accent,
                                title: u.name,
                                subtitle: '${u.email} · ${u.uniqueId}',
                                pill: u.status.replaceAll('_', ' ').toUpperCase(),
                                pillColor: switch (u.status) {
                                  'active' => AppColors.success,
                                  'suspended' => AppColors.critical,
                                  _ => AppColors.warning,
                                },
                                onTap: () => StaffPatientProfileSheet.show(
                                  context,
                                  patientId: u.id,
                                  patientName: u.name,
                                  loadFromAdmin: true,
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

  Widget _statusChip(String? status, String label) {
    final selected = _statusFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: () => setState(() => _statusFilter = status),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandIndigo.withOpacity(0.14)
                : AppPalette.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(
              color: selected ? AppColors.brandIndigo : AppPalette.border(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.brandIndigo : AppPalette.textMuted(context),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
