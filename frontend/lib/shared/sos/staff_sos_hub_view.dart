import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/web/web_platform.dart' as web_platform;
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/user_role.dart';
import '../navigation/sos_navigation.dart';
import '../navigation/staff_destinations.dart';
import '../services/admin_sos_service.dart';
import '../services/doctor_session_service.dart';
import '../state/staff_state.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_loading_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/role_shell.dart';
import '../widgets/section_label.dart';

/// Unified emergency command center — doctor (caseload), admin & assistant
/// (platform-wide). One place to see, acknowledge, and resolve SOS events.
class StaffSosHubView extends StatefulWidget {
  const StaffSosHubView({super.key, this.initialPatientId, this.initialEventId});

  final String? initialPatientId;
  final String? initialEventId;

  @override
  State<StaffSosHubView> createState() => _StaffSosHubViewState();
}

class _StaffSosHubViewState extends State<StaffSosHubView> {
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};
  String? _highlightEventId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _highlightEventId = widget.initialEventId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refresh();
      if (mounted) setState(() => _loading = false);
      _scrollToHighlight();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  UserRole get _role => AuthState.instance.user?.role ?? UserRole.doctor;

  String get _currentRoute => SosNavigation.hubRouteFor(_role);

  Future<void> _refresh() async {
    if (_role == UserRole.doctor) {
      await DoctorSessionService.instance.syncFromApi();
    } else {
      await AdminSosService.instance.syncFromApi();
    }
    if (mounted) setState(() {});
  }

  List<StaffPatientSos> _activeEvents() {
    final all = StaffState.instance.patientSos.where((e) => e.isActive).toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    if (_role == UserRole.doctor) {
      final ids = StaffState.instance
          .assignedPatientsForDoctor()
          .map((p) => p.id)
          .toSet();
      return all.where((e) => ids.contains(e.patientId)).toList();
    }
    return all;
  }

  List<StaffPatientSos> _recentResolvedEvents() {
    final all = StaffState.instance.patientSos
        .where((e) => !e.isActive)
        .toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    if (_role == UserRole.doctor) {
      final ids = StaffState.instance
          .assignedPatientsForDoctor()
          .map((p) => p.id)
          .toSet();
      return all.where((e) => ids.contains(e.patientId)).take(8).toList();
    }
    return all.take(12).toList();
  }

  void _scrollToHighlight() {
    final id = _highlightEventId ?? widget.initialEventId;
    if (id == null) return;
    final key = _cardKeys[id];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  Future<void> _resolve(String id, String status) async {
    final label = switch (status) {
      'acknowledged' => 'Acknowledge this SOS?',
      'resolved' => 'Mark this SOS as resolved?',
      'falseAlarm' => 'Mark as false alarm?',
      _ => 'Update this SOS?',
    };
    final message = switch (status) {
      'acknowledged' =>
        'The care team will see this event as acknowledged.',
      'resolved' => 'This closes the emergency event for all responders.',
      'falseAlarm' => 'Use only when the trigger was accidental or not an emergency.',
      _ => 'Confirm this status change.',
    };
    final ok = await AppDialog.confirm(
      context,
      title: label,
      message: message,
      danger: status == 'resolved' || status == 'falseAlarm',
      icon: AppIcons.sos,
    );
    if (ok != true || !mounted) return;

    final success = _role == UserRole.doctor
        ? await StaffState.instance.resolveSos(id, status: status)
        : await StaffState.instance.adminResolveSos(id, status: status);
    if (!mounted) return;
    if (success) {
      AppToast.success(context, 'SOS updated.');
      await _refresh();
    } else {
      AppToast.error(context, 'Could not update SOS.');
    }
  }

  void _openMap(String? url) {
    if (url == null || !kIsWeb) return;
    web_platform.openWindow(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    final destinations = switch (role) {
      UserRole.doctor => StaffDestinations.doctor(),
      UserRole.mcareAssistant => StaffDestinations.assistant(),
      _ => StaffDestinations.admin(),
    };
    final profileRoute = switch (role) {
      UserRole.doctor => RouteNames.doctorProfile,
      UserRole.mcareAssistant => RouteNames.assistantProfile,
      _ => RouteNames.adminProfile,
    };
    final notificationsRoute = switch (role) {
      UserRole.doctor => RouteNames.doctorNotifications,
      UserRole.mcareAssistant => RouteNames.assistantNotifications,
      _ => RouteNames.adminNotifications,
    };

    final subtitle = switch (role) {
      UserRole.doctor => 'Active emergencies in your caseload',
      UserRole.mcareAssistant => 'Platform emergencies — respond & coordinate',
      _ => 'Platform emergencies — respond & coordinate',
    };

    return RoleShell(
      currentRoute: _currentRoute,
      destinations: destinations,
      profileRoute: profileRoute,
      notificationsRoute: notificationsRoute,
      scrollable: false,
      title: 'Emergency SOS',
      subtitle: subtitle,
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          if (_loading) {
            return const AppLoadingView(message: 'Loading emergency events…');
          }

          final active = _activeEvents();
          final filtered = widget.initialPatientId == null
              ? active
              : active
                  .where((e) => e.patientId == widget.initialPatientId)
                  .toList();
          final recent = _recentResolvedEvents();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.zero,
              children: [
              if (active.isNotEmpty)
                GlassCard(
                  frosted: true,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: AppPalette.criticalSoft(context),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.critical, width: 2),
                        ),
                        child: const Icon(
                          AppIcons.sos,
                          color: AppColors.critical,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${active.length} active SOS',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.critical,
                                  ),
                            ),
                            Text(
                              'Respond immediately — patients are waiting',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppPalette.textMuted(context),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              SectionLabel(
                title: 'Active emergencies',
                icon: AppIcons.sos,
                trailing: '${filtered.length}',
                actionLabel: 'Refresh',
                onAction: _refresh,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (filtered.isEmpty)
                GlassCard(
                  frosted: true,
                  child: EmptyStateView(
                    icon: AppIcons.sos,
                    title: 'No active SOS',
                    message: role == UserRole.doctor
                        ? 'When a patient in your caseload triggers SOS, it appears here instantly.'
                        : 'When any patient triggers SOS, it appears here for coordination.',
                    compact: true,
                  ),
                )
              else
                ...filtered.map((e) => _SosEventCard(
                      key: _cardKeys.putIfAbsent(e.id, GlobalKey.new),
                      event: e,
                      highlighted: e.id == _highlightEventId,
                      showOpenChart: role == UserRole.doctor,
                      onAcknowledge: () => _resolve(e.id, 'acknowledged'),
                      onResolve: () => _resolve(e.id, 'resolved'),
                      onFalseAlarm: () => _resolve(e.id, 'falseAlarm'),
                      onOpenChart: () => SosNavigation.openRespond(
                        context,
                        patientId: e.patientId,
                        eventId: e.id,
                        role: role,
                      ),
                      onOpenMap: e.mapsUrl != null
                          ? () => _openMap(e.mapsUrl)
                          : null,
                    )),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                SectionLabel(
                  title: 'Recently resolved',
                  icon: AppIcons.audit,
                  trailing: '${recent.length}',
                ),
                const SizedBox(height: AppSpacing.sm),
                ...recent.map(
                  (e) => _ResolvedSosRow(event: e, role: role),
                ),
              ],
              const SizedBox(height: AppSpacing.huge),
            ],
          ),
        );
        },
      ),
    );
  }
}

