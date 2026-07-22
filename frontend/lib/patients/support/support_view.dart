import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/support_ticket.dart';
import '../../shared/state/support_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_floating_button.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';
import 'create_ticket_sheet.dart';

class SupportView extends StatefulWidget {
  const SupportView({super.key});

  @override
  State<SupportView> createState() => _SupportViewState();
}

enum _SupportFilter { all, open, resolved, priority }

class _SupportViewState extends State<SupportView> {
  _SupportFilter _filter = _SupportFilter.all;

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);

    return PatientScaffold(
      currentRoute: RouteNames.patientSupport,
      detachedNav: true,
      title: 'Support',
      subtitle: 'Open a ticket — we usually respond within an hour',
      floatingActionButton: tier.isHandheld
          ? GlassFloatingButton(
              icon: AppIcons.add,
              label: 'New ticket',
              accent: AppColors.info,
              onPressed: () => CreateTicketSheet.show(context),
            )
          : null,
      body: AnimatedBuilder(
        animation: SupportState.instance,
        builder: (context, _) {
          final open = SupportState.instance.open;
          final closed = SupportState.instance.closed;
          final urgent = open
              .where((t) =>
                  t.priority == TicketPriority.urgent ||
                  t.priority == TicketPriority.high)
              .length;
          final showOpen = _filter == _SupportFilter.all ||
              _filter == _SupportFilter.open ||
              _filter == _SupportFilter.priority;
          final showClosed = _filter == _SupportFilter.all ||
              _filter == _SupportFilter.resolved;
          final openList = _filter == _SupportFilter.priority
              ? open
                  .where((t) =>
                      t.priority == TicketPriority.urgent ||
                      t.priority == TicketPriority.high)
                  .toList()
              : open;
          final closedList = closed;
          final mostRecent = open.isNotEmpty
              ? open.first.updatedAt ?? open.first.createdAt
              : (closed.isNotEmpty
                  ? closed.first.updatedAt ?? closed.first.createdAt
                  : null);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(index: 0, child: PatientDateHeader()),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _SupportHero(
                  openCount: open.length,
                  closedCount: closed.length,
                  urgentCount: urgent,
                  lastActivity: mostRecent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 2,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: PatientQuickActionsBar(
                    children: [
                      PatientQuickAction(
                        icon: AppIcons.add,
                        label: 'New ticket',
                        onTap: () => CreateTicketSheet.show(context),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.support,
                        label: 'Open',
                        badge: open.isNotEmpty ? '${open.length}' : null,
                        selected: _filter == _SupportFilter.open,
                        onTap: () => setState(() => _filter = _SupportFilter.open),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.check,
                        label: 'Resolved',
                        badge: closed.isNotEmpty ? '${closed.length}' : null,
                        badgeColor: AppColors.success,
                        selected: _filter == _SupportFilter.resolved,
                        onTap: () =>
                            setState(() => _filter = _SupportFilter.resolved),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.alert,
                        label: 'Priority',
                        badge: urgent > 0 ? '$urgent' : null,
                        badgeColor: AppColors.warning,
                        selected: _filter == _SupportFilter.priority,
                        onTap: () =>
                            setState(() => _filter = _SupportFilter.priority),
                      ),
                    ],
                  ),
                ),
              ),
              if (showOpen && openList.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                StaggeredEntry(
                  index: 3,
                  child: SectionLabel(
                    title: _filter == _SupportFilter.priority
                        ? 'Priority tickets'
                        : 'Open tickets',
                    icon: AppIcons.support,
                    trailing: '${openList.length}',
                    actionLabel: _filter != _SupportFilter.all ? 'Show all' : null,
                    onAction: _filter != _SupportFilter.all
                        ? () => setState(() => _filter = _SupportFilter.all)
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(
                  index: 4,
                  child: _TicketListCard(tickets: openList),
                ),
              ],
              if (showClosed && closedList.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                StaggeredEntry(
                  index: 5,
                  child: SectionLabel(
                    title: 'Resolved / closed',
                    icon: AppIcons.check,
                    trailing: '${closedList.length}',
                    actionLabel: _filter != _SupportFilter.all ? 'Show all' : null,
                    onAction: _filter != _SupportFilter.all
                        ? () => setState(() => _filter = _SupportFilter.all)
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(
                  index: 6,
                  child: _TicketListCard(tickets: closedList),
                ),
              ],
              if (openList.isEmpty &&
                  closedList.isEmpty &&
                  (_filter != _SupportFilter.all || open.isEmpty && closed.isEmpty))
                StaggeredEntry(
                  index: 3,
                  child: GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.support,
                      title: _filter == _SupportFilter.priority
                          ? 'No priority tickets'
                          : _filter == _SupportFilter.open
                              ? 'No open tickets'
                              : _filter == _SupportFilter.resolved
                                  ? 'No resolved tickets'
                                  : 'No tickets yet',
                      message: _filter == _SupportFilter.all
                          ? 'Need help? Open a ticket and our team will assist.'
                          : 'Try another filter or create a new ticket.',
                      actionLabel: _filter != _SupportFilter.all
                          ? 'Show all'
                          : 'Create ticket',
                      onAction: _filter != _SupportFilter.all
                          ? () => setState(() => _filter = _SupportFilter.all)
                          : () => CreateTicketSheet.show(context),
                      compact: true,
                    ),
                  ),
                ),
              SizedBox(height: tier.isHandheld ? 88 : AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

class _SupportHero extends StatelessWidget {
  const _SupportHero({
    required this.openCount,
    required this.closedCount,
    required this.urgentCount,
    required this.lastActivity,
  });

  final int openCount;
  final int closedCount;
  final int urgentCount;
  final DateTime? lastActivity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUrgent = urgentCount > 0;
    final accent = isUrgent ? AppColors.warning : AppColors.info;
    final iconBg = isUrgent ? AppPalette.warningSoft(context) : AppPalette.infoSoft(context);

    final headline = isUrgent
        ? '$urgentCount priority ticket${urgentCount == 1 ? '' : 's'}'
        : openCount > 0
            ? 'We\'re on it'
            : 'How can we help?';

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  isUrgent ? AppIcons.alert : AppIcons.support,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (lastActivity != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                'Last updated ${patientRelativeTime(lastActivity!)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              PatientHeroStat(label: 'Open', value: '$openCount'),
              const PatientHeroStatDivider(),
              PatientHeroStat(label: 'Resolved', value: '$closedCount'),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Priority',
                value: '$urgentCount',
                accent: urgentCount > 0 ? AppColors.warning : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TicketListCard extends StatelessWidget {
  const _TicketListCard({required this.tickets});
  final List<SupportTicket> tickets;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          for (var i = 0; i < tickets.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            _TicketRow(ticket: tickets[i]),
          ],
        ],
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket});
  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(
          RouteNames.patientTicketDetail,
          arguments: ticket.id,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: ticket.status.softBg(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: ticket.status.color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: ticket.status.color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(
                  AppIcons.support,
                  color: ticket.status.color,
                  size: 16,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.subject,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        _Pill(
                          label: ticket.status.label,
                          color: ticket.status.color,
                          bg: ticket.status.softBg(context),
                        ),
                        const SizedBox(width: 6),
                        _Pill(
                          label: ticket.priority.label,
                          color: ticket.priority.color,
                          bg: ticket.priority.color.withOpacity(0.12),
                        ),
                      ],
                    ),
                    Text(
                      '${ticket.category.label} · ${DateFormat.MMMd().format(ticket.createdAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, size: 14, color: AppPalette.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, required this.bg});
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// Ticket detail view — kept in same file for routing compatibility.
class TicketDetailView extends StatefulWidget {
  const TicketDetailView({super.key, required this.ticketId});
  final String ticketId;

  @override
  State<TicketDetailView> createState() => _TicketDetailViewState();
}

class _TicketDetailViewState extends State<TicketDetailView> {
  final _reply = TextEditingController();

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _sendReply(String ticketId) async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    _reply.clear();
    try {
      await SupportState.instance.addReplyRemote(ticketId, text);
    } catch (e) {
      if (!mounted) return;
      AppToast.warn(context, 'Could not send: $e');
      return;
    }
    if (!mounted) return;
    AppToast.success(context, 'Reply sent.');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SupportState.instance,
      builder: (context, _) {
        final ticket = SupportState.instance.byId(widget.ticketId);
        if (ticket == null) {
          return PatientScaffold(
            currentRoute: RouteNames.patientSupport,
            detachedNav: true,
            title: 'Ticket',
            body: EmptyStateView(
              icon: AppIcons.support,
              title: 'Not found',
              message: 'This ticket could not be loaded.',
              compact: true,
            ),
          );
        }

        return PatientScaffold(
          currentRoute: RouteNames.patientSupport,
          detachedNav: true,
          scrollable: false,
          title: ticket.subject,
          subtitle: ticket.status.label,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Opened ${DateFormat.yMMMd().format(ticket.createdAt)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppPalette.textMuted(context),
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  children: [
                    for (final r in ticket.replies)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Align(
                          alignment: r.isStaff
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                            ),
                            decoration: BoxDecoration(
                              color: r.isStaff
                                  ? AppPalette.surfaceAlt(context)
                                  : AppColors.brandIndigo.withOpacity(0.12),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                              border: Border.all(color: AppPalette.border(context)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.author,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(fontSize: 10),
                                ),
                                Text(
                                  r.body,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontSize: 14),
                                ),
                                Text(
                                  DateFormat.jm().format(r.sentAt),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: AppPalette.textMuted(context),
                                        fontSize: 10,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (ticket.status != TicketStatus.closed &&
                  ticket.status != TicketStatus.resolved)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: 'Add a reply…',
                          hintStyle: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppPalette.textMuted(context)),
                          filled: true,
                          fillColor: AppPalette.surfaceAlt(context),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusPill),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppButton.icon(
                      icon: AppIcons.chat,
                      semanticLabel: 'Send reply',
                      onPressed: () => _sendReply(ticket.id),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
