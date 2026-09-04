import 'package:flutter/material.dart';

/// Root navigator key — required for navigation from [MaterialApp.builder]
/// overlays (e.g. the global Sign in link) that sit above the [Navigator].
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Tracks the active route name for widgets outside the navigator subtree.
///
/// Every callback below asks the same question first: did this happen to the
/// route that is actually on screen? Without that check, the bookkeeping
/// `pushNamedAndRemoveUntil` does — push the new route, then tear out the
/// stack underneath it — reported each discarded route's neighbour as the
/// current one, and reported `null` once the last of them went. So the tracker
/// went blank on exactly the navigation the app uses to change context: a tab
/// switch, a sign-out, landing on a dashboard after launch.
class AppRouteTracker extends NavigatorObserver {
  static String? currentRouteName;

  /// The route [currentRouteName] describes, kept so an event about some other
  /// route in the stack can be recognised and ignored.
  static Route<dynamic>? _current;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _current = route;
    currentRouteName = route.settings.name ?? currentRouteName;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!identical(route, _current)) return;
    _current = previousRoute;
    currentRouteName = previousRoute?.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null && !identical(oldRoute, _current)) return;
    _current = newRoute;
    currentRouteName = newRoute?.settings.name;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!identical(route, _current)) return;
    _current = previousRoute;
    currentRouteName = previousRoute?.settings.name;
  }
}
