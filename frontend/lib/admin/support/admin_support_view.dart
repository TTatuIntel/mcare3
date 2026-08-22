import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/patient_domain_mapper.dart';
import '../../shared/account/account_preferences_list.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/models/support_ticket.dart';
import '../../shared/models/user_role.dart';
import '../../shared/state/support_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/staff_filter_chip.dart';

class SupportQueueScreen extends StatefulWidget {
  const SupportQueueScreen({
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
  State<SupportQueueScreen> createState() => _SupportQueueScreenState();
}

class _SupportQueueScreenState extends State<SupportQueueScreen> {
  // 'all' | 'open' | 'in_progress' | 'resolved' | 'closed'
  String _filter = 'open';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final rows = await AdminApi.instance.listSupportTickets();
      final tickets =
          rows.map((e) => PatientDomainMapper.supportTicketFromApi(e)).toList();
      SupportState.instance.seed(tickets);
    } catch (_) {
      // Cached tickets from login sync remain visible.
    }
  }

  List<SupportTicket> _filtered(List<SupportTicket> all) {
    if (_filter == 'all') return all;
    return all.where((t) {
      if (_filter == 'open') return t.status == TicketStatus.open;
      if (_filter == 'in_progress') return t.status == TicketStatus.inProgress;
      if (_filter == 'resolved') return t.status == TicketStatus.resolved;
      if (_filter == 'closed') return t.status == TicketStatus.closed;
      return true;
    }).toList();
  }

