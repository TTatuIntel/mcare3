import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../auth/sign_out_action.dart';
import '../constants/route_names.dart';
import '../models/app_user.dart';
import '../models/patient_profile.dart';
import '../models/profile_completion.dart';
import '../models/sos.dart';
import '../models/user_role.dart';
import '../navigation/profile_navigation.dart';
import '../dashboard/admin_workspace_catalog.dart';
import '../state/profile_state.dart';
import '../state/sos_state.dart';
import '../state/vitals_state.dart';
import '../settings/widgets/settings_quick_actions.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
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

  /// Every store the sheet renders from — auth identity plus the health,
  /// emergency and vitals data shown in [_AccountSnapshot] — so a background
  /// sync while the sheet is open refreshes it in place.
  late final Listenable _sources = Listenable.merge([
    AuthState.instance,
    ProfileState.instance,
    SosState.instance,
    VitalsState.instance,
  ]);

  @override
  void initState() {
    super.initState();
    _sources.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _sources.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
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
        const SizedBox(height: AppSpacing.lg),
        _AccountSnapshot(user: user, onOpenRoute: _openRoute),
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
          onPressed: () => confirmAndSignOut(context),
        ),
      ],
    );
  }
}

/// Everything the account sheet knows about the signed-in user, in one place.
///
/// The sheet is the account *information* surface: it answers "what does the
/// system have on me, and am I ready?" without navigating anywhere. Actions
/// stay in the menu rows below — and never duplicate a destination the primary
/// navigation already owns (see `ProfileNavigation.menuFor`).
///
/// Every value is read from an existing store — [AuthState], [ProfileState],
/// [SosState], [VitalsState] — and renders "—" / "Not added" when the store has
/// nothing, so the block is safe for any role and any load state.
class _AccountSnapshot extends StatelessWidget {
  const _AccountSnapshot({required this.user, required this.onOpenRoute});

  final AppUser user;
  final void Function(String route) onOpenRoute;

  static String _statusLabel(ApprovalStatus status) => switch (status) {
    ApprovalStatus.active => 'Active',
    ApprovalStatus.pendingApproval => 'Pending approval',
    ApprovalStatus.suspended => 'Suspended',
    ApprovalStatus.rejected => 'Rejected',
  };

  static Color _statusColor(ApprovalStatus status) => switch (status) {
    ApprovalStatus.active => AppColors.success,
    ApprovalStatus.pendingApproval => AppColors.warning,
    ApprovalStatus.suspended || ApprovalStatus.rejected => AppColors.critical,
  };

