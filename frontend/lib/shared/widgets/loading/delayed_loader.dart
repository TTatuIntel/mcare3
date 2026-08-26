import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import 'mcare_pulse.dart';

/// Switches between content and a loader directly from [isLoading].
///
/// The historical name is retained for source compatibility, but this widget
/// no longer delays or prolongs the loading state. The only duration is the
/// visual cross-fade; the state itself follows the real operation exactly.
class DelayedLoader extends StatelessWidget {
  const DelayedLoader({
    super.key,
    required this.isLoading,
    required this.child,
    this.placeholder,
    this.transition = AppMotion.crossFade,
  });

  final bool isLoading;

  /// Real content shown as soon as the operation reports ready.
  final Widget child;

  /// Defaults to a centred branded pulse.
  final Widget? placeholder;

  final Duration transition;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: transition,
      reverseDuration: transition,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: Curves.easeInCubic,
      child: isLoading
          ? KeyedSubtree(
              key: const ValueKey('mcare.loading'),
              child: placeholder ?? const Center(child: McarePulse()),
            )
          : KeyedSubtree(key: const ValueKey('mcare.content'), child: child),
    );
  }
}

/// State-synchronised inline indicator for a button, row, chip, or field.
/// Occupies a stable footprint so the surrounding layout never shifts.
class InlineBusy extends StatelessWidget {
  const InlineBusy({
    super.key,
    required this.isLoading,
    this.size = McarePulseSize.inline,
    this.color,
  });

  final bool isLoading;
  final McarePulseSize size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: DelayedLoader(
        isLoading: isLoading,
        placeholder: McarePulse(size: size, color: color),
        child: const SizedBox.shrink(),
      ),
    );
  }
}
