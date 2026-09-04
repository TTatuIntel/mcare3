import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/realtime/realtime_refresh_mixin.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/loading/loading.dart';

class AdminSystemView extends StatefulWidget {
  const AdminSystemView({super.key});

  @override
  State<AdminSystemView> createState() => _AdminSystemViewState();
}

class _AdminSystemViewState extends State<AdminSystemView>
    with RealtimeRefreshMixin<AdminSystemView> {
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    watchRealtime(const {'settings'}, _loadSettings);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final rows = await AdminApi.instance.listSystemSettings();
      if (rows.isEmpty) return;
      final settings =
          rows.map((e) => StaffMapper.systemSettingFromApi(e)).toList();
      StaffState.instance.mergeSystemSettings(settings);
    } catch (_) {
      // Fall back to seeded mock settings in StaffState.
    }
  }

  static const _categoryIcons = <String, IconData>{
    'Notifications': AppIcons.bell,
    'Access': AppIcons.permissions,
    'Data': AppIcons.storage,
    'Runtime': AppIcons.settings,
  };

  Future<void> _toggle(SystemConfigSection item, bool value) async {
    if (_saving.contains(item.key)) return;
    setState(() => _saving.add(item.key));
    final prev = item.value;
    StaffState.instance.toggleSystemByKey(item.key, value);
    try {
      await AdminApi.instance.updateSystemSetting(item.key, value: value);
    } catch (e, st) {
      debugPrint('System toggle "${item.key}" failed: $e\n$st');
      StaffState.instance.toggleSystemByKey(item.key, prev);
      if (mounted) {
        AppToast.error(context, 'Could not save "${item.title}".');
      }
    } finally {
      if (mounted) setState(() => _saving.remove(item.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.adminSystem,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
      title: 'System settings',
      subtitle: 'Notifications, access, data and runtime configuration',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final items = StaffState.instance.system;

          // group by category
          final groups = <String, List<SystemConfigSection>>{};
          for (final item in items) {
            groups.putIfAbsent(item.category, () => []).add(item);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final group in groups.entries) ...[
                SectionLabel(
                  title: group.key,
                  icon: _categoryIcons[group.key] ?? AppIcons.settings,
                  trailing: '${group.value.where((i) => i.value).length}/${group.value.length} on',
                ),
                GlassCard(
                  frosted: true,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < group.value.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: AppPalette.surfaceMuted(context),
                            indent: AppSpacing.md,
                          ),
                        _SettingTile(
                          item: group.value[i],
                          saving: _saving.contains(group.value[i].key),
                          onChanged: (v) => _toggle(group.value[i], v),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.item,
    required this.saving,
    required this.onChanged,
  });

  final SystemConfigSection item;
  final bool saving;
  final ValueChanged<bool> onChanged;

  static const _dangerKeys = {'maintenance_mode', 'two_factor_required'};

  @override
  Widget build(BuildContext context) {
    final isDanger = _dangerKeys.contains(item.key);
    final activeColor =
        isDanger ? AppColors.critical : AppColors.brandIndigo;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: item.value && isDanger
                                ? AppColors.critical
                                : null,
                          ),
                    ),
                    if (item.value && isDanger) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.critical.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: AppColors.critical,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (saving)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: McarePulse(
                size: McarePulseSize.micro,
                color: activeColor,
                semanticLabel: null,
              ),
            )
          else
            Switch(
              value: item.value,
              onChanged: onChanged,
              activeThumbColor: activeColor,
              activeTrackColor: activeColor.withValues(alpha: 0.35),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }
}
