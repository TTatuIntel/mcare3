import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/api/api_error_messages.dart';
import '../core/api/auth_api.dart';
import '../core/async/app_busy.dart';
import '../core/env/app_env.dart';
import '../shared/constants/route_names.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_text_field.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/glass_sheet.dart';
import '../shared/widgets/otp_code_field.dart';
import 'widgets/auth_shell.dart';

/// Reset credentials supplied by an emailed deep link or an SMS OTP exchange.
/// Kept beside the recovery flow so request, verification, and reset remain one
/// cohesive feature instead of separate authentication screens.
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

  /// Reads `?email=` and `?token=` when a Flutter web reset link is opened.
  static ResetPasswordArgs? fromUri() {
    if (!kIsWeb) return null;
    final query = Uri.base.queryParameters;
    final email = query['email'] ?? '';
    final token = query['token'] ?? '';
    if (email.isEmpty || token.isEmpty) return null;
    return ResetPasswordArgs(email: email, token: token);
  }
}

enum _ResetChannel { email, sms }

enum _RecoveryStage { request, emailSent, codeSent, reset, complete }

/// One responsive recovery flow for email links and phone OTPs.
///
/// [show] is the normal entry point and keeps the user visually anchored on
/// sign-in. The widget can still render inside [AuthShell] for compatibility,
/// while reset URLs open this same flow with [initialReset] pre-populated.
class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({
    super.key,
    this.initialReset,
    this.embedded = false,
  });

  final ResetPasswordArgs? initialReset;
  final bool embedded;

  static Future<void> show(
    BuildContext context, {
    ResetPasswordArgs? initialReset,
  }) {
    return GlassSheet.show<void>(
      context,
      title: 'Account recovery',
      subtitle: 'Securely verify your identity and choose a new password.',
      leadingIcon: AppIcons.lock,
      maxWidth: 560,
      maxHeightFactor: 0.94,
      child: ForgotPasswordView(initialReset: initialReset, embedded: true),
    );
  }

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _identifier = TextEditingController();
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _otpKey = GlobalKey<OtpCodeFieldState>();

  _ResetChannel _channel = _ResetChannel.email;
  late _RecoveryStage _stage;
  bool _loading = false;
  bool _verifying = false;
  String _destination = '';
  int _expiresInMinutes = 60;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    final reset = widget.initialReset ?? ResetPasswordArgs.fromUri();
    _stage = reset == null ? _RecoveryStage.request : _RecoveryStage.reset;
    if (reset != null) {
      _email.text = reset.email;
      _token.text = reset.token;
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final controller in [
      _identifier,
      _email,
      _token,
      _password,
      _confirm,
    ]) {
      controller.dispose();
    }
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

  void _goToRequest() {
    _resendTimer?.cancel();
    _otpKey.currentState?.clear();
    setState(() {
      _stage = _RecoveryStage.request;
      _resendIn = 0;
      _token.clear();
      _password.clear();
      _confirm.clear();
    });
  }

  void _closeToSignIn() {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(RouteNames.login);
    }
  }

  Future<void> _send({bool resend = false}) async {
    final identifier = _identifier.text.trim();
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
        _stage = dispatch.isSms
            ? _RecoveryStage.codeSent
            : _RecoveryStage.emailSent;
        if (!dispatch.isSms) _email.text = identifier;
      });
      _startResendCooldown();
      if (dispatch.isSms) {
        if (resend) {
          _otpKey.currentState?.clear();
          AppToast.info(context, 'A new code is on its way.');
        }
      } else if (resend) {
        AppToast.info(context, 'A new reset link is on its way.');
      }
    } on ApiException catch (error) {
      if (mounted) {
        AppToast.error(context, ApiErrorMessages.sanitize(error.message));
      }
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
    if (_verifying) return;
    if (code.length != 6) {
      AppToast.warn(context, 'Enter the complete 6-digit code.');
      return;
    }

    setState(() => _verifying = true);
    try {
      final grant = await AppBusy.instance.run(
        () => AuthApi.instance.verifyResetOtp(
          identifier: _identifier.text.trim(),
          code: code,
        ),
        blocking: true,
        message: 'Verifying code…',
      );
      if (!mounted) return;
      _resendTimer?.cancel();
      setState(() {
        _email.text = grant.email;
        _token.text = grant.token;
        _stage = _RecoveryStage.reset;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      _otpKey.currentState?.clear();
      AppToast.error(context, ApiErrorMessages.sanitize(error.message));
    } catch (_) {
      if (!mounted) return;
      _otpKey.currentState?.clear();
      AppToast.error(context, 'Could not verify that code. Try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _submitReset() async {
    final email = _email.text.trim();
    final token = _token.text.trim();
    if (email.isEmpty || token.isEmpty) {
      AppToast.warn(context, 'Reset link or code is incomplete.');
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
            await Future<void>.delayed(const Duration(milliseconds: 600));
          }
        },
        blocking: true,
        message: 'Updating password…',
      );
      if (!mounted) return;
      setState(() => _stage = _RecoveryStage.complete);
    } on ApiException catch (error) {
      if (mounted) {
        AppToast.error(context, ApiErrorMessages.sanitize(error.message));
      }
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
    final content = Column(
      key: const ValueKey('password-recovery-flow'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _progress(context),
        const SizedBox(height: AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: Column(
            key: ValueKey('recovery-${_stage.name}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppPalette.ink(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.textMuted(context),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _stageBody(context),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return content;
    return AuthShell(
      title: 'Account recovery',
      subtitle: 'Secure email or phone verification.',
      child: content,
    );
  }

  String get _title => switch (_stage) {
    _RecoveryStage.request => 'Reset your password',
    _RecoveryStage.emailSent => 'Check your email',
    _RecoveryStage.codeSent => 'Verify your phone',
    _RecoveryStage.reset => 'Create a new password',
    _RecoveryStage.complete => 'Password updated',
  };

  String get _subtitle => switch (_stage) {
    _RecoveryStage.request =>
      'Use the email or phone linked to an existing mCare account. Recovery credentials are short-lived and single-use.',
    _RecoveryStage.emailSent =>
      'If $_destination belongs to an mCare account, we sent a secure link and 6-digit code. Both expire in $_expiresInMinutes minutes.',
    _RecoveryStage.codeSent =>
      'Enter the 6-digit code sent to $_destination. It expires in $_expiresInMinutes minutes.',
    _RecoveryStage.reset =>
      'Use at least 8 characters. Finishing this step signs out every existing device.',
    _RecoveryStage.complete =>
      'Your password is secure and all previous sessions were revoked. Sign in again on this device.',
  };

  int get _progressIndex => switch (_stage) {
    _RecoveryStage.request => 0,
    _RecoveryStage.emailSent || _RecoveryStage.codeSent => 1,
    _RecoveryStage.reset || _RecoveryStage.complete => 2,
  };

  Widget _progress(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    const labels = ['Send', 'Verify', 'Reset'];
    return Semantics(
      label: 'Password recovery step ${_progressIndex + 1} of 3',
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index <= _progressIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == labels.length - 1 ? 0 : AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 4,
                    decoration: BoxDecoration(
                      color: active ? accent : AppPalette.border(context),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusPill,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    labels[index],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: active ? accent : AppPalette.textMuted(context),
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _stageBody(BuildContext context) => switch (_stage) {
    _RecoveryStage.request => _requestForm(context),
    _RecoveryStage.emailSent => _emailSentState(context),
    _RecoveryStage.codeSent => _codeForm(context),
    _RecoveryStage.reset => _resetForm(context),
    _RecoveryStage.complete => _completeState(context),
  };

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
          controller: _identifier,
          prefixIcon: _channel == _ResetChannel.sms
              ? AppIcons.phone
              : AppIcons.email,
          autofocus: true,
          keyboardType: _channel == _ResetChannel.sms
              ? TextInputType.phone
              : TextInputType.emailAddress,
          onChanged: (value) {
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
          'Send recovery instructions by',
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
                caption: 'One-tap secure link',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _channelTile(
                context,
                channel: _ResetChannel.sms,
                icon: AppIcons.phone,
                label: 'SMS code',
                caption: '6-digit verification',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Only an existing account can receive and use recovery instructions. For privacy, this screen never confirms whether an address is registered.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: _channel == _ResetChannel.sms
              ? 'Send verification code'
              : 'Send secure reset link',
          loadingLabel: 'Sending…',
          size: AppButtonSize.lg,
          expand: true,
          loading: _loading,
          onPressed: _loading ? null : _send,
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _closeToSignIn,
            child: const Text('Cancel and return to sign in'),
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
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Verify and continue',
          loadingLabel: 'Verifying…',
          size: AppButtonSize.lg,
          expand: true,
          loading: _verifying,
          onPressed: _verifying
              ? null
              : () => _verifyCode(_otpKey.currentState?.code ?? ''),
        ),
        const SizedBox(height: AppSpacing.sm),
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
            onPressed: _verifying ? null : _goToRequest,
            child: const Text('Use a different recovery method'),
          ),
        ),
      ],
    );
  }

  Widget _emailSentState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.mark_email_read_outlined,
                color: AppColors.success,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Check your inbox and spam folder. Open the secure link, or use the 6-digit code in the same email.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Enter the 6-digit email code',
          icon: AppIcons.lock,
          size: AppButtonSize.lg,
          expand: true,
          onPressed: () => setState(() => _stage = _RecoveryStage.reset),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: _resendIn > 0
              ? 'Send again in ${_resendIn}s'
              : 'Send link and code again',
          size: AppButtonSize.lg,
          variant: AppButtonVariant.secondary,
          expand: true,
          loading: _loading,
          onPressed: _loading || _resendIn > 0
              ? null
              : () => _send(resend: true),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _goToRequest,
            child: const Text('Use a different recovery method'),
          ),
        ),
      ],
    );
  }

  Widget _resetForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_email.text.isEmpty) ...[
          AppTextField(
            label: 'Email address',
            hint: 'you@example.com',
            controller: _email,
            prefixIcon: AppIcons.email,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (_token.text.isEmpty) ...[
          AppTextField(
            label: 'Reset code',
            hint: 'Paste the code from your email',
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
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Confirm new password',
          controller: _confirm,
          obscureText: true,
          canRevealObscured: true,
          prefixIcon: AppIcons.lock,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitReset(),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Update password securely',
          loadingLabel: 'Updating password…',
          size: AppButtonSize.lg,
          expand: true,
          loading: _loading,
          onPressed: _loading ? null : _submitReset,
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _goToRequest,
            child: const Text('Request a new link or code'),
          ),
        ),
      ],
    );
  }

  Widget _completeState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Icon(
            Icons.verified_user_outlined,
            size: 58,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Return to sign in',
          size: AppButtonSize.lg,
          expand: true,
          onPressed: _closeToSignIn,
        ),
      ],
    );
  }
}
