import 'package:flutter/material.dart';

import '../../core/realtime/session_poller.dart';
import '../constants/route_names.dart';
import '../navigation/navigation_roots.dart';
import '../navigation/root_navigation_scope.dart';
import '../services/patient_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_toast.dart';
import 'bubble_background.dart';
import 'patient_app_header.dart';
import 'patient_bottom_nav.dart';
import 'patient_ui_scope.dart';
import 'responsive.dart';

/// Single scaffold patient screens render into. Handles:
///  - mobile: header + bottom nav
///  - tablet: header + bottom nav with wider content
///  - desktop: side rail + header + content (no bottom nav)
class PatientScaffold extends StatelessWidget {
  static const double _desktopPageInset = 25;

  const PatientScaffold({
    super.key,
    required this.currentRoute,
    required this.body,
    this.title,
    this.subtitle,
    this.headerActions,
    this.floatingActionButton,
    this.maxContentWidth = 1360,
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

  Future<void> _refresh(BuildContext context) async {
    try {
      await PatientSessionService.instance.syncFromApi();
    } catch (_) {
      if (context.mounted) {
        AppToast.warn(
          context,
          'Could not refresh right now. Your last synced information is still available.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final isHome = NavigationRoots.isPrimaryHome(currentRoute);

    // A tab switch replaces the whole stack, so on a hub tab there is nothing
    // left to pop and a system back would close the app. Android users expect
    // it to land on Home first, so the pop is blocked and redirected there.
    final isTabHub =
        !isHome &&
        PatientBottomNav.destinations.any((d) => d.route == currentRoute);

    void popToHome(bool didPop, Object? _) {
      if (didPop || !isTabHub) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(RouteNames.patientDashboard, (_) => false);
    }

    final pad =
        padding ??
        EdgeInsets.symmetric(
          horizontal: tier.isMobile
              ? AppSpacing.pageInsetMobile
              : tier.isTablet
              ? AppSpacing.pageInsetTablet
              : _desktopPageInset,
          vertical: AppSpacing.lg,
        );

    final centered = Center(
      child: ConstrainedBox(
        // Patient pages should use all of the workspace beside the desktop
        // rail. Width caps remain useful on tablet, where several focused
        // hubs deliberately request a narrower composition.
        constraints: BoxConstraints(
          maxWidth: tier.isDesktop ? double.infinity : maxContentWidth,
        ),
        child: Padding(padding: pad, child: body),
      ),
    );

    final scrollBody = scrollable
        ? RefreshIndicator(
            onRefresh: () => _refresh(context),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: centered,
            ),
          )
        : centered;

    final surface = AppPalette.scaffoldBg(context);

    if (!tier.isMobile) {
      return SessionPollerScope(
        child: PatientUiScope(
          child: _PatientDesktopScaler(
            enabled: tier.isDesktop,
            child: RootNavigationScope(
              route: currentRoute,
              child: PopScope(
                canPop: !isHome && !isTabHub,
                onPopInvokedWithResult: popToHome,
                child: Scaffold(
                  backgroundColor: surface,
                  body: Row(
                    children: [
                      PatientSideRail(
                        currentRoute: currentRoute,
                        compact: tier.isTablet,
                      ),
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
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Container(
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: AppPalette.surface(context),
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusLg,
                                    ),
                                    border: Border.all(
                                      color: AppPalette.border(
                                        context,
                                      ).withValues(alpha: 0.6),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: BubbleBackground(
                                    bubbleCount: 5,
                                    surfaceColor: AppPalette.surface(context),
                                    child: scrollBody,
                                  ),
                                ),
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
        ),
      );
    }

    return SessionPollerScope(
      child: PatientUiScope(
        child: RootNavigationScope(
          route: currentRoute,
          child: PopScope(
            canPop: !isHome && !isTabHub,
            onPopInvokedWithResult: popToHome,
            child: Scaffold(
              backgroundColor: surface,
              appBar: PatientAppHeader(
                title: title,
                subtitle: subtitle,
                actions: headerActions,
                currentRoute: currentRoute,
              ),
              body: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppPalette.surface(context),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(
                      color: AppPalette.border(context).withValues(alpha: 0.6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: BubbleBackground(
                    bubbleCount: 5,
                    surfaceColor: AppPalette.surface(context),
                    child: scrollBody,
                  ),
                ),
              ),
              bottomNavigationBar: detachedNav
                  ? const PatientBottomNav.detached()
                  : PatientBottomNav(currentRoute: currentRoute),
              floatingActionButton: floatingActionButton,
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlarges the complete patient shell as wide desktop viewports grow.
///
/// Scaling the shell as one unit keeps type, icons, controls, cards, spacing,
/// the header, and the navigation rail in the same visual proportion. The
/// logical viewport is reduced by the inverse scale so layout and hit testing
/// continue to match what is painted.
class _PatientDesktopScaler extends StatelessWidget {
  const _PatientDesktopScaler({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  static const double _baselineWidth = 1600;
  static const double _maximumScale = 1.1;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / _baselineWidth).clamp(
          1.0,
          _maximumScale,
        );
        if (scale == 1.0) return child;

        final logicalSize = Size(
          constraints.maxWidth / scale,
          constraints.maxHeight / scale,
        );
        final mediaQuery = MediaQuery.of(context);

        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: logicalSize,
                child: MediaQuery(
                  data: mediaQuery.copyWith(size: logicalSize),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
