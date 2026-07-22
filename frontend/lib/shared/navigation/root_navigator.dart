import 'package:flutter/material.dart';

/// Root navigator key — required for navigation from [MaterialApp.builder]
/// overlays (e.g. the global Sign in link) that sit above the [Navigator].
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Tracks the active route name for widgets outside the navigator subtree.
class AppRouteTracker extends NavigatorObserver {
  static String? currentRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRouteName = route.settings.name ?? currentRouteName;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRouteName = previousRoute?.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentRouteName = newRoute?.settings.name;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRouteName = previousRoute?.settings.name;
  }
}
