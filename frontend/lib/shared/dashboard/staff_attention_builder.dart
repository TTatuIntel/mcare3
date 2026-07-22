import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/support_ticket.dart';
import '../models/vital.dart';
import '../navigation/sos_navigation.dart';
import '../state/staff_state.dart';
import '../state/support_state.dart';
import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';
import 'staff_attention_section.dart';

/// Which set of route constants an attention item should push to.
enum AttentionRoleRoutes { admin, assistant }

/// Assembles the "Needs attention" list used by both the Admin and
/// Assistant dashboards.
///
/// `hasPermission` gates assistant-specific rows (SOS, approvals, care requests,
/// support). Admins pass a function that returns true for every key.
class StaffAttentionBuilder {
  const StaffAttentionBuilder._();

  static List<StaffAttentionItem> build(
    BuildContext context, {
    required AttentionRoleRoutes roleRoutes,
    required bool Function(String key) hasPermission,
  }) {
    final routes = _routes(roleRoutes);

    final activeSos = StaffState.instance.patientSos
        .where((e) => e.isActive)
        .toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    final openAlerts = StaffState.instance.alerts
        .where((a) => !a.acknowledged && !a.resolved)
        .toList();

    final pendingApprovals = StaffState.instance.approvals
        .where((a) => a.status == 'pending')
        .toList();

    final pendingRequests = StaffState.instance.careRequests
        .where((r) => r.status == 'pending')
        .toList();

    final openTickets = SupportState.instance.all
        .where((t) =>
            t.status == TicketStatus.open ||
            t.status == TicketStatus.inProgress)
        .toList();

    return [
      // SOS — admins always see; assistants require the emergency-location
      // permission because SOS reveals live GPS.
      if (roleRoutes == AttentionRoleRoutes.admin ||
          hasPermission(AssistantPermissions.canAccessEmergencyLocation))
        for (final e in activeSos.take(roleRoutes == AttentionRoleRoutes.admin ? 2 : 3))
          StaffAttentionItem(
            icon: AppIcons.sos,
            color: AppColors.critical,
            title: e.patientName ??
                StaffState.instance.patientById(e.patientId)?.name ??
                'Patient',
            subtitle:
                '${e.kindLabel} · ${DateFormat.jm().format(e.triggeredAt)}',
            pill: 'SOS',
            onTap: () => SosNavigation.openHub(
              context,
              patientId: e.patientId,
              eventId: e.id,
            ),
          ),
      // Alerts — always visible to both roles.
      for (final a in openAlerts.take(roleRoutes == AttentionRoleRoutes.admin ? 3 : 4))
        StaffAttentionItem(
          icon: AppIcons.alert,
          color: a.severity == RiskLevel.critical
              ? AppColors.critical
              : AppColors.warning,
          title: a.patientName,
          subtitle:
              '${a.vital.label} · ${a.value} · ${DateFormat.jm().format(a.createdAt)}',
          pill: a.severity == RiskLevel.critical ? 'Critical' : 'Warning',
          onTap: () => Navigator.of(context).pushNamed(routes.alerts),
        ),
      // Approvals — gated on assistant side.
      if (roleRoutes == AttentionRoleRoutes.admin ||
          hasPermission(AssistantPermissions.canApproveHealthworkers))
        for (final a in pendingApprovals.take(2))
          StaffAttentionItem(
            icon: AppIcons.approval,
            color: AppColors.adminPurple,
            title: a.name,
            subtitle: a.specialty,
            pill: 'Approval',
            onTap: () => Navigator.of(context).pushNamed(routes.approvals),
          ),
      // Care requests — gated on assistant side.
      if (roleRoutes == AttentionRoleRoutes.admin ||
          hasPermission(AssistantPermissions.canManageCareRequests))
        for (final r in pendingRequests.take(2))
          StaffAttentionItem(
            icon: AppIcons.careRequest,
            color: AppColors.info,
            title: '${r.patient} → ${r.providerRequested}',
            subtitle: r.reason,
            pill: 'Request',
            onTap: () => Navigator.of(context).pushNamed(routes.careRequests),
          ),
      // Support tickets — assistant only (admins have a dedicated support view).
      if (roleRoutes == AttentionRoleRoutes.assistant)
        for (final t in openTickets.take(2))
          StaffAttentionItem(
            icon: AppIcons.support,
            color: AppColors.info,
            title: t.subject,
            subtitle: t.patientName ?? 'Support ticket',
            pill: 'Support',
            onTap: () => Navigator.of(context).pushNamed(routes.support),
          ),
    ].take(roleRoutes == AttentionRoleRoutes.admin ? 6 : 8).toList();
  }

  static _AttentionRoutes _routes(AttentionRoleRoutes r) =>
      r == AttentionRoleRoutes.admin
          ? const _AttentionRoutes(
              alerts: RouteNames.adminAlerts,
              approvals: RouteNames.adminApprovals,
              careRequests: RouteNames.adminCareRequests,
              support: RouteNames.adminSupport,
            )
          : const _AttentionRoutes(
              alerts: RouteNames.assistantAlerts,
              approvals: RouteNames.assistantApprovals,
              careRequests: RouteNames.assistantCareRequests,
              support: RouteNames.assistantSupport,
            );
}

class _AttentionRoutes {
  const _AttentionRoutes({
    required this.alerts,
    required this.approvals,
    required this.careRequests,
    required this.support,
  });
  final String alerts;
  final String approvals;
  final String careRequests;
  final String support;
}
