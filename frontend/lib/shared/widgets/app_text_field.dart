import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';

/// The single text field used in forms.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.obscureText = false,
    this.canRevealObscured = false,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.helperText,
    this.textInputAction,
    this.focusNode,
    this.dense = AppLayout.compactFields,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final bool obscureText;
  final bool canRevealObscured;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final bool enabled;
  final bool autofocus;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final String? helperText;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool dense;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.dense;

    final suffix = widget.canRevealObscured
        ? IconButton(
            splashRadius: compact ? 14 : 18,
            visualDensity: compact
                ? VisualDensity.compact
                : VisualDensity.standard,
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? AppIcons.visibility : AppIcons.visibilityOff,
              size: compact ? AppLayout.controlIconSize : 20,
              color: AppPalette.textMuted(context),
            ),
          )
        : (widget.suffixIcon != null
              ? IconButton(
                  splashRadius: compact ? 14 : 18,
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  onPressed: widget.onSuffixTap,
                  icon: Icon(
                    widget.suffixIcon,
                    size: compact ? AppLayout.controlIconSize : 20,
                    color: AppPalette.textMuted(context),
                  ),
                )
              : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppPalette.ink(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 4 : AppSpacing.sm),
        ],
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: _obscure,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          maxLines: _obscure ? 1 : widget.maxLines,
          minLines: widget.minLines,
          maxLength: widget.maxLength,
          textInputAction: widget.textInputAction,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.2),
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            helperText: widget.helperText,
            counterText: '',
            isDense: compact,
            contentPadding: compact ? AppLayout.controlPadding : null,
            constraints: compact ? AppLayout.controlConstraints : null,
            prefixIcon: widget.prefixIcon == null
                ? null
                : Icon(
                    widget.prefixIcon,
                    size: compact ? AppLayout.controlIconSize : 20,
                    color: AppPalette.textMuted(context),
                  ),
            prefixIconConstraints: compact
                ? const BoxConstraints(
                    minWidth: AppLayout.controlPrefixWidth,
                    minHeight: AppLayout.controlHeight,
                  )
                : null,
            suffixIcon: suffix,
            suffixIconConstraints: compact
                ? const BoxConstraints(
                    minWidth: AppLayout.controlPrefixWidth,
                    minHeight: AppLayout.controlHeight,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
