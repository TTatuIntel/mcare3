import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/env/app_env.dart';
import '../../core/mock/mock_otp_service.dart';
import '../../core/push/push_notification_service.dart';
import '../auth/auth_state.dart';
import '../models/notification_item.dart';
import '../models/user_role.dart';
import '../navigation/profile_navigation.dart';
import '../state/notification_state.dart';
import '../state/settings_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/otp_code_field.dart';

/// Role-agnostic self-service password change. OTP flow in mock mode,
/// server-side verification when the backend is reachable.
class ChangePasswordSheet {
  ChangePasswordSheet._();

  static Future<void> show(BuildContext context) {
    final user = AuthState.instance.user;
    if (user == null) return Future.value();
    return GlassSheet.show(
      context,
      title: 'Change password',
      subtitle: 'Verify with a one-time code sent to your phone or email.',
      child: _ChangePasswordForm(userEmail: user.email),
    );
  }
}

class _ChangePasswordForm extends StatefulWidget {
  const _ChangePasswordForm({required this.userEmail});
  final String userEmail;

  @override
  State<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<_ChangePasswordForm> {
  final _current = TextEditingController();
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();
  final _otpKey = GlobalKey<OtpCodeFieldState>();
  int _step = 0;
  bool _loading = false;
  String? _demoOtp;

  @override
  void dispose() {
    _current.dispose();
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_current.text.isEmpty) {
      AppToast.warn(context, 'Enter your current password first.');
      return;
    }
    if (_newPass.text.length < 8) {
      AppToast.warn(context, 'New password must be at least 8 characters.');
      return;
    }
    if (_newPass.text != _confirm.text) {
      AppToast.warn(context, 'New passwords do not match.');
      return;
    }

    if (AppEnv.backendEnabled) {
      await _saveBackend();
      return;
    }

    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    _demoOtp = MockOtpService.send(purpose: 'password_change');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = 1;
    });
    AppToast.info(context, 'Verification code sent. Demo code: $_demoOtp');
  }

  Future<void> _saveBackend() async {
    setState(() => _loading = true);
    try {
      await ApiClient.instance.post(
        '/auth/change-password',
        body: {
          'current_password': _current.text,
          'new_password': _newPass.text,
          'new_password_confirmation': _confirm.text,
        },
      );
      await PushNotificationService.instance.setEnabled(
        SettingsState.instance.notifications.pushEnabled,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      final user = AuthState.instance.user;
      if (user != null && user.mustChangePassword) {
        AuthState.instance.updateUser(user.copyWith(mustChangePassword: false));
      }
      final settingsRoute = user != null
          ? ProfileNavigation.settingsRouteFor(user.role)
          : null;
      NotificationState.instance.add(
        AppNotification(
          id: 'pwd_${DateTime.now().millisecondsSinceEpoch}',
          kind: NotificationKind.profile,
          title: 'Password changed',
          body: 'Your password was updated successfully.',
          createdAt: DateTime.now(),
          actionRoute:
              settingsRoute ??
              ProfileNavigation.profileRouteFor(user?.role ?? UserRole.patient),
        ),
      );
      AppToast.success(context, 'Password updated.');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(
        context,
        'Could not update password. Check your current password.',
      );
    }
  }

  Future<void> _verifyAndSave(String code) async {
    if (code.length != 6) return;
    setState(() => _loading = true);

    if (AppEnv.backendEnabled) {
      await _saveBackend();
      return;
    }

    final result = await AuthState.instance.changePassword(
      currentPassword: _current.text,
      newPassword: _newPass.text,
      otpCode: code,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case PasswordChangeResult.success:
        final user = AuthState.instance.user;
        final settingsRoute = user != null
            ? ProfileNavigation.settingsRouteFor(user.role)
            : null;
        NotificationState.instance.add(
          AppNotification(
            id: 'pwd_${DateTime.now().millisecondsSinceEpoch}',
            kind: NotificationKind.profile,
            title: 'Password changed',
            body: 'Your password was updated successfully.',
            createdAt: DateTime.now(),
            actionRoute:
                settingsRoute ??
                ProfileNavigation.profileRouteFor(
                  user?.role ?? UserRole.patient,
                ),
          ),
        );
        AppToast.success(context, 'Password updated.');
        Navigator.of(context).pop();
      case PasswordChangeResult.wrongPassword:
        AppToast.warn(context, 'Current password is incorrect.');
        _otpKey.currentState?.clear();
      case PasswordChangeResult.weakPassword:
        AppToast.warn(context, 'Password must be at least 8 characters.');
      case PasswordChangeResult.invalidOtp:
        AppToast.warn(context, 'Invalid code. Try again.');
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
            controller: _current,
            obscureText: true,
            prefixIcon: AppIcons.lock,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'New password',
            controller: _newPass,
            obscureText: true,
            prefixIcon: AppIcons.lock,
            hint: 'At least 8 characters',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Confirm new password',
            controller: _confirm,
            obscureText: true,
            prefixIcon: AppIcons.lock,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppEnv.backendEnabled
                ? 'Your current password will be verified on the server.'
                : 'We will send a 6-digit code to ${widget.userEmail} to confirm this change.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: AppEnv.backendEnabled
                ? 'Update password'
                : 'Send verification code',
            icon: AppIcons.email,
            expand: true,
            loading: _loading,
            onPressed: _loading ? null : _sendOtp,
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
          'Sent to ${widget.userEmail}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        OtpCodeField(
          key: _otpKey,
          enabled: !_loading,
          onCompleted: _verifyAndSave,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Confirm password change',
          icon: AppIcons.check,
          expand: true,
          loading: _loading,
          onPressed: _loading
              ? null
              : () => _verifyAndSave(_otpKey.currentState?.code ?? ''),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: _loading ? null : _sendOtp,
          child: const Text('Resend code'),
        ),
      ],
    );
  }
}
