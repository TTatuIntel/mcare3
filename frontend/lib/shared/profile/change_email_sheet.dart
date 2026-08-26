import 'package:flutter/material.dart';

import '../../core/api/profile_api.dart';
import '../../core/env/app_env.dart';
import '../auth/auth_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/otp_code_field.dart';

/// Role-agnostic email change. Confirms the current password, then verifies a
/// 6-digit code sent to the new address before the change is trusted.
class ChangeEmailSheet {
  ChangeEmailSheet._();

  static Future<void> show(BuildContext context) {
    final user = AuthState.instance.user;
    if (user == null) return Future.value();
    return GlassSheet.show(
      context,
      title: 'Change email',
      subtitle: 'Confirm your password, then verify your new address.',
      child: _ChangeEmailForm(currentEmail: user.email),
    );
  }
}

class _ChangeEmailForm extends StatefulWidget {
  const _ChangeEmailForm({required this.currentEmail});
  final String currentEmail;

  @override
  State<_ChangeEmailForm> createState() => _ChangeEmailFormState();
}

class _ChangeEmailFormState extends State<_ChangeEmailForm> {
  final _password = TextEditingController();
  final _newEmail = TextEditingController();
  final _otpKey = GlobalKey<OtpCodeFieldState>();
  int _step = 0;
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    _newEmail.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String value) {
    final v = value.trim();
    return v.contains('@') && v.contains('.') && v.length >= 5;
  }

  Future<void> _requestChange() async {
    if (_password.text.isEmpty) {
      AppToast.warn(context, 'Enter your current password.');
      return;
    }
    if (!_looksLikeEmail(_newEmail.text)) {
      AppToast.warn(context, 'Enter a valid new email address.');
      return;
    }

    setState(() => _loading = true);
    try {
      if (!AppEnv.backendEnabled) {
        // Demo mode: apply locally, no verification round-trip.
        final user = AuthState.instance.user;
        if (user != null) {
          // Demo mode has no verification round-trip, so keep the account
          // verified to avoid RoleGuard bouncing to the verify-email screen.
          AuthState.instance.updateUser(
            user.copyWith(email: _newEmail.text.trim()),
          );
        }
        if (!mounted) return;
        AppToast.success(context, 'Email updated (demo).');
        Navigator.of(context).pop();
        return;
      }

      await ProfileApi.instance.changeEmail(
        currentPassword: _password.text,
        newEmail: _newEmail.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = 1;
      });
      AppToast.info(
        context,
        'Verification code sent to ${_newEmail.text.trim()}.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(
        context,
        'Could not change email. Check your password and that the address is free.',
      );
    }
  }

  Future<void> _verify(String code) async {
    if (code.length != 6) return;
    setState(() => _loading = true);
    try {
      await ProfileApi.instance.verifyEmailCode(
        email: _newEmail.text.trim(),
        code: code,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.success(context, 'Email verified and updated.');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.warn(context, 'Invalid or expired code. Try again.');
      _otpKey.currentState?.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_step == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Current password',
            controller: _password,
            obscureText: true,
            prefixIcon: AppIcons.lock,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'New email address',
            controller: _newEmail,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: AppIcons.email,
            hint: 'name@example.com',
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppEnv.backendEnabled
                ? 'Current email: ${widget.currentEmail}. We will send a 6-digit code to your new address to confirm.'
                : 'Demo mode — the change is applied locally without verification.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: AppEnv.backendEnabled
                ? 'Send verification code'
                : 'Update email',
            icon: AppIcons.email,
            expand: true,
            loading: _loading,
            onPressed: _loading ? null : _requestChange,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the 6-digit code',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Sent to ${_newEmail.text.trim()}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        OtpCodeField(key: _otpKey, enabled: !_loading, onCompleted: _verify),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Confirm new email',
          icon: AppIcons.check,
          expand: true,
          loading: _loading,
          onPressed: _loading
              ? null
              : () => _verify(_otpKey.currentState?.code ?? ''),
        ),
      ],
    );
  }
}
