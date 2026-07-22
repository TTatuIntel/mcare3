import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Standard page transition used app-wide via `Navigator.push(AppPageRoute(...))`.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) : super(
          settings: settings,
          fullscreenDialog: fullscreenDialog,
          transitionDuration: AppMotion.pageFast,
          reverseTransitionDuration: AppMotion.pageFast,
          pageBuilder: (ctx, anim, secondary) => builder(ctx),
          transitionsBuilder: (ctx, anim, secondary, child) {
            final curved =
                CurvedAnimation(parent: anim, curve: AppMotion.easeOut);
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(position: slide, child: child),
            );
          },
        );
}

/// Staggered entrance for dashboard sections and list rows.
///
/// Stateful so parent [AnimatedBuilder] rebuilds do not reset the animation
/// (which previously caused white-screen flicker during state floods).
class StaggeredEntry extends StatefulWidget {
  const StaggeredEntry({
    super.key,
    required this.index,
    required this.child,
    this.totalItems = 6,
  });

  final int index;
  final int totalItems;
  final Widget child;

  @override
  State<StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    final disable = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.itemEntry,
      value: disable ? 1 : 0,
    );
    final curved = CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut);
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curved);

    if (!disable) {
      if (widget.index == 0) {
        _ctrl.forward();
      } else {
        final cap = widget.totalItems.clamp(1, 12);
        final delayMs = (widget.index / cap * AppMotion.entryStagger.inMilliseconds)
            .round();
        Future<void>.delayed(Duration(milliseconds: delayMs), () {
          if (mounted) _ctrl.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _offset, child: widget.child),
      ),
    );
  }
}
