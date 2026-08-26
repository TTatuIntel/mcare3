import 'package:flutter/material.dart';

import '../core/async/app_busy.dart';
import '../shared/constants/route_names.dart';
import '../shared/services/auth_service.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_text_field.dart';
import '../shared/navigation/root_navigator.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/responsive.dart';
import 'register_view.dart';
import 'widgets/auth_shell.dart';
import 'widgets/auth_form_layout.dart';
import 'widgets/social_buttons.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController(text: 'admin@mcare.health');
  final _password = TextEditingController(text: 'demo-password');
  bool _loading = false;
  bool _remember = true;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final result = await AppBusy.instance.run(
      () => AuthService.instance.signInWithPassword(
        identifier: _identifier.text.trim(),
        password: _password.text,
      ),
      blocking: true,
      message: 'Signing you in…',
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.isSuccess) {
      AppToast.error(context, result.errorMessage ?? 'Sign-in failed.');
      return;
    }
    final user = result.user!;
    AuthService.instance.completeNavigation(context, result);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final root = rootNavigatorKey.currentContext;
      if (root != null) {
        AppToast.success(root, 'Welcome back, ${user.firstName}.');
      }
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
  final result = await AuthService.instance.signInWithGoogle(
      context: context,
      createAccount: false,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.cancelled) return;
    if (!result.isSuccess) {
      AppToast.error(context, result.errorMessage ?? 'Google sign-in failed.');
      return;
    }
    AuthService.instance.completeNavigation(context, result);
  }

  Future<void> _signInWithApple() async {
    if (_loading) return;
    setState(() => _loading = true);
    final result = await AuthService.instance.signInWithApple(
      context: context,
      createAccount: false,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.cancelled) return;
    if (!result.isSuccess) {
      AppToast.error(context, result.errorMessage ?? 'Apple sign-in failed.');
      return;
    }
    AuthService.instance.completeNavigation(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final handheld = ResponsiveBuilder.of(context).isHandheld;
    return AuthShell(
      showSignIn: false,
      compact: handheld,
      title: 'Welcome back',
      subtitle: 'Sign in to your mCare account',
      footer: _footer(context),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SocialSignInRow(
              compact: true,
              onGoogle: _loading ? null : _signInWithGoogle,
              onApple: _loading ? null : _signInWithApple,
            ),
            const SizedBox(height: AuthFormLayout.sectionGap),
            const OrDivider(label: 'or use your email'),
            const SizedBox(height: AuthFormLayout.sectionGap),
            AppTextField(
              label: 'Email, phone, or mCare ID',
              hint: 'you@example.com',
              prefixIcon: AppIcons.user,
              controller: _identifier,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              dense: AuthFormLayout.denseFields,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AuthFormLayout.fieldGap),
            AppTextField(
              label: 'Password',
              hint: 'Your password',
              prefixIcon: AppIcons.lock,
              controller: _password,
              obscureText: true,
              canRevealObscured: true,
              textInputAction: TextInputAction.done,
              dense: AuthFormLayout.denseFields,
              onSubmitted: (_) => _signIn(),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'At least 6 characters' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Checkbox(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                  visualDensity: VisualDensity.compact,
                ),
                Text('Keep me signed in',
                    style: TextStyle(color: AppPalette.textMuted(context))),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .pushNamed(RouteNames.forgotPassword),
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
            const SizedBox(height: AuthFormLayout.sectionGap),
            AppButton(
              label: 'Sign in',
              loadingLabel: 'Signing in…',
              size: AuthFormLayout.buttonSize,
              loading: _loading,
              expand: true,
              onPressed: _loading ? null : _signIn,
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Don't have an account?",
            style: TextStyle(color: AppPalette.textMuted(context))),
        TextButton(
          onPressed: () => RegisterView.show(context),
          child: const Text('Create one'),
        ),
      ],
    );
  }
}
