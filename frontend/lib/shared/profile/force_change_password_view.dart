import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/env/app_env.dart';
import '../../core/push/push_notification_service.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../services/auth_storage.dart';
import '../state/settings_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/bubble_background.dart';
import '../widgets/glass_card.dart';

/// Full-screen gate after admin issues a temporary password.
class ForceChangePasswordView extends StatefulWidget {
  const ForceChangePasswordView({super.key, required this.role});

  final UserRole role;

  @override
  State<ForceChangePasswordView> createState() =>
      _ForceChangePasswordViewState();
}

class _ForceChangePasswordViewState extends State<ForceChangePasswordView> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _clearMustChangeFlag(AppUser updated) async {
    AuthState.instance.updateUser(updated);
    final stored = await AuthStorage.read();
    if (stored == null) return;
    final userMap = Map<String, dynamic>.from(stored.user);
    userMap['must_change_password'] = false;
    await AuthStorage.save(
      token: stored.token,
      user: userMap,
      hasHealthProfile: stored.hasHealthProfile,
      // Changing a password is not a place to quietly change how long the
      // session lasts — keep whatever the user chose when they signed in.
      remember: stored.remember,
      expiresAt: stored.expiresAt,
    );
  }

  Future<void> _save() async {
    if (_current.text.isEmpty) {
      AppToast.warn(context, 'Enter the temporary password you were given.');
      return;
    }
    if (_next.text.length < 8) {
      AppToast.warn(context, 'New password must be at least 8 characters.');
      return;
    }
    if (_next.text != _confirm.text) {
      AppToast.warn(context, 'New passwords do not match.');
      return;
    }

    setState(() => _saving = true);
    try {
      final current = AuthState.instance.user;
      if (current == null) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(RouteNames.login, (_) => false);
        return;
      }

      if (AppEnv.backendEnabled) {
        final res = await ApiClient.instance.post(
          '/auth/change-password',
          body: {'current_password': _current.text, 'new_password': _next.text},
        );
        final data = res['data'] as Map<String, dynamic>?;
        final userMap = data?['user'] as Map<String, dynamic>?;
        final updated = userMap != null
            ? AppUser.fromJson(userMap)
            : current.copyWith(mustChangePassword: false);
        await _clearMustChangeFlag(updated);
        await PushNotificationService.instance.setEnabled(
          SettingsState.instance.notifications.pushEnabled,
        );
      } else {
        await _clearMustChangeFlag(current.copyWith(mustChangePassword: false));
      }

      if (!mounted) return;
      AppToast.success(context, 'Password updated — welcome back.');
      final user = AuthState.instance.user ?? current;
      final route = AuthService.instance.routeForAuthUser(user, true);
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(
        context,
        'Could not update password. Check the temporary password and try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: BubbleBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: GlassCard(
                  frosted: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(AppIcons.lock, size: 36, color: widget.role.accent),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Set a new password',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'An admin issued a temporary password for your account. Choose a new one before continuing.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        label: 'Temporary / current password',
                        controller: _current,
                        obscureText: true,
                        prefixIcon: AppIcons.lock,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'New password',
                        controller: _next,
                        obscureText: true,
                        prefixIcon: AppIcons.lock,
                        hint: 'At least 8 characters',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'Confirm new password',
                        controller: _confirm,
                        obscureText: true,
                        prefixIcon: AppIcons.lock,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        label: 'Save and continue',
                        icon: AppIcons.check,
                        expand: true,
                        loading: _saving,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
