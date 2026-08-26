import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../navigation/profile_navigation.dart';
import '../navigation/root_navigator.dart';
import '../dashboard/admin_workspace_catalog.dart';
import '../settings/widgets/settings_quick_actions.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_dialog.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'section_label.dart';
import 'user_identity_header.dart';

/// Account menu opened from the avatar.
///
/// Uses [showModalBottomSheet] (not [GlassSheet]/showGeneralDialog]) because
/// dialog pop→push is unreliable on Flutter web.
///
/// Navigation is **result-based**: a menu tap pops the sheet returning an
/// [AccountSheetAction], then [ProfileNavigation.applySheetAction] performs the
/// push AFTER the sheet route is fully removed. Pushing directly from inside a
/// still-open modal route is the classic cause of "sheet closes, destination
/// never opens" on Flutter web.
class ProfileMenuSheet {
  ProfileMenuSheet._();

  static Future<void> show(BuildContext context) async {
    final user = AuthState.instance.user;
    if (user == null) {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => const _SheetChrome(
          title: 'Account',
          subtitle: 'Sign in to continue',
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Text('No account session. Sign in to view your profile.'),
          ),
        ),
      );
      return;
    }

    final action = await showModalBottomSheet<AccountSheetAction>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetChrome(
        title: 'Account',
        subtitle: ProfileNavigation.subtitleFor(user.role),
        child: _Body(user: user),
      ),
    );

    if (action == null || !context.mounted) return;
    await ProfileNavigation.applySheetAction(context, action);
  }
}

/// Shared chrome matching the GlassSheet look (handle, title, close, panel).
class _SheetChrome extends StatelessWidget {
  const _SheetChrome({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxH),
        child: Material(
          color: AppPalette.surface(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: AppSpacing.md),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.borderStrong(context),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.sm,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.ink(context),
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppPalette.textMuted(context),
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        AppIcons.close,
                        color: AppPalette.ink(context),
                      ),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH - 120),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.user});

  final AppUser user;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AuthState.instance.addListener(_onAuth);
  }

  @override
  void dispose() {
    AuthState.instance.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  AppUser get user => AuthState.instance.user ?? widget.user;

  /// Close the sheet, returning [action] so the caller navigates AFTER the
  /// modal route is fully removed (reliable on Flutter web).
  void _select(AccountSheetAction action) {
    if (_busy) return;
    _busy = true;
    Navigator.of(context).pop(action);
  }

  void _openRoute(String route) {
    if (route.isEmpty) return;
    _select(AccountSheetAction.navigate(route));
  }

  void _openEdit() => _select(const AccountSheetAction.editProfile());

  @override
  Widget build(BuildContext context) {
    final items = ProfileNavigation.menuFor(user.role);
    final quick = ProfileNavigation.quickActionsFor(user.role);
    final profileRoute = ProfileNavigation.profileRouteFor(user.role);
    final openTickets =
        (user.role == UserRole.admin || user.role == UserRole.mcareAssistant)
        ? AdminWorkspaceCounts.openSupport
        : 0;
    final incomplete = !user.isProfileComplete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MenuRow(
          onTap: () => _openRoute(profileRoute),
          child: Row(
            children: [
              Expanded(child: UserIdentityHeader(user: user)),
              Icon(
                AppIcons.chevronRight,
                color: AppPalette.textFaint(context),
                size: 18,
              ),
            ],
          ),
        ),
        if (incomplete) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(AppIcons.alert, size: 16, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Complete your profile — name and phone are required.',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: incomplete ? 'Complete profile' : 'Edit profile',
          icon: AppIcons.edit,
          variant: AppButtonVariant.secondary,
          expand: true,
          onPressed: _openEdit,
        ),
        if (quick.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const SectionLabel(title: 'Quick actions', icon: AppIcons.home),
          const SizedBox(height: AppSpacing.sm),
          SettingsQuickActionsBar(
            actions: quick
                .map(
                  (a) => SettingsQuickActionDef(
                    icon: a.icon,
                    label: a.label,
                    badge:
                        a.route ==
                                ProfileNavigation.supportRouteFor(user.role) &&
                            openTickets > 0
                        ? '$openTickets'
                        : null,
                    onTap: () => _openRoute(a.route),
                  ),
                )
                .toList(),
          ),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          for (final item in items)
            _MenuRow(
              onTap: () => _openRoute(item.route),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 20,
                    color: item.danger
                        ? AppColors.critical
                        : AppPalette.ink(context),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: item.danger
                                    ? AppColors.critical
                                    : AppPalette.ink(context),
                              ),
                        ),
                        if (item.subtitle != null &&
                            item.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppPalette.textMuted(context),
                                ),
                          ),
                        ],
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
        ],
        const SizedBox(height: AppSpacing.md),
        const _SignOutButton(),
      ],
    );
  }
}

/// Full-width tappable row — [InkWell] only (no competing scrim).
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: AppPalette.border(context)),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.critical,
            side: BorderSide(color: AppColors.critical.withValues(alpha: 0.35)),
            backgroundColor: AppColors.critical.withValues(alpha: 0.04),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
          icon: const Icon(AppIcons.logout, size: 18),
          label: const Text(
            'Sign out',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          onPressed: () async {
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
          },
        ),
      ],
    );
  }
}
