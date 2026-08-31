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
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _dismiss(immediate: true);

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _GlassToastBanner(
        message: message,
        kind: kind,
        title: title,
        actionLabel: actionLabel,
        onAction: onAction,
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

  static void notification(
    BuildContext context, {
    required String title,
    required String message,
    VoidCallback? onOpen,
  }) => show(
    context,
    title: title,
    message: message,
    kind: AppToastKind.info,
    duration: const Duration(seconds: 6),
    actionLabel: onOpen == null ? null : 'Open',
    onAction: onOpen,
  );
}

class _GlassToastBanner extends StatefulWidget {
  const _GlassToastBanner({
    required this.message,
    required this.kind,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.onStateCreated,
  });

  final String message;
  final AppToastKind kind;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final ValueChanged<_GlassToastBannerState> onStateCreated;

  @override
  State<_GlassToastBanner> createState() => _GlassToastBannerState();
}

class _GlassToastBannerState extends State<_GlassToastBanner>
    with SingleTickerProviderStateMixin {
  /// Below this width the layout is single-column with a bottom CTA.
  static const double _topAnchorMaxWidth = 640;

  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.page,
      reverseDuration: const Duration(milliseconds: 260),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.easeOut,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(_curve);
    _controller.forward();
  }

  Future<void> playOut() async {
    if (!mounted) return;
    await _controller.reverse();
  }

  @override
  void dispose() {
    _curve.dispose();
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
    final media = MediaQuery.of(context);

    // Narrow screens put the primary call-to-action near the bottom of the
    // page, so anchor the toast under the status bar there — a bottom banner
    // would sit on top of the very button the message is about. Wider layouts
    // keep the familiar bottom-corner placement, lifted above the keyboard.
    final anchorTop = media.size.width < _topAnchorMaxWidth;
    final slide = _curve.drive(
      Tween<Offset>(
        begin: Offset(0, anchorTop ? -0.22 : 0.22),
        end: Offset.zero,
      ),
    );

    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      top: anchorTop ? media.padding.top + AppSpacing.md : null,
      bottom: anchorTop
          ? null
          : media.viewInsets.bottom + media.padding.bottom + AppSpacing.xl,
      child: Align(
        alignment: anchorTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: slide,
              child: Semantics(
                container: true,
                liveRegion: true,
                label: [
                  if (widget.title != null) widget.title!,
                  widget.message,
                ].join('. '),
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      boxShadow: [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.2),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                          spreadRadius: -4,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
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
                            color: AppPalette.surface(
                              context,
                            ).withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusLg,
                            ),
                            border: Border.all(
                              color: palette.accent.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                height: 38,
                                width: 38,
                                decoration: BoxDecoration(
                                  color: palette.soft.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusMd,
                                  ),
                                  border: Border.all(
                                    color: palette.accent.withValues(
                                      alpha: 0.3,
                                    ),
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
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.title != null)
                                      Text(
                                        widget.title!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: AppPalette.ink(context),
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    Text(
                                      widget.message,
                                      maxLines: widget.title == null ? 3 : 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: widget.title == null
                                                ? AppPalette.ink(context)
                                                : AppPalette.textMuted(context),
                                            fontWeight: widget.title == null
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            height: 1.25,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.actionLabel != null &&
                                  widget.onAction != null)
                                TextButton(
                                  onPressed: () {
                                    final action = widget.onAction!;
                                    AppToast._dismiss(immediate: true);
                                    action();
                                  },
                                  child: Text(widget.actionLabel!),
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
          ),
        ),
      ),
    );
  }
}
