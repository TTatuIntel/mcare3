import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/realtime/session_poller.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/user_role.dart';
import '../navigation/root_navigation_scope.dart';
import '../state/staff_state.dart';
import '../state/support_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/time_greeting.dart';
import '../widgets/app_icons.dart';
import '../widgets/brand_logo.dart';
import '../widgets/critical_event_overlay.dart';
import '../widgets/notification_bell.dart';
import '../widgets/profile_menu_sheet.dart';
import '../widgets/responsive.dart';
import 'staff_hub_data.dart';
import 'staff_hub_models.dart';
import 'staff_hub_pages.dart';

/// Responsive Guided Operations Hub for administrators and delegated human
/// mCare Assistants.
///
/// The hub changes navigation and presentation only. Its cards are read-only
/// summaries and every action opens an existing named route, keeping the
/// established feature screen, guard, validation and API implementation as
/// the workflow owner.
class StaffGuidedOperationsHub extends StatefulWidget {
  const StaffGuidedOperationsHub({
    super.key,
    required this.role,
    required this.currentRoute,
    this.initialSection = StaffHubSection.home,
  }) : assert(
         role == UserRole.admin || role == UserRole.mcareAssistant,
         'The Guided Operations Hub supports Admin and mCare Assistant.',
       );

  final UserRole role;
  final String currentRoute;
  final StaffHubSection initialSection;

  @override
  State<StaffGuidedOperationsHub> createState() =>
      _StaffGuidedOperationsHubState();
}

class _StaffGuidedOperationsHubState extends State<StaffGuidedOperationsHub> {
  late StaffHubSection _section = widget.initialSection;

