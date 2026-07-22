import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
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
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/staff_patient_profile_sheet.dart';

/// Role options shown in create/change flows — respects assistant grants.
List<DropdownMenuItem<String>> _creatableRoleItems({String? includeRole}) {
  final isAdmin = AuthState.instance.user?.role == UserRole.admin;
  final has = AuthState.instance.hasAssistantPermission;
  final items = <DropdownMenuItem<String>>[
    const DropdownMenuItem(value: 'patient', child: Text('Patient')),
    const DropdownMenuItem(
        value: 'doctor', child: Text('Doctor / Healthworker')),
    if (isAdmin || has(AssistantPermissions.canRegisterAssistant))
      const DropdownMenuItem(
          value: 'mcareAssistant', child: Text('mCare Assistant')),
    if (isAdmin || has(AssistantPermissions.canRegisterAdmin))
      const DropdownMenuItem(value: 'admin', child: Text('Admin')),
  ];
  if (includeRole != null &&
      !items.any((i) => i.value == includeRole)) {
    items.add(DropdownMenuItem(
      value: includeRole,
      child: Text(includeRole),
    ));
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

  List<RoleNavDestination> get destinations => isAssistant
      ? StaffDestinations.assistant()
      : StaffDestinations.admin();
}

class AdminUsersView extends StatefulWidget {
  const AdminUsersView({super.key});

  @override
  State<AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends State<AdminUsersView> {
  UserRole? _filter;
  /// When true, show locked or temp-password accounts that need staff help.
  bool _passwordAssistOnly = false;
  final _q = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminApi.instance.listUsers(perPage: 100);
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
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
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
                hint: 'user@example.com',
                keyboardType: TextInputType.emailAddress,
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
                    horizontal: AppSpacing.md, vertical: 4),
                child: DropdownButton<String>(
                  value: selectedRole,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setSt(() => selectedRole = v ?? 'patient'),
                  items: _creatableRoleItems(includeRole: selectedRole),
                ),
              ),
              if (selectedRole == 'doctor') ...[
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: specialtyCtrl,
                  label: 'Specialty / profession',
                  hint: 'e.g. General Practitioner, Nurse, Cardiologist',
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
                onPressed: () async {
                  final first = firstCtrl.text.trim();
                  final last = lastCtrl.text.trim();
                  final email = emailCtrl.text.trim();
                  if (first.isEmpty || last.isEmpty || email.isEmpty) {
                    AppToast.warn(
                        ctx, 'First name, last name and email are required.');
                    return;
                  }
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
                        await showDialog<void>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('Account created'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$first $last is ready.'),
                                if (temp != null) ...[
                                  const SizedBox(height: 12),
                                  const Text('Temporary password',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  SelectableText(
                                    temp,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                                if (invite != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    emailSent
                                        ? 'Invite email sent to $email.'
                                        : 'Invite token issued (7-day expiry). Share securely or resend from user detail.',
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Invite token',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  SelectableText(
                                    invite,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dCtx).pop(),
                                child: const Text('Done'),
                              ),
                            ],
                          ),
                        );
                      } else {
                        AppToast.success(
                            context, '$first $last created successfully.');
                      }
                      _loadUsers();
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      AppToast.error(ctx, 'Could not create user: $e');
                    }
                  } finally {
                    setSt(() => creating = false);
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
    _q.dispose();
    super.dispose();
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
        AppButton(
          label: 'Create',
          icon: AppIcons.add,
          size: AppButtonSize.sm,
          onPressed: () => _openCreateSheet(context),
        ),
        const SizedBox(width: 8),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          if (_loading) {
            return const AppLoadingView();
          }
          if (_error != null) {
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

          var list = StaffState.instance.users;
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
                .where((u) =>
                    u.name.toLowerCase().contains(q) ||
                    u.email.toLowerCase().contains(q) ||
                    u.uniqueId.toLowerCase().contains(q))
                .toList();
          }
          final assistCount = StaffState.instance.users
              .where((u) => u.isLocked || u.mustChangePassword)
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
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
                        controller: _q,
                        decoration: const InputDecoration(
                          hintText: 'Search users…',
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(context, null, 'All'),
                    _filterChip(context, UserRole.patient, 'Patients'),
                    _filterChip(context, UserRole.doctor, 'Doctors'),
                    _filterChip(context, UserRole.mcareAssistant, 'Assistants'),
                    _filterChip(context, UserRole.admin, 'Admins'),
                    _assistFilterChip(context, assistCount),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (list.isEmpty)
                GlassCard(
                  frosted: true,
                  child: EmptyStateView(
                    icon: AppIcons.users,
                    title: 'No users match',
                    compact: true,
                  ),
                )
              else
                StaffListCard(
                  children: list
                      .map((u) => StaffListRow(
                            icon: AppIcons.user,
                            iconColor: u.role.accent,
                            title: u.name,
                            subtitle: [
                              u.email,
                              u.uniqueId,
                              if (u.specialty?.trim().isNotEmpty == true)
                                u.specialty!.trim(),
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
                            onTap: () => Navigator.of(context).pushNamed(
                              nav.isAssistant
                                  ? RouteNames.assistantUserDetail
                                  : RouteNames.adminUserDetail,
                              arguments: u.id,
                            ),
                          ))
                      .toList(),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _assistFilterChip(BuildContext context, int count) {
    final selected = _passwordAssistOnly;
    final accent = AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: () => setState(() {
          _passwordAssistOnly = !_passwordAssistOnly;
          if (_passwordAssistOnly) _filter = null;
        }),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.14) : AppPalette.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: selected ? accent : AppPalette.border(context)),
          ),
          child: Text(
            count > 0 ? 'Password assist ($count)' : 'Password assist',
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

  Widget _filterChip(BuildContext context, UserRole? r, String label) {
    final selected = !_passwordAssistOnly && _filter == r;
    final accent = r?.accent ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: () => setState(() {
          _filter = r;
          _passwordAssistOnly = false;
        }),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.14) : AppPalette.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: selected ? accent : AppPalette.border(context)),
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

class AdminUserDetailView extends StatelessWidget {
  const AdminUserDetailView({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final nav = _navConfig();
        final user = StaffState.instance.userById(userId);
        if (user == null) {
          return RoleShell(
            currentRoute: nav.currentRoute,
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
          currentRoute: nav.currentRoute,
          destinations: nav.destinations,
          profileRoute: nav.profileRoute,
          notificationsRoute: nav.notificationsRoute,
          title: user.name,
          subtitle: '${user.role.label} · ${user.uniqueId}',
          subjectIdentity: user.role == UserRole.patient
              ? RoleSubjectIdentity(
                  name: user.name,
                  initials: _initials(user.name),
                  accent: user.role.accent,
                  onTap: () => StaffPatientProfileSheet.show(
                    context,
                    patientId: user.id,
                    patientName: user.name,
                    loadFromAdmin: true,
                  ),
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                frosted: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: user.role == UserRole.patient
                          ? () => StaffPatientProfileSheet.show(
                                context,
                                patientId: user.id,
                                patientName: user.name,
                                loadFromAdmin: true,
                              )
                          : null,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                      child: Row(
                        children: [
                          Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(
                              color: user.role.accent.withOpacity(0.14),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusPill),
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
                                Text(user.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(user.email,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                if (user.role == UserRole.patient)
                                  Text(
                                    'Tap for full clinical profile',
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
                          if (user.role == UserRole.patient)
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
                    Text('Status: ${user.status}',
                        style: Theme.of(context).textTheme.bodyMedium),
                    if (user.isLocked)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          user.lockedUntil != null
                              ? 'Locked until ${DateFormat.yMMMd().add_jm().format(user.lockedUntil!.toLocal())}'
                              : 'Account locked after failed sign-ins',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    if (user.role == UserRole.doctor &&
                        user.specialty?.trim().isNotEmpty == true)
                      Text('Specialty: ${user.specialty!.trim()}',
                          style: Theme.of(context).textTheme.bodyMedium),
                    if (user.role == UserRole.doctor &&
                        user.licenseNumber?.trim().isNotEmpty == true)
                      Text('License: ${user.licenseNumber!.trim()}',
                          style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              if (user.role == UserRole.patient) ...[
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'View full profile',
                  icon: AppIcons.profile,
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: () => StaffPatientProfileSheet.show(
                    context,
                    patientId: user.id,
                    patientName: user.name,
                    loadFromAdmin: true,
                  ),
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
                            message:
                                'They will gain access immediately.',
                            icon: AppIcons.approval,
                          );
                          if (ok != true) return;
                          try {
                            await StaffState.instance
                                .approveApplicationRemote(user.id);
                            if (!context.mounted) return;
                            AppToast.success(context, '${user.name} approved.');
                          } catch (e) {
                            if (!context.mounted) return;
                            AppToast.error(
                                context, 'Could not approve: $e');
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
                            AppToast.info(
                                context, '${user.name} rejected.');
                          } catch (e) {
                            if (!context.mounted) return;
                            AppToast.error(
                                context, 'Could not reject: $e');
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    AppButton(
                      label: user.status == 'active' ? 'Suspend account' : 'Reactivate',
                      icon: user.status == 'active'
                          ? AppIcons.lock
                          : AppIcons.check,
                      variant: user.status == 'active'
                          ? AppButtonVariant.danger
                          : AppButtonVariant.primary,
                      onPressed: () async {
                        final next = user.status == 'active' ? 'suspended' : 'active';
                        final ok = await AppDialog.confirm(
                          context,
                          title:
                              user.status == 'active' ? 'Suspend account?' : 'Reactivate?',
                          message: user.status == 'active'
                              ? 'User will lose access immediately.'
                              : 'User will regain access immediately.',
                          danger: user.status == 'active',
                        );
                        if (ok != true) return;
                        try {
                          await StaffState.instance.setUserStatusRemote(user.id, next);
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
                        AssistantPermissions.canChangeUserTypes))
                      AppButton(
                        label: 'Change role',
                        icon: AppIcons.permissions,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _changeRole(context, user),
                      ),
                    if (AuthState.instance.hasAssistantPermission(
                        AssistantPermissions.canChangeUserTypes))
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
                        onPressed: () => Navigator.of(context)
                            .pushNamed(RouteNames.adminPermissions),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionLabel(
                title: 'Password assist',
                icon: AppIcons.lock,
              ),
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
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Temporary password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share this securely with ${user.name}. It is shown only once.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Temporary password',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(
                password.isEmpty ? '(not returned — retry)' : password,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          actions: [
            if (password.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: password));
                  if (ctx.mounted) {
                    AppToast.success(ctx, 'Copied to clipboard');
                  }
                },
                icon: const Icon(AppIcons.copy, size: 16),
                label: const Text('Copy'),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
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
        AppToast.warn(context, 'Invite was not returned — user may have already accepted.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invite reissued'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New invite for ${user.email} (expires in 7 days).'),
              if (emailSent) ...[
                const SizedBox(height: 8),
                Text(
                  'Invite email sent to ${user.email}.',
                  style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Invite token',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(
                token,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Direct them to Accept invite in the app and paste this token.',
                style: TextStyle(
                  color: AppPalette.textMuted(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
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
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New role',
                style: Theme.of(ctx)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppPalette.textMuted(context)),
              ),
              const SizedBox(height: 4),
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 4),
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
      ),
    );

    if (ok != true || !context.mounted) return;
    try {
      await StaffState.instance.changeUserRoleRemote(
        userId,
        newRole: selectedRole,
        reason: reasonCtrl.text.trim(),
      );
      if (!context.mounted) return;
      AppToast.success(context, 'Role updated to $selectedRole.');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not change role: $e');
    }
  }
}
