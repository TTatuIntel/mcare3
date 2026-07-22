import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';

/// Admin view for managing mCare Assistant delegated permissions.
/// Loads each assistant's grant set from the API, lets admin toggle in-place,
/// and syncs the full updated set on every toggle.
class AdminPermissionsView extends StatefulWidget {
  const AdminPermissionsView({super.key});

  @override
  State<AdminPermissionsView> createState() => _AdminPermissionsViewState();
}

class _AdminPermissionsViewState extends State<AdminPermissionsView> {
  /// permissionGrants[userId] = set of granted keys (loaded from API).
  final Map<String, Set<String>> _permissionGrants = {};
  final Set<String> _loading = {}; // user IDs currently being synced
  bool _initialising = false;
  String? _initError;

  static const _permissionLabels = <String, String>{
    AssistantPermissions.canApproveHealthworkers: 'Approve healthworkers',
    AssistantPermissions.canManageCareRequests: 'Manage care requests',
    AssistantPermissions.canAssignPatients: 'Assign patients',
    AssistantPermissions.canCreateUsers: 'Create users',
    AssistantPermissions.canChangeUserTypes: 'Change user types',
    AssistantPermissions.canRegisterAdmin: 'Register admins',
    AssistantPermissions.canRegisterAssistant: 'Register assistants',
    AssistantPermissions.canViewActivityLogs: 'View activity logs',
    AssistantPermissions.canViewSecurityIncidents: 'View security incidents',
    AssistantPermissions.canAccessEmergencyLocation: 'Access emergency location',
    AssistantPermissions.canManageAdvertising: 'Manage advertising',
    AssistantPermissions.canManageVitalCatalog: 'Manage vital catalog',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPermissions());
  }

  Future<void> _loadPermissions() async {
    final assistants = StaffState.instance.users
        .where((u) => u.role.name == 'mcareAssistant')
        .toList();
    if (assistants.isEmpty) return;

    setState(() {
      _initialising = true;
      _initError = null;
    });

    var successes = 0;
    Object? lastError;
    for (final a in assistants) {
      if (!mounted) return;
      try {
        final list = await AdminApi.instance.getUserPermissions(a.id);
        if (!mounted) return;
        setState(() => _permissionGrants[a.id] = list.toSet());
        successes++;
      } catch (e) {
        lastError = e;
      }
    }

    if (!mounted) return;
    setState(() {
      _initialising = false;
      if (successes == 0 && lastError != null) {
        _initError = 'Could not reach the permissions service. $lastError';
      }
    });
  }

  /// Toggle one key for one assistant, then sync the full set to the server.
  Future<void> _toggle(String userId, String key, bool value) async {
    final grants = _permissionGrants[userId] ?? <String>{};
    final next = Set<String>.from(grants);
    if (value) {
      next.add(key);
    } else {
      next.remove(key);
    }

    // Optimistic update in UI
    setState(() {
      _permissionGrants[userId] = next;
      _loading.add(userId);
    });

    // If this is the currently signed-in assistant, keep AuthState in sync
    if (AuthState.instance.user?.id == userId) {
      AuthState.instance.setAssistantPermissions(next);
    }

    final userName = StaffState.instance.userById(userId)?.name ?? userId;
    final label = _permissionLabels[key] ?? key;

    try {
      if (mounted) {
        final synced = await AdminApi.instance.syncUserPermissions(
          userId,
          next.toList(),
        );
        if (mounted) {
          setState(() {
            _permissionGrants[userId] = synced.toSet();
            _loading.remove(userId);
          });
        }
      }
      // Write audit entry
      StaffState.instance.addAudit(
        AuditEntry(
          id: 'perm_${DateTime.now().millisecondsSinceEpoch}',
          at: DateTime.now(),
          actor: AuthState.instance.user?.fullName ?? 'Admin',
          action:
              value ? 'Granted "$label"' : 'Revoked "$label"',
          target: userName,
          category: 'security',
        ),
      );
      if (mounted) {
        AppToast.show(
          context,
          message: value
              ? 'Granted "$label" to $userName.'
              : 'Revoked "$label" from $userName.',
        );
      }
    } catch (e) {
      // Revert optimistic change on error
      if (mounted) {
        setState(() {
          _permissionGrants[userId] = grants;
          _loading.remove(userId);
        });
        AppToast.error(context, 'Could not update permissions: $e');
      }
    }
  }

  /// Grant or revoke ALL permissions at once.
  Future<void> _setAll(String userId, bool grantAll) async {
    final next = grantAll ? Set<String>.from(AssistantPermissions.all) : <String>{};
    setState(() {
      _permissionGrants[userId] = next;
      _loading.add(userId);
    });

    if (AuthState.instance.user?.id == userId) {
      AuthState.instance.setAssistantPermissions(next);
    }

    final userName = StaffState.instance.userById(userId)?.name ?? userId;
    try {
      final synced = await AdminApi.instance.syncUserPermissions(
        userId,
        next.toList(),
      );
      if (mounted) {
        setState(() {
          _permissionGrants[userId] = synced.toSet();
          _loading.remove(userId);
        });
      }
      StaffState.instance.addAudit(
        AuditEntry(
          id: 'perm_all_${DateTime.now().millisecondsSinceEpoch}',
          at: DateTime.now(),
          actor: AuthState.instance.user?.fullName ?? 'Admin',
          action: grantAll ? 'Granted all permissions' : 'Revoked all permissions',
          target: userName,
          category: 'security',
        ),
      );
      if (mounted) {
        AppToast.show(
          context,
          message: grantAll
              ? 'All permissions granted to $userName.'
              : 'All permissions revoked from $userName.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Could not update permissions: $e');
        _loadPermissions();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.adminPermissions,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
      title: 'mCare Assistant permissions',
      subtitle: 'Delegated capabilities · admin retains full control',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final assistants = StaffState.instance.users
              .where((u) => u.role.name == 'mcareAssistant')
              .toList();

          if (assistants.isEmpty) {
            return GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.permissions,
                title: 'No mCare Assistants yet',
                message:
                    'Create an assistant account in Users → then return here to configure permissions.',
                compact: true,
              ),
            );
          }

          if (_initialising) {
            return const AppLoadingView();
          }

          if (_initError != null) {
            return GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.alert,
                title: 'Could not load permissions',
                message: _initError,
                actionLabel: 'Retry',
                onAction: _loadPermissions,
                compact: true,
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in assistants) ...[
                SectionLabel(
                  title: a.name,
                  icon: AppIcons.permissions,
                  trailing: a.uniqueId,
                ),
                _AssistantPermissionCard(
                  userId: a.id,
                  grants: _permissionGrants[a.id] ?? <String>{},
                  permissionLabels: _permissionLabels,
                  isSyncing: _loading.contains(a.id),
                  onToggle: (key, value) => _toggle(a.id, key, value),
                  onGrantAll: () => _setAll(a.id, true),
                  onRevokeAll: () => _setAll(a.id, false),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-assistant permission card
// ---------------------------------------------------------------------------

class _AssistantPermissionCard extends StatelessWidget {
  const _AssistantPermissionCard({
    required this.userId,
    required this.grants,
    required this.permissionLabels,
    required this.isSyncing,
    required this.onToggle,
    required this.onGrantAll,
    required this.onRevokeAll,
  });

  final String userId;
  final Set<String> grants;
  final Map<String, String> permissionLabels;
  final bool isSyncing;
  final void Function(String key, bool value) onToggle;
  final VoidCallback onGrantAll;
  final VoidCallback onRevokeAll;

  @override
  Widget build(BuildContext context) {
    final grantCount = grants.length;
    final totalCount = AssistantPermissions.all.length;
    final allGranted = grantCount == totalCount;

    return GlassCard(
      frosted: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grant summary row + bulk actions
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: grantCount == 0
                        ? AppPalette.surfaceMuted(context)
                        : grantCount == totalCount
                            ? AppColors.success.withValues(alpha: 0.12)
                            : AppColors.mcareAmber.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    '$grantCount / $totalCount permissions',
                    style: TextStyle(
                      color: grantCount == 0
                          ? AppPalette.textMuted(context)
                          : grantCount == totalCount
                              ? AppColors.success
                              : AppColors.mcareAmber,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (isSyncing) ...[
                  const SizedBox(width: AppSpacing.sm),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: isSyncing
                      ? null
                      : (allGranted ? onRevokeAll : onGrantAll),
                  child: Text(
                    allGranted ? 'Revoke all' : 'Grant all',
                    style: TextStyle(
                      color: allGranted
                          ? AppColors.critical
                          : AppColors.brandIndigo,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppPalette.border(context)),
          // Permission toggles
          for (final entry in permissionLabels.entries)
            _PermissionRow(
              label: entry.value,
              permKey: entry.key,
              granted: grants.contains(entry.key),
              enabled: !isSyncing,
              onChanged: (v) => onToggle(entry.key, v),
            ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.permKey,
    required this.granted,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String permKey;
  final bool granted;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: granted,
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: enabled ? null : AppPalette.textMuted(context),
            ),
      ),
      subtitle: Text(
        permKey,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10,
            ),
      ),
      activeThumbColor: AppColors.mcareAmber,
      onChanged: enabled ? onChanged : null,
      dense: true,
    );
  }
}