  Future<void> _openDetail(BuildContext context, SupportTicket ticket) async {
    await GlassSheet.show<void>(
      context,
      title: ticket.subject,
      subtitle: '${ticket.category.label} · ${ticket.priority.label}',
      child: _TicketDetailSheet(ticket: ticket),
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
      title: 'Support inbox',
      subtitle: 'Patient and staff help requests',
      body: AnimatedBuilder(
        animation: SupportState.instance,
        builder: (context, _) {
          final all = SupportState.instance.all;
          final openCount = all
              .where((t) =>
                  t.status == TicketStatus.open ||
                  t.status == TicketStatus.inProgress)
              .length;
          final items = _filtered(all);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PatientDateHeader(),
              const SizedBox(height: AppSpacing.sm),
              if (openCount > 0)
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(AppIcons.support,
                          size: 20, color: AppColors.adminPurple),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$openCount open ticket${openCount == 1 ? '' : 's'}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'Assign, reply, and resolve from ticket details',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppPalette.textMuted(context)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              StaffFilterChipBar(
                options: [
                  const StaffFilterOption(value: 'open', label: 'Open'),
                  StaffFilterOption(
                    value: 'in_progress',
                    label: 'In Progress',
                    color: AppColors.warning,
                  ),
                  StaffFilterOption(value: 'all', label: 'All'),
                  StaffFilterOption(
                    value: 'resolved',
                    label: 'Resolved',
                    color: AppColors.success,
                  ),
                  StaffFilterOption(
                    value: 'closed',
                    label: 'Closed',
                    color: AppPalette.textMuted(context),
                  ),
                ],
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: AppSpacing.sm),

              // list
              if (items.isEmpty)
                GlassCard(
                  frosted: true,
                  child: EmptyStateView(
                    icon: AppIcons.support,
                    title: 'No tickets',
                    compact: true,
                  ),
                )
              else
                StaffListCard(
                  children: items
                      .map((t) => StaffListRow(
                            icon: AppIcons.support,
                            iconColor: t.status.color,
                            title: t.subject,
                            subtitle: [
                              if (t.patientName != null) t.patientName!,
                              t.category.label,
                              DateFormat.MMMd().format(t.createdAt),
                            ].join(' · '),
                            pill: t.status.label,
                            pillColor: t.status.color,
                            trailing: t.replies.isNotEmpty
                                ? _ReplyBadge(count: t.replies.length)
                                : null,
                            onTap: () => _openDetail(context, t),
                          ))
                      .toList(),
                ),
              const SizedBox(height: AppSpacing.lg),
              if (AuthState.instance.user?.role == UserRole.admin)
                AccountHubQuickLinks(
                  role: UserRole.admin,
                  currentRoute: widget.currentRoute,
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket detail sheet — replies + compose + close
// ---------------------------------------------------------------------------

class _TicketDetailSheet extends StatefulWidget {
  const _TicketDetailSheet({required this.ticket});
  final SupportTicket ticket;

  @override
  State<_TicketDetailSheet> createState() => _TicketDetailSheetState();
}

class _TicketDetailSheetState extends State<_TicketDetailSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  bool _closing = false;
  bool _assigning = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pollTicket());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pollTicket() async {
    try {
      final rows = await AdminApi.instance.listSupportTickets();
      Map<String, dynamic>? match;
      for (final r in rows) {
        if (r['id'] == widget.ticket.id) {
          match = r;
          break;
        }
      }
      if (match != null) {
        final updated = PatientDomainMapper.supportTicketFromApi(match);
        final current = List<SupportTicket>.from(SupportState.instance.all);
        final i = current.indexWhere((t) => t.id == updated.id);
        if (i != -1) {
          current[i] = updated;
          SupportState.instance.seed(current);
        }
      }
    } catch (_) {}
  }

  SupportTicket get _current =>
      SupportState.instance.byId(widget.ticket.id) ?? widget.ticket;

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await SupportState.instance
          .addReplyRemote(_current.id, body, isStaff: true);
      _ctrl.clear();
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not send reply.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resolve() async {
    setState(() => _closing = true);
    try {
      await SupportState.instance.resolveRemote(_current.id);
      if (mounted) {
        AppToast.success(context, 'Ticket marked resolved.');
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not resolve ticket.');
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _close() async {
    setState(() => _closing = true);
    try {
      await SupportState.instance.closeRemote(_current.id);
      if (mounted) {
        AppToast.success(context, 'Ticket closed.');
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not close ticket.');
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _reopen() async {
    await SupportState.instance.reopenRemote(_current.id);
    if (mounted) AppToast.info(context, 'Ticket reopened.');
  }

  List<DirectoryUser> get _assignableStaff {
    return StaffState.instance.users
        .where((u) =>
            (u.role == UserRole.admin || u.role == UserRole.mcareAssistant) &&
            u.status == 'active')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _assign(String? assigneeId) async {
    if (_assigning) return;
    setState(() => _assigning = true);
    try {
      await SupportState.instance.assignRemote(
        _current.id,
        assigneeId: assigneeId,
      );
      if (!mounted) return;
      AppToast.success(
        context,
        assigneeId == null ? 'Ticket unassigned.' : 'Assignee updated.',
      );
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not update assignment.');
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SupportState.instance,
      builder: (context, _) {
        final t = _current;
        final isClosed = t.status == TicketStatus.closed ||
            t.status == TicketStatus.resolved;

        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // header badges
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _StatusChip(label: t.status.label, color: t.status.color),
                  _StatusChip(
                      label: t.priority.label, color: t.priority.color),
                  _StatusChip(
                      label: t.category.label,
                      color: AppColors.brandIndigo),
                  if (t.assignedTo != null && t.assignedTo!.isNotEmpty)
                    _StatusChip(
                      label: t.assignedToName ?? 'Assigned',
                      color: AppColors.mcareAmber,
                    ),
                ],
              ),
              if (t.patientName != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(AppIcons.user,
                        size: 14, color: AppPalette.textMuted(context)),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Requested by ${t.patientName!}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              // assignment
              _AssignmentCard(
                assignedTo: t.assignedTo,
                assignedToName: t.assignedToName,
                assignableStaff: _assignableStaff,
                assigning: _assigning,
                onChanged: (v) {
                  if (v == t.assignedTo) return;
                  _assign(v);
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // description
              _SectionHeader(
                icon: AppIcons.info,
                title: 'Original request',
                color: AppColors.brandIndigo,
              ),
              const SizedBox(height: AppSpacing.xs),
              GlassCard(
                frosted: true,
                child: Text(
                  t.description,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // replies
              if (t.replies.isNotEmpty) ...[
                SectionLabel(
                  title: 'Conversation (${t.replies.length})',
                  icon: AppIcons.chat,
                ),
                for (final r in t.replies) _ReplyBubble(reply: r),
                const SizedBox(height: AppSpacing.sm),
              ],

              // compose
              if (!isClosed) ...[
                _SectionHeader(
                  icon: AppIcons.send,
                  title: 'Reply to requester',
                  color: AppColors.adminPurple,
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.surface(context),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: AppPalette.border(context)),
                  ),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _ctrl,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                          hintText: 'Write a helpful reply…',
                          border: InputBorder.none,
                          isCollapsed: true,
                          hintStyle: TextStyle(
                              color: AppPalette.textMuted(context)),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Reply will be visible to the requester.',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppPalette.textFaint(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          AppButton(
                            label: 'Send',
                            icon: AppIcons.send,
                            size: AppButtonSize.sm,
                            loading: _sending,
                            onPressed: _send,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Mark resolved',
                        icon: AppIcons.check,
                        expand: true,
                        loading: _closing,
                        onPressed: _resolve,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppButton(
                        label: 'Close',
                        icon: AppIcons.close,
                        expand: true,
                        variant: AppButtonVariant.secondary,
                        loading: _closing,
                        onPressed: _close,
                      ),
                    ),
                  ],
                ),
              ],

              if (isClosed) ...[
                GlassCard(
                  frosted: true,
                  child: Column(
                    children: [
                      Icon(AppIcons.check, color: AppColors.success, size: 28),
                      const SizedBox(height: AppSpacing.xs),
                      Text('This ticket is ${t.status.label.toLowerCase()}.',
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Reopen',
                        icon: AppIcons.refresh,
                        size: AppButtonSize.sm,
                        onPressed: _reopen,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });
  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.assignedTo,
    required this.assignedToName,
    required this.assignableStaff,
    required this.assigning,
    required this.onChanged,
  });

  final String? assignedTo;
  final String? assignedToName;
  final List<DirectoryUser> assignableStaff;
  final bool assigning;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.mcareAmber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(AppIcons.users,
                    size: 14, color: AppColors.mcareAmber),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assigned to',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      assigning
                          ? 'Updating…'
                          : 'Reassign without sending a reply',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (assigning)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppPalette.surface(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: assignedTo,
                icon: Icon(AppIcons.expandMore,
                    color: AppPalette.textMuted(context)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppPalette.ink(context),
                  fontWeight: FontWeight.w600,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  for (final u in assignableStaff)
                    DropdownMenuItem<String?>(
                      value: u.id,
                      child: Text(
                        '${u.name} · ${u.role.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: assigning ? null : onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.reply});
  final TicketReply reply;

  @override
  Widget build(BuildContext context) {
    final isStaff = reply.isStaff;
    final color = isStaff ? AppColors.mcareAmber : AppColors.brandIndigo;
    return Align(
      alignment: isStaff ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment:
              isStaff ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              reply.author,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              reply.body,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat.jm().format(reply.sentAt),
              style: TextStyle(color: AppPalette.textMuted(context), fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReplyBadge extends StatelessWidget {
  const _ReplyBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.brandIndigo.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.chat, size: 10, color: AppColors.brandIndigo),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              color: AppColors.brandIndigo,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
