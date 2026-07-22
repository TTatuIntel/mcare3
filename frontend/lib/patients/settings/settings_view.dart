import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/settings/settings_definitions.dart';
import '../../shared/settings/widgets/patient_privacy_settings_section.dart';
import '../../shared/settings/widgets/personal_settings_body.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/state/settings_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../care_team/external_access_sheet.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _appearanceKey = GlobalKey();
  final _notificationsKey = GlobalKey();
  final _privacyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientSettings,
      detachedNav: true,
      title: context.l10n.settings,
      subtitle: context.l10n.settingsSubtitle,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          SettingsState.instance,
          ProfileState.instance,
        ]),
        builder: (context, _) {
          final tier = ResponsiveBuilder.of(context);

          return PersonalSettingsBody(
            notificationRole: SettingsNotificationRole.patient,
            accent: AppColors.info,
            heroTitle: 'Personalise your experience',
            profileRoute: RouteNames.patientProfile,
            appearanceKey: _appearanceKey,
            notificationsKey: _notificationsKey,
            privacyKey: _privacyKey,
            privacySection: PatientPrivacySettingsSection(
              onManageExternalAccess: () => ExternalAccessSheet.show(context),
            ),
            useStaggered: true,
            bottomSpacing: tier.isHandheld ? 24 : 48,
            themeQuickLabel: context.l10n.theme,
            alertsQuickLabel: context.l10n.alerts,
            privacyQuickLabel: context.l10n.privacy,
            profileQuickLabel: context.l10n.profile,
          );
        },
      ),
    );
  }
}
