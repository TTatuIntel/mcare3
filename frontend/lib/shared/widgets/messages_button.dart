import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../navigation/profile_navigation.dart';
import '../state/messages_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';

/// Messaging entry point for every role — sits beside the [NotificationBell]
/// in the app header so chat is never buried behind a "More" menu.
///
/// Listens to the shared [MessagesState] and badges the icon with the total
/// unread count. Default tap opens the signed-in user's messages list via
/// [ProfileNavigation.messagesRouteFor]. Pass [onTap] to override. Roles
/// without a messages route (guest / external doctor) render nothing.
class MessagesButton extends StatelessWidget {
  const MessagesButton({super.key, this.onTap, this.iconSize = 28});

  final VoidCallback? onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final role = AuthState.instance.user?.role;
    final route = role == null
        ? null
        : ProfileNavigation.messagesRouteFor(role);
    if (onTap == null && route == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: MessagesState.instance,
      builder: (context, _) {
        final count = MessagesState.instance.totalUnread;
        return IconButton(
          splashRadius: 28,
          iconSize: iconSize,
          padding: const EdgeInsets.all(AppSpacing.xs),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'Messages',
          onPressed: onTap ?? () => Navigator.of(context).pushNamed(route!),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(AppIcons.chat, size: iconSize),
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
}
