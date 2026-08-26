import 'package:flutter/material.dart';

import '../shared/auth/auth_state.dart';
import '../shared/constants/route_names.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/glass_card.dart';

class PendingApprovalView extends StatelessWidget {
  const PendingApprovalView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffoldBg(context),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: GlassCard(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    height: 76,
                    width: 76,
                    decoration: BoxDecoration(
                      color: AppPalette.warningSoft(context),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusPill,
                      ),
                    ),
                    child: const Icon(
                      AppIcons.time,
                      size: 34,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Awaiting approval',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Thanks for registering. Our admin team is reviewing your '
                    'credentials. You\'ll get an email and SMS the moment '
                    'your account is approved.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.textMuted(context),
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppPalette.surfaceAlt(context),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Column(
                      children: const [
                        _Step(label: 'Account created', done: true),
                        SizedBox(height: AppSpacing.md),
                        _Step(label: 'Email verified', done: true),
                        SizedBox(height: AppSpacing.md),
                        _Step(label: 'Admin review', done: false),
                        SizedBox(height: AppSpacing.md),
                        _Step(label: 'Access granted', done: false),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Sign out',
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: () {
                      AuthState.instance.signOut();
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil(RouteNames.login, (_) => false);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done});
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 22,
          width: 22,
          decoration: BoxDecoration(
            color: done ? AppColors.success : AppPalette.surfaceMuted(context),
            shape: BoxShape.circle,
            border: Border.all(
              color: done
                  ? AppColors.success
                  : AppPalette.borderStrong(context),
            ),
          ),
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : null,
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: done
                ? AppPalette.ink(context)
                : AppPalette.textMuted(context),
          ),
        ),
      ],
    );
  }
}
