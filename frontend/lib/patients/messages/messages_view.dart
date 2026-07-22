import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/message.dart';
import '../../shared/state/messages_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';

String _relativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class MessagesView extends StatefulWidget {
  const MessagesView({super.key});

  @override
  State<MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends State<MessagesView> {
  Timer? _timer;
  _ChatFilter _filter = _ChatFilter.all;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);

    return PatientScaffold(
      currentRoute: RouteNames.patientMessages,
      title: 'Chat',
      subtitle: 'Secure chat with your care team',
      body: AnimatedBuilder(
        animation: MessagesState.instance,
        builder: (context, _) {
          final s = MessagesState.instance;
          final allConvos = s.conversations;
          final convos = _filterConversations(allConvos);
          final unread = s.totalUnread;
          final online =
              allConvos.where((c) => c.participant.online).length;
          final mostRecent =
              allConvos.isEmpty ? null : allConvos.first.lastMessage.sentAt;
          Conversation? firstUnread;
          for (final c in allConvos) {
            if (c.unreadCount > 0) {
              firstUnread = c;
              break;
            }
          }

          final todayStr = DateFormat('EEEE, MMM d').format(DateTime.now());

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: Text(
                  todayStr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _ChatHero(
                  totalConversations: allConvos.length,
                  unread: unread,
                  online: online,
                  lastActivity: mostRecent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 2,
                child: _ChatQuickActions(
                  filter: _filter,
                  unread: unread,
                  online: online,
                  firstUnreadId: firstUnread?.id,
                  onFilter: (f) => setState(() => _filter = f),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: 'Conversations',
                  icon: AppIcons.chat,
                  trailing: unread > 0 ? '$unread unread' : '${convos.length}',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (convos.isEmpty)
                StaggeredEntry(
                  index: 4,
                  child: GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.chat,
                      title: _filter == _ChatFilter.unread
                          ? 'No unread messages'
                          : _filter == _ChatFilter.online
                              ? 'No one online'
                              : 'No conversations',
                      message: _filter == _ChatFilter.all
                          ? 'Message your assigned providers once care is established.'
                          : 'Try another filter or check back later.',
                      compact: true,
                      actionLabel:
                          _filter != _ChatFilter.all ? 'Show all' : null,
                      onAction: _filter != _ChatFilter.all
                          ? () => setState(() => _filter = _ChatFilter.all)
                          : null,
                    ),
                  ),
                )
              else
                StaggeredEntry(
                  index: 4,
                  child: _ConversationsCard(convos: convos),
                ),
              SizedBox(height: tier.isHandheld ? 24 : AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  List<Conversation> _filterConversations(List<Conversation> all) {
    switch (_filter) {
      case _ChatFilter.unread:
        return all.where((c) => c.unreadCount > 0).toList();
      case _ChatFilter.online:
        return all.where((c) => c.participant.online).toList();
      case _ChatFilter.all:
        return all;
    }
  }
}

enum _ChatFilter { all, unread, online }

class _ChatHero extends StatelessWidget {
  const _ChatHero({
    required this.totalConversations,
    required this.unread,
    required this.online,
    required this.lastActivity,
  });

  final int totalConversations;
  final int unread;
  final int online;
  final DateTime? lastActivity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = unread > 0;
    final accent = isUnread ? AppColors.warning : AppColors.doctorGreen;
    final iconBg = isUnread
        ? AppPalette.warningSoft(context)
        : AppColors.doctorGreen.withOpacity(0.15);

    final headline = unread == 0
        ? totalConversations == 0
            ? 'Your care chat'
            : 'All caught up'
        : '$unread new message${unread == 1 ? '' : 's'}';

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
                  isUnread ? AppIcons.alert : AppIcons.chat,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppPalette.ink(context),
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
                border: Border.all(color: accent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    AppIcons.time,
                    size: 14,
                    color: AppPalette.textMuted(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Last activity ${_relativeTime(lastActivity!)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _HeroStat(label: 'Chats', value: '$totalConversations'),
              _HeroStatDivider(),
              _HeroStat(
                label: 'Unread',
                value: '$unread',
                accent: unread > 0 ? AppColors.warning : null,
              ),
              _HeroStatDivider(),
              _HeroStat(
                label: 'Online',
                value: '$online',
                accent: online > 0 ? AppColors.success : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                color: accent ?? AppPalette.ink(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      color: AppPalette.border(context),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}

class _ChatQuickActions extends StatelessWidget {
  const _ChatQuickActions({
    required this.filter,
    required this.unread,
    required this.online,
    required this.firstUnreadId,
    required this.onFilter,
  });

  final _ChatFilter filter;
  final int unread;
  final int online;
  final String? firstUnreadId;
  final ValueChanged<_ChatFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: PatientQuickActionsBar(
        children: [
          PatientQuickAction(
            icon: AppIcons.chat,
            label: 'Unread',
            badge: unread > 0 ? '$unread' : null,
            badgeColor: AppColors.warning,
            selected: filter == _ChatFilter.unread,
            onTap: () {
              if (filter == _ChatFilter.unread && firstUnreadId != null) {
                Navigator.of(context).pushNamed(
                  RouteNames.patientChatThread,
                  arguments: firstUnreadId,
                );
                return;
              }
              onFilter(_ChatFilter.unread);
            },
          ),
          PatientQuickAction(
            icon: AppIcons.careTeam,
            label: 'Care team',
            onTap: () => Navigator.of(context)
                .pushNamed(RouteNames.patientCareTeam),
          ),
          PatientQuickAction(
            icon: AppIcons.bell,
            label: 'Alerts',
            onTap: () => Navigator.of(context)
                .pushNamed(RouteNames.patientNotifications),
          ),
          PatientQuickAction(
            icon: AppIcons.user,
            label: 'Online',
            badge: online > 0 ? '$online' : null,
            badgeColor: AppColors.success,
            selected: filter == _ChatFilter.online,
            onTap: () {
              if (filter == _ChatFilter.online && online > 0) {
                final onlineConvo = MessagesState.instance.conversations
                    .where((c) => c.participant.online)
                    .firstOrNull;
                if (onlineConvo != null) {
                  Navigator.of(context).pushNamed(
                    RouteNames.patientChatThread,
                    arguments: onlineConvo.id,
                  );
                }
                return;
              }
              onFilter(_ChatFilter.online);
            },
          ),
        ],
      ),
    );
  }
}

class _ConversationsCard extends StatelessWidget {
  const _ConversationsCard({required this.convos});
  final List<Conversation> convos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newest = convos.first.lastMessage.sentAt;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 8,
                width: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Updated ${_relativeTime(newest)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < convos.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            _ConversationRow(convo: convos[i]),
          ],
        ],
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.convo});
  final Conversation convo;

  Color _avatarColor(int seed) {
    const colors = [
      AppColors.brandIndigo,
      AppColors.doctorGreen,
      AppColors.bpPurple,
      AppColors.glucoseAmber,
    ];
    return colors[seed % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = convo.participant;
    final last = convo.lastMessage;
    final time = _relativeTime(last.sentAt);
    final color = _avatarColor(p.avatarColorSeed);
    final hasUnread = convo.unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(
          RouteNames.patientChatThread,
          arguments: convo.id,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: hasUnread
                ? AppColors.brandIndigo.withOpacity(0.06)
                : AppPalette.surfaceAlt(context).withOpacity(0.5),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: hasUnread
                  ? AppColors.brandIndigo.withOpacity(0.2)
                  : AppPalette.border(context),
            ),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 32,
                    width: 32,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      p.initials,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (p.online)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppPalette.surface(context), width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppPalette.textMuted(context),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (p.specialty != null)
                      Text(
                        p.specialty!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      last.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: hasUnread
                            ? AppPalette.ink(context)
                            : AppPalette.textMuted(context),
                        fontWeight:
                            hasUnread ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasUnread) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandIndigo,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    '${convo.unreadCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 2),
                Icon(
                  AppIcons.chevronRight,
                  size: 14,
                  color: AppPalette.textMuted(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
