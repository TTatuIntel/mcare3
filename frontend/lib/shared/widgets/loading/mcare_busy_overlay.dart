import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/async/app_busy.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import 'mcare_loading_mark.dart';
import 'mcare_pulse.dart';

/// Full-screen mCare loading treatment for genuinely critical work.
///
/// Visibility is a direct projection of [AppBusy.isBlocking]: there is no
/// display delay and no minimum timer. Authentication, initialisation, and
/// critical page preparation opt into that state; ordinary reads use the slim
/// busy bar and small writes use their control's inline loading treatment.
///
/// Mount once around the app's `child` in `MaterialApp.builder`.
class McareBusyOverlay extends StatelessWidget {
  const McareBusyOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppBusy.instance,
      builder: (context, _) {
        final blocking = AppBusy.instance.isBlocking;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                // The outgoing visual may finish its fade, but interaction is
                // restored the instant the real loading state finishes.
                ignoring: !blocking,
                child: AnimatedSwitcher(
                  duration: AppMotion.crossFade,
                  reverseDuration: AppMotion.crossFade,
                  switchInCurve: AppMotion.easeOut,
                  switchOutCurve: Curves.easeInCubic,
                  child: blocking
                      ? _BusyScrim(
                          key: const ValueKey('mcare-busy-active'),
                          message: AppBusy.instance.blockingMessage,
                        )
                      : const SizedBox.expand(key: ValueKey('mcare-busy-idle')),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BusyScrim extends StatelessWidget {
  const _BusyScrim({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final status = message ?? 'Loading information…';

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = math.max(
          136.0,
          math.min(184.0, constraints.maxWidth - AppSpacing.huge),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // The underlying page remains recognisable, preserving visual
            // continuity while clearly marking it as temporarily unavailable.
            ClipRect(
              key: const ValueKey('mcare-busy-backdrop'),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: ColoredBox(
                  color: (dark ? Colors.black : Colors.white).withValues(
                    alpha: dark ? 0.24 : 0.22,
                  ),
                ),
              ),
            ),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.96, end: 1),
                duration: AppMotion.itemEntry,
                curve: AppMotion.easeOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: SizedBox(
                  key: const ValueKey('mcare-busy-glass'),
                  width: cardWidth,
                  height: 142,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: dark ? 0.30 : 0.12,
                          ),
                          blurRadius: 30,
                          spreadRadius: -6,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                (dark
                                        ? AppColors.darkSurface
                                        : AppColors.surface)
                                    .withValues(alpha: dark ? 0.72 : 0.70),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusXl,
                            ),
                            border: Border.all(
                              color: (dark ? Colors.white : AppColors.surface)
                                  .withValues(alpha: dark ? 0.18 : 0.86),
                            ),
                          ),
                          child: Semantics(
                            container: true,
                            liveRegion: true,
                            label: status,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const McareLoadingMark(
                                  size: McareMarkSize.medium,
                                  semanticLabel: null,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                const McarePulse(
                                  size: McarePulseSize.small,
                                  semanticLabel: null,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                  ),
                                  child: Text(
                                    status,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppPalette.ink(context),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
