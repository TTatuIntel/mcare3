import 'package:flutter/material.dart';

import '../core/api/auth_api.dart';
import '../core/api/api_client.dart';
import '../core/env/app_env.dart';
import '../shared/auth/auth_state.dart';
import '../shared/constants/route_names.dart';
import '../shared/models/app_user.dart';
import '../shared/services/auth_service.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_text_field.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/bubble_background.dart';
import '../shared/widgets/glass_card.dart';
import '../shared/widgets/pre_login_top_bar.dart';

/// Invite-acceptance flow. Clinicians/assistants/admins land here from
/// an admin-generated email link, set their password, then continue to
/// login. Mock-only today — backend exchange goes via AuthService.
class AcceptInviteView extends StatefulWidget {
  const AcceptInviteView({super.key, this.token});
  final String? token;

  @override
  State<AcceptInviteView> createState() => _AcceptInviteViewState();
}

class _AcceptInviteViewState extends State<AcceptInviteView> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_password.text.length < 8) {
      AppToast.warn(context, 'Password must be at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      AppToast.warn(context, 'Passwords do not match.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (AppEnv.backendEnabled && widget.token != null) {
        final data = await AuthApi.instance.acceptInvite(
          token: widget.token!,
          password: _password.text,
        );
        if (!mounted) return;
        if (data != null) {
          final token = data['token'] as String?;
          if (token != null) ApiClient.instance.setToken(token);
          final userMap = data['user'] as Map<String, dynamic>?;
          if (userMap != null) {
            AuthState.instance.signIn(AppUser.fromJson(userMap));
            AuthService.instance.completeNavigation(
              context,
              AuthFlowResult.signedIn(
                AppUser.fromJson(userMap),
                seededProfile: data['has_health_profile'] == true,
              ),
            );
            return;
          }
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 600));
      }
      if (!mounted) return;
      AppToast.success(context, 'Invite accepted — please sign in.');
      Navigator.of(context).pushNamedAndRemoveUntil(
        RouteNames.login,
        (_) => false,
      );
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Could not accept invite. Link may have expired.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = AppPalette.scaffoldBg(context);
    return Scaffold(
      backgroundColor: surface,
      body: BubbleBackground(
        surfaceColor: surface,
        child: SafeArea(
          child: Column(
            children: [
              const PreLoginTopBar(),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: GlassCard(
                        frosted: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(AppIcons.approval,
                                color: Theme.of(context).colorScheme.primary,
                                size: 32),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Accept your invite',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              widget.token == null
                                  ? 'No token detected. Make sure you used the link from your invitation email.'
                                  : 'Set a password to activate your account.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppPalette.textMuted(context)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppTextField(
                              controller: _password,
                              label: 'New password',
                              hint: 'At least 8 characters',
                              obscureText: true,
                              canRevealObscured: true,
                              prefixIcon: AppIcons.lock,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            AppTextField(
                              controller: _confirm,
                              label: 'Confirm password',
                              obscureText: true,
                              canRevealObscured: true,
                              prefixIcon: AppIcons.lock,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppButton(
                              label: 'Accept invite',
                              icon: AppIcons.check,
                              loading: _busy,
                              onPressed: _busy ? null : _accept,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
