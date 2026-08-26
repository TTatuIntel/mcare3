import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'modal_scrim.dart';

/// The one and only confirmation dialog.
class AppDialog {
  AppDialog._();

  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool danger = false,
    IconData? icon,

    /// When true, the icon banner is the confirm action and only an X dismisses.
    bool iconActionOnly = false,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: iconActionOnly,
      barrierColor: Colors.transparent,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: AppMotion.easeOut,
          reverseCurve: Curves.easeInCubic,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(
              opacity: curve,
              child: ModalScrim(
                onTap: iconActionOnly
                    ? () => Navigator.of(ctx).pop(false)
                    : null,
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: curve,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      pageBuilder: (ctx, animation, secondaryAnimation) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        backgroundColor: AppPalette.surface(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: iconActionOnly && icon != null
                ? _IconActionBody(
                    ctx: ctx,
                    title: title,
                    message: message,
                    icon: icon,
                    danger: danger,
                  )
                : _StandardBody(
                    ctx: ctx,
                    title: title,
                    message: message,
                    confirmLabel: confirmLabel,
                    cancelLabel: cancelLabel,
                    danger: danger,
                    icon: icon,
                  ),
          ),
        ),
      ),
    );
  }
}

class _IconActionBody extends StatefulWidget {
  const _IconActionBody({
    required this.ctx,
    required this.title,
    required this.message,
    required this.icon,
    required this.danger,
  });

  final BuildContext ctx;
  final String title;
  final String message;
  final IconData icon;
  final bool danger;

  @override
  State<_IconActionBody> createState() => _IconActionBodyState();
}

class _IconActionBodyState extends State<_IconActionBody>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _pulse;
  late final Animation<double> _closeOpacity;
  late final Animation<Offset> _closeSlide;
  late final Animation<double> _bannerOpacity;
  late final Animation<double> _bannerScale;
  late final Animation<Offset> _bannerSlide;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseGlow;

  bool _pressed = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _closeOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0, 0.4, curve: AppMotion.easeOut),
      ),
    );
    _closeSlide = Tween<Offset>(begin: const Offset(0, -0.35), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entry,
            curve: const Interval(0, 0.4, curve: AppMotion.easeOut),
          ),
        );

    _bannerOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.08, 0.58, curve: AppMotion.easeOut),
      ),
    );
    _bannerScale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.08, 0.58, curve: AppMotion.easeOut),
      ),
    );
    _bannerSlide =
        Tween<Offset>(
          begin: const Offset(0, AppMotion.translateY / 72),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _entry,
            curve: const Interval(0.08, 0.58, curve: AppMotion.easeOut),
          ),
        );

    _textOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.32, 0.88, curve: AppMotion.easeOut),
      ),
    );
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entry,
            curve: const Interval(0.32, 0.88, curve: AppMotion.easeOut),
          ),
        );

    _pulseScale = Tween<double>(
      begin: 1,
      end: 1.018,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _pulseGlow = Tween<double>(
      begin: 0.12,
      end: 0.28,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _entry.forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _dismiss() => Navigator.of(widget.ctx).pop(false);

  Future<void> _confirm() async {
    if (_confirming) return;
    setState(() {
      _confirming = true;
      _pressed = true;
    });
    HapticFeedback.mediumImpact();
    _pulse.stop();
    await Future<void>.delayed(AppMotion.micro);
    if (!mounted) return;
    await _entry.reverse();
    if (!mounted) return;
    Navigator.of(widget.ctx).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger ? AppColors.critical : AppColors.info;
    final soft = widget.danger
        ? AppPalette.criticalSoft(context)
        : AppPalette.infoSoft(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeTransition(
          opacity: _closeOpacity,
          child: SlideTransition(
            position: _closeSlide,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close',
                onPressed: _dismiss,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  AppIcons.close,
                  color: AppPalette.textMuted(context),
                ),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: _bannerOpacity,
          child: SlideTransition(
            position: _bannerSlide,
            child: ScaleTransition(
              scale: _bannerScale,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final breathe = _confirming ? 1.0 : _pulseScale.value;
                  final press = _pressed ? 0.96 : 1.0;
                  return Transform.scale(scale: breathe * press, child: child);
                },
                child: AnimatedBuilder(
                  animation: _pulseGlow,
                  builder: (context, child) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusLg,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withOpacity(
                              _confirming ? 0 : _pulseGlow.value,
                            ),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: Material(
                    color: soft,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _confirm,
                      onTapDown: (_) => setState(() => _pressed = true),
                      onTapUp: (_) => setState(() => _pressed = false),
                      onTapCancel: () => setState(() => _pressed = false),
                      child: Semantics(
                        button: true,
                        label: widget.title,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xl,
                          ),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: _confirming ? -0.12 : 0,
                            ),
                            duration: AppMotion.micro,
                            curve: AppMotion.easeOut,
                            builder: (context, slide, child) {
                              return Transform.translate(
                                offset: Offset(0, slide * 24),
                                child: child,
                              );
                            },
                            child: Icon(widget.icon, color: accent, size: 32),
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
        const SizedBox(height: AppSpacing.lg),
        FadeTransition(
          opacity: _textOpacity,
          child: SlideTransition(
            position: _textSlide,
            child: Column(
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(widget.ctx).textTheme.headlineSmall?.copyWith(
                    color: AppPalette.ink(widget.ctx),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(widget.ctx).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.textMuted(widget.ctx),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StandardBody extends StatelessWidget {
  const _StandardBody({
    required this.ctx,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.danger,
    this.icon,
  });

  final BuildContext ctx;
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (icon != null) ...[
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: (danger
                  ? AppPalette.criticalSoft(context)
                  : AppPalette.infoSoft(context)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Icon(
              icon,
              color: danger ? AppColors.critical : AppColors.info,
              size: 26,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text(
          title,
          style: Theme.of(
            ctx,
          ).textTheme.headlineSmall?.copyWith(color: AppPalette.ink(ctx)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          style: Theme.of(
            ctx,
          ).textTheme.bodyMedium?.copyWith(color: AppPalette.textMuted(ctx)),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: cancelLabel,
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: confirmLabel,
              variant: danger
                  ? AppButtonVariant.danger
                  : AppButtonVariant.primary,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ],
    );
  }
}
