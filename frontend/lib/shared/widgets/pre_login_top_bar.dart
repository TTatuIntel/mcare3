import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../auth/session_recovery.dart';
import '../constants/route_names.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'brand_logo.dart';

/// Canonical pre-login chrome — logo top-left, Sign in top-right.
///
/// Same placement on every auth and landing screen per the mCare design system.
/// Import from `lib/shared/widgets/` only; do not duplicate in feature modules.
class PreLoginTopBar extends StatelessWidget {
  const PreLoginTopBar({super.key, this.showSignIn = true, this.padding});

  /// Hide on screens where sign-in is the primary action (e.g. login).
  final bool showSignIn;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
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
          // The wordmark takes most of a 390px phone, leaving the action
          // barely its own width. Flexible + the scale-down inside
          // [_SignInAction] mean a longer label shrinks instead of
          // overflowing the bar.
          if (showSignIn) const Flexible(child: _SignInAction()),
        ],
      ),
    );
  }
}

/// The bar's right-hand action. Never renders as empty space.
///
/// It used to collapse to nothing for a signed-in user, on the assumption
/// that a signed-in user is never on a pre-login screen. When that assumption
/// broke — a session restored late, a route that no longer exists — the
/// result was a landing page with a bare header and no way off it. Signed in,
/// the action now points at the session's own home instead.
class _SignInAction extends StatelessWidget {
  const _SignInAction();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) {
        final signedIn = AuthState.instance.isAuthenticated;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: signedIn
                ? SessionRecovery.goHome
                : () => Navigator.of(context).pushNamed(RouteNames.login),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  signedIn ? 'Home' : 'Sign in',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.brandIndigo,
                    fontWeight: FontWeight.w600,
                    fontSize: 21,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
