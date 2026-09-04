import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'modal_scrim.dart';

/// The one and only bottom sheet / modal form container for every role.
///
/// Uses a blurred scrim (native) or tinted overlay (web) and sizes to
/// content so panels never render as empty white blocks.
class GlassSheet {
  GlassSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    IconData? leadingIcon,
    Color? leadingColor,
    String? statusLabel,
    Color? statusColor,
    required Widget child,
    bool isDismissible = true,
    double? maxWidth,
    double maxHeightFactor = 0.92,
  }) async {
    final locale = Localizations.localeOf(context);
    final route = RawDialogRoute<T>(
      barrierDismissible: isDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: AppMotion.pageFast,
      transitionBuilder: (ctx, animation, secondary, dialogChild) =>
          dialogChild,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        // Inherit locale + Material localizations inside overlay routes.
        return Localizations(
          locale: locale,
          delegates: AppLocalizations.localizationsDelegates,
          child: _SheetRoute<T>(
            animation: animation,
            title: title,
            subtitle: subtitle,
            leadingIcon: leadingIcon,
            leadingColor: leadingColor,
            statusLabel: statusLabel,
            statusColor: statusColor,
            maxWidth: maxWidth ?? 640,
            maxHeightFactor: maxHeightFactor,
            isDismissible: isDismissible,
            child: child,
          ),
        );
      },
    );

    final result = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<T>(route);

    // `push` resolves the moment the sheet is popped — the panel is still on
    // screen, still building, for the length of its exit transition. Callers
    // routinely dispose the controllers they handed the sheet as soon as this
    // future returns, and a `TextEditingController` used after disposal throws
    // mid-build, which takes the whole Overlay down with it. Waiting for
    // `completed` means the route is off the tree before the caller resumes,
    // so "await show(); controller.dispose();" is safe by construction.
    await route.completed;
    return result;
  }
}

class _SheetRoute<T> extends StatelessWidget {
  const _SheetRoute({
    required this.animation,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.leadingColor,
    required this.statusLabel,
    required this.statusColor,
    required this.maxWidth,
    required this.maxHeightFactor,
    required this.isDismissible,
    required this.child,
  });

  final Animation<double> animation;
  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final String? statusLabel;
  final Color? statusColor;
  final double maxWidth;
  final double maxHeightFactor;
  final bool isDismissible;
  final Widget child;

  void _dismiss(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop<T>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.easeOut,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(curved);

    final isDark = AppPalette.isDark(context);
    final scrim = isDark ? AppColors.darkOverlay : AppColors.overlay;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dimmed backdrop — dismiss only. Must sit BEHIND the panel.
          FadeTransition(
            opacity: curved,
            child: ModalScrim(
              color: scrim,
              onTap: isDismissible ? () => _dismiss(context) : null,
            ),
          ),
          // Panel is a separate stack layer so menu InkWells are never under
          // the scrim's GestureDetector (that bug made taps only dismiss).
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: slide,
                child: FadeTransition(
                  opacity: curved,
                  child: Material(
                    color: Colors.transparent,
                    child: _SheetPanel(
                      title: title,
                      subtitle: subtitle,
                      leadingIcon: leadingIcon,
                      leadingColor: leadingColor,
                      statusLabel: statusLabel,
                      statusColor: statusColor,
                      maxWidth: maxWidth,
                      maxHeightFactor: maxHeightFactor,
                      onClose: () => _dismiss(context),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetPanel extends StatelessWidget {
  const _SheetPanel({
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.leadingColor,
    required this.statusLabel,
    required this.statusColor,
    required this.maxWidth,
    required this.maxHeightFactor,
    required this.onClose,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final String? statusLabel;
  final Color? statusColor;
  final double maxWidth;
  final double maxHeightFactor;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.max(
      200.0,
      screenHeight * maxHeightFactor - viewInsets.bottom,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md + viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: _FrostedSheetSurface(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const headerEstimate = 120.0;
              final bodyMax = math.max(
                120.0,
                constraints.maxHeight - headerEstimate,
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: AppSpacing.md),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.borderStrong(context),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusPill,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.sm,
                      0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (leadingIcon != null) ...[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: (leadingColor ?? AppColors.brandIndigo)
                                  .withValues(alpha: 0.11),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusSm,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              leadingIcon,
                              size: 20,
                              color: leadingColor ?? AppColors.brandIndigo,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppPalette.ink(context),
                                    ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppPalette.textMuted(context),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (statusLabel != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: (statusColor ?? AppColors.brandIndigo)
                                  .withValues(alpha: 0.11),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusPill,
                              ),
                            ),
                            child: Text(
                              statusLabel!,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: statusColor ?? AppColors.brandIndigo,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                  ),
                            ),
                          ),
                        ],
                        IconButton(
                          tooltip: 'Close',
                          onPressed: onClose,
                          icon: Icon(
                            AppIcons.close,
                            color: AppPalette.ink(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Flexible, not just capped: headerEstimate is a guess, and
                  // a title or subtitle that wraps to an extra line makes the
                  // real header taller than it. Capped alone that overflowed
                  // the panel by those few pixels; flexible lets the scroll
                  // view give them back instead.
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: bodyMax),
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.lg,
                          AppSpacing.xl,
                          AppSpacing.xl,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FrostedSheetSurface extends StatelessWidget {
  const _FrostedSheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppSpacing.radiusXl);
    final borderColor = AppPalette.borderStrong(context);
    final fill = isDark ? AppColors.darkSurface : AppPalette.surface(context);

    final decoration = BoxDecoration(
      color: fill,
      borderRadius: radius,
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: AppPalette.ink(
            context,
          ).withValues(alpha: isDark ? 0.45 : 0.14),
          blurRadius: 32,
          offset: const Offset(0, -10),
        ),
      ],
    );

    // Always clip to radius so children / ink don't spill past rounded corners.
    // BackdropFilter is unreliable on Flutter web — use an opaque surface there.
    if (kIsWeb) {
      return Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(decoration: decoration, child: child),
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: decoration.copyWith(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.94)
                : AppPalette.surface(context).withValues(alpha: 0.96),
          ),
          child: child,
        ),
      ),
    );
  }
}
