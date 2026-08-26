import 'package:flutter/foundation.dart';
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

/// Token + email reset flow — linked from forgot-password email.
class ResetPasswordArgs {
  const ResetPasswordArgs({required this.email, required this.token});

  final String email;
  final String token;

  static ResetPasswordArgs? tryParse(Object? raw) {
    if (raw is ResetPasswordArgs) return raw;
    if (raw is Map) {
      final email = raw['email']?.toString() ?? '';
      final token = raw['token']?.toString() ?? '';
      if (email.isNotEmpty && token.isNotEmpty) {
        return ResetPasswordArgs(email: email, token: token);
      }
    }
    return null;
  }

  /// Reads `?email=` and `?token=` when opened on Flutter web.
  static ResetPasswordArgs? fromUri() {
    if (!kIsWeb) return null;
    final q = Uri.base.queryParameters;
    final email = q['email'] ?? '';
    final token = q['token'] ?? '';
    if (email.isEmpty || token.isEmpty) return null;
    return ResetPasswordArgs(email: email, token: token);
  }
}

class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key, this.args});

  final ResetPasswordArgs? args;

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  late final TextEditingController _email;
  late final TextEditingController _token;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final resolved = widget.args ?? ResetPasswordArgs.fromUri();
    _email = TextEditingController(text: resolved?.email ?? '');
    _token = TextEditingController(text: resolved?.token ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final token = _token.text.trim();
    if (email.isEmpty || token.isEmpty) {
      AppToast.warn(context, 'Reset link is invalid or incomplete.');
      return;
    }
    if (_password.text.length < 8) {
      AppToast.warn(context, 'Password must be at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      AppToast.warn(context, 'Passwords do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      await AppBusy.instance.run(
        () async {
          if (AppEnv.backendEnabled) {
            await AuthApi.instance.resetPassword(
              email: email,
              token: token,
              password: _password.text,
            );
          } else {
            await Future.delayed(const Duration(milliseconds: 600));
          }
        },
        blocking: true,
        message: 'Updating your password…',
      );
      if (!mounted) return;
      setState(() => _done = true);
    } catch (_) {
      if (mounted) {
        AppToast.error(
          context,
          'Could not reset password. The link may have expired.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Choose a new password',
      subtitle: _done
          ? 'Your password was updated. You can sign in now.'
          : 'Enter the reset code from your email and a new password.',
      child: _done ? _doneState(context) : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final hasPrefill = _email.text.isNotEmpty && _token.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasPrefill) ...[
          AppTextField(
            label: 'Email',
            hint: 'you@example.com',
            controller: _email,
            prefixIcon: AppIcons.email,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Reset code',
            hint: 'Paste code from email',
            controller: _token,
            prefixIcon: AppIcons.lock,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppTextField(
          label: 'New password',
          hint: 'At least 8 characters',
          controller: _password,
          obscureText: true,
          canRevealObscured: true,
          prefixIcon: AppIcons.lock,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Confirm password',
          controller: _confirm,
          obscureText: true,
          canRevealObscured: true,
          prefixIcon: AppIcons.lock,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Update password',
          loadingLabel: 'Updating your password…',
          size: AppButtonSize.lg,
          expand: true,
          loading: _loading,
          onPressed: _loading ? null : _submit,
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
    return AppButton(
      label: 'Sign in',
      size: AppButtonSize.lg,
      expand: true,
      onPressed: () =>
          Navigator.of(context).pushReplacementNamed(RouteNames.login),
    );
  }
}
