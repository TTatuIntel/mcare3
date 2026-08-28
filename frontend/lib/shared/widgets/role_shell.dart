import 'package:flutter/material.dart';

export '../navigation/role_nav_destination.dart';
import '../navigation/navigation_roots.dart';
import '../navigation/role_nav_destination.dart';
import '../navigation/root_navigation_scope.dart';
import '../../core/realtime/session_poller.dart';
import '../auth/auth_state.dart';
import '../models/user_role.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'brand_logo.dart';
import 'bubble_background.dart';
import 'critical_event_overlay.dart';
import 'messages_button.dart';
import 'notification_bell.dart';
import '../utils/time_greeting.dart';
import 'profile_menu_sheet.dart';
import 'responsive.dart';

/// A compact, semantic page action rendered in the staff header on narrow
/// screens. Pages may keep their full [headerActions] for wide layouts while
/// exposing the same command without sacrificing the back button on mobile.
class RoleHeaderAction {
  const RoleHeaderAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

/// One scaffold every staff role renders into.
///
/// Implements §5.3 of the documentation: avatar, role badge, back chip,
/// bell, bottom rail (mobile) → side rail (desktop). Same destinations,
/// same icons, same guard logic — only the *content* and accent differ
/// between roles.
class RoleShell extends StatelessWidget {
  const RoleShell({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.body,
    this.title,
    this.subtitle,
    this.headerActions,
    this.headerMenuActions = const <RoleHeaderAction>[],
    this.floatingActionButton,
    this.maxContentWidth = 1360,
    this.scrollable = true,
    this.padding,
    this.bottomRailVisible = true,
    this.profileRoute,
    this.notificationsRoute,
    this.subjectIdentity,
  });

  /// Active route name — used to highlight the matching rail item.
  final String currentRoute;

  /// Destinations for the rail. mCare Assistant items are auto-filtered
  /// using their `permissionKey`.
  final List<RoleNavDestination> destinations;

  /// Main screen content.
  final Widget body;

  final String? title;
  final String? subtitle;
  final List<Widget>? headerActions;
  final List<RoleHeaderAction> headerMenuActions;
  final Widget? floatingActionButton;
  final double maxContentWidth;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;
  final bool bottomRailVisible;

  /// Override the default profile / notifications routes (e.g. doctor vs admin).
  final String? profileRoute;
  final String? notificationsRoute;
  final RoleSubjectIdentity? subjectIdentity;

  @override
  Widget build(BuildContext context) {
    // Rebuild the shell (and its permission-filtered nav) whenever the
    // assistant's grants change, so revoked destinations disappear live.
    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final visible = _visibleDestinations();
    // Block the system back gesture on dashboard home screens. When a
    // drill-down was opened directly, intercept the gesture and use its
    // declared parent hub instead of allowing the platform to close the app.
    final isHome = NavigationRoots.isPrimaryHome(currentRoute);
    final hasHistory = Navigator.canPop(context);
    final hasParentFallback = NavigationRoots.parentFor(currentRoute) != null;
    final platformCanPop = !isHome && (hasHistory || !hasParentFallback);

    final pad =
        padding ??
        EdgeInsets.symmetric(
          horizontal: tier.isMobile
              ? AppSpacing.pageInsetMobile
              : tier.isTablet
              ? AppSpacing.pageInsetTablet
              : AppSpacing.pageInsetDesktop,
          vertical: AppSpacing.lg,
        );

    final centered = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: Padding(padding: pad, child: body),
      ),
    );

