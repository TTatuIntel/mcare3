import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_directory_controls.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/staff_credential_dialog.dart';
import '../../shared/widgets/dossier/user_dossier_sheet.dart';
import '../reports/patient_report_builder_sheet.dart';
import '../reports/patient_report_status_sheet.dart';

/// Role options shown in create/change flows — respects assistant grants.
List<DropdownMenuItem<String>> _creatableRoleItems({String? includeRole}) {
  final isAdmin = AuthState.instance.user?.role == UserRole.admin;
  final has = AuthState.instance.hasAssistantPermission;
  final items = <DropdownMenuItem<String>>[
    const DropdownMenuItem(value: 'patient', child: Text('Patient')),
    const DropdownMenuItem(
      value: 'doctor',
      child: Text('Doctor / Healthworker'),
    ),
    if (isAdmin || has(AssistantPermissions.canRegisterAssistant))
      const DropdownMenuItem(
        value: 'mcareAssistant',
        child: Text('mCare Assistant'),
      ),
    if (isAdmin || has(AssistantPermissions.canRegisterAdmin))
      const DropdownMenuItem(value: 'admin', child: Text('Admin')),
  ];
  if (includeRole != null && !items.any((i) => i.value == includeRole)) {
    items.add(DropdownMenuItem(value: includeRole, child: Text(includeRole)));
  }
  return items;
}

/// Returns the correct nav config for whoever is currently logged in so that
/// AdminUsersView and AdminUserDetailView can be reused by mCare Assistants.
_UsersNavConfig _navConfig() {
  final role = AuthState.instance.user?.role;
  if (role == UserRole.mcareAssistant) {
    return const _UsersNavConfig(
      currentRoute: RouteNames.assistantUsers,
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
      isAssistant: true,
    );
  }
  return const _UsersNavConfig(
    currentRoute: RouteNames.adminUsers,
    profileRoute: RouteNames.adminProfile,
    notificationsRoute: RouteNames.adminNotifications,
    isAssistant: false,
  );
}

class _UsersNavConfig {
  const _UsersNavConfig({
    required this.currentRoute,
    required this.profileRoute,
    required this.notificationsRoute,
    required this.isAssistant,
  });
  final String currentRoute;
  final String profileRoute;
  final String notificationsRoute;
  final bool isAssistant;

  List<RoleNavDestination> get destinations =>
      isAssistant ? StaffDestinations.assistant() : StaffDestinations.admin();
}

class AdminUsersView extends StatefulWidget {
  const AdminUsersView({super.key});

  @override
  State<AdminUsersView> createState() => _AdminUsersViewState();
}

/// Sort options for the Users directory.
enum _UserSort {
  nameAsc('Name (A → Z)'),
  nameDesc('Name (Z → A)'),
  newest('Recently joined'),
  oldest('Oldest first'),
  mcareId('mCare ID'),
  roleAsc('Role');

  const _UserSort(this.label);
  final String label;
}

class _AdminUsersViewState extends State<AdminUsersView> {
  // Persisted filter state — restored when the user returns to the page.
  static UserRole? _persistedFilter;
  static bool _persistedAssistOnly = false;
  static _UserSort _persistedSort = _UserSort.nameAsc;

  late UserRole? _filter = _persistedFilter;

  /// When true, show locked or temp-password accounts that need staff help.
  late bool _passwordAssistOnly = _persistedAssistOnly;
  late _UserSort _sort = _persistedSort;

  final _q = TextEditingController();
  bool _loading = false;
  String? _error;
  DateTime? _lastSyncedAt;
  Timer? _syncedTicker;

  bool get _hasActiveFilters =>
      _filter != null ||
      _passwordAssistOnly ||
      _sort != _UserSort.nameAsc ||
      _q.text.trim().isNotEmpty;

