import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/async/app_busy.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import 'mcare_loading_mark.dart';

/// On-screen "working on it" indicator.
///
/// Appears over the content area — not inside the control the user pressed —
/// whenever a user-initiated write ([AppBusy.isMutating]) outlives
/// [AppMotion.loaderDelay]. Sign in, save, submit, delete: the button keeps
/// its label and goes quiet, and this is what tells the user the app is busy.
///
/// It absorbs input while visible, which also makes double-submits impossible.
/// Background polling and ordinary screen reads never trigger it.
///
/// Mount once, around the app's `child` in `MaterialApp.builder`.
class McareBusyOverlay extends StatefulWidget {
  const McareBusyOverlay({
    super.key,
    required this.child,
    this.delay = AppMotion.loaderDelay,
    this.minVisible = AppMotion.loaderMinVisible,
  });

  final Widget child;
  final Duration delay;
  final Duration minVisible;

  @override
  State<McareBusyOverlay> createState() => _McareBusyOverlayState();
}

class _McareBusyOverlayState extends State<McareBusyOverlay> {
  Timer? _showTimer;
  Timer? _hideTimer;
  bool _visible = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    AppBusy.instance.addListener(_onBusyChanged);
    if (AppBusy.instance.isMutating) _scheduleShow();
  }

  @override
  void dispose() {
    AppBusy.instance.removeListener(_onBusyChanged);
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onBusyChanged() {
    if (!mounted) return;
    if (AppBusy.instance.isMutating) {
      _scheduleShow();
    } else {
      _scheduleHide();
    }
  }

  void _scheduleShow() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_visible) return;
    _showTimer?.cancel();
    _showTimer = Timer(widget.delay, () {
      if (!mounted || !AppBusy.instance.isMutating) return;
      setState(() {
        _visible = true;
        _shownAt = DateTime.now();
      });
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _showTimer = null;
    if (!_visible) return;

    final shownAt = _shownAt;
    final elapsed =
        shownAt == null ? widget.minVisible : DateTime.now().difference(shownAt);
    final remaining = widget.minVisible - elapsed;

    void hide() {
      if (!mounted || AppBusy.instance.isMutating) return;
      setState(() => _visible = false);
    }

    if (remaining <= Duration.zero) {
      hide();
      return;
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(remaining, hide);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_visible)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.crossFade,
              curve: AppMotion.easeOut,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              // Absorbs taps, so the user cannot fire the same action twice.
              child: const _BusyScrim(),
            ),
          ),
      ],
    );
  }
}

class _BusyScrim extends StatelessWidget {
  const _BusyScrim();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AbsorbPointer(
      child: ColoredBox(
        color: (dark ? AppColors.darkScaffoldBg : AppColors.scaffoldBg)
            .withValues(alpha: 0.72),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                color: dark ? AppColors.darkBorder : AppColors.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.42 : 0.10),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.xl,
              ),
              child: McareLoadingMark(size: McareMarkSize.medium),
            ),
          ),
        ),
      ),
    );
  }
}
