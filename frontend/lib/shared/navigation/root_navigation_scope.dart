import 'package:flutter/material.dart';

import '../navigation/navigation_roots.dart';

/// Ensures root tab routes sit at the top of the navigator stack (no stray
/// drill-down routes underneath that would show a back affordance).
class RootNavigationScope extends StatefulWidget {
  const RootNavigationScope({
    super.key,
    required this.route,
    required this.child,
  });

  final String route;
  final Widget child;

  @override
  State<RootNavigationScope> createState() => _RootNavigationScopeState();
}

class _RootNavigationScopeState extends State<RootNavigationScope> {
  @override
  void initState() {
    super.initState();
    _clean();
  }

  @override
  void didUpdateWidget(RootNavigationScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) _clean();
  }

  void _clean() {
    NavigationRoots.ensureCleanRootStack(context, widget.route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
