import 'package:flutter/material.dart';

import '../auth/session_recovery.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Replaces Flutter's default error box in release builds.
///
/// The stock [ErrorWidget] renders an unstyled grey rectangle, which on a full
/// screen is indistinguishable from a blank page. This gives the user a clear
/// statement and a way forward instead.
///
/// Deliberately self-contained: an error can surface above `MaterialApp`, so
/// this must not read `Theme`, `Directionality`, or any localisation — which
/// is also why the way out navigates through `rootNavigatorKey` rather than
/// this widget's own context.
class AppErrorFallback extends StatelessWidget {
  const AppErrorFallback({super.key, this.details});

  final FlutterErrorDetails? details;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.scaffoldBg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: AppColors.textMutedAA,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  "This section didn't load",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandInk,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Go back and try again, or reload the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textMutedAA),
                ),
                const SizedBox(height: AppSpacing.lg),
                // The screen behind this is broken, so the only reliable exit
                // is a route change. Signed in, that is the dashboard; signed
                // out, landing.
                const _BackToSafety(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain [GestureDetector] rather than the usual `AppButton`/[InkWell]: this
/// button only ever renders inside a screen that has already failed, so it
/// takes on no ancestor it cannot prove is there. A crash inside the crash
/// screen has nowhere left to fall back to.
class _BackToSafety extends StatelessWidget {
  const _BackToSafety();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: SessionRecovery.goHome,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.brandIndigo,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: const Text(
          'Back to safety',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}
