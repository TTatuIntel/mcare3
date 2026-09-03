import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Six-digit OTP input row (password change, verification flows).
///
/// Codes arrive as one string — copied out of an email, or lifted off an SMS
/// by the keyboard — and almost never as six separate keystrokes. Six boxes
/// each capped at one character fought that: a pasted code dropped five of its
/// digits into nothing, and the platform's own one-time-code autofill had
/// nowhere to put its value. Both are handled here, so the common way of
/// entering a code is the way that works.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
  });

  /// Fired the moment six digits are present, however they got there.
  final ValueChanged<String>? onCompleted;

  /// Fired on every change, for callers that enable a button on completeness.
  final ValueChanged<String>? onChanged;

  final bool enabled;

  /// Paints the boxes as rejected. Cleared by the next keystroke.
  final bool hasError;

  final bool autofocus;

  @override
  State<OtpCodeField> createState() => OtpCodeFieldState();
}

class OtpCodeFieldState extends State<OtpCodeField> {
  static const _length = 6;

  final _controllers = List.generate(_length, (_) => TextEditingController());
  final _nodes = List.generate(_length, (_) => FocusNode());

  String get code => _controllers.map((c) => c.text).join();

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    if (mounted) setState(() {});
    _nodes.first.requestFocus();
    widget.onChanged?.call('');
  }

  /// Fills the row from a single string — a paste, or an autofilled SMS code.
  void fill(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    for (var i = 0; i < _length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    final filled = digits.length.clamp(0, _length);
    // Park the caret on the first empty box, or the last one when complete,
    // so a short paste leaves the person where they need to keep typing.
    _nodes[(filled - 1).clamp(0, _length - 1)].requestFocus();
    if (mounted) setState(() {});
    _emit();
  }

  void _emit() {
    final value = code;
    widget.onChanged?.call(value);
    if (value.length == _length) {
      FocusScope.of(context).unfocus();
      widget.onCompleted?.call(value);
    }
  }

  void _onChanged(int index, String value) {
    // More than one character means a paste (or an autofill) landed in this
    // box. Spread it across the row from here rather than truncating it.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (index == 0 || digits.length >= _length) {
        fill(digits);
        return;
      }
      for (var i = index; i < _length; i++) {
        final at = i - index;
        _controllers[i].text = at < digits.length ? digits[at] : '';
      }
      _nodes[(index + digits.length - 1).clamp(0, _length - 1)].requestFocus();
      setState(() {});
      _emit();
      return;
    }

    if (value.isNotEmpty && index < _length - 1) {
      _nodes[index + 1].requestFocus();
    }
    setState(() {});
    _emit();
  }

  /// Backspace on an empty box steps back and clears the one before it, which
  /// is what every other code field on the person's phone does.
  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_controllers[index].text.isNotEmpty || index == 0) {
      return KeyEventResult.ignored;
    }
    _controllers[index - 1].clear();
    _nodes[index - 1].requestFocus();
    setState(() {});
    _emit();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.hasError
        ? AppColors.critical
        : AppPalette.border(context);

    return AutofillGroup(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_length, (i) {
          return Flexible(
            child: Padding(
              padding: EdgeInsets.only(right: i == _length - 1 ? 0 : 6),
              child: SizedBox(
                height: 52,
                child: Focus(
                  onKeyEvent: (_, event) => _onKey(i, event),
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _nodes[i],
                    enabled: widget.enabled,
                    autofocus: widget.autofocus && i == 0,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    // The platform delivers a whole SMS code to the first
                    // box; capping the length here would throw it away.
                    autofillHints: i == 0
                        ? const [AutofillHints.oneTimeCode]
                        : null,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        borderSide: BorderSide(
                          color: widget.hasError
                              ? AppColors.critical
                              : AppColors.brandIndigo,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        borderSide: BorderSide(
                          color: AppPalette.border(context),
                        ),
                      ),
                    ),
                    onChanged: (v) => _onChanged(i, v),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
