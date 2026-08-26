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
/// The parent owns the real loading state. This view starts fading in as soon
/// as it is mounted and is removed as soon as the parent has content; no timer
/// delays or extends the operation it represents.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    super.key,
    this.message,
    this.itemCount = 4,
    this.padding,
    this.variant = AppLoadingVariant.skeleton,
  });

  final String? message;
  final int itemCount;
  final EdgeInsetsGeometry? padding;
  final AppLoadingVariant variant;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.crossFade,
      curve: AppMotion.easeOut,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
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
