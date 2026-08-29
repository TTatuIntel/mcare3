import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api/auth_api.dart';
import '../core/async/app_busy.dart';
import '../core/env/app_env.dart';
import '../shared/auth/auth_state.dart';
import '../shared/services/auth_service.dart';
import '../shared/services/auth_storage.dart';
import '../shared/constants/route_names.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_toast.dart';
import 'widgets/auth_shell.dart';

class OtpView extends StatefulWidget {
  const OtpView({super.key, this.isEmail = false});
  final bool isEmail;

  @override
  State<OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends State<OtpView> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  int _resendIn = 30;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _resendIn = (_resendIn - 1).clamp(0, 60));
      if (_resendIn > 0) _tick();
    });
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

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_code.length != 6) {
      AppToast.warn(context, 'Enter the 6-digit code.');
      return;
    }
    setState(() => _loading = true);
    try {
      final verifiedByApi = await AppBusy.instance.run(
        () async {
          if (AppEnv.backendEnabled) {
            final user = AuthState.instance.user;
            final identifier = user?.email ?? user?.phone ?? '';
            final storedSession = await AuthStorage.read();
            final data = await AuthApi.instance.verifyOtp(
              identifier: identifier.isNotEmpty
                  ? identifier
                  : 'demo@mcare.health',
              code: _code,
              purpose: widget.isEmail ? 'email_verify' : 'login',
              remember: storedSession?.remember ?? false,
              deviceName: AuthService.instance.deviceName,
            );
            if (data == null) return false;
            final result = await AuthService.instance.completeOtpPayload(data);
            if (!result.isSuccess) return false;
            if (mounted)
              AuthService.instance.completeNavigation(context, result);
            return true;
          } else {
            await Future.delayed(const Duration(milliseconds: 600));
            return true;
          }
        },
        blocking: true,
        message: 'Verifying account…',
      );
      if (!mounted) return;
      if (verifiedByApi) {
        AppToast.success(context, 'Verified.');
        if (!AppEnv.backendEnabled) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(RouteNames.patientDashboard, (_) => false);
        }
        return;
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Invalid or expired code.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Verify your ${widget.isEmail ? 'email' : 'phone'}',
      subtitle: widget.isEmail
          ? 'We sent a 6-digit code to your email. Enter it below.'
          : 'We sent a 6-digit code by SMS. Enter it below.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              return SizedBox(
                width: 48,
                height: 56,
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _nodes[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide(color: AppPalette.border(context)),
                    ),
                  ),
                  onChanged: (v) {
                    if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
                    if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
                    if (_code.length == 6) _verify();
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Verify',
            loadingLabel: 'Verifying…',
            size: AppButtonSize.lg,
            expand: true,
            loading: _loading,
            onPressed: _loading ? null : _verify,
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: TextButton(
              onPressed: _resendIn > 0
                  ? null
                  : () async {
                      setState(() => _resendIn = 30);
                      _tick();
                      try {
                        final user = AuthState.instance.user;
                        await AuthApi.instance.resendOtp(
                          identifier: user?.email ?? '',
                        );
                        if (context.mounted) {
                          AppToast.info(context, 'Verification code resent.');
                        }
                      } catch (_) {
                        if (context.mounted) {
                          AppToast.error(context, 'Could not resend the code.');
                        }
                      }
                    },
              child: Text(
                _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
