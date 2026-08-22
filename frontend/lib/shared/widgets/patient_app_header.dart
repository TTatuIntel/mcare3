import 'package:flutter/material.dart';

import '../utils/time_greeting.dart';
import '../widgets/app_icons.dart';
import '../navigation/navigation_roots.dart';
import '../auth/auth_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'notification_bell.dart';
import 'profile_menu_sheet.dart';

/// Patient-side header. Same on every patient screen.
class PatientAppHeader extends StatelessWidget implements PreferredSizeWidget {
  const PatientAppHeader({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.elevated = false,
    this.currentRoute,
  });

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final bool elevated;
  final String? currentRoute;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user;
    final canPop = Navigator.canPop(context);
    final route = NavigationRoots.resolveRoute(context, currentRoute);
    final showBack = NavigationRoots.shouldShowBack(
      canPop: canPop,
      currentRoute: route,
      context: context,
    );
    final onPrimaryHome = NavigationRoots.isPrimaryHome(route);
    return Material(
      color: AppPalette.surface(context),
      elevation: elevated ? 1 : 0,
      shadowColor: Colors.black12,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              if (leading != null)
                Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: leading!)
              else if (showBack)
                _BackButton(
                  onTap: () => NavigationRoots.smartBack(
                    context,
                    currentRoute: route,
                  ),
                )
              else
                _Avatar(onTap: () => ProfileMenuSheet.show(context)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title ?? timeGreeting(firstName: user?.firstName),
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else if (user != null)
                      Text(
                        'How are you feeling today?',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (actions != null && !onPrimaryHome) ...actions!,
              const NotificationBell(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        height: 42,
        width: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppPalette.border(context).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Icon(
          AppIcons.backIos,
          size: 18,
          color: AppPalette.ink(context),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user;
    final accent = user?.role.accent ?? AppColors.brandIndigo;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        height: 42,
        width: 42,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, accent.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        alignment: Alignment.center,
        child: Text(
          user?.initials ?? '··',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
