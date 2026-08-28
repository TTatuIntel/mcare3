import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth/google_sign_in_service.dart';
import '../../core/env/app_env.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_sheet.dart';

/// Google account used by the mock picker or bridged from real OAuth.
class MockGoogleAccount {
  const MockGoogleAccount({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.isReturningPatient,
    this.idToken,
    this.photoUrl,
  });

  final String firstName;
  final String lastName;
  final String email;
  final bool isReturningPatient;
  final String? idToken;
  final String? photoUrl;

  String get displayName => '$firstName $lastName';

  factory MockGoogleAccount.fromCredentials(GoogleSignInCredentials c) {
    return MockGoogleAccount(
      firstName: c.firstName,
      lastName: c.lastName,
      email: c.email,
      isReturningPatient: false,
      idToken: c.idToken,
      photoUrl: c.photoUrl,
    );
  }
}

/// Account chooser — real Google OAuth on web; demo shortcuts when offline.
class GoogleAccountPickerSheet {
  GoogleAccountPickerSheet._();

  static const _returning = MockGoogleAccount(
    firstName: 'Amara',
    lastName: 'Okonkwo',
    email: 'amara.o@gmail.com',
    isReturningPatient: true,
  );

  static const _newPatient = MockGoogleAccount(
    firstName: 'James',
    lastName: 'Mwangi',
    email: 'james.mwangi@gmail.com',
    isReturningPatient: false,
  );

  static Future<MockGoogleAccount?> show(BuildContext context) {
    return GlassSheet.show<MockGoogleAccount>(
      context,
      title: 'Sign in with Google',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose an account to continue to mCare',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (kIsWeb && AppEnv.hasGoogleClientId) ...[
            _RealGoogleTile(onTap: () => _pickRealGoogleAccount(context)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Demo shortcuts (offline preview)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textFaint(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          _AccountTile(account: _returning),
          Divider(height: 1, color: AppPalette.border(context)),
          _AccountTile(account: _newPatient),
          Divider(height: 1, color: AppPalette.border(context)),
          _UseAnotherAccountTile(
            onTap: () {
              if (kIsWeb && AppEnv.hasGoogleClientId) {
                _pickRealGoogleAccount(context);
              } else {
                Navigator.of(context).pop(
                  MockGoogleAccount(
                    firstName: 'New',
                    lastName: 'Patient',
                    email:
                        'patient.${DateTime.now().millisecondsSinceEpoch}@gmail.com',
                    isReturningPatient: false,
                  ),
                );
              }
            },
          ),
          if (!kIsWeb || !AppEnv.hasGoogleClientId) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Demo mode: pick Amara for a full profile, or another account for onboarding.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textFaint(context),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _pickRealGoogleAccount(
    BuildContext context, {
    bool createAccount = false,
  }) async {
    try {
      if (AppEnv.backendEnabled) {
        final creds = await GoogleSignInService.instance.requestCredentials();
        if (!context.mounted) return;
        if (creds == null) return;
        Navigator.of(context).pop(MockGoogleAccount.fromCredentials(creds));
        return;
      }
      // Only reached with the backend disabled: there is no server to record
      // a device against and nothing to remember past the demo session.
      await GoogleSignInService.instance.beginRedirectSignIn(
        createAccount: createAccount,
        remember: false,
        deviceName: 'mCare demo',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'Google sign-in failed. Please try again.',
          ),
        ),
      );
    }
  }
}

class _RealGoogleTile extends StatelessWidget {
  const _RealGoogleTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.surfaceMuted(context),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: AppPalette.surface(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppPalette.border(context)),
                ),
                child: const Icon(
                  AppIcons.google,
                  color: AppColors.brandIndigo,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue with Google',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Sign in or create an account with your Gmail',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                color: AppPalette.textFaint(context),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UseAnotherAccountTile extends StatelessWidget {
  const _UseAnotherAccountTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final realGoogle = kIsWeb && AppEnv.hasGoogleClientId;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Icon(
          realGoogle ? AppIcons.logout : AppIcons.add,
          size: 20,
          color: AppColors.brandIndigo,
        ),
      ),
      title: Text(
        realGoogle ? 'Use another account' : 'Use another account',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        realGoogle
            ? 'Pick a different Gmail or Google Workspace account'
            : 'New patient — onboarding required',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: onTap,
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});
  final MockGoogleAccount account;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: AppColors.brandIndigo.withOpacity(0.12),
        child: Text(
          account.firstName.isNotEmpty ? account.firstName[0] : '?',
          style: const TextStyle(
            color: AppColors.brandIndigo,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        account.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(account.email),
      trailing: account.isReturningPatient
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppPalette.successSoft(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                'Demo profile',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                ),
              ),
            )
          : null,
      onTap: () => Navigator.of(context).pop(account),
    );
  }
}
