import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/api/api_error_messages.dart';
import '../core/api/auth_api.dart';
import '../core/async/app_busy.dart';
import '../shared/constants/route_names.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_text_field.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/otp_code_field.dart';
import 'reset_password_view.dart';
import 'widgets/auth_shell.dart';

/// Account recovery, step 1. The user picks how the secret reaches them: an
/// emailed reset link, or a 6-digit code by SMS which is verified here and
/// exchanged for the token the reset screen needs.
enum _ResetChannel { email, sms }

enum _Stage { request, emailSent, codeSent }

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _id = TextEditingController();
  final _otpKey = GlobalKey<OtpCodeFieldState>();

  _ResetChannel _channel = _ResetChannel.email;
  _Stage _stage = _Stage.request;
  bool _loading = false;
  bool _verifying = false;

  /// Masked address/number echoed by the API, e.g. `+234•••••5678`.
  String _destination = '';
  int _expiresInMinutes = 60;

  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _id.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 45);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _send({bool resend = false}) async {
    final identifier = _id.text.trim();
    if (identifier.isEmpty) {
      AppToast.warn(context, 'Enter your email or phone.');
      return;
    }
    if (_channel == _ResetChannel.email &&
        (!identifier.contains('@') || !identifier.contains('.'))) {
      AppToast.warn(context, 'Enter the email address on your account.');
      return;
    }
    if (_channel == _ResetChannel.sms &&
        !RegExp(r'^[\d\s()+.-]{7,}$').hasMatch(identifier)) {
      AppToast.warn(context, 'Enter the phone number on your account.');
      return;
    }

    setState(() => _loading = true);
    try {
      final dispatch = await AppBusy.instance.run(
        () => AuthApi.instance.forgotPassword(
          identifier,
          channel: _channel == _ResetChannel.sms ? 'sms' : 'email',
        ),
        blocking: true,
        message: _channel == _ResetChannel.sms
            ? 'Sending code…'
            : 'Sending instructions…',
      );
      if (!mounted) return;

      setState(() {
        _destination = dispatch.destination;
        _expiresInMinutes = dispatch.expiresInMinutes;
        _channel = dispatch.isSms ? _ResetChannel.sms : _ResetChannel.email;
        _stage = dispatch.isSms ? _Stage.codeSent : _Stage.emailSent;
      });
      if (dispatch.isSms) {
        _startResendCooldown();
        if (resend) {
          _otpKey.currentState?.clear();
          AppToast.info(context, 'A new code is on its way.');
        }
      }
    } on ApiException catch (e) {
      if (mounted)
        AppToast.error(context, ApiErrorMessages.sanitize(e.message));
    } catch (_) {
      if (mounted) {
        AppToast.error(
          context,
          'Could not send reset instructions. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode(String code) async {
    if (_verifying || code.length != 6) return;

    setState(() => _verifying = true);
    try {
      final grant = await AppBusy.instance.run(
        () => AuthApi.instance.verifyResetOtp(
          identifier: _id.text.trim(),
          code: code,
        ),
        blocking: true,
        message: 'Verifying code…',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        RouteNames.resetPassword,
        arguments: ResetPasswordArgs(email: grant.email, token: grant.token),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _otpKey.currentState?.clear();
      AppToast.error(context, ApiErrorMessages.sanitize(e.message));
    } catch (_) {
      if (!mounted) return;
      _otpKey.currentState?.clear();
      AppToast.error(context, 'Could not verify that code. Try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: switch (_stage) {
        _Stage.request => 'Reset password',
        _Stage.emailSent => 'Check your email',
        _Stage.codeSent => 'Enter your code',
      },
      subtitle: switch (_stage) {
        _Stage.request =>
          'Enter your email or phone, then choose how to receive your reset '
              'instructions.',
        _Stage.emailSent =>
          'If an account exists, we sent a reset link to $_destination. '
              'It expires in $_expiresInMinutes minutes.',
        _Stage.codeSent =>
          'We texted a 6-digit code to $_destination. '
              'It expires in $_expiresInMinutes minutes.',
      },
      child: switch (_stage) {
        _Stage.request => _requestForm(context),
        _Stage.emailSent => _emailSentState(context),
        _Stage.codeSent => _codeForm(context),
      },
    );
  }

  Widget _requestForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: _channel == _ResetChannel.sms
              ? 'Phone number'
              : 'Email address',
          hint: _channel == _ResetChannel.sms
              ? '+256 700 000 000'
              : 'you@example.com',
          controller: _id,
          prefixIcon: _channel == _ResetChannel.sms
              ? AppIcons.phone
              : AppIcons.email,
          keyboardType: _channel == _ResetChannel.sms
              ? TextInputType.phone
              : TextInputType.emailAddress,
          onChanged: (value) {
            // Typing a phone number pre-selects SMS; an address containing "@"
            // pre-selects email. Either can still be overridden by tapping.
            final trimmed = value.trim();
            if (trimmed.isEmpty) return;
            final looksLikePhone =
                !trimmed.contains('@') &&
                RegExp(r'^[\d\s()+.-]{7,}$').hasMatch(trimmed);
            final next = looksLikePhone
                ? _ResetChannel.sms
                : _ResetChannel.email;
            if (next != _channel) setState(() => _channel = next);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Send my reset instructions by',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _channelTile(
                context,
                channel: _ResetChannel.email,
                icon: AppIcons.email,
                label: 'Email link',
                caption: 'A one-tap reset link',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _channelTile(
                context,
                channel: _ResetChannel.sms,
                icon: AppIcons.phone,
                label: 'Text a code',
                caption: '6 digits by SMS',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: _channel == _ResetChannel.sms
              ? 'Send code by SMS'
              : 'Send reset link',
          loadingLabel: 'Sending…',
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

  Widget _channelTile(
    BuildContext context, {
    required _ResetChannel channel,
    required IconData icon,
    required String label,
    required String caption,
  }) {
    final selected = _channel == channel;
    final accent = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label. $caption',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: _loading ? null : () => setState(() => _channel = channel),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.08)
                : AppPalette.surface(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected ? accent : AppPalette.border(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? accent : AppPalette.textMuted(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : AppPalette.ink(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OtpCodeField(
          key: _otpKey,
          enabled: !_verifying,
          onCompleted: _verifyCode,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Verify code',
          loadingLabel: 'Verifying code…',
          size: AppButtonSize.lg,
          expand: true,
          loading: _verifying,
          onPressed: _verifying
              ? null
              : () => _verifyCode(_otpKey.currentState?.code ?? ''),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            onPressed: _resendIn > 0 || _loading
                ? null
                : () => _send(resend: true),
            child: Text(
              _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _stage = _Stage.request),
            child: const Text('Use a different method'),
          ),
        ),
      ],
    );
  }

  Widget _emailSentState(BuildContext context) {
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
          label: 'Send it again',
          size: AppButtonSize.lg,
          variant: AppButtonVariant.secondary,
          expand: true,
          loading: _loading,
          onPressed: _loading ? null : () => _send(resend: true),
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
}
