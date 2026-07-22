import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';

enum AppToastKind { success, error, info, warning }

/// Single transient feedback API — glass floating update popups.
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;
  static _GlassToastBannerState? _activeState;

  static const Duration defaultDuration = Duration(milliseconds: 3500);

  static void show(
    BuildContext context, {
    required String message,
    AppToastKind kind = AppToastKind.info,
    Duration duration = defaultDuration,
  }) {
    _dismiss(immediate: true);

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _GlassToastBanner(
        message: message,
        kind: kind,
        onStateCreated: (state) => _activeState = state,
      ),
    );

    _entry = entry;
    overlay.insert(entry);

    _timer?.cancel();
    _timer = Timer(duration, () => _dismiss());
  }

  static Future<void> _dismiss({bool immediate = false}) async {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    final state = _activeState;
    _entry = null;
    _activeState = null;

    if (entry == null) return;

    if (!immediate && state != null) {
      await state.playOut();
    }
    entry.remove();
  }

  static void success(BuildContext c, String msg) =>
      show(c, message: msg, kind: AppToastKind.success);
  static void error(BuildContext c, String msg) =>
      show(c, message: msg, kind: AppToastKind.error);
  static void info(BuildContext c, String msg) =>
      show(c, message: msg, kind: AppToastKind.info);
  static void warn(BuildContext c, String msg) =>
      show(c, message: msg, kind: AppToastKind.warning);
}

class _GlassToastBanner extends StatefulWidget {
  const _GlassToastBanner({
    required this.message,
    required this.kind,
    required this.onStateCreated,
  });

  final String message;
  final AppToastKind kind;
  final ValueChanged<_GlassToastBannerState> onStateCreated;

  @override
  State<_GlassToastBanner> createState() => _GlassToastBannerState();
}

class _GlassToastBannerState extends State<_GlassToastBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.page,
      reverseDuration: const Duration(milliseconds: 260),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.easeOut,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(curve);
    _controller.forward();
  }

  Future<void> playOut() async {
    if (!mounted) return;
    await _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({Color accent, Color soft, IconData icon}) _palette(BuildContext context) =>
      switch (widget.kind) {
        AppToastKind.success => (
            accent: AppColors.success,
            soft: AppPalette.successSoft(context),
            icon: AppIcons.check,
          ),
        AppToastKind.error => (
            accent: AppColors.critical,
            soft: AppPalette.criticalSoft(context),
            icon: AppIcons.alert,
          ),
        AppToastKind.warning => (
            accent: AppColors.warning,
            soft: AppPalette.warningSoft(context),
            icon: AppIcons.alert,
          ),
        AppToastKind.info => (
            accent: AppColors.brandIndigo,
            soft: AppPalette.infoSoft(context),
            icon: AppIcons.info,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: bottomInset + 108,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: palette.accent.withOpacity(0.2),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                    spreadRadius: -4,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.surface(context).withOpacity(0.94),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusLg),
                      border: Border.all(
                        color: palette.accent.withOpacity(0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 38,
                          width: 38,
                          decoration: BoxDecoration(
                            color: palette.soft.withOpacity(0.9),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                            border: Border.all(
                              color: palette.accent.withOpacity(0.3),
                            ),
                          ),
                          child: Icon(
                            palette.icon,
                            color: palette.accent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: AppPalette.ink(context),
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () => AppToast._dismiss(),
                          icon: Icon(
                            AppIcons.close,
                            size: 18,
                            color: AppPalette.textFaint(context),
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
    );
  }
}