    final scrollBody = scrollable
        ? SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: centered,
          )
        : centered;

    final surface = AppPalette.scaffoldBg(context);

    if (!tier.isMobile) {
      return SessionPollerScope(
        child: _StaffNavigationScope(
          route: currentRoute,
          child: PopScope(
            canPop: platformCanPop,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && !isHome && hasParentFallback) {
                NavigationRoots.smartBack(context, currentRoute: currentRoute);
              }
            },
            child: CriticalEventOverlay(
              currentRoute: currentRoute,
              child: Scaffold(
                backgroundColor: surface,
                body: Row(
                  children: [
                    _SideRail(
                      destinations: visible,
                      currentRoute: currentRoute,
                      compact: tier.isTablet,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _StaffHeader(
                            title: title,
                            subtitle: subtitle,
                            actions: headerActions,
                            menuActions: headerMenuActions,
                            notificationsRoute: notificationsRoute,
                            subjectIdentity: subjectIdentity,
                            currentRoute: currentRoute,
                          ),
                          Expanded(
                            child: BubbleBackground(
                              bubbleCount: 5,
                              surfaceColor: surface,
                              child: scrollBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                floatingActionButton: floatingActionButton,
              ),
            ),
          ),
        ),
      );
    }

    return SessionPollerScope(
      child: _StaffNavigationScope(
        route: currentRoute,
        child: PopScope(
          canPop: platformCanPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !isHome && hasParentFallback) {
              NavigationRoots.smartBack(context, currentRoute: currentRoute);
            }
          },
          child: CriticalEventOverlay(
            currentRoute: currentRoute,
            child: Scaffold(
              backgroundColor: surface,
              appBar: _StaffHeader(
                title: title,
                subtitle: subtitle,
                actions: headerActions,
                menuActions: headerMenuActions,
                notificationsRoute: notificationsRoute,
                subjectIdentity: subjectIdentity,
                currentRoute: currentRoute,
              ),
              body: BubbleBackground(
                bubbleCount: 5,
                surfaceColor: surface,
                child: scrollBody,
              ),
              bottomNavigationBar: bottomRailVisible
                  ? _BottomRail(
                      destinations: visible,
                      currentRoute: currentRoute,
                    )
                  : null,
              floatingActionButton: floatingActionButton,
            ),
          ),
        ),
      ),
    );
  }

  List<RoleNavDestination> _visibleDestinations() {
    // A destination is shown when it carries no permission key, or when the
    // signed-in user holds that grant. Admins pass every check; assistants are
    // filtered to their delegated grants (which refresh live via the poller).
    return destinations
        .where(
          (d) => d.permissionKey == null || _hasPermission(d.permissionKey!),
        )
        .toList();
  }

  bool _hasPermission(String key) =>
      AuthState.instance.hasAssistantPermission(key);
}

/// Routes with an explicit parent are drill-downs even when retained in the
/// legacy root-route set. Keeping their parent route in the stack preserves
/// hub scroll/filter state and gives native Back the same result as header
/// Back. True tab roots still receive the normal stack cleanup.
class _StaffNavigationScope extends StatelessWidget {
  const _StaffNavigationScope({required this.route, required this.child});

  final String route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (NavigationRoots.parentFor(route) != null) return child;
    return RootNavigationScope(route: route, child: child);
  }
}