class _ResolvedSosRow extends StatelessWidget {
  const _ResolvedSosRow({required this.event, required this.role});

  final StaffPatientSos event;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final name = event.patientName ??
        StaffState.instance.patientById(event.patientId)?.name ??
        'Patient';
    final statusColor = switch (event.status) {
      'falseAlarm' => AppPalette.textMuted(context),
      _ => AppColors.success,
    };

    return GlassCard(
      frosted: true,
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: role == UserRole.doctor
          ? () => SosNavigation.openRespond(
                context,
                patientId: event.patientId,
                eventId: event.id,
                role: role,
              )
          : null,
      child: Row(
        children: [
          Icon(AppIcons.sos, size: 16, color: statusColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${event.kindLabel} · ${DateFormat.MMMd().add_jm().format(event.triggeredAt)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              event.status == 'falseAlarm' ? 'FALSE ALARM' : 'RESOLVED',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SosEventCard extends StatelessWidget {
  const _SosEventCard({
    super.key,
    required this.event,
    required this.highlighted,
    required this.showOpenChart,
    required this.onAcknowledge,
    required this.onResolve,
    required this.onFalseAlarm,
    required this.onOpenChart,
    this.onOpenMap,
  });

  final StaffPatientSos event;
  final bool highlighted;
  final bool showOpenChart;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;
  final VoidCallback onFalseAlarm;
  final VoidCallback onOpenChart;
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = event.patientName ??
        StaffState.instance.patientById(event.patientId)?.name ??
        'Patient';

    return GlassCard(
      frosted: true,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      border: highlighted
          ? Border.all(color: AppColors.critical, width: 2)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.sos, color: AppColors.critical, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(status: event.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            event.kindLabel,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.critical,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (event.note != null && event.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(event.note!),
            ),
          const SizedBox(height: 4),
          Text(
            '${DateFormat.MMMd().add_jm().format(event.triggeredAt)} · ${_relative(event.triggeredAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          if (event.locationLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(AppIcons.location,
                      size: 14, color: AppColors.info),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      event.locationLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (event.respondedBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Responded by ${event.respondedBy}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (showOpenChart)
            AppButton(
              label: 'Open patient emergency',
              variant: AppButtonVariant.danger,
              icon: AppIcons.patients,
              expand: true,
              onPressed: onOpenChart,
            ),
          if (showOpenChart) const SizedBox(height: AppSpacing.sm),
          if (event.status == 'active')
            AppButton(
              label: 'Acknowledge — en route',
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: onAcknowledge,
            ),
          if (event.status == 'active') const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (onOpenMap != null) ...[
                Expanded(
                  child: AppButton(
                    label: 'Map',
                    variant: AppButtonVariant.secondary,
                    icon: AppIcons.map,
                    onPressed: onOpenMap,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: AppButton(
                  label: 'Resolve',
                  variant: AppButtonVariant.danger,
                  onPressed: onResolve,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'False alarm',
                  variant: AppButtonVariant.secondary,
                  onPressed: onFalseAlarm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => AppColors.critical,
      'acknowledged' => AppColors.warning,
      _ => AppColors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        status.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
      ),
    );
  }
}
