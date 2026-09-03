import 'package:flutter/material.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/app_user.dart';
import '../../shared/navigation/patient_nav_badges.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_hub.dart';

/// Patient-facing landing page for their record, personal details and app
/// preferences.
///
/// Two changes from the first version worth stating, because both were about
/// what the tab is *for*:
///
/// Notifications no longer has a tile. The bell sits in the header of every
/// patient screen with the same unread count on it, so a tile here was a
/// second door to a room the patient is already standing outside — it took the
/// slot of something with no other way in.
///
/// What went in its place is the record itself. Everything the platform holds
/// about a patient was readable by their clinic and nowhere by them; the
/// clinical profile is that same dossier, and it is the first thing on the
/// page because it is the thing this tab was missing.
class PatientMoreHubView extends StatelessWidget {
  const PatientMoreHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        PatientNavBadges.listenable,
        AuthState.instance,
      ]),
      builder: (context, _) => PatientScaffold(
        currentRoute: RouteNames.patientMore,
        title: 'More',
        subtitle: 'Your record, profile and preferences',
        maxContentWidth: 1080,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (AuthState.instance.user case final user?) ...[
              _AccountSummaryCard(user: user),
              const SizedBox(height: AppSpacing.xl),
            ],
            SectionHub(
              title: 'Account and preferences',
              description:
                  'Read the record your care team keeps, maintain your health '
                  'profile and personalise mCare.',
              groups: [
                AppSectionGroup(
                  title: 'Your record',
                  description:
                      'Everything the platform holds about your health, and '
                      'every report drawn from it.',
                  links: [
                    const AppSectionLink(
                      title: 'Clinical profile',
                      description:
                          'The full record your doctors and clinic read — '
                          'health profile, vitals, medicines, care team and '
                          'account history.',
                      icon: AppIcons.vitals,
                      route: RouteNames.patientClinicalProfile,
                      color: AppColors.brandIndigo,
                    ),
                    AppSectionLink(
                      title: 'Reports about you',
                      description:
                          'See every report drawn from your record, who it '
                          'went to, and read it yourself.',
                      icon: AppIcons.report,
                      route: RouteNames.patientReportConsents,
                      color: AppColors.warning,
                      badge: PatientNavBadges.sharingRequests,
                    ),
                    const AppSectionLink(
                      title: 'Documents',
                      description:
                          'Lab results, prescriptions, imaging and letters — '
                          'yours and your care team\'s.',
                      icon: AppIcons.document,
                      route: RouteNames.patientDocuments,
                      color: AppColors.bpPurple,
                    ),
                  ],
                ),
                const AppSectionGroup(
                  title: 'Your account',
                  description:
                      'Personal information, application options and help.',
                  links: [
                    AppSectionLink(
                      title: 'Profile',
                      description:
                          'Update personal details, monitoring and emergency '
                          'contacts.',
                      icon: AppIcons.profile,
                      route: RouteNames.patientProfile,
                      color: AppColors.doctorGreen,
                    ),
                    AppSectionLink(
                      title: 'Settings',
                      description:
                          'Manage appearance, language, notifications and '
                          'privacy.',
                      icon: AppIcons.settings,
                      route: RouteNames.patientSettings,
                      color: AppColors.weightSlate,
                    ),
                    AppSectionLink(
                      title: 'Help and support',
                      description:
                          'Raise a support request and follow previous '
                          'tickets.',
                      icon: AppIcons.support,
                      route: RouteNames.patientSupport,
                      color: AppColors.info,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Who is signed in, at a glance, opening onto the full record.
///
/// The tab used to start with a heading and nothing else, which meant the one
/// question a patient opens "More" to answer — *is this my account, and is it
/// in good standing?* — took two taps. It is answered here, and the card is
/// the shortest route into the record rather than a decoration.
class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = user.role.accent;
    final hasPhoto = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return GlassCard(
      onTap: () =>
          Navigator.of(context).pushNamed(RouteNames.patientClinicalProfile),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
              image: hasPhoto
                  ? DecorationImage(
                      image: NetworkImage(user.avatarUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasPhoto
                ? null
                : Text(
                    user.initials,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  user.uniqueId.isEmpty
                      ? 'Patient'
                      : 'Patient · ${user.uniqueId}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Open your clinical profile',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            AppIcons.chevronRight,
            size: 20,
            color: AppPalette.textMuted(context),
          ),
        ],
      ),
    );
  }
}
