import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_definitions.dart';
import '../../state/settings_state.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/patient_page_blocks.dart';
import '../../widgets/section_label.dart';
import 'appearance_settings_section.dart';
import 'notification_settings_section.dart';
import 'settings_hero.dart';
import 'settings_quick_actions.dart';

int personalSettingsEnabledCount(
  SettingsNotificationRole role,
  SettingsState s,
) =>
    switch (role) {
      SettingsNotificationRole.patient => s.patientEnabledNotificationCount,
      SettingsNotificationRole.doctor ||
      SettingsNotificationRole.assistant =>
        s.doctorEnabledNotificationCount,
      SettingsNotificationRole.admin => s.adminEnabledNotificationCount,
    };

/// Shared settings column — appearance, notifications, optional privacy.
/// Used by staff shells and patient settings.
class PersonalSettingsBody extends StatelessWidget {
  const PersonalSettingsBody({
    super.key,
    required this.notificationRole,
    required this.accent,
    required this.heroTitle,
    required this.profileRoute,
    required this.appearanceKey,
    required this.notificationsKey,
    this.privacyKey,
    this.privacySection,
    this.showPrivacyQuickAction = true,
    this.useStaggered = false,
    this.bottomSpacing = AppSpacing.huge,
    this.appearanceTitle,
    this.notificationsTitle,
    this.privacyTitle,
    this.themeQuickLabel = 'Theme',
    this.alertsQuickLabel = 'Alerts',
    this.privacyQuickLabel = 'Privacy',
    this.profileQuickLabel = 'Profile',
    this.leadingQuickActions = const [],
    this.trailingSections = const [],
  });

  final SettingsNotificationRole notificationRole;
  final Color accent;
  final String heroTitle;
  final String profileRoute;
  final GlobalKey appearanceKey;
  final GlobalKey notificationsKey;
  final GlobalKey? privacyKey;
  final Widget? privacySection;
  final bool showPrivacyQuickAction;
  final bool useStaggered;
  final double bottomSpacing;
  final String? appearanceTitle;
  final String? notificationsTitle;
  final String? privacyTitle;
  final String themeQuickLabel;
  final String alertsQuickLabel;
  final String privacyQuickLabel;
  final String profileQuickLabel;
  /// Ops shortcuts shown before Theme / Alerts (e.g. Ticket inbox).
  final List<SettingsQuickActionDef> leadingQuickActions;

  /// Extra sections appended after privacy (e.g. admin platform administration).
  /// Rendered verbatim, so callers include their own section labels/spacing.
  final List<Widget> trailingSections;

  Widget _wrap(int index, Widget child) {
    if (!useStaggered) return child;
    return StaggeredEntry(index: index, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = SettingsState.instance;
    final enabledCount = personalSettingsEnabledCount(notificationRole, s);
    final hasPrivacy = privacySection != null && privacyKey != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _wrap(0, const PatientDateHeader()),
        const SizedBox(height: AppSpacing.sm),
        _wrap(
          1,
          SettingsHero(
            title: heroTitle,
            accent: accent,
            themeLabel: l10n.themeLabel(s.themeMode),
            language: s.language,
            notificationsOn: enabledCount,
            onThemeTap: () => patientScrollToKey(appearanceKey),
            onLanguageTap: () => patientScrollToKey(appearanceKey),
            onAlertsTap: () => patientScrollToKey(notificationsKey),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _wrap(
          2,
          SettingsQuickActionsBar(
            actions: [
              ...leadingQuickActions,
              SettingsQuickActionDef(
                icon: AppIcons.settings,
                label: themeQuickLabel,
                onTap: () => patientScrollToKey(appearanceKey),
              ),
              SettingsQuickActionDef(
                icon: AppIcons.bell,
                label: alertsQuickLabel,
                badge: enabledCount > 0 ? '$enabledCount' : null,
                onTap: () => patientScrollToKey(notificationsKey),
              ),
              if (showPrivacyQuickAction && hasPrivacy)
                SettingsQuickActionDef(
                  icon: AppIcons.visibility,
                  label: privacyQuickLabel,
                  onTap: () => patientScrollToKey(privacyKey!),
                ),
              SettingsQuickActionDef(
                icon: AppIcons.profile,
                label: profileQuickLabel,
                onTap: () => Navigator.of(context).pushNamed(profileRoute),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _wrap(
          3,
          SectionLabel(
            title: appearanceTitle ?? l10n.appearance,
            icon: AppIcons.settings,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _wrap(
          4,
          AppearanceSettingsSection(sectionKey: appearanceKey),
        ),
        const SizedBox(height: AppSpacing.md),
        _wrap(
          5,
          SectionLabel(
            title: notificationsTitle ?? l10n.alerts,
            icon: AppIcons.bell,
            trailing: '$enabledCount on',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _wrap(
          6,
          NotificationSettingsSection(
            sectionKey: notificationsKey,
            role: notificationRole,
          ),
        ),
        if (hasPrivacy) ...[
          const SizedBox(height: AppSpacing.md),
          _wrap(
            7,
            KeyedSubtree(
              key: privacyKey,
              child: SectionLabel(
                title: privacyTitle ?? l10n.privacy,
                icon: AppIcons.visibility,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _wrap(8, privacySection!),
        ],
        ...trailingSections,
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}