  @override
  Widget build(BuildContext context) {
    final isPatient = user.role == UserRole.patient;
    final health = isPatient ? ProfileState.instance.health : null;
    final contacts = isPatient
        ? SosState.instance.contacts
        : const <EmergencyContact>[];
    final trackedVitals = VitalsState.instance.tracked.toList();
    final completion = ProfileCompletion.forUser(
      user: user,
      health: health,
      contacts: contacts,
      assignedVitals: isPatient ? trackedVitals : const [],
    );
    final missing = completion.incompleteItems
        .map((i) => i.label)
        .take(3)
        .toList();
    final sharesLocation = health?.locationConsent ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Account details', icon: AppIcons.user),
        _SnapshotCard(
          children: [
            _CompletionMeter(percent: completion.percent, missing: missing),
            _DetailRow(label: 'Full name', value: user.fullName),
            _DetailRow(
              label: 'Email',
              value: user.email.isEmpty ? '—' : user.email,
              badge: user.emailVerified ? null : 'Unverified',
              badgeColor: AppColors.warning,
            ),
            _DetailRow(
              label: 'Phone',
              value: (user.phone ?? '').trim().isEmpty
                  ? 'Not added'
                  : user.phone!.trim(),
              muted: (user.phone ?? '').trim().isEmpty,
            ),
            _DetailRow(
              label: isPatient ? 'Patient ID' : 'Staff ID',
              value: user.uniqueId.isEmpty ? '—' : user.uniqueId,
            ),
            _DetailRow(label: 'Role', value: user.role.label),
            _DetailRow(
              label: 'Account status',
              value: _statusLabel(user.approvalStatus),
              valueColor: _statusColor(user.approvalStatus),
            ),
            if ((user.specialty ?? '').trim().isNotEmpty)
              _DetailRow(label: 'Specialty', value: user.specialty!.trim()),
            if ((user.licenseNumber ?? '').trim().isNotEmpty)
              _DetailRow(label: 'License', value: user.licenseNumber!.trim()),
          ],
        ),
        if (isPatient) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel(title: 'Health and safety', icon: AppIcons.vitals),
          _SnapshotCard(
            children: [
              if (health == null)
                const _DetailRow(
                  label: 'Health profile',
                  value: 'Not completed yet',
                  muted: true,
                )
              else ...[
                _DetailRow(label: 'Age', value: '${health.ageYears} yrs'),
                _DetailRow(label: 'Gender', value: health.gender.label),
                _DetailRow(label: 'Blood type', value: health.bloodType.label),
                _DetailRow(
                  label: 'BMI',
                  value:
                      '${health.bmi.toStringAsFixed(1)} · ${health.bmiCategory}',
                ),
                _DetailRow(
                  label: 'Allergies',
                  value: health.allergies.isNotEmpty
                      ? health.allergies.join(', ')
                      : (health.noKnownAllergies
                            ? 'None known'
                            : 'Not recorded'),
                  muted: health.allergies.isEmpty && !health.noKnownAllergies,
                ),
                _DetailRow(
                  label: 'Conditions',
                  value: health.chronicConditions.isNotEmpty
                      ? health.chronicConditions.join(', ')
                      : 'None recorded',
                  muted: health.chronicConditions.isEmpty,
                ),
              ],
              _DetailRow(
                label: 'Tracked vitals',
                value: '${trackedVitals.length}',
              ),
              _DetailRow(
                label: 'Emergency contacts',
                value: contacts.isEmpty ? 'None added' : '${contacts.length}',
                muted: contacts.isEmpty,
              ),
              _DetailRow(
                label: 'Location on SOS',
                value: sharesLocation ? 'Shared with care team' : 'Not shared',
                valueColor: sharesLocation ? AppColors.success : null,
                muted: !sharesLocation,
              ),
              // Readiness links to the same page the home page's emergency
              // block opens — information here, the action itself stays there.
              _SnapshotLink(
                label: contacts.isEmpty
                    ? 'Add emergency contacts'
                    : 'Review emergency setup',
                onTap: () => onOpenRoute(RouteNames.patientSos),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Bordered container used by the snapshot sections.
class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Label to value line. Long values wrap instead of clipping.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.badge,
    this.badgeColor,
    this.valueColor,
    this.muted = false,
  });

  final String label;
  final String value;
  final String? badge;
  final Color? badgeColor;
  final Color? valueColor;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    valueColor ??
                    (muted
                        ? AppPalette.textFaint(context)
                        : AppPalette.ink(context)),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (badgeColor ?? AppColors.warning).withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: badgeColor ?? AppColors.warning,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Profile completeness bar shown at the top of the details card.
class _CompletionMeter extends StatelessWidget {
  const _CompletionMeter({required this.percent, required this.missing});

  final int percent;
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = percent >= 100;
    final accent = complete ? AppColors.success : AppColors.brandIndigo;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Profile completeness',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppPalette.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          if (!complete && missing.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Still missing: ${missing.join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textFaint(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline text action inside a snapshot card.
class _SnapshotLink extends StatelessWidget {
  const _SnapshotLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.brandIndigo,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(AppIcons.chevronRight, size: 16, color: AppColors.brandIndigo),
          ],
        ),
      ),
    );
  }
}
