import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api/auth_api.dart';
import '../core/api/api_client.dart';
import '../core/async/app_busy.dart';
import '../core/env/app_env.dart';
import '../shared/auth/auth_state.dart';
import '../shared/constants/route_names.dart';
import '../shared/services/auth_service.dart';
import '../shared/services/auth_storage.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/glass_sheet.dart';
import '../shared/widgets/otp_code_field.dart';

/// How the account was proven, for the caller deciding where to go next.
enum VerificationOutcome {
  /// Finished — by code here, or by a link the person opened elsewhere.
  verified,

  /// Closed without finishing. The account still exists and is unverified.
  dismissed,
}

/// Proving an email address, as a popup over wherever the person already is.
///
/// This used to be a full page pushed onto the stack, which made verification
/// look like the next step of signing up rather than a short interruption in
/// it — and left no way back if the person needed to go and check something.
/// A sheet says the truth: one small thing to finish, and the app is waiting
/// underneath.
///
/// It watches for all three ways this ends. The person types the code; or they
/// tap the emailed link on this device and come back; or they tap it on a
/// desktop, in which case nothing at all reaches this screen — so it asks the
/// server, quietly, until the answer changes.
class VerifyEmailSheet extends StatefulWidget {
  const VerifyEmailSheet({super.key, this.initialStatus, this.dispatch});

  /// `verified` / `invalid` when the app was opened from a verification link.
  final String? initialStatus;

  /// What the sign-up or sign-in response already said about the code it
  /// sent. Passed in so the sheet can name the inbox on its first frame
  /// instead of showing a bare row of boxes.
  final VerificationDispatch? dispatch;

  /// Opens the sheet and resolves once verification finishes or is dismissed.
  static Future<VerificationOutcome> show(
    BuildContext context, {
    String? initialStatus,
    VerificationDispatch? dispatch,
  }) async {
    final result = await GlassSheet.show<VerificationOutcome>(
      context,
      title: 'Verify your email',
      subtitle: 'One step left before your account is ready.',
      leadingIcon: AppIcons.email,
      maxWidth: 460,
      maxHeightFactor: 0.9,
      child: VerifyEmailSheet(initialStatus: initialStatus, dispatch: dispatch),
    );
    return result ?? VerificationOutcome.dismissed;
  }

  @override
  State<VerifyEmailSheet> createState() => _VerifyEmailSheetState();
}

class _VerifyEmailSheetState extends State<VerifyEmailSheet> {
  final _codeKey = GlobalKey<OtpCodeFieldState>();

