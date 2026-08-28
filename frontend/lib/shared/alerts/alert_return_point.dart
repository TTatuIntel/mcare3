import 'package:flutter/widgets.dart';

import '../constants/route_names.dart';
import '../navigation/navigation_roots.dart';

/// Where an alert workflow began, so that finishing it has a defined ending.
///
/// Working an emergency is the one flow in the app that moves the operator
/// somewhere else: tapping "Respond now" on an alert takes ownership and then
/// pushes the SOS hub scoped to that patient. Before this existed, closing the
/// emergency simply left them standing on whichever page the flow had walked
/// them to, with no statement of what had finished or where they had come
/// from — the dashboard they started on was two ambiguous back-taps away.
///
/// A return point is captured when the workflow starts and offered — never
/// forced — when it ends. The operator chooses: go back to where they were,
/// or stay and keep working the queue.
@immutable
class AlertReturnPoint {
  const AlertReturnPoint({
    required this.route,
    required this.label,
    this.arguments,
  });

  /// Named route to return to.
  final String route;

  /// How the destination is described to the operator, e.g. "Dashboard".
  final String label;

  final Object? arguments;

  static AlertReturnPoint? _current;

  /// The pending return point, or null when no workflow is in flight.
  static AlertReturnPoint? get current => _current;

  /// Record where the operator is standing, before a workflow moves them.
  ///
  /// Does nothing when the current route is itself a destination the workflow
  /// would send them to — returning to the page you are already ending on is
  /// not a return, and offering it reads as a bug.
  static void remember(BuildContext context, {String? currentRoute}) {
    final route = NavigationRoots.resolveRoute(context, currentRoute);
    if (route == null || _workflowDestinations.contains(route)) {
      return;
    }
    _current = AlertReturnPoint(route: route, label: labelFor(route));
  }

  static void clear() => _current = null;

  /// Take the operator back, by replacing the current page with the origin.
  ///
  /// Deliberately not `popUntil`: there is no public way to ask whether a
  /// named route is still on the stack, so a predicate that never matches
  /// pops everything and leaves a blank window. A replace always lands on a
  /// real page.
  static void go(BuildContext context) {
    final target = _current;
    if (target == null) return;
    _current = null;
    Navigator.of(
      context,
    ).pushReplacementNamed(target.route, arguments: target.arguments);
  }

  /// Pages an alert workflow can itself land on. Returning to one of these is
  /// never a meaningful ending.
  static const Set<String> _workflowDestinations = {
    RouteNames.doctorSos,
    RouteNames.adminSos,
    RouteNames.assistantSos,
  };

  /// Human name for a route, used in "Back to …".
  static String labelFor(String route) => switch (route) {
    RouteNames.adminDashboard ||
    RouteNames.doctorDashboard ||
    RouteNames.assistantDashboard => 'Dashboard',
    RouteNames.adminWork || RouteNames.assistantWork => 'Work',
    RouteNames.adminPeople || RouteNames.assistantPeople => 'People',
    RouteNames.adminMore ||
    RouteNames.doctorMore ||
    RouteNames.assistantMore => 'More',
    RouteNames.adminPatients ||
    RouteNames.doctorPatients ||
    RouteNames.assistantPatients => 'Patients',
    RouteNames.adminAlerts ||
    RouteNames.doctorAlerts ||
    RouteNames.assistantAlerts => 'Alerts',
    RouteNames.doctorInbox => 'Action inbox',
    _ => 'where you were',
  };
}
