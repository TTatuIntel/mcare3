import 'package:flutter/material.dart';

import '../core/api/auth_api.dart';
import '../core/async/app_busy.dart';
import '../core/env/app_env.dart';
import '../shared/constants/route_names.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_text_field.dart';
import '../shared/widgets/app_toast.dart';
import 'widgets/auth_shell.dart';

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _id = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_id.text.trim().isEmpty) {
      AppToast.warn(context, 'Enter your email or phone.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AppBusy.instance.run(
        () async {
          if (AppEnv.backendEnabled) {
            await AuthApi.instance.forgotPassword(_id.text.trim());
          } else {
            await Future.delayed(const Duration(milliseconds: 600));
          }
        },
        blocking: true,
        message: 'Sending instructions…',
      );
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Could not send reset link. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Reset password',
      subtitle: _sent
          ? 'If an account exists, we sent reset instructions. Check your inbox.'
          : 'Enter your email or phone — we\'ll send you a reset link.',
      child: _sent ? _doneState(context) : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Email or phone',
          hint: 'you@example.com',
          controller: _id,
          prefixIcon: AppIcons.email,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Send reset link',
          loadingLabel: 'Sending instructions…',
          size: AppButtonSize.lg,
          expand: true,
          loading: _loading,
          onPressed: _loading ? null : _send,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            onPressed: () =>
                Navigator.of(context).pushReplacementNamed(RouteNames.login),
            child: const Text('Back to sign in'),
          ),
        ),
      ],
    );
  }

  Widget _doneState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'I have a reset code',
          size: AppButtonSize.lg,
          expand: true,
          icon: AppIcons.lock,
          onPressed: () =>
              Navigator.of(context).pushNamed(RouteNames.resetPassword),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Back to sign in',
          size: AppButtonSize.lg,
          variant: AppButtonVariant.secondary,
          expand: true,
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed(RouteNames.login),
        ),
      ],
    );
  }
}
