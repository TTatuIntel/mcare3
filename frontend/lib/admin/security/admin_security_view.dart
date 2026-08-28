import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/realtime/realtime_refresh_mixin.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';

class AdminSecurityView extends StatelessWidget {
  const AdminSecurityView({super.key});

  @override
  Widget build(BuildContext context) => SecurityIncidentsScreen(
    currentRoute: RouteNames.adminSecurity,
    destinations: StaffDestinations.admin(),
    profileRoute: RouteNames.adminProfile,
    notificationsRoute: RouteNames.adminNotifications,
  );
}

/// Unified security feed — SOS events + security audit entries.
class SecurityIncidentsScreen extends StatefulWidget {
  const SecurityIncidentsScreen({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
  });

  final String currentRoute;
  final List<dynamic> destinations;
  final String profileRoute;
  final String notificationsRoute;

  @override
  State<SecurityIncidentsScreen> createState() =>
      _SecurityIncidentsScreenState();
}

class _SecurityIncidentsScreenState extends State<SecurityIncidentsScreen>
    with RealtimeRefreshMixin<SecurityIncidentsScreen> {
  List<Map<String, dynamic>> _incidents = [];
  bool _loading = true;
  bool _showResolved = false;

  @override
  void initState() {
    super.initState();
    watchRealtime(const {'sos', 'audit'}, _load);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await AdminApi.instance.listSecurityIncidents(
        resolved: _showResolved ? true : false,
      );
      if (mounted) {
        setState(() {
          _incidents = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _severityColor(String? severity) => switch (severity) {
    'critical' => AppColors.critical,
    'high' => AppColors.warning,
    _ => AppColors.info,
  };

  String _title(Map<String, dynamic> item) {
    if (item['source'] == 'audit') {
      return item['action'] as String? ?? 'Security event';
    }
    return '${item['kind'] ?? 'SOS'} · ${item['patient_name'] ?? 'Patient'}';
  }

  String _subtitle(Map<String, dynamic> item) {
    final at = item['happened_at'] ?? item['triggered_at'];
    final when = at is String
        ? DateFormat.MMMd().add_jm().format(
            DateTime.tryParse(at) ?? DateTime.now(),
          )
        : '';
    if (item['source'] == 'audit') {
      return '${item['actor']} → ${item['target']} · $when';
    }
    return '${item['status']} · $when';
  }

  Future<void> _resolve(Map<String, dynamic> item) async {
    final title = _title(item);
    final ok = await AppDialog.confirm(
      context,
      title: 'Acknowledge incident?',
      message: 'Mark "$title" as reviewed and resolved on the security feed.',
      icon: AppIcons.security,
    );
    if (ok != true || !mounted) return;

    final id = item['id'] as String;
    await AdminApi.instance.acknowledgeSecurityIncident(id);
    if (!mounted) return;
    AppToast.success(context, 'Incident acknowledged.');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      scrollable: false,
      title: 'Security incidents',
      subtitle: 'SOS events and security audit feed',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FilterChip(
                label: const Text('Active'),
                selected: !_showResolved,
                onSelected: (_) {
                  setState(() => _showResolved = false);
                  _load();
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              FilterChip(
                label: const Text('Resolved'),
                selected: _showResolved,
                onSelected: (_) {
                  setState(() => _showResolved = true);
                  _load();
                },
              ),
              const Spacer(),
              IconButton(icon: const Icon(AppIcons.refresh), onPressed: _load),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SectionLabel(
            title: _showResolved ? 'Resolved' : 'Active',
            icon: AppIcons.security,
            trailing: '${_incidents.length}',
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: _loading
                ? const AppLoadingView()
                : _incidents.isEmpty
                ? const GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.security,
                      title: 'No incidents',
                      message: 'Security events will appear here.',
                      compact: true,
                    ),
                  )
                : ListView.separated(
                    itemCount: _incidents.length,
                    separatorBuilder: (ctx, i) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, i) {
                      final item = _incidents[i];
                      final severity = item['severity'] as String?;
                      return GlassCard(
                        frosted: true,
                        child: StaffListRow(
                          icon: item['source'] == 'sos'
                              ? AppIcons.sos
                              : AppIcons.security,
                          iconColor: _severityColor(severity),
                          title: _title(item),
                          subtitle: _subtitle(item),
                          pill: severity ?? item['source'] as String?,
                          pillColor: _severityColor(severity),
                          trailing: !_showResolved && item['source'] == 'sos'
                              ? AppButton(
                                  label: 'Resolve',
                                  size: AppButtonSize.sm,
                                  onPressed: () => _resolve(item),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