class _StaffHeader extends StatelessWidget implements PreferredSizeWidget {
  const _StaffHeader({
    this.title,
    this.subtitle,
    this.actions,
    this.menuActions = const <RoleHeaderAction>[],
    this.notificationsRoute,
    this.subjectIdentity,
    this.currentRoute,
  });

  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final List<RoleHeaderAction> menuActions;
  final String? notificationsRoute;
  final RoleSubjectIdentity? subjectIdentity;
  final String? currentRoute;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user;
    final canPop = Navigator.canPop(context);
    final route = NavigationRoots.resolveRoute(context, currentRoute);
    final showBack =
        NavigationRoots.shouldShowBack(
          canPop: canPop,
          currentRoute: route,
          context: context,
        ) ||
        (!NavigationRoots.isPrimaryHome(route) &&
            NavigationRoots.parentFor(route) != null);
    final onPrimaryHome = NavigationRoots.isPrimaryHome(route);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final effectiveSubject = showBack || onPrimaryHome ? null : subjectIdentity;
    final effectiveActions =
        onPrimaryHome || (compact && menuActions.isNotEmpty) ? null : actions;
    final effectiveMenuActions = onPrimaryHome
        ? const <RoleHeaderAction>[]
        : menuActions;
    return Material(
      color: AppPalette.surface(context),
      elevation: 0,
      shadowColor: Colors.black12,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              if (showBack)
                _BackButton(
                  onTap: () =>
                      NavigationRoots.smartBack(context, currentRoute: route),
                )
              else if (effectiveSubject != null)
                _SubjectAvatar(identity: effectiveSubject)
              else
                _Avatar(onTap: () => ProfileMenuSheet.show(context)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: InkWell(
                  onTap: showBack ? null : effectiveSubject?.onTap,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
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
                        else if (user != null && effectiveSubject == null)
                          Text(
                            '${user.role.label} · ${user.uniqueId}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              ...?effectiveActions,
              if (compact && effectiveMenuActions.isNotEmpty)
                _HeaderActionMenu(actions: effectiveMenuActions),
              const MessagesButton(),
              const NotificationBell(),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderActionMenu extends StatelessWidget {
  const _HeaderActionMenu({required this.actions});

  final List<RoleHeaderAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.length == 1) {
      final action = actions.single;
      return IconButton(
        tooltip: action.label,
        onPressed: action.onPressed,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(action.icon, size: 21),
      );
    }

    return PopupMenuButton<int>(
      tooltip: 'Page actions',
      icon: const Icon(AppIcons.more, size: 22),
      onSelected: (index) => actions[index].onPressed?.call(),
      itemBuilder: (context) => [
        for (var index = 0; index < actions.length; index++)
          PopupMenuItem<int>(
            value: index,
            enabled: actions[index].onPressed != null,
            child: Row(
              children: [
                Icon(actions[index].icon, size: 19),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(actions[index].label)),
              ],
            ),
          ),
      ],
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
            colors: [accent, accent.withValues(alpha: 0.7)],
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

class _SubjectAvatar extends StatelessWidget {
  const _SubjectAvatar({required this.identity});
  final RoleSubjectIdentity identity;

  @override
  Widget build(BuildContext context) {
    final accent = identity.accent ?? AppColors.doctorGreen;
    return InkWell(
      onTap: identity.onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        height: 42,
        width: 42,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, accent.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        alignment: Alignment.center,
        child: Text(
          identity.initials,
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

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('staff-header-back'),
      button: true,
      label: 'Back',
      child: InkWell(
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
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.destinations,
    required this.currentRoute,
    required this.compact,
  });

  final List<RoleNavDestination> destinations;
  final String currentRoute;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user;
    return Container(
      width: compact ? 80 : 232,
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        border: Border(right: BorderSide(color: AppPalette.border(context))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.lg : AppSpacing.xl,
                AppSpacing.xl,
                compact ? AppSpacing.lg : AppSpacing.xl,
                AppSpacing.md,
              ),
              child: compact
                  ? Icon(
                      AppIcons.heartRate,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                      semanticLabel: 'mCare',
                    )
                  : const BrandLogo(height: BrandLogo.railHeight),
            ),
            if (user != null && !compact) _RoleBadge(role: user.role),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: destinations
                    .map(
                      (d) => _RailItem(
                        destination: d,
                        selected: d.isActive(currentRoute),
                        compact: compact,
                        onTap: () => _activateDestination(
                          context,
                          destination: d,
                          currentRoute: currentRoute,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _BottomRail extends StatelessWidget {
  const _BottomRail({required this.destinations, required this.currentRoute});

  final List<RoleNavDestination> destinations;
  final String currentRoute;

  static const int _maxVisible = 5;

  @override
  Widget build(BuildContext context) {
    final allShown = destinations.where((d) => d.showInBottomNav).toList();
    final hasMore = allShown.length > _maxVisible;
    // When overflow exists reserve last slot for "More" button.
    final primary = hasMore
        ? allShown.take(_maxVisible - 1).toList()
        : allShown;
    final primaryRoutes = primary.map((d) => d.route).toSet();
    final overflowActive =
        hasMore &&
        !primaryRoutes.contains(currentRoute) &&
        allShown.any((d) => d.isActive(currentRoute));

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        border: Border(top: BorderSide(color: AppPalette.border(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ...primary.map(
                (d) => _BottomNavItem(
                  destination: d,
                  selected: d.isActive(currentRoute),
                  onTap: () => _activateDestination(
                    context,
                    destination: d,
                    currentRoute: currentRoute,
                  ),
                ),
              ),
              if (hasMore)
                _buildMoreItem(
                  context,
                  destinations: allShown,
                  selected: overflowActive,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "More" tab — shown when there are more nav destinations than [_maxVisible].
  Widget _buildMoreItem(
    BuildContext context, {
    required List<RoleNavDestination> destinations,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final color = selected ? accent : AppPalette.textMuted(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: () => _openMoreSheet(context, destinations),
        child: AnimatedContainer(
          duration: AppMotion.micro,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AppMotion.micro,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Icon(AppIcons.more, color: color, size: 22),
              ),
              const SizedBox(height: 4),
              Text(
                'More',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMoreSheet(
    BuildContext context,
    List<RoleNavDestination> destinations,
  ) async {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    // Await sheet result — never pop+push in the same frame (Flutter web).
    final selectedRoute = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Material(
            color: AppPalette.surface(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Text(
                    'Navigation',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ...destinations.map((d) {
                  final isActive = d.isActive(currentRoute);
                  return InkWell(
                    onTap: () => Navigator.of(ctx).pop(d.route),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            d.icon,
                            size: 20,
                            color: isActive
                                ? accent
                                : AppPalette.textMuted(context),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              d.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isActive
                                    ? AppPalette.ink(context)
                                    : AppPalette.textMuted(context),
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isActive)
                            Icon(AppIcons.checkMark, size: 16, color: accent),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );

    if (selectedRoute == null ||
        selectedRoute.isEmpty ||
        selectedRoute == currentRoute) {
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(selectedRoute, (_) => false);
  }
}

/// Activates one of the persistent staff navigation destinations.
///
/// Tapping the selected parent tab from one of its drill-down pages should
/// return to the existing hub when that hub is in the stack. A directly opened
/// deep link has no such parent route, so the search must stop safely at the
/// first route and then install the requested hub as the new root. This keeps
/// the bottom and side navigation responsive without risking an unbounded
/// [Navigator.popUntil] search for a route that is not present.
void _activateDestination(
  BuildContext context, {
  required RoleNavDestination destination,
  required String currentRoute,
}) {
  if (destination.route == currentRoute) return;

  final navigator = Navigator.of(context);
  if (destination.isActive(currentRoute) && navigator.canPop()) {
    var foundParent = false;
    navigator.popUntil((route) {
      if (route.settings.name == destination.route) {
        foundParent = true;
        return true;
      }
      return route.isFirst;
    });
    if (foundParent) return;
  }

  navigator.pushNamedAndRemoveUntil(destination.route, (_) => false);
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final RoleNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final color = selected ? accent : AppPalette.textMuted(context);
    return Expanded(
      child: Semantics(
        key: ValueKey('staff-bottom-nav:${destination.route}'),
        button: true,
        selected: selected,
        label: '${destination.label} navigation tab',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.micro,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.micro,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? accent.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusPill,
                        ),
                      ),
                      child: Icon(destination.icon, color: color, size: 22),
                    ),
                    if ((destination.badgeCount ?? 0) > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: _Badge(count: destination.badgeCount!),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.onTap,
  });
  final RoleNavDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final color = selected ? accent : AppPalette.textMuted(context);
    final item = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 2,
      ),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(destination.icon, color: color, size: 20),
                if (!compact) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: selected ? AppPalette.ink(context) : color,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if ((destination.badgeCount ?? 0) > 0)
                    _Badge(count: destination.badgeCount!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!compact) return item;
    return Tooltip(message: destination.label, child: item);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      decoration: BoxDecoration(
        color: AppColors.critical,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: role.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 18,
              width: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: role.accent,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                role.badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              role.label,
              style: TextStyle(
                color: role.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
