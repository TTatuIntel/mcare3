import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../navigation/root_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_icons.dart';
import '../widgets/glass_card.dart';
import '../widgets/patient_page_blocks.dart';
import '../widgets/section_label.dart';
import 'change_email_sheet.dart';
import 'change_password_sheet.dart';

/// Uniform "Account information" section — the read-only view of everything the
/// user provided at sign-up, with a single Edit entry point. Shared by every
/// role so patient / doctor / admin / assistant profiles look identical.
class ProfileAccountSection extends StatelessWidget {
  const ProfileAccountSection({
    super.key,
    required this.user,
    this.onEdit,
  });

  final AppUser user;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final phone = user.phone?.trim() ?? '';
    final specialty = user.specialty?.trim() ?? '';
    final licence = user.licenseNumber?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Account information',
          icon: AppIcons.user,
          actionLabel: onEdit == null ? null : 'Edit',
          onAction: onEdit,
        ),
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            children: [
              PatientCompactInfoRow(label: 'Full name', value: user.fullName),
              PatientCompactInfoRow(
                label: 'Email',
                value: user.emailVerified
                    ? user.email
                    : '${user.email}  (unverified)',
              ),
              PatientCompactInfoRow(
                label: 'Phone',
                value: phone.isEmpty ? 'Not set' : phone,
              ),
              PatientCompactInfoRow(label: 'Role', value: user.role.label),
              PatientCompactInfoRow(label: 'mCare ID', value: user.uniqueId),
              if (user.role == UserRole.doctor) ...[
                PatientCompactInfoRow(
                  label: 'Specialty',
                  value: specialty.isEmpty ? 'Not set' : specialty,
                ),
                PatientCompactInfoRow(
                  label: 'Licence no.',
                  value: licence.isEmpty ? 'Not set' : licence,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Uniform "Security" section — change password, change email and sign out.
/// Used on every role's profile so account safety controls live in one place.
class ProfileSecuritySection extends StatelessWidget {
  const ProfileSecuritySection({super.key, this.showSignOut = true});

  final bool showSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'Security', icon: AppIcons.lock),
        GlassCard(
          frosted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton(
                label: 'Change password',
                variant: AppButtonVariant.secondary,
                icon: AppIcons.lock,
                onPressed: () => ChangePasswordSheet.show(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Change email',
                variant: AppButtonVariant.secondary,
                icon: AppIcons.email,
                onPressed: () => ChangeEmailSheet.show(context),
              ),
              if (showSignOut) ...[
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: AppPalette.border(context)),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Sign out',
                  variant: AppButtonVariant.danger,
                  icon: AppIcons.logout,
                  onPressed: () => _signOut(context),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _signOut(BuildContext context) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Sign out?',
      message:
          'You\'ll be returned to the home screen and will need to sign in again.',
      danger: true,
      icon: AppIcons.logout,
      iconActionOnly: true,
    );
    if (ok != true) return;
    AuthState.instance.signOut();
    rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(
      RouteNames.landing,
      (_) => false,
    );
  }
}
