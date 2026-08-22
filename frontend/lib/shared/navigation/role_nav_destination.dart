import 'package:flutter/material.dart';

/// One staff side-rail / bottom-rail destination.
class RoleNavDestination {
  const RoleNavDestination({
    required this.icon,
    required this.label,
    required this.route,
    this.badgeCount,
    this.permissionKey,
    this.showInBottomNav = true,
    this.activeRoutes = const <String>{},
  });

  final IconData icon;
  final String label;
  final String route;
  final int? badgeCount;
  final String? permissionKey;
  final bool showInBottomNav;

  /// Legacy/detail routes represented by this parent destination.
  ///
  /// The approved navigation is task-based (Home/Work/People/More), while all
  /// existing named routes remain valid. Parent selection therefore cannot use
  /// exact route equality alone.
  final Set<String> activeRoutes;

  bool isActive(String currentRoute) =>
      route == currentRoute || activeRoutes.contains(currentRoute);
}

/// Optional patient/subject identity shown in the staff header.
class RoleSubjectIdentity {
  const RoleSubjectIdentity({
    required this.name,
    required this.initials,
    this.accent,
    this.onTap,
  });

  final String name;
  final String initials;
  final Color? accent;
  final VoidCallback? onTap;
}
