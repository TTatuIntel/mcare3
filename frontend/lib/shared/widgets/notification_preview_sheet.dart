import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts/alert_center.dart';
import '../alerts/urgent_alert_dialog.dart';
import '../auth/auth_state.dart';
import '../models/notification_item.dart';
import '../navigation/notification_router.dart';
import '../navigation/profile_navigation.dart';
import '../state/notification_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'notification_components.dart';

/// Fast, role-aware notification triage opened from the shared bell.
///
/// Urgent clinical work is deliberately separated from ordinary updates: an
/// alert can be read without being acknowledged, and acknowledging is not the
/// same as resolving. Every mutation still goes through the existing shared
/// state/services and every full-list route remains available.
class NotificationPreviewSheet {
  NotificationPreviewSheet._();

  static Future<void> show(BuildContext context) async {
    final role = AuthState.instance.user?.role;
    if (role == null) return;
    final notificationsRoute = ProfileNavigation.notificationsRouteFor(role);
    if (notificationsRoute == null) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final pageContext = navigator.context;
    final height = MediaQuery.sizeOf(pageContext).height;

    await showModalBottomSheet<void>(
      context: pageContext,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      constraints: BoxConstraints(maxWidth: 560, maxHeight: height * 0.88),
      builder: (sheetContext) => _NotificationPreviewBody(
        onOpenAll: () {
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (pageContext.mounted) {
              Navigator.of(pageContext).pushNamed(notificationsRoute);
            }
          });
        },
        onOpenNotification: (notification) {
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (pageContext.mounted) {
              NotificationRouter.handleTap(pageContext, notification);
            }
          });
        },
        onOpenUrgent: (items) {
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!pageContext.mounted) return;
            AlertCenter.instance.forceDue(items.map((item) => item.id));
            unawaited(UrgentAlertDialog.showQueue(pageContext, items));
          });
        },
      ),
    );
  }
}

class _NotificationPreviewBody extends StatelessWidget {
  const _NotificationPreviewBody({
    required this.onOpenAll,
    required this.onOpenNotification,
    required this.onOpenUrgent,
  });

  final VoidCallback onOpenAll;
  final ValueChanged<AppNotification> onOpenNotification;
  final ValueChanged<List<UrgentItem>> onOpenUrgent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.surface(context),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          NotificationState.instance,
          AlertCenter.instance,
        ]),
        builder: (context, _) {
          final notificationState = NotificationState.instance;
          final urgent = AlertCenter.instance.openQueue;
          final duplicateUrgentIds = urgent.map((item) {
            final rawId = item.id.split(':').last;
            return item.isSos ? 'staff_sos_$rawId' : 'staff_alert_$rawId';
          }).toSet();
          final updates = notificationState.activeItems
              .where((item) => !duplicateUrgentIds.contains(item.id))
              .take(6)
              .toList(growable: false);

          return Semantics(
            namesRoute: true,
            label: 'Notification preview',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PreviewHeader(
                  unread: notificationState.unreadCount,
                  onMarkRead: notificationState.unreadCount == 0
                      ? null
                      : () => unawaited(notificationState.markAllReadRemote()),
                ),
                Divider(height: 1, color: AppPalette.border(context)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    children: [
                      if (urgent.isNotEmpty) ...[
                        _UrgentPreview(
                          items: urgent,
                          onOpen: () => onOpenUrgent(urgent),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      _SectionHeading(
                        title: urgent.isEmpty ? 'Needs attention' : 'Updates',
                        count: updates.length,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (updates.isEmpty)
                        _EmptyUpdates(hasUrgent: urgent.isNotEmpty)
                      else
                        for (
                          var index = 0;
                          index < updates.length;
                          index++
                        ) ...[
                          _PreviewNotificationRow(
                            item: updates[index],
                            onTap: () => onOpenNotification(updates[index]),
                          ),
                          if (index < updates.length - 1)
                            Divider(
                              height: 1,
                              indent: 48,
                              color: AppPalette.border(context),
                            ),
                        ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: AppButton(
                    label: 'Open all notifications',
                    icon: AppIcons.notifications,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: onOpenAll,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.unread, required this.onMarkRead});

  final int unread;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.infoSoft(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(
              AppIcons.notificationsActive,
              size: 21,
              color: AppColors.brandIndigo,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  unread == 0
                      ? 'You are caught up'
                      : '$unread unread update${unread == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          if (onMarkRead != null)
            TextButton(onPressed: onMarkRead, child: const Text('Mark read')),
          IconButton(
            tooltip: 'Close notifications',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(AppIcons.close),
          ),
        ],
      ),
    );
  }
}

class _UrgentPreview extends StatelessWidget {
  const _UrgentPreview({required this.items, required this.onOpen});

  final List<UrgentItem> items;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final unattended = items.where((item) => !item.acknowledged).length;
    final hasCritical = items.any(
      (item) => item.isSos || item.kind == UrgentKind.criticalVital,
    );
    final accent = hasCritical ? AppColors.critical : AppColors.warning;

    return Semantics(
      liveRegion: unattended > 0,
      button: true,
      label:
          '$unattended unattended urgent item${unattended == 1 ? '' : 's'}. Open urgent queue.',
      child: Material(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: accent.withValues(alpha: 0.34)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(AppIcons.alert, size: 18, color: accent),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Urgent care queue',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            unattended > 0
                                ? '$unattended not yet acknowledged'
                                : '${items.length} owned and still open',
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(color: accent),
                          ),
                        ],
                      ),
                    ),
                    Icon(AppIcons.chevronRight, color: accent),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final item in items.take(2))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${item.patientName} · ${item.title} · '
                            '${notificationRelativeTime(item.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (items.length > 2)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '+${items.length - 2} more urgent',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PreviewNotificationRow extends StatelessWidget {
  const _PreviewNotificationRow({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = item.kind.tint;
    return Semantics(
      button: true,
      label:
          '${item.read ? '' : 'Unread. '}${item.title}. ${item.body}. ${notificationRelativeTime(item.createdAt)}.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(item.kind.icon, size: 19, color: accent),
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
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          notificationRelativeTime(item.createdAt),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppPalette.textMuted(context),
                                fontSize: 10,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (!item.read)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.info,
                    shape: BoxShape.circle,
                  ),
                )
              else
                Icon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: AppPalette.textFaint(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyUpdates extends StatelessWidget {
  const _EmptyUpdates({required this.hasUrgent});

  final bool hasUrgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.surfaceMuted(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            hasUrgent ? AppIcons.info : AppIcons.check,
            size: 18,
            color: hasUrgent ? AppColors.info : AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              hasUrgent
                  ? 'No other updates are waiting.'
                  : 'No active notifications. You are caught up.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
