import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/loading/loading.dart';
import 'launch_readiness.dart';

/// Covers the app with the mCare loading mark until bootstrap finishes.
///
/// The HTML splash only exists on web, and only until it is dismissed. This
/// is the platform-independent equivalent: on a hot restart, a cold start, or
/// any rebuild that re-runs bootstrap, the user sees the brand mark rather
/// than an empty frame while session restore and settings load.
///
/// It sits inside `MaterialApp.builder`, so it is themed and covers whatever
/// route is being built underneath.
class BootSplashGate extends StatelessWidget {
  const BootSplashGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LaunchReadiness.instance,
      builder: (context, _) {
        final ready = LaunchReadiness.instance.bootstrapComplete;
        return Stack(
          children: [
            child,
            // Fades rather than cuts, so the handoff to the first real screen
            // reads as one motion instead of a flash.
            IgnorePointer(
              ignoring: ready,
              child: AnimatedOpacity(
                opacity: ready ? 0 : 1,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                child: const _BootSplash(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: AppPalette.scaffoldBg(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const McareLoadingMark(
              size: McareMarkSize.large,
              semanticLabel: 'Starting mCare',
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Remote care, connected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
