import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'loading/mcare_pulse.dart';
import 'skeleton.dart';

/// How a page-level wait is drawn.
enum AppLoadingVariant {
  /// Placeholder rows that hold the page's shape. Best when the content that
  /// is arriving is a list or a stack of cards.
  skeleton,

  /// Centred mCare pulse. Best when the shape of the incoming content is not
  /// known, or the area is too small for a convincing skeleton.
  pulse,
}

/// Full-page loading placeholder.
///
/// Gated by [AppMotion.skeletonDelay] so a fast load paints its real content
/// directly instead of flashing a placeholder. The gate is deliberately much
/// shorter than [AppMotion.loaderDelay] used by [DelayedLoader]: a skeleton
/// preserves layout, so it does not read as a flash the way a spinner does.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    super.key,
    this.message,
    this.itemCount = 4,
    this.padding,
    this.variant = AppLoadingVariant.skeleton,
    this.delay = AppMotion.skeletonDelay,
  });

  final String? message;
  final int itemCount;
  final EdgeInsetsGeometry? padding;
  final AppLoadingVariant variant;

  /// Wait this long before painting anything.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return _LoadingGate(
      delay: delay,
      child: switch (variant) {
        AppLoadingVariant.skeleton => _SkeletonBody(
            message: message,
            itemCount: itemCount,
            padding: padding,
          ),
        AppLoadingVariant.pulse => _PulseBody(message: message),
      },
    );
  }
}

/// Holds an empty box until [delay] elapses, then fades its child in.
class _LoadingGate extends StatefulWidget {
  const _LoadingGate({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_LoadingGate> createState() => _LoadingGateState();
}

class _LoadingGateState extends State<_LoadingGate> {
  Timer? _timer;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay <= Duration.zero) {
      _open = true;
      return;
    }
    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() => _open = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _open ? 1 : 0,
      duration: AppMotion.crossFade,
      curve: AppMotion.easeOut,
      child: _open ? widget.child : const SizedBox.expand(),
    );
  }
}

class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody({
    required this.message,
    required this.itemCount,
    required this.padding,
  });

  final String? message;
  final int itemCount;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                const McarePulse(
                  size: McarePulseSize.inline,
                  semanticLabel: null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Expanded(
          child: SkeletonList(
            itemCount: itemCount,
            padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
          ),
        ),
      ],
    );
  }
}

class _PulseBody extends StatelessWidget {
  const _PulseBody({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const McarePulse(size: McarePulseSize.large),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