  void _clearAllFilters() {
    setState(() {
      _filter = null;
      _passwordAssistOnly = false;
      _sort = _UserSort.nameAsc;
      _q.clear();
      _persistedFilter = null;
      _persistedAssistOnly = false;
      _persistedSort = _UserSort.nameAsc;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
    _syncedTicker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _lastSyncedAt != null) setState(() {});
    });
  }

  Future<void> _loadUsers() async {
    // Preserve StaffState.seedDemo() fixtures when networking is disabled.
    // The disabled API response is transport-shaped but intentionally empty.
    if (!AppEnv.backendEnabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminApi.instance.listUsers(perPage: 100);
      final rawList = data['users'] as List? ?? const [];
      final users = rawList
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

  Future<void> _openCreateSheet(BuildContext context) async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final specialtyCtrl = TextEditingController();
    final licenseCtrl = TextEditingController();
    String selectedRole = 'patient';
    bool creating = false;

    await GlassSheet.show(
      context,
      title: 'Create user',
      subtitle: 'New account — a welcome email will be sent',
      child: StatefulBuilder(
        builder: (ctx, setSt) {
          final first = firstCtrl.text.trim();
          final last = lastCtrl.text.trim();
          final email = emailCtrl.text.trim();
          final specialtyReq = selectedRole == 'doctor' &&
              specialtyCtrl.text.trim().isEmpty;
          final canSubmit = first.isNotEmpty &&
              last.isNotEmpty &&
              _looksLikeEmail(email) &&
              !specialtyReq &&
              !creating;

          return Column(
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
                      onChanged: (_) => setSt(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppTextField(
                      controller: lastCtrl,
                      label: 'Last name',
                      hint: 'e.g. Okonkwo',
                      onChanged: (_) => setSt(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: emailCtrl,
                label: 'Email address',
                hint: 'user@example.com',
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setSt(() {}),
                errorText: email.isEmpty || _looksLikeEmail(email)
                    ? null
                    : 'Enter a valid email address',
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: phoneCtrl,
                label: 'Phone (optional)',
                hint: '+254 7XX XXX XXX',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Role',
                style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
              ),
              const SizedBox(height: 4),
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 4,
                ),
                child: DropdownButton<String>(
                  value: selectedRole,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) =>
                      setSt(() => selectedRole = v ?? 'patient'),
                  items: _creatableRoleItems(includeRole: selectedRole),
                ),
              ),
              if (selectedRole == 'doctor') ...[
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: specialtyCtrl,
                  label: 'Specialty / profession',
                  hint: 'e.g. General Practitioner, Nurse, Cardiologist',
                  onChanged: (_) => setSt(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: licenseCtrl,
                  label: 'License number',
                  hint: 'Professional registration or license ID',
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Create account',
                icon: AppIcons.user,
                expand: true,
                loading: creating,
                onPressed: !canSubmit ? null : () async {
                setSt(() => creating = true);
                try {
                  final data = await AdminApi.instance.createUser(
                    firstName: first,
                    lastName: last,
                    email: email,
                    phone: phoneCtrl.text.trim().isEmpty
                        ? null
                        : phoneCtrl.text.trim(),
                    role: selectedRole,
                    specialty: specialtyCtrl.text.trim(),
                    licenseNumber: licenseCtrl.text.trim(),
                  );
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    final temp = data?['temp_password'] as String?;
                    final invite = data?['invite_token'] as String?;
                    final emailSent = data?['email_sent'] as bool? ?? false;
                    if (temp != null || invite != null) {
                      await showStaffCredentialDialog(
                        context,
                        title: 'Account created',
                        message:
                            '$first $last is ready. Share credentials only through a secure channel.',
                        icon: AppIcons.check,
                        statusMessage: invite != null && emailSent
                            ? 'Invite email sent to $email.'
                            : null,
                        values: [
                          if (temp != null)
                            StaffCredentialValue(
                              label: 'Temporary password',
                              value: temp,
                            ),
                          if (invite != null)
                            StaffCredentialValue(
                              label: 'Invite token · expires in 7 days',
                              value: invite,
                            ),
                        ],
                      );
                    } else {
                      AppToast.success(
                        context,
                        '$first $last created successfully.',
                      );
                    }
                    _loadUsers();
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    AppToast.error(ctx, 'Could not create user: $e');
                  }
                } finally {
                  if (ctx.mounted) setSt(() => creating = false);
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
    specialtyCtrl.dispose();
    licenseCtrl.dispose();
  }

  @override
  void dispose() {
    _syncedTicker?.cancel();
    _q.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String s) {
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(s);
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

  int get _activeFilterCount {
    var n = 0;
    if (_filter != null) n++;
    if (_passwordAssistOnly) n++;
    if (_sort != _UserSort.nameAsc) n++;
    return n;
  }

  List<({String label, VoidCallback onRemove})> _activeFilterPills() {
    final pills = <({String label, VoidCallback onRemove})>[];
    if (_filter != null) {
      pills.add((
        label: _filter!.label,
        onRemove: () => setState(() {
          _filter = null;
          _persistedFilter = null;
        }),
      ));
    }
    if (_passwordAssistOnly) {
      pills.add((
        label: 'Password assist',
        onRemove: () => setState(() {
          _passwordAssistOnly = false;
          _persistedAssistOnly = false;
        }),
      ));
    }
    if (_sort != _UserSort.nameAsc) {
      pills.add((
        label: _sort.label,
        onRemove: () => setState(() {
          _sort = _UserSort.nameAsc;
          _persistedSort = _UserSort.nameAsc;
        }),
      ));
    }
    return pills;
  }

  List<DirectoryUser> _sortedList(List<DirectoryUser> input) {
    final list = [...input];
    switch (_sort) {
      case _UserSort.nameAsc:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _UserSort.nameDesc:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _UserSort.newest:
        list.sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
        break;
      case _UserSort.oldest:
        list.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
        break;
      case _UserSort.mcareId:
        list.sort((a, b) =>
            a.uniqueId.toLowerCase().compareTo(b.uniqueId.toLowerCase()));
        break;
      case _UserSort.roleAsc:
        list.sort((a, b) {
          final byRole = a.role.label.compareTo(b.role.label);
          if (byRole != 0) return byRole;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final nav = _navConfig();
    return RoleShell(
      currentRoute: nav.currentRoute,
      destinations: nav.destinations,
      profileRoute: nav.profileRoute,
      notificationsRoute: nav.notificationsRoute,
      title: 'Users & passwords',
      subtitle: 'Accounts · temp passwords · unlocks',
      headerActions: [
        Tooltip(
          message: 'Create a new user account',
          child: AppButton(
            label: 'Create',
            icon: AppIcons.add,
            size: AppButtonSize.sm,
            onPressed: () => _openCreateSheet(context),
          ),
        ),
        const SizedBox(width: 8),
      ],
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
                    title: 'Failed to load users',
                    message: _error,
                    compact: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Retry',
                    icon: AppIcons.refresh,
                    onPressed: _loadUsers,
                  ),
                ],
              ),
            );
          }

          final all = StaffState.instance.users;
          var list = all;
          if (_filter != null) {
            list = list.where((u) => u.role == _filter).toList();
          }
          if (_passwordAssistOnly) {
            list = list
                .where((u) => u.isLocked || u.mustChangePassword)
                .toList();
          }
          final q = _q.text.trim().toLowerCase();
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
          list = _sortedList(list);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: StaffDirectorySearch(
                      controller: _q,
                      hintText: 'Search name, email or mCare ID…',
                      semanticLabel: 'Search users and passwords directory',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _filterIconButton(context, all),
                ],
              ),
              if (_activeFilterPills().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _activeFilterStrip(),
              ],
              const SizedBox(height: AppSpacing.md),
              SectionLabel(
                title: 'User directory',
                icon: AppIcons.users,
                trailing: '${list.length}/${all.length}',
                actionLabel: _loading ? null : 'Refresh',
                onAction: _loading ? null : _loadUsers,
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
              if (list.isEmpty)
                GlassCard(
                  frosted: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EmptyStateView(
                        icon: AppIcons.users,
                        title: 'No users match',
                        message: _hasActiveFilters
                            ? 'Adjust or clear filters to see more accounts.'
                            : 'No user accounts to show yet.',
                        compact: true,
                      ),
                      if (_hasActiveFilters) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: 'Clear all filters',
                          icon: AppIcons.close,
                          onPressed: _clearAllFilters,
                        ),
                      ],
                    ],
                  ),
                )
              else
                StaffListCard(
                  children: list.map((u) => _userRow(context, u, nav)).toList(),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterIconButton(BuildContext context, List<DirectoryUser> all) {
    final active = _activeFilterCount;
    return Semantics(
      button: true,
      label: active == 0 ? 'Open filters' : '$active filters active',
      child: InkWell(
        onTap: () => _openFilterSheet(context, all),
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
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: AppColors.brandIndigo,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
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

  Widget _activeFilterStrip() {
    final pills = _activeFilterPills();
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final pill in pills)
          _UsersRemovablePill(label: pill.label, onRemove: pill.onRemove),
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

  Future<void> _openFilterSheet(
    BuildContext context,
    List<DirectoryUser> all,
  ) async {
    var draftRole = _filter;
    var draftAssist = _passwordAssistOnly;
    var draftSort = _sort;

    int roleCount(UserRole? r) => r == null
        ? all.length
        : all.where((u) => u.role == r).length;
    final assistCount =
        all.where((u) => u.isLocked || u.mustChangePassword).length;

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

            Widget roleChip(UserRole? r, String label) {
              return StaffDirectoryFilterChip(
                label: '$label · ${roleCount(r)}',
                selected: draftRole == r,
                accent: r?.accent ?? AppColors.brandIndigo,
                onTap: () => setSt(() => draftRole = r),
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
                            'Filter users',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setSt(() {
                              draftRole = null;
                              draftAssist = false;
                              draftSort = _UserSort.nameAsc;
                            }),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    ),
                    section('ROLE', [
                      roleChip(null, 'All'),
                      roleChip(UserRole.patient, 'Patients'),
                      roleChip(UserRole.doctor, 'Doctors'),
                      roleChip(UserRole.mcareAssistant, 'Assistants'),
                      roleChip(UserRole.admin, 'Admins'),
                    ]),
                    section('ATTENTION', [
                      StaffDirectoryFilterChip(
                        label: 'Password assist · $assistCount',
                        selected: draftAssist,
                        accent: AppColors.warning,
                        onTap: () => setSt(() => draftAssist = !draftAssist),
                      ),
                    ]),
                    section('SORT BY', [
                      for (final s in _UserSort.values)
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
        _filter = draftRole;
        _passwordAssistOnly = draftAssist;
        _sort = draftSort;
        _persistedFilter = draftRole;
        _persistedAssistOnly = draftAssist;
        _persistedSort = draftSort;
      });
    }
  }

  Widget _userRow(BuildContext context, DirectoryUser u, _UsersNavConfig nav) {
    final detailRoute = nav.isAssistant
        ? RouteNames.assistantUserDetail
        : RouteNames.adminUserDetail;
    return GestureDetector(
      onLongPress: () => _showRowActions(context, u, detailRoute),
      behavior: HitTestBehavior.opaque,
      child: StaffListRow(
        icon: AppIcons.user,
        iconColor: u.role.accent,
        title: u.name,
        subtitle: [
          u.email,
          u.uniqueId,
          if (u.specialty?.trim().isNotEmpty == true) u.specialty!.trim(),
          if (u.licenseNumber?.trim().isNotEmpty == true)
            u.licenseNumber!.trim(),
        ].join(' · '),
        pill: u.isLocked
            ? 'LOCKED'
            : u.mustChangePassword
                ? 'TEMP PWD'
                : u.status.toUpperCase(),
        pillColor: u.isLocked
            ? AppColors.critical
            : u.mustChangePassword
                ? AppColors.warning
                : switch (u.status) {
                    'active' => AppColors.success,
                    'suspended' => AppColors.critical,
                    _ => AppColors.warning,
                  },
        onTap: () =>
            Navigator.of(context).pushNamed(detailRoute, arguments: u.id),
      ),
    );
  }

  Future<void> _showRowActions(
    BuildContext context,
    DirectoryUser u,
    String detailRoute,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(AppIcons.user, color: u.role.accent, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.name,
                          style: Theme.of(ctx).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${u.role.label} · ${u.uniqueId}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Open details'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context)
                    .pushNamed(detailRoute, arguments: u.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Copy email'),
              subtitle: Text(u.email),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: u.email));
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (!context.mounted) return;
                AppToast.success(context, 'Email copied');
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Copy mCare ID'),
              subtitle: Text(u.uniqueId),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: u.uniqueId));
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (!context.mounted) return;
                AppToast.success(context, 'mCare ID copied');
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _UsersRemovablePill extends StatelessWidget {
  const _UsersRemovablePill({required this.label, required this.onRemove});

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

class AdminUserDetailView extends StatelessWidget {
  const AdminUserDetailView({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final nav = _navConfig();
        final detailRoute = nav.isAssistant
            ? RouteNames.assistantUserDetail
            : RouteNames.adminUserDetail;
        final user = StaffState.instance.userById(userId);
        if (user == null) {
          return RoleShell(
            currentRoute: detailRoute,
            destinations: nav.destinations,
            profileRoute: nav.profileRoute,
            notificationsRoute: nav.notificationsRoute,
            title: 'User',
            body: GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.user,
                title: 'User not found',
                compact: true,
              ),
            ),
          );
        }
        return RoleShell(
          currentRoute: detailRoute,
          destinations: nav.destinations,
          profileRoute: nav.profileRoute,
          notificationsRoute: nav.notificationsRoute,
          title: user.name,
          subtitle: '${user.role.label} · ${user.uniqueId}',
          // Every role now opens the same full dossier, not just patients.
          subjectIdentity: RoleSubjectIdentity(
            name: user.name,
            initials: _initials(user.name),
            accent: user.role.accent,
            onTap: () => _openDossier(context, user),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                frosted: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _openDossier(context, user),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      child: Row(
                        children: [
                          Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(
                              color: user.role.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusPill,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _initials(user.name),
                              style: TextStyle(
                                color: user.role.accent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  user.email,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  user.role == UserRole.patient
                                      ? 'Tap for full clinical profile'
                                      : 'Tap for full account record',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: AppColors.info,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 10,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            AppIcons.chevronRight,
                            size: 16,
                            color: AppPalette.textMuted(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Divider(height: 1, color: AppPalette.border(context)),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Joined ${DateFormat.yMMMd().format(user.joinedAt)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      'Status: ${user.status}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (user.isLocked)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          user.lockedUntil != null
                              ? 'Locked until ${DateFormat.yMMMd().add_jm().format(user.lockedUntil!.toLocal())}'
                              : 'Account locked after failed sign-ins',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.critical,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    if (user.mustChangePassword)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          'Must change temporary password on next sign-in',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    if (user.role == UserRole.doctor &&
                        user.specialty?.trim().isNotEmpty == true)
                      Text(
                        'Specialty: ${user.specialty!.trim()}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    if (user.role == UserRole.doctor &&
                        user.licenseNumber?.trim().isNotEmpty == true)
                      Text(
                        'License: ${user.licenseNumber!.trim()}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'View full profile',
                icon: AppIcons.profile,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: () => _openDossier(context, user),
              ),
              if (user.role == UserRole.patient) ...[
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Issue patient report',
                  icon: AppIcons.report,
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: () => _issueReport(context, user),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                frosted: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user.status == 'pending') ...[
                      AppButton(
                        label: 'Approve account',
                        icon: AppIcons.approval,
                        onPressed: () async {
                          final ok = await AppDialog.confirm(
                            context,
                            title: 'Approve ${user.name}?',
                            message: 'They will gain access immediately.',
                            icon: AppIcons.approval,
                          );
                          if (ok != true) return;
                          try {
                            await StaffState.instance.approveApplicationRemote(
                              user.id,
                            );
                            if (!context.mounted) return;
                            AppToast.success(context, '${user.name} approved.');
                          } catch (e) {
                            if (!context.mounted) return;
                            AppToast.error(context, 'Could not approve: $e');
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Reject application',
                        icon: AppIcons.close,
                        variant: AppButtonVariant.danger,
                        onPressed: () async {
                          final ok = await AppDialog.confirm(
                            context,
                            title: 'Reject application?',
                            message: 'This cannot be undone.',
                            danger: true,
                            icon: AppIcons.close,
                          );
                          if (ok != true) return;
                          try {
                            await StaffState.instance.rejectApplicationRemote(
                              user.id,
                              reason: 'Application rejected by staff.',
                            );
                            if (!context.mounted) return;
                            AppToast.info(context, '${user.name} rejected.');
                          } catch (e) {
                            if (!context.mounted) return;
                            AppToast.error(context, 'Could not reject: $e');
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    AppButton(
                      label: user.status == 'active'
                          ? 'Suspend account'
                          : 'Reactivate',
                      icon: user.status == 'active'
                          ? AppIcons.lock
                          : AppIcons.check,
                      variant: user.status == 'active'
                          ? AppButtonVariant.danger
                          : AppButtonVariant.primary,
                      onPressed: () async {
                        final next = user.status == 'active'
                            ? 'suspended'
                            : 'active';
                        final ok = await AppDialog.confirm(
                          context,
                          title: user.status == 'active'
                              ? 'Suspend account?'
                              : 'Reactivate?',
                          message: user.status == 'active'
                              ? 'User will lose access immediately.'
                              : 'User will regain access immediately.',
                          danger: user.status == 'active',
                        );
                        if (ok != true) return;
                        try {
                          await StaffState.instance.setUserStatusRemote(
                            user.id,
                            next,
                          );
                          if (!context.mounted) return;
                          AppToast.success(context, 'Status updated.');
                        } catch (_) {
                          if (!context.mounted) return;
                          AppToast.error(context, 'Could not update status.');
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (AuthState.instance.hasAssistantPermission(
                      AssistantPermissions.canChangeUserTypes,
                    ))
                      AppButton(
                        label: 'Change role',
                        icon: AppIcons.permissions,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _changeRole(context, user),
                      ),
                    if (AuthState.instance.hasAssistantPermission(
                      AssistantPermissions.canChangeUserTypes,
                    ))
                      const SizedBox(height: AppSpacing.sm),
                    if (_usesInvite(user.role)) ...[
                      AppButton(
                        label: 'Resend invite',
                        icon: AppIcons.email,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _resendInvite(context, user),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (user.role == UserRole.mcareAssistant &&
                        AuthState.instance.user?.role == UserRole.admin) ...[
                      AppButton(
                        label: 'Manage permissions',
                        icon: AppIcons.permissions,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => Navigator.of(
                          context,
                        ).pushNamed(RouteNames.adminPermissions),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionLabel(title: 'Password assist', icon: AppIcons.lock),
              const SizedBox(height: AppSpacing.sm),
              GlassCard(
                frosted: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      user.isLocked
                          ? 'This account is locked. Unlock it, or issue a temporary password if they lost access.'
                          : user.mustChangePassword
                          ? 'A temporary password is still active. Re-issue one if they lost it before signing in.'
                          : 'Help with lockouts or forgotten passwords. Temporary passwords must be changed on next sign-in.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Issue temporary password',
                      icon: AppIcons.lock,
                      onPressed: () => _resetPassword(context, user),
                    ),
                    if (user.isLocked) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Unlock account',
                        icon: AppIcons.check,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _unlockAccount(context, user),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Future<void> _resetPassword(BuildContext context, DirectoryUser user) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Issue temporary password?',
      message:
          'A one-time password will be shown once for ${user.name}. '
          'They must change it on next sign-in. Any lockout is cleared and their active sessions end immediately.',
      icon: AppIcons.lock,
    );
    if (ok != true || !context.mounted) return;
    try {
      final temp = await AdminApi.instance.resetUserPassword(user.id);
      if (!context.mounted) return;
      user
        ..isLocked = false
        ..lockedUntil = null
        ..mustChangePassword = true;
      StaffState.instance.notifyDirectoryChanged();
      final password = temp ?? '';
      await showStaffCredentialDialog(
        context,
        title: 'Temporary password',
        message:
            'Share this securely with ${user.name}. It is shown only once and must be changed at the next sign-in.',
        values: [
          StaffCredentialValue(label: 'Temporary password', value: password),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not issue temporary password: $e');
    }
  }

  Future<void> _unlockAccount(BuildContext context, DirectoryUser user) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Unlock account?',
      message:
          'Clear the login lockout for ${user.name} so they can sign in again. You can also issue a temporary password if they lost theirs.',
      icon: AppIcons.check,
    );
    if (ok != true || !context.mounted) return;
    try {
      await AdminApi.instance.unlockUser(user.id);
      if (!context.mounted) return;
      user
        ..isLocked = false
        ..lockedUntil = null;
      StaffState.instance.notifyDirectoryChanged();
      AppToast.success(context, '${user.name} unlocked.');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not unlock account: $e');
    }
  }

  static bool _usesInvite(UserRole role) =>
      role == UserRole.doctor ||
      role == UserRole.mcareAssistant ||
      role == UserRole.admin;

  /// Full account record — identical shape for every role, so an admin sees
  /// a doctor's caseload and approval trail as readily as a patient's chart.
  void _openDossier(BuildContext context, DirectoryUser user) {
    UserDossierSheet.show(
      context,
      userId: user.id,
      name: user.name,
      subtitle: '${user.role.label} · ${user.uniqueId}',
      onIssueReport: user.role == UserRole.patient
          ? () => _issueReport(context, user)
          : null,
    );
  }

  /// Tick-list report builder, then straight into the consent / signature
  /// tracker so the admin can drive the request to completion in one pass.
  Future<void> _issueReport(BuildContext context, DirectoryUser user) async {
    final request = await PatientReportBuilderSheet.show(
      context,
      patientId: user.id,
      patientName: user.name,
    );
    if (request == null || !context.mounted) return;

    await PatientReportStatusSheet.show(context, request: request);
  }

  Future<void> _resendInvite(BuildContext context, DirectoryUser user) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Resend invite?',
      message:
          'A new 7-day invite token will be issued for ${user.name}. Share it securely so they can set their password.',
      icon: AppIcons.email,
    );
    if (ok != true || !context.mounted) return;
    try {
      final data = await AdminApi.instance.resendUserInvite(userId);
      if (!context.mounted) return;
      final token = data?['invite_token'] as String?;
      final emailSent = data?['email_sent'] as bool? ?? false;
      if (token == null) {
        AppToast.warn(
          context,
          'Invite was not returned — user may have already accepted.',
        );
        return;
      }
      await showStaffCredentialDialog(
        context,
        title: 'Invite reissued',
        message:
            'New invite for ${user.email}. Ask them to open Accept invite and paste this token.',
        icon: AppIcons.email,
        statusMessage: emailSent ? 'Invite email sent to ${user.email}.' : null,
        values: [
          StaffCredentialValue(
            label: 'Invite token · expires in 7 days',
            value: token,
          ),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not resend invite: $e');
    }
  }

  Future<void> _changeRole(BuildContext context, DirectoryUser user) async {
    String selectedRole = user.role.name;
    final reasonCtrl = TextEditingController();

    final ok = await GlassSheet.show<bool>(
      context,
      title: 'Change role',
      subtitle: 'Update ${user.name}\'s system role',
      child: StatefulBuilder(
        builder: (ctx, setSt) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New role',
              style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
            const SizedBox(height: 4),
            GlassCard(
              frosted: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 4,
              ),
              child: DropdownButton<String>(
                value: selectedRole,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                onChanged: (v) => setSt(() => selectedRole = v ?? selectedRole),
                items: _creatableRoleItems(includeRole: selectedRole),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: reasonCtrl,
              label: 'Reason (required for audit)',
              hint: 'e.g. Promoted to admin role',
              maxLines: 2,
              onChanged: (_) => setSt(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Confirm change',
              icon: AppIcons.check,
              expand: true,
              onPressed: reasonCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || !context.mounted) return;
    try {
      await StaffState.instance.changeUserRoleRemote(
        userId,
        newRole: selectedRole,
        reason: reason,
      );
      if (!context.mounted) return;
      AppToast.success(context, 'Role updated to $selectedRole.');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not change role: $e');
    }
  }
}
