import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import 'mcare_pulse.dart';

/// Shows a loading indicator **only when the wait is long enough to notice**.
///
/// Two rules, both of which exist to stop the UI flickering:
///
/// * **Delay gate** — nothing appears until [isLoading] has been true for
///   [delay]. A request that resolves in 80 ms never flashes a spinner.
/// * **Minimum visible** — once the indicator *has* appeared it stays for at
///   least [minVisible], so it can never blink in and out in one frame.
///
/// While the gate is still closed the existing [child] keeps rendering, so a
/// refresh shows slightly stale content rather than a blank page.
class DelayedLoader extends StatefulWidget {
  const DelayedLoader({
    super.key,
    required this.isLoading,
    required this.child,
    this.placeholder,
    this.delay = AppMotion.loaderDelay,
    this.minVisible = AppMotion.loaderMinVisible,
    this.transition = AppMotion.crossFade,
  });

  final bool isLoading;

  /// Real content. Stays on screen during the delay gate.
  final Widget child;

  /// What to show once the gate opens. Defaults to a centred [McarePulse].
  final Widget? placeholder;

  final Duration delay;
  final Duration minVisible;
  final Duration transition;

  @override
  State<DelayedLoader> createState() => _DelayedLoaderState();
}

class _DelayedLoaderState extends State<DelayedLoader> {
  Timer? _showTimer;
  Timer? _hideTimer;
  bool _visible = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    if (widget.isLoading) _scheduleShow();
  }

  @override
  void didUpdateWidget(DelayedLoader old) {
    super.didUpdateWidget(old);
    if (widget.isLoading == old.isLoading) return;
    if (widget.isLoading) {
      _scheduleShow();
    } else {
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleShow() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_visible) return; // Already up from a previous cycle — keep it.
    _showTimer?.cancel();
    _showTimer = Timer(widget.delay, () {
      if (!mounted || !widget.isLoading) return;
      setState(() {
        _visible = true;
        _shownAt = DateTime.now();
      });
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _showTimer = null;
    if (!_visible) return; // Gate never opened — nothing to take down.

    final shownAt = _shownAt;
    final elapsed =
        shownAt == null ? widget.minVisible : DateTime.now().difference(shownAt);
    final remaining = widget.minVisible - elapsed;

    if (remaining <= Duration.zero) {
      setState(() => _visible = false);
      return;
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(remaining, () {
      if (!mounted || widget.isLoading) return;
      setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: widget.transition,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      child: _visible
          ? KeyedSubtree(
              key: const ValueKey('mcare.loading'),
              child: widget.placeholder ?? const Center(child: McarePulse()),
            )
          : KeyedSubtree(
              key: const ValueKey('mcare.content'),
              child: widget.child,
            ),
    );
  }
}

/// Delay-gated inline indicator for a button, row, chip, or field.
///
/// Occupies the same footprint whether or not it is showing, so nothing
/// reflows when a wait starts.
class InlineBusy extends StatelessWidget {
  const InlineBusy({
    super.key,
    required this.isLoading,
    this.size = McarePulseSize.inline,
    this.color,
    this.delay = AppMotion.loaderDelay,
  });

  final bool isLoading;
  final McarePulseSize size;
  final Color? color;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: DelayedLoader(
        isLoading: isLoading,
        delay: delay,
        placeholder: McarePulse(size: size, color: color),
        child: const SizedBox.shrink(),
      ),
    );
  }
}