  void _openSection(StaffHubSection section) {
    if (_section == section) return;
    final route = switch ((widget.role, section)) {
      (UserRole.admin, StaffHubSection.home) => RouteNames.adminDashboard,
      (UserRole.admin, StaffHubSection.work) => RouteNames.adminWork,
      (UserRole.admin, StaffHubSection.people) => RouteNames.adminPeople,
      (UserRole.admin, StaffHubSection.more) => RouteNames.adminMore,
      (UserRole.mcareAssistant, StaffHubSection.home) =>
        RouteNames.assistantDashboard,
      (UserRole.mcareAssistant, StaffHubSection.work) =>
        RouteNames.assistantWork,
      (UserRole.mcareAssistant, StaffHubSection.people) =>
        RouteNames.assistantPeople,
      (UserRole.mcareAssistant, StaffHubSection.more) =>
        RouteNames.assistantMore,
      _ => widget.currentRoute,
    };
    if (route == widget.currentRoute) {
      setState(() => _section = section);
      return;
    }
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return SessionPollerScope(
      child: RootNavigationScope(
        route: widget.currentRoute,
        child: _PermissionSafeEventOverlay(
          role: widget.role,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              AuthState.instance,
              StaffState.instance,
              SupportState.instance,
            ]),
            builder: (context, _) {
              final snapshot = StaffHubData.build(widget.role);
              return _HubScaffold(
                role: widget.role,
                section: _section,
                snapshot: snapshot,
                onSectionChanged: _openSection,
                openRoute: (route) => Navigator.of(context).pushNamed(route),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Every staff role now gets the overlay. The grant check that previously
/// forced this to admin-only moved into [AlertCenter], which filters SOS
/// items by `can_access_emergency_location` — so a delegated Assistant
/// receives vital alerts without gaining emergency-location detail.
class _PermissionSafeEventOverlay extends StatelessWidget {
  const _PermissionSafeEventOverlay({required this.role, required this.child});

  final UserRole role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isStaff =
        role == UserRole.admin ||
        role == UserRole.mcareAssistant ||
        role == UserRole.doctor;
    if (isStaff) return CriticalEventOverlay(child: child);
    return child;
  }
}

class _HubScaffold extends StatelessWidget {
  const _HubScaffold({
    required this.role,
    required this.section,
    required this.snapshot,
    required this.onSectionChanged,
    required this.openRoute,
  });

  final UserRole role;
  final StaffHubSection section;
  final StaffHubSnapshot snapshot;
  final ValueChanged<StaffHubSection> onSectionChanged;
  final StaffRouteOpener openRoute;

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final content = _HubContent(
      role: role,
      section: section,
      snapshot: snapshot,
      onSectionChanged: onSectionChanged,
      openRoute: openRoute,
    );

    final supportRoute = role == UserRole.admin
        ? RouteNames.adminSupport
        : RouteNames.assistantSupport;
    final messagesRoute = role == UserRole.admin
        ? RouteNames.adminMessages
        : RouteNames.assistantMessages;

    void openTickets() => openRoute(supportRoute);
    void openMessages() => openRoute(messagesRoute);

    final messagingFab = FloatingActionButton(
      heroTag: 'staff-hub-messages-fab',
      tooltip: 'Messages',
      onPressed: openMessages,
      backgroundColor: role.accent,
      foregroundColor: Colors.white,
      child: const Icon(AppIcons.chat),
    );

    if (!tier.isMobile) {
      return Scaffold(
        backgroundColor: AppPalette.scaffoldBg(context),
        floatingActionButton: messagingFab,
        body: Row(
          children: [
            _DesktopNavigation(
              role: role,
              selected: section,
              compact: tier.isTablet,
              onSelected: onSectionChanged,
            ),
            Expanded(
              child: Column(
                children: [
                  _HubTopBar(role: role, onOpenTickets: openTickets),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppPalette.scaffoldBg(context),
      appBar: _HubTopBar(role: role, onOpenTickets: openTickets),
      body: content,
      floatingActionButton: messagingFab,
      bottomNavigationBar: _MobileNavigation(
        role: role,
        selected: section,
        onSelected: onSectionChanged,
      ),
    );
  }
}

class _HubContent extends StatelessWidget {
  const _HubContent({
    required this.role,
    required this.section,
    required this.snapshot,
    required this.onSectionChanged,
    required this.openRoute,
  });

  final UserRole role;
  final StaffHubSection section;
  final StaffHubSnapshot snapshot;
  final ValueChanged<StaffHubSection> onSectionChanged;
  final StaffRouteOpener openRoute;

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final horizontal = tier.isMobile
        ? AppSpacing.pageInsetMobile
        : tier.isTablet
        ? AppSpacing.pageInsetTablet
        : AppSpacing.pageInsetDesktop;
    final top = section == StaffHubSection.home
        ? AppSpacing.xl
        : tier.isMobile
        ? AppSpacing.xs
        : AppSpacing.xxl;

    final page = switch (section) {
      StaffHubSection.home => StaffHubHomePage(
        snapshot: snapshot,
        openRoute: openRoute,
        openSection: onSectionChanged,
      ),
      StaffHubSection.work => StaffHubWorkPage(
        snapshot: snapshot,
        openRoute: openRoute,
      ),
      StaffHubSection.people => StaffHubPeoplePage(
        snapshot: snapshot,
        openRoute: openRoute,
      ),
      StaffHubSection.more => StaffHubMorePage(
        snapshot: snapshot,
        openRoute: openRoute,
      ),
    };

    final scrollable = SingleChildScrollView(
      key: PageStorageKey<String>('staff-hub-${section.name}'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1220),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              top,
              horizontal,
              AppSpacing.huge,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(key: ValueKey(section), child: page),
            ),
          ),
        ),
      ),
    );

    if (section != StaffHubSection.home) return scrollable;

    return Stack(
      children: [
        Positioned.fill(child: scrollable),
        Positioned(
          top: AppSpacing.sm,
          left: horizontal,
          right: horizontal,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _WelcomeReveal(
                child: _WelcomePanel(role: role, snapshot: snapshot),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.role, required this.snapshot});

  final UserRole role;
  final StaffHubSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user;
    final firstName = user?.firstName;
    final urgent = snapshot.urgentCount;
    final urgencyColor = urgent > 0 ? AppColors.critical : AppColors.success;
    final urgencyText = urgent > 0
        ? '$urgent urgent ${urgent == 1 ? 'item needs' : 'items need'} attention'
        : 'No urgent items in your visible scope';
    final theme = Theme.of(context);
    final borderColor = AppPalette.border(context).withValues(alpha: 0.55);

    return Semantics(
      container: true,
      label:
          '${timeGreeting(firstName: firstName)}. $urgent urgent items. Current session data.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppPalette.surface(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    timeGreeting(firstName: firstName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppPalette.ink(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Tooltip(
                  message: 'Reading current session data',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Live',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  urgent > 0 ? AppIcons.alert : AppIcons.check,
                  color: urgencyColor,
                  size: 16,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    urgencyText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: urgencyColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    '·  Tap to dismiss',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Time-of-day bucket the welcome banner keys off. Bumping across a bucket
/// boundary (morning → afternoon → evening → night) makes the banner reveal
/// again the next time the Home tab is visited.
int _welcomeBucket(DateTime now) {
  final h = now.hour;
  if (h < 12) return 0; // morning
  if (h < 18) return 1; // afternoon
  if (h < 22) return 2; // evening
  return 3; // night
}

/// Session-scoped memo — reset on app restart. The banner shows once per bucket
/// per session so tab-swaps back to Home don't spam the greeting.
int? _lastRevealedBucket;

/// Wraps the welcome banner so it slides in on entry and collapses out after a
/// short display window, freeing the vertical space for the real content. Only
/// re-reveals when the time-of-day bucket changes since the last show.
class _WelcomeReveal extends StatefulWidget {
  const _WelcomeReveal({required this.child});

  final Widget child;

  static const Duration _visibleFor = Duration(seconds: 5);

  @override
  State<_WelcomeReveal> createState() => _WelcomeRevealState();
}

class _WelcomeRevealState extends State<_WelcomeReveal> {
  Timer? _timer;
  late bool _visible;

  @override
  void initState() {
    super.initState();
    final bucket = _welcomeBucket(DateTime.now());
    _visible = _lastRevealedBucket != bucket;
    if (_visible) {
      _lastRevealedBucket = bucket;
      _timer = Timer(_WelcomeReveal._visibleFor, () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismissNow() {
    if (!_visible) return;
    _timer?.cancel();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _visible
            ? GestureDetector(
                key: const ValueKey('welcome-visible'),
                behavior: HitTestBehavior.opaque,
                onTap: _dismissNow,
                child: widget.child,
              )
            : const SizedBox.shrink(key: ValueKey('welcome-hidden')),
      ),
    );
  }
}

class _HubTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _HubTopBar({required this.role, this.onOpenTickets});

  final UserRole role;

  /// Opens the support / help-desk tickets area. When null the icon is hidden.
  final VoidCallback? onOpenTickets;

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final user = AuthState.instance.user;
    final initials = (user?.initials.trim().isNotEmpty ?? false)
        ? user!.initials.toUpperCase()
        : role.badge;

    return Material(
      color: AppPalette.surface(context),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: preferredSize.height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppPalette.border(context)),
            ),
          ),
          child: Row(
            children: [
              if (tier.isMobile)
                const BrandLogo(
                  height: 30,
                  tappable: false,
                  animateHeartbeat: false,
                  showLifeline: false,
                )
              else
                Text(
                  role == UserRole.admin
                      ? 'Administrator workspace'
                      : 'Delegated assistant workspace',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppPalette.ink(context),
                  ),
                ),
              const Spacer(),
              if (onOpenTickets != null)
                IconButton(
                  tooltip: 'Support tickets',
                  onPressed: onOpenTickets,
                  icon: const Icon(AppIcons.ticket),
                ),
              const NotificationBell(iconSize: 27),
              const SizedBox(width: AppSpacing.xs),
              Semantics(
                button: true,
                label: 'Open account menu',
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  onTap: () => ProfileMenuSheet.show(context),
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: role.accent.withValues(alpha: 0.13),
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: role.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.role,
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  final UserRole role;
  final StaffHubSection selected;
  final bool compact;
  final ValueChanged<StaffHubSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.surface(context),
      child: SafeArea(
        right: false,
        child: Container(
          width: compact ? 80 : 232,
          padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.lg),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: AppPalette.border(context)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                child: compact
                    ? Icon(
                        AppIcons.heartRate,
                        color: role.accent,
                        size: 32,
                        semanticLabel: 'mCare',
                      )
                    : const BrandLogo(
                        height: 36,
                        tappable: false,
                        animateHeartbeat: false,
                        showLifeline: false,
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final destination in StaffHubSection.values) ...[
                _DesktopDestination(
                  destination: destination,
                  selected: selected == destination,
                  accent: role.accent,
                  compact: compact,
                  onTap: () => onSelected(destination),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const Spacer(),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    role.label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: role.accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopDestination extends StatelessWidget {
  const _DesktopDestination({
    required this.destination,
    required this.selected,
    required this.accent,
    required this.compact,
    required this.onTap,
  });

  final StaffHubSection destination;
  final bool selected;
  final Color accent;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.11) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: onTap,
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
                Icon(
                  destination.icon,
                  color: selected ? accent : AppPalette.textMuted(context),
                ),
                if (!compact) ...[
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    destination.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selected ? accent : AppPalette.ink(context),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
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

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({
    required this.role,
    required this.selected,
    required this.onSelected,
  });

  final UserRole role;
  final StaffHubSection selected;
  final ValueChanged<StaffHubSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        indicatorColor: role.accent.withValues(alpha: 0.13),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return Theme.of(context).textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? role.accent
                : AppPalette.textMuted(context),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? role.accent
                : AppPalette.textMuted(context),
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: selected.index,
        onDestinationSelected: (index) =>
            onSelected(StaffHubSection.values[index]),
        destinations: StaffHubSection.values
            .map(
              (destination) => NavigationDestination(
                icon: Icon(destination.icon),
                label: destination.label,
              ),
            )
            .toList(),
      ),
    );
  }
}
