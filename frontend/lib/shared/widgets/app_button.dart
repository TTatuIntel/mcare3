import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

enum AppButtonVariant { primary, secondary, ghost, danger, icon }

enum AppButtonSize { sm, md, lg }

/// The single button used across the app. No screen rolls its own.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.loading = false,
    this.expand = false,
    this.semanticLabel,
  });

  /// Icon-only button: use this constructor and omit a label.
  const AppButton.icon({
    super.key,
    required IconData icon,
    this.onPressed,
    this.size = AppButtonSize.md,
    this.loading = false,
    this.semanticLabel,
  })  : label = '',
        icon = icon,
        trailingIcon = null,
        variant = AppButtonVariant.icon,
        expand = false;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool expand;
  final String? semanticLabel;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = widget.onPressed == null || widget.loading;
    final accent = theme.colorScheme.primary;
    final style = _resolveStyle(context, accent, disabled);

    final padding = switch (widget.size) {
      AppButtonSize.sm =>
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      AppButtonSize.md =>
        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      AppButtonSize.lg =>
        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    };

    final textStyle = switch (widget.size) {
      AppButtonSize.sm => theme.textTheme.labelMedium,
      AppButtonSize.md => theme.textTheme.labelLarge,
      AppButtonSize.lg =>
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    };

    Widget child;
    if (widget.variant == AppButtonVariant.icon) {
      child = Icon(widget.icon, size: 20, color: style.fg);
    } else {
      child = Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 18, color: style.fg),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              widget.label,
              style: textStyle?.copyWith(color: style.fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.trailingIcon != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(widget.trailingIcon, size: 18, color: style.fg),
          ],
        ],
      );
    }

    // A button in flight keeps its label and simply stops responding. The
    // "something is happening" signal belongs on the screen (McareBusyOverlay),
    // not swapped into the control the user just pressed — replacing the label
    // loses the affordance and makes the button look broken.

    final radius = widget.variant == AppButtonVariant.icon
        ? BorderRadius.circular(AppSpacing.radiusPill)
        : BorderRadius.circular(AppSpacing.radiusMd);

    final minHeight = switch (widget.size) {
      AppButtonSize.sm => 40.0,
      AppButtonSize.md => 48.0,
      AppButtonSize.lg => 56.0,
    };

    final btn = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: AppMotion.micro,
      curve: Curves.easeOut,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minHeight,
          minWidth: widget.variant == AppButtonVariant.icon ? minHeight : 0,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              color: style.bg,
              gradient: style.gradient,
              borderRadius: radius,
              border: style.border,
              boxShadow: style.shadow,
            ),
            child: InkWell(
              onTap: disabled ? null : widget.onPressed,
              onHighlightChanged: disabled
                  ? null
                  : (highlighted) => setState(() => _pressed = highlighted),
              borderRadius: radius,
              mouseCursor: disabled
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: Padding(
                padding: widget.variant == AppButtonVariant.icon
                    ? const EdgeInsets.all(10)
                    : padding,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      label: widget.semanticLabel ?? widget.label,
      button: true,
      enabled: !disabled,
      child: widget.expand
          ? SizedBox(width: double.infinity, child: btn)
          : btn,
    );
  }

  _BtnStyle _resolveStyle(BuildContext context, Color accent, bool disabled) {
    if (disabled) {
      return _BtnStyle(
        bg: AppPalette.surfaceMuted(context),
        fg: AppPalette.textFaint(context),
        border: Border.all(color: AppPalette.border(context)),
      );
    }
    switch (widget.variant) {
      case AppButtonVariant.primary:
        return _BtnStyle(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent, accent.withOpacity(0.85)],
          ),
          fg: Colors.white,
          shadow: [
            BoxShadow(
              color: accent.withOpacity(0.28),
              blurRadius: 18,
              offset: const Offset(0, 10),
              spreadRadius: -4,
            ),
          ],
        );
      case AppButtonVariant.secondary:
        return _BtnStyle(
          bg: AppPalette.surface(context),
          fg: accent,
          border: Border.all(color: accent.withOpacity(0.4), width: 1.2),
        );
      case AppButtonVariant.ghost:
        return _BtnStyle(
          bg: Colors.transparent,
          fg: accent,
        );
      case AppButtonVariant.danger:
        return _BtnStyle(
          gradient: const LinearGradient(
            colors: [AppColors.critical, Color(0xFFF87171)],
          ),
          fg: Colors.white,
          shadow: [
            BoxShadow(
              color: AppColors.critical.withOpacity(0.28),
              blurRadius: 18,
              offset: const Offset(0, 10),
              spreadRadius: -4,
            ),
          ],
        );
      case AppButtonVariant.icon:
        return _BtnStyle(
          bg: AppPalette.surfaceAlt(context),
          fg: AppPalette.ink(context),
          border: Border.all(color: AppPalette.border(context)),
        );
    }
  }
}

class _BtnStyle {
  _BtnStyle({
    this.bg,
    this.gradient,
    required this.fg,
    this.border,
    this.shadow,
  });
  final Color? bg;
  final Gradient? gradient;
  final Color fg;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;
}
