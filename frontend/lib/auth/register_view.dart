import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../core/async/app_busy.dart';
import '../shared/constants/route_names.dart';
import '../shared/services/auth_service.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_motion.dart';
import '../shared/widgets/modal_scrim.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_text_field.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/responsive.dart';
import 'widgets/auth_shell.dart';
import 'widgets/auth_form_layout.dart';
import 'widgets/social_buttons.dart';

/// Patient-only signup. Clinicians, assistants, and admins do not self-register
/// — they are provisioned by an administrator and use the shared login screen.
class RegisterView extends StatefulWidget {
  const RegisterView({super.key, this.asSheet = false});

  /// When true, the view is hosted inside a bottom sheet over the landing page.
  final bool asSheet;

  /// Opens register as a compact sheet on handheld, full page on desktop.
  static Future<void> show(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    if (tier.isHandheld) {
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        barrierLabel: 'Dismiss',
        transitionDuration: AppMotion.pageFast,
        transitionBuilder: (ctx, animation, secondary, child) => child,
        pageBuilder: (ctx, animation, secondary) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.easeOut,
            reverseCurve: Curves.easeInCubic,
          );
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FadeTransition(
                  opacity: curved,
                  child: ModalScrim(onTap: () => Navigator.of(ctx).pop()),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(curved),
                      child: FadeTransition(
                        opacity: curved,
                        child: const RegisterView(asSheet: true),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    return Navigator.of(context).pushNamed(RouteNames.register);
  }

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _terms = false;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _completeSignUp({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    String? password,
  }) async {
    setState(() => _loading = true);
    final result = await AppBusy.instance.run(
      () => AuthService.instance.registerPatient(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone ?? '',
        password: password ?? _password.text,
      ),
      blocking: true,
      message: 'Creating account…',
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.isSuccess) {
      AppToast.error(context, result.errorMessage ?? 'Registration failed.');
      return;
    }
    AppToast.success(context, 'Account created! Let\'s set up your profile.');
    AuthService.instance.completeNavigation(context, result);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_terms) {
      AppToast.warn(context, 'Please accept the Terms and Privacy Policy.');
      return;
    }
    await _completeSignUp(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
    );
  }

  Future<void> _signUpWithGoogle() async {
    if (_loading) return;
    if (!_terms) {
      AppToast.warn(context, 'Please accept the Terms and Privacy Policy.');
      return;
    }
    setState(() => _loading = true);
    final result = await AuthService.instance.signInWithGoogle(
      context: context,
      createAccount: true,
      remember: true,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.cancelled) return;
    if (!result.isSuccess) {
      AppToast.error(context, result.errorMessage ?? 'Google sign-up failed.');
      return;
    }
    AppToast.success(
      context,
      'Signed up with Google! Let\'s set up your profile.',
    );
    AuthService.instance.completeNavigation(context, result);
  }

  Future<void> _signUpWithApple() async {
    if (_loading) return;
    if (!_terms) {
      AppToast.warn(context, 'Please accept the Terms and Privacy Policy.');
      return;
    }
    setState(() => _loading = true);
    final result = await AuthService.instance.signInWithApple(
      context: context,
      createAccount: true,
      remember: true,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.cancelled) return;
    if (!result.isSuccess) {
      AppToast.error(context, result.errorMessage ?? 'Apple sign-up failed.');
      return;
    }
    AppToast.success(
      context,
      'Signed up with Apple! Let\'s set up your profile.',
    );
    AuthService.instance.completeNavigation(context, result);
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final compact = widget.asSheet || tier.isHandheld;
    const fieldGap = AuthFormLayout.fieldGap;
    const sectionGap = AuthFormLayout.sectionGap;
    const btnSize = AuthFormLayout.buttonSize;
    const denseFields = AuthFormLayout.denseFields;

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SocialSignInRow(
            compact: true,
            onGoogle: _signUpWithGoogle,
            onApple: _signUpWithApple,
          ),
          const SizedBox(height: sectionGap),
          const OrDivider(label: 'or sign up with email'),
          const SizedBox(height: sectionGap),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'First name',
                  hint: 'Amara',
                  controller: _firstName,
                  prefixIcon: AppIcons.user,
                  dense: denseFields,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(
                  label: 'Last name',
                  hint: 'Okonkwo',
                  controller: _lastName,
                  dense: denseFields,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
            ],
          ),
          SizedBox(height: fieldGap),
          AppTextField(
            label: 'Email',
            hint: 'you@example.com',
            controller: _email,
            prefixIcon: AppIcons.email,
            keyboardType: TextInputType.emailAddress,
            dense: denseFields,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (!v.contains('@')) return 'Invalid email';
              return null;
            },
          ),
          SizedBox(height: fieldGap),
          AppTextField(
            label: 'Phone',
            hint: '+254 712 000 000',
            controller: _phone,
            prefixIcon: AppIcons.phone,
            keyboardType: TextInputType.phone,
            dense: denseFields,
            validator: (v) =>
                (v == null || v.trim().length < 7) ? 'Invalid phone' : null,
          ),
          SizedBox(height: fieldGap),
          AppTextField(
            label: 'Password',
            hint: 'At least 8 characters',
            controller: _password,
            prefixIcon: AppIcons.lock,
            obscureText: true,
            canRevealObscured: true,
            dense: denseFields,
            validator: (v) =>
                (v == null || v.length < 8) ? 'Min 8 characters' : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _terms,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() => _terms = v ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: compact ? 4 : 14),
                  child: Text(
                    'I agree to the Terms of Service and Privacy Policy.',
                    style: TextStyle(
                      fontSize: compact ? 11 : 13,
                      color: AppPalette.textMuted(context),
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
          AppButton(
            label: compact ? 'Create account' : 'Create patient account',
            loadingLabel: 'Creating account…',
            size: btnSize,
            expand: true,
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
          if (compact) ...[
            const SizedBox(height: AppSpacing.sm),
            _ClinicianNotice(compact: true, inSheet: widget.asSheet),
          ],
        ],
      ),
    );

