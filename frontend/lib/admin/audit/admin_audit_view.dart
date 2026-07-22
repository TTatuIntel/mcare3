import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/realtime/session_poller.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/utils/file_download.dart';
import '../../shared/widgets/staff_filter_chip.dart';

class AdminAuditView extends StatelessWidget {
  const AdminAuditView({super.key});

  @override
  Widget build(BuildContext context) {
    return AuditScreen(
      currentRoute: RouteNames.adminAudit,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
    );
  }
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({
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
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _searchCtrl = TextEditingController();
  String _filter = 'all'; // 'all' | 'security' | 'activity'
  String _query = '';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SessionPoller.instance.triggerNow();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AuditEntry> _apply(List<AuditEntry> entries) {
    var list = entries;

    if (_filter == 'security') {
      list = list.where((e) => e.category == 'security').toList();
    } else if (_filter == 'activity') {
      list = list.where((e) => e.category != 'security').toList();
    }

    if (_query.isNotEmpty) {
      list = list
          .where((e) =>
              e.action.toLowerCase().contains(_query) ||
              e.actor.toLowerCase().contains(_query) ||
              e.target.toLowerCase().contains(_query))
          .toList();
    }
    return list;
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final bytes = await AdminApi.instance.exportAudit();
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        AppToast.warn(context, 'No export data returned.');
        return;
      }
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final saved = await saveBytesAsFile(
        bytes: bytes,
        suggestedName: 'mcare_audit_$stamp.csv',
      );
      if (!mounted) return;
      if (saved) {
        AppToast.success(context, 'Audit CSV saved.');
      } else {
        AppToast.info(context, 'Export cancelled.');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not export audit: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Audit log',
      subtitle: 'System activity and security events',
      headerActions: [
        AppButton(
          label: 'Export',
          icon: AppIcons.download,
          size: AppButtonSize.sm,
          loading: _exporting,
          variant: AppButtonVariant.secondary,
          onPressed: _exportCsv,
        ),
        const SizedBox(width: 8),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final all = StaffState.instance.audit;
          final filtered = _apply(all);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search bar
              GlassCard(
                frosted: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search action, actor or target…',
                    hintStyle: TextStyle(color: AppPalette.textMuted(context)),
                    prefixIcon: Icon(AppIcons.search,
                        size: 18, color: AppPalette.textMuted(context)),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(AppIcons.close,
                                size: 16, color: AppPalette.textMuted(context)),
                            onPressed: () {
                              _searchCtrl.clear();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),

              // Category filter chips
              StaffFilterChipBar(
                options: const [
                  StaffFilterOption(
                    value: 'all',
                    label: 'All',
                    color: AppColors.brandIndigo,
                  ),
                  StaffFilterOption(
                    value: 'security',
                    label: 'Security',
                    color: AppColors.critical,
                  ),
                  StaffFilterOption(
                    value: 'activity',
                    label: 'Activity',
                    color: AppColors.info,
                  ),
                ],
                selected: _filter,
                accent: AppColors.brandIndigo,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Result count
              if (_query.isNotEmpty || _filter != 'all')
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    '${filtered.length} of ${all.length} entries',
                    style: TextStyle(
                      color: AppPalette.textMuted(context),
                      fontSize: 11,
                    ),
                  ),
                ),

              // Empty state
              if (all.isEmpty)
                GlassCard(
                  frosted: true,
                  child: EmptyStateView(
                    icon: AppIcons.audit,
                    title: 'No audit entries yet',
                    compact: true,
                  ),
                )
              else if (filtered.isEmpty)
                GlassCard(
                  frosted: true,
                  child: EmptyStateView(
                    icon: AppIcons.search,
                    title: 'No matches',
                    message: 'Try a different search or filter.',
                    compact: true,
                  ),
                )
              else
                _EntryList(entries: filtered),
            ],
          );
        },
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.entries});
  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    // Group by date
    final groups = <String, List<AuditEntry>>{};
    for (final e in entries) {
      final key = DateFormat.yMMMd().format(e.at);
      groups.putIfAbsent(key, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups.entries) ...[
          SectionLabel(
            title: group.key,
            icon: AppIcons.calendar,
            trailing: '${group.value.length}',
          ),
          StaffListCard(
            children: group.value
                .map((e) => StaffListRow(
                      icon: e.category == 'security'
                          ? AppIcons.alert
                          : AppIcons.audit,
                      iconColor: e.category == 'security'
                          ? AppColors.critical
                          : AppColors.brandIndigo,
                      title: e.action,
                      subtitle:
                          '${e.actor} · ${e.target} · ${DateFormat.jm().format(e.at)}',
                      pill: e.category == 'security' ? 'Security' : null,
                      pillColor: AppColors.critical,
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
