import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../navigation/profile_navigation.dart';
import '../state/notification_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';

/// One bell for every role. Listens to the shared NotificationState.
///
/// Default tap opens the signed-in user's role inbox via
/// [ProfileNavigation.notificationsRouteFor]. Pass [onTap] to override.
/// Guests / external doctors (no inbox route) are a no-op.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.onTap, this.iconSize = 32});

  final VoidCallback? onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationState.instance,
      builder: (context, _) {
        final count = NotificationState.instance.unreadCount;
        return IconButton(
          splashRadius: 28,
          iconSize: iconSize,
          padding: const EdgeInsets.all(AppSpacing.xs),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'Notifications',
          onPressed: onTap ?? () => _openInbox(context),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(AppIcons.bell, size: iconSize),
              if (count > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: AnimatedScale(
                    scale: 1.0,
                    duration: AppMotion.micro,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      constraints: const BoxConstraints(minWidth: 20),
                      decoration: BoxDecoration(
                        color: AppColors.critical,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: AppPalette.surface(context),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static void _openInbox(BuildContext context) {
    final role = AuthState.instance.user?.role;
    if (role == null) return;
    final route = ProfileNavigation.notificationsRouteFor(role);
    if (route == null) return;
    Navigator.of(context).pushNamed(route);
  }
}
