import 'package:flutter/material.dart';

import '../../core/realtime/session_poller.dart';
import '../navigation/navigation_roots.dart';
import '../navigation/root_navigation_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'bubble_background.dart';
import 'patient_app_header.dart';
import 'patient_bottom_nav.dart';
import 'responsive.dart';

/// Single scaffold patient screens render into. Handles:
///  - mobile: header + bottom nav
///  - tablet: header + bottom nav with wider content
///  - desktop: side rail + header + content (no bottom nav)
class PatientScaffold extends StatelessWidget {
  const PatientScaffold({
    super.key,
    required this.currentRoute,
    required this.body,
    this.title,
    this.subtitle,
    this.headerActions,
    this.floatingActionButton,
    this.maxContentWidth = 1180,
    this.scrollable = true,
    this.padding,
    this.detachedNav = false,
  });

  final String currentRoute;
  final Widget body;
  final String? title;
  final String? subtitle;
  final List<Widget>? headerActions;
  final Widget? floatingActionButton;
  final double maxContentWidth;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;
  final bool detachedNav;

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final isHome = NavigationRoots.isPrimaryHome(currentRoute);

    final pad = padding ??
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
                parent: AlwaysScrollableScrollPhysics()),
            child: centered,
          )
        : centered;

    final surface = AppPalette.scaffoldBg(context);

    if (tier.isDesktop) {
      return SessionPollerScope(
        child: RootNavigationScope(
          route: currentRoute,
          child: PopScope(
            canPop: !isHome,
            child: Scaffold(
          backgroundColor: surface,
          body: Row(
            children: [
              PatientSideRail(currentRoute: currentRoute),
              Expanded(
                child: Column(
                  children: [
                    PatientAppHeader(
                      title: title,
                      subtitle: subtitle,
                      actions: headerActions,
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
      );
    }

    return SessionPollerScope(
      child: RootNavigationScope(
        route: currentRoute,
        child: PopScope(
          canPop: !isHome,
          child: Scaffold(
        backgroundColor: surface,
        appBar: PatientAppHeader(
          title: title,
          subtitle: subtitle,
          actions: headerActions,
          currentRoute: currentRoute,
        ),
        body: BubbleBackground(
          bubbleCount: 5,
          surfaceColor: surface,
          child: scrollBody,
        ),
        bottomNavigationBar: detachedNav
            ? const PatientBottomNav.detached()
            : PatientBottomNav(currentRoute: currentRoute),
        floatingActionButton: floatingActionButton,
          ),
        ),
      ),
    );
  }
}
