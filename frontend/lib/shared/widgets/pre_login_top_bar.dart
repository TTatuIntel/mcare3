import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'brand_logo.dart';

/// Canonical pre-login chrome — logo top-left, Sign in top-right.
///
/// Same placement on every auth and landing screen per the mCare design system.
/// Import from `lib/shared/widgets/` only; do not duplicate in feature modules.
class PreLoginTopBar extends StatelessWidget {
  const PreLoginTopBar({
    super.key,
    this.showSignIn = true,
    this.padding,
  });

  /// Hide on screens where sign-in is the primary action (e.g. login).
  final bool showSignIn;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(height: 53),
          const Spacer(),
          if (showSignIn) const _SignInAction(),
        ],
      ),
    );
  }
}

class _SignInAction extends StatelessWidget {
  const _SignInAction();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) {
        if (AuthState.instance.isAuthenticated) {
          return const SizedBox.shrink();
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).pushNamed(RouteNames.login),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                'Sign in',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.brandIndigo,
                      fontWeight: FontWeight.w600,
                      fontSize: 21,
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}
