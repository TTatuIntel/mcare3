import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/async/app_busy.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import 'mcare_loading_mark.dart';

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
    final status = message ?? 'Loading…';

    // No card, no panel: the mark sits directly on the blurred page. A soft
    // radial halo — the page's own surface colour fading to nothing — lifts the
    // wordmark off busy content without drawing an edge around it.
    final haloBase = dark ? AppColors.darkScaffoldBg : AppColors.surface;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortest = math.min(constraints.maxWidth, constraints.maxHeight);
        // Halo and text scale with the viewport so the treatment reads the same
        // on a phone, a tablet and a desktop window.
        final haloSize = shortest.isFinite
            ? math.min(math.max(shortest * 0.86, 220.0), 460.0)
            : 320.0;
        final textWidth = math.min(
          360.0,
          math.max(160.0, constraints.maxWidth - AppSpacing.huge),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // The underlying page remains recognisable, preserving visual
            // continuity while clearly marking it as temporarily unavailable.
            ClipRect(
              key: const ValueKey('mcare-busy-backdrop'),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: ColoredBox(
                  color: (dark ? Colors.black : Colors.white).withValues(
                    alpha: dark ? 0.20 : 0.16,
                  ),
                ),
              ),
            ),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1),
                duration: AppMotion.itemEntry,
                curve: AppMotion.easeOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Semantics(
                  key: const ValueKey('mcare-busy-mark'),
                  container: true,
                  liveRegion: true,
                  label: status,
                  child: SizedBox(
                    width: haloSize,
                    height: haloSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            haloBase.withValues(alpha: dark ? 0.46 : 0.52),
                            haloBase.withValues(alpha: dark ? 0.22 : 0.26),
                            haloBase.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.46, 1.0],
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const McareLoadingMark(
                            size: McareMarkSize.large,
                            semanticLabel: null,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: textWidth,
                            child: Text(
                              status,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppPalette.ink(context),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    height: 1.3,
                                    letterSpacing: 0.1,
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
          ],
        );
      },
    );
  }
}
