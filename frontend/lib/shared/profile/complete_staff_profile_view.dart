import 'package:flutter/material.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/profile_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/bubble_background.dart';
import '../../shared/widgets/glass_card.dart';

/// One-time staff profile setup — name and phone required before workspace access.
class CompleteStaffProfileView extends StatefulWidget {
  const CompleteStaffProfileView({super.key, required this.role});

  final UserRole role;

  @override
  State<CompleteStaffProfileView> createState() =>
      _CompleteStaffProfileViewState();
}

class _CompleteStaffProfileViewState extends State<CompleteStaffProfileView> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = AuthState.instance.user;
    _firstName = TextEditingController(text: user?.firstName ?? '');
    _lastName = TextEditingController(text: user?.lastName ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  String get _roleLabel => widget.role.label;

  Future<void> _save() async {
    final user = AuthState.instance.user;
    if (user == null) return;

    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      AppToast.warn(context, 'First and last name are required.');
      return;
    }
    if (_phone.text.trim().length < 7) {
      AppToast.warn(context, 'Enter a valid mobile phone number.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ProfileService.updateAccount(
        editor: user,
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
      );
      if (!mounted) return;
      final next = AuthState.instance.user ?? user;
      AppToast.success(context, 'Profile complete — welcome to mCare.');
      final route = AuthService.instance.routeForAuthUser(next, true);
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not save profile — please retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user;
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
                      Row(
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.role.accent,
                                  widget.role.accent.withOpacity(0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusPill,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              user?.initials ?? '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Complete your profile',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '$_roleLabel account · ${user?.email ?? ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppPalette.textMuted(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Add your contact details so your team can reach you for alerts, approvals and support.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppPalette.textMuted(context),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        label: 'First name',
                        controller: _firstName,
                        prefixIcon: AppIcons.user,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'Last name',
                        controller: _lastName,
                        prefixIcon: AppIcons.user,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'Mobile phone',
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        prefixIcon: AppIcons.phone,
                        hint: '+254 7XX XXX XXX',
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: 'Save and continue',
                        icon: AppIcons.check,
                        expand: true,
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: () {
                          AuthState.instance.signOut();
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            RouteNames.login,
                            (_) => false,
                          );
                        },
                        child: const Text('Sign out'),
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