  VerificationDispatch? _dispatch;
  bool _verifying = false;
  bool _resending = false;
  bool _codeRejected = false;
  String? _error;
  int _resendIn = 0;
  Timer? _cooldown;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // A link opened on this device lands back here already finished. Say so
    // and close, rather than asking for a code that is no longer needed.
    if (widget.initialStatus == 'verified') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirmFromLink());
    } else {
      if (widget.initialStatus == 'invalid') {
        _error = 'That verification link has expired or was already used. '
            'Ask for a new one below.';
      }
      _dispatch = widget.dispatch;
      if (widget.dispatch != null && !widget.dispatch!.delivered) {
        _error = 'We could not deliver the code. Check the address, then '
            'send it again.';
      }
      // The server said how long it wants; only fall back to the shared
      // default when this sheet was opened without a dispatch to read.
      _startCooldown(
        widget.dispatch?.retryAfter ?? AuthApi.resendCooldownSeconds,
      );
      _startPolling();
    }
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  String get _identifier {
    final user = AuthState.instance.user;
    return user?.email ?? user?.phone ?? '';
  }

  // --- The three ways this ends ---------------------------------------------

  /// The link was opened on this device; the account is already verified.
  Future<void> _confirmFromLink() async {
    final ok = await AuthService.instance.refreshVerificationStatus();
    if (!mounted) return;
    if (ok) {
      _finish('Email verified.');
      return;
    }
    // Verified in the browser but no session here to hydrate — the person has
    // to sign in, which is a better answer than a code field that will now
    // reject every code.
    setState(() {
      _error = 'Your email is verified. Sign in to continue.';
    });
  }

  /// The link was opened elsewhere. Nothing tells us but the server.
  void _startPolling() {
    if (!AppEnv.backendEnabled) return;
    _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_verifying || _resending) return;
      final ok = await AuthService.instance.refreshVerificationStatus();
      if (!mounted || !ok) return;
      _finish('Email verified from your link.');
    });
  }

  Future<void> _verify(String code) async {
    if (code.length != 6 || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
      _codeRejected = false;
    });

    try {
      final verified = await AppBusy.instance.run(
        () async {
          if (!AppEnv.backendEnabled) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            return true;
          }
          final stored = await AuthStorage.read();
          final data = await AuthApi.instance.verifyOtp(
            identifier: _identifier,
            code: code,
            purpose: 'email_verify',
            remember: stored?.remember ?? false,
            deviceName: AuthService.instance.deviceName,
          );
          if (data == null) return false;
          final result = await AuthService.instance.completeOtpPayload(data);
          return result.isSuccess;
        },
        blocking: true,
        message: 'Verifying…',
      );

      if (!mounted) return;
      if (verified) {
        _finish('Email verified.');
        return;
      }
      _rejectCode('That code was not accepted. Check it and try again.');
    } on ApiException catch (e) {
      if (mounted) _rejectCode(e.message);
    } catch (_) {
      if (mounted) {
        _rejectCode('We could not reach the server. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _rejectCode(String message) {
    setState(() {
      _error = message;
      _codeRejected = true;
    });
    _codeKey.currentState?.clear();
  }

  void _finish(String message) {
    _poll?.cancel();
    _cooldown?.cancel();
    AppToast.success(context, message);
    Navigator.of(context).pop(VerificationOutcome.verified);
  }

  // --- Resend ---------------------------------------------------------------

  Future<void> _resend({String? channel}) async {
    if (_resending || (_resendIn > 0 && channel == null)) return;
    setState(() {
      _resending = true;
      _error = null;
    });

    try {
      final dispatch = await AuthApi.instance.resendOtp(
        identifier: _identifier,
        channel: channel,
      );
      if (!mounted) return;
      setState(() {
        _dispatch = dispatch;
        _codeRejected = false;
      });
      _codeKey.currentState?.clear();
      _startCooldown(
        dispatch.retryAfter > 0
            ? dispatch.retryAfter
            : AuthApi.resendCooldownSeconds,
      );
      AppToast.success(context, dispatch.destinationSentence);
    } on ApiException catch (e) {
      if (!mounted) return;
      // A refused send must not start a countdown — that would hide the retry
      // behind a timer for a code that never went anywhere.
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'We could not send the code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _startCooldown(int seconds) {
    _cooldown?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dispatch = _dispatch;
    final email = dispatch?.email ?? AuthState.instance.user?.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          email == null
              ? 'Enter the 6-digit code we sent you, or tap the link in the '
                    'email.'
              : 'Enter the 6-digit code we sent to $email — or just tap the '
                    'link in that email, on any device.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppPalette.textMuted(context),
            height: 1.45,
          ),
        ),
        if (dispatch != null && dispatch.sentBySms) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'We also texted it to ${dispatch.phone}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),

        OtpCodeField(
          key: _codeKey,
          enabled: !_verifying,
          hasError: _codeRejected,
          onChanged: (_) {
            if (_codeRejected) setState(() => _codeRejected = false);
          },
          onCompleted: _verify,
        ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(AppIcons.alert, size: 16, color: AppColors.critical),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.critical,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Verify',
          loadingLabel: 'Verifying…',
          size: AppButtonSize.lg,
          expand: true,
          loading: _verifying,
          onPressed: _verifying
              ? null
              : () => _verify(_codeKey.currentState?.code ?? ''),
        ),

        const SizedBox(height: AppSpacing.md),
        _resendRow(theme),

        // Only offered when there is a number to text. A dead "send by SMS"
        // button is worse than no button: it promises a way out that is not
        // there.
        if (dispatch?.smsAvailable ?? false) ...[
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: TextButton.icon(
              onPressed: _resending ? null : () => _resend(channel: 'sms'),
              icon: const Icon(AppIcons.phone, size: 16),
              label: const Text('Send the code by SMS instead'),
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: _verifying ? null : _signOutAndClose,
            child: Text(
              'Verify later',
              style: TextStyle(color: AppPalette.textMuted(context)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resendRow(ThemeData theme) {
    final waiting = _resendIn > 0;
    return Center(
      child: TextButton(
        onPressed: waiting || _resending ? null : () => _resend(),
        child: Text(
          _resending
              ? 'Sending…'
              : waiting
              ? 'Resend code in ${_resendIn}s'
              : 'Resend code',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: waiting ? AppPalette.textMuted(context) : null,
          ),
        ),
      ),
    );
  }

  void _signOutAndClose() {
    _poll?.cancel();
    _cooldown?.cancel();
    Navigator.of(context).pop(VerificationOutcome.dismissed);
  }
}

/// Route host for `/verify-email`.
///
/// The route still exists — it is where the emailed link lands — but it no
/// longer renders a page of its own. It shows the landing screen with the
/// sheet over it, so arriving from an email looks like arriving anywhere else.
class VerifyEmailRouteHost extends StatefulWidget {
  const VerifyEmailRouteHost({super.key, required this.child, this.status});

  /// What the page underneath the sheet is.
  final Widget child;

  /// `verified` / `invalid`, read off the link the person followed.
  final String? status;

  @override
  State<VerifyEmailRouteHost> createState() => _VerifyEmailRouteHostState();
}

class _VerifyEmailRouteHostState extends State<VerifyEmailRouteHost> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (_opened || !mounted) return;
    _opened = true;

    final outcome = await VerifyEmailSheet.show(
      context,
      initialStatus: widget.status,
    );
    if (!mounted) return;

    final user = AuthState.instance.user;
    if (outcome == VerificationOutcome.verified && user != null) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AuthService.instance.routeAfterAuth(user),
        (_) => false,
      );
      return;
    }

    // Dismissed, or verified in a browser with no session here: sign-in is the
    // only place that can carry on from either.
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(RouteNames.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
