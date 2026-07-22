import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/notification_item.dart';
import '../navigation/notification_router.dart';
import '../state/notification_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'app_toast.dart';
import 'empty_state.dart';
import 'glass_card.dart';
import 'section_label.dart';
import 'staff_blocks.dart';

String notificationRelativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Unified hero — same look for patient, doctor, admin, assistant.
class NotificationHero extends StatelessWidget {
  const NotificationHero({
    super.key,
    required this.unread,
    required this.activeCount,
    required this.resolvedCount,
    this.vitalResolvedCount,
  });

  final int unread;
  final int activeCount;
  final int resolvedCount;
  final int? vitalResolvedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = unread > 0;
    final accent = isUnread ? AppColors.warning : AppColors.brandIndigo;
    final iconBg =
        isUnread ? AppPalette.warningSoft(context) : AppPalette.infoSoft(context);
    final headline = isUnread
        ? '$unread notification${unread == 1 ? '' : 's'} need attention'
        : activeCount == 0
            ? 'You\'re all caught up'
            : 'No unread notifications';

    final sub = vitalResolvedCount != null
        ? '$activeCount active · $resolvedCount resolved · $vitalResolvedCount vitals cleared'
        : '$activeCount active · $resolvedCount resolved';

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
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
              isUnread ? AppIcons.alert : AppIcons.bell,
              color: accent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Active / resolved segment control + mark-all-read — shared across roles.
class NotificationSegmentBar extends StatelessWidget {
  const NotificationSegmentBar({
    super.key,
    required this.showResolved,
    required this.activeCount,
    required this.resolvedCount,
    required this.unread,
    required this.onSelectActive,
    required this.onSelectResolved,
    this.onMarkAllRead,
  });

  final bool showResolved;
  final int activeCount;
  final int resolvedCount;
  final int unread;
  final VoidCallback onSelectActive;
  final VoidCallback onSelectResolved;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SegmentChip(
            label: 'Active · $activeCount',
            selected: !showResolved,
            onTap: onSelectActive,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _SegmentChip(
            label: 'Resolved · $resolvedCount',
            selected: showResolved,
            onTap: onSelectResolved,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppButton(
          label: 'Mark all read',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          onPressed: unread == 0 ? null : onMarkAllRead,
        ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brandIndigo
              : AppPalette.surfaceMuted(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected
                    ? Colors.white
                    : AppPalette.textMuted(context),
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

/// Single notification row — one implementation for all roles.
class NotificationListRow extends StatelessWidget {
  const NotificationListRow({super.key, required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.MMMd().add_jm().format(item.createdAt);
    return StaffListRow(
      icon: item.kind.icon,
      iconColor: item.kind.tint,
      title: item.title,
      subtitle: '${item.body}\n$time',
      pill: item.resolved
          ? 'Resolved'
          : (item.read ? null : 'New'),
      pillColor: item.resolved ? AppColors.success : AppColors.info,
      onTap: () => NotificationRouter.handleTap(context, item),
      trailing: item.resolved
          ? null
          : _NotificationRowMenu(
              onMarkRead: item.read
                  ? null
                  : () => NotificationState.instance.markReadRemote(item.id),
              onResolve: () {
                NotificationState.instance.resolveRemote(item.id);
                AppToast.show(context, message: 'Notification resolved.');
              },
            ),
    );
  }
}

class _NotificationRowMenu extends StatelessWidget {
  const _NotificationRowMenu({
    required this.onMarkRead,
    required this.onResolve,
  });

  final VoidCallback? onMarkRead;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(AppIcons.more, size: 20, color: AppPalette.textMuted(context)),
      onSelected: (v) {
        switch (v) {
          case 'read':
            onMarkRead?.call();
            break;
          case 'resolve':
            onResolve();
            break;
        }
      },
      itemBuilder: (_) => [
        if (onMarkRead != null)
          const PopupMenuItem(value: 'read', child: Text('Mark as read')),
        const PopupMenuItem(value: 'resolve', child: Text('Resolve')),
      ],
    );
  }
}

/// Full notifications body — plug into PatientScaffold or RoleShell.
class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({
    super.key,
    this.initialShowResolved = false,
    this.showVitalResolvedCount = false,
  });

  final bool initialShowResolved;
  final bool showVitalResolvedCount;

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  late bool _showResolved;

  @override
  void initState() {
    super.initState();
    _showResolved = widget.initialShowResolved;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationState.instance,
      builder: (context, _) {
        final state = NotificationState.instance;
        final active = state.activeItems;
        final resolved = state.resolvedItems;
        final unread = state.unreadCount;
        final items = _showResolved ? resolved : active;

        if (active.isEmpty && resolved.isEmpty) {
          return GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.bell,
              title: 'You\'re all caught up',
              message:
                  'New alerts and updates will appear here.',
              compact: true,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NotificationHero(
              unread: unread,
              activeCount: active.length,
              resolvedCount: resolved.length,
              vitalResolvedCount: widget.showVitalResolvedCount
                  ? state.resolvedVitalAlertCount
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            NotificationSegmentBar(
              showResolved: _showResolved,
              activeCount: active.length,
              resolvedCount: resolved.length,
              unread: unread,
              onSelectActive: () => setState(() => _showResolved = false),
              onSelectResolved: () => setState(() => _showResolved = true),
              onMarkAllRead: () => NotificationState.instance.markAllReadRemote(),
            ),
            const SizedBox(height: AppSpacing.md),
            SectionLabel(
              title: _showResolved ? 'Resolved' : 'Active',
              icon: _showResolved ? AppIcons.check : AppIcons.bell,
              trailing: items.isEmpty ? null : '${items.length}',
            ),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              GlassCard(
                frosted: true,
                child: EmptyStateView(
                  icon: _showResolved ? AppIcons.check : AppIcons.bell,
                  title: _showResolved
                      ? 'No resolved notifications'
                      : 'No active notifications',
                  message: _showResolved
                      ? 'Cleared items appear here.'
                      : 'New alerts will surface here.',
                  compact: true,
                ),
              )
            else
              StaffListCard(
                children: items
                    .map((n) => NotificationListRow(item: n))
                    .toList(),
              ),
          ],
        );
      },
    );
  }
}