    final shell = AuthShell(
      compact: compact,
      embedded: widget.asSheet,
      balanceContent: !widget.asSheet,
      onClose: widget.asSheet ? _close : null,
      title: compact ? 'Create account' : 'Create your patient account',
      subtitle: compact
          ? 'Track vitals, get alerts and stay connected.'
          : 'Track your vitals, get instant alerts and stay connected to your '
                'care team — all in one place.',
      footer: _footer(context, compact: compact),
      maxCardWidth: compact ? 380 : 460,
      child: compact
          ? form
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ClinicianNotice(),
                const SizedBox(height: AppSpacing.xl),
                form,
              ],
            ),
    );

    if (!widget.asSheet) return shell;

    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.max(320.0, screenHeight * 0.90 - viewInsets.bottom);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusXl),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppPalette.surface(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusXl),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 28,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    Center(
                      child: Container(
                        height: 4,
                        width: 36,
                        decoration: BoxDecoration(
                          color: AppPalette.borderStrong(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xs,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: shell,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, {required bool compact}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account?',
          style: TextStyle(
            color: AppPalette.textMuted(context),
            fontSize: compact ? 11.5 : null,
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: compact ? VisualDensity.compact : null,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm)
                : null,
          ),
          onPressed: () {
            if (widget.asSheet) _close();
            Navigator.of(context).pushNamed(RouteNames.login);
          },
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}

/// Clinician boundary notice — compact inline on sheet, soft banner on desktop.
class _ClinicianNotice extends StatefulWidget {
  const _ClinicianNotice({this.compact = false, this.inSheet = false});
  final bool compact;
  final bool inSheet;

  @override
  State<_ClinicianNotice> createState() => _ClinicianNoticeState();
}

class _ClinicianNoticeState extends State<_ClinicianNotice> {
  late final TapGestureRecognizer _signInTap;

  @override
  void initState() {
    super.initState();
    _signInTap = TapGestureRecognizer()
      ..onTap = () {
        if (widget.inSheet) {
          Navigator.of(context).pop();
          Navigator.of(context).pushNamed(RouteNames.login);
        } else {
          Navigator.of(context).pushReplacementNamed(RouteNames.login);
        }
      };
  }

  @override
  void dispose() {
    _signInTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: AppPalette.textMuted(context),
            ),
            children: [
              const TextSpan(text: 'Clinician or assistant? '),
              TextSpan(
                text: 'Sign in here.',
                style: const TextStyle(
                  color: AppColors.brandIndigo,
                  fontWeight: FontWeight.w700,
                ),
                recognizer: _signInTap,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.infoSoft(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.info.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.info, size: 18, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppPalette.ink(context),
                ),
                children: [
                  const TextSpan(
                    text: 'Clinician or assistant? ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text: 'Your account is provisioned by your administrator. ',
                  ),
                  TextSpan(
                    text: 'Sign in here.',
                    style: const TextStyle(
                      color: AppColors.brandIndigo,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: _signInTap,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
