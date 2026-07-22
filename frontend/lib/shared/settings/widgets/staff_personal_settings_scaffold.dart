import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../navigation/role_nav_destination.dart';
import '../../state/settings_state.dart';
import '../../widgets/role_shell.dart';
import '../settings_definitions.dart';
import 'personal_settings_body.dart';
import 'privacy_settings_section.dart';
import 'settings_quick_actions.dart';

/// Shared personal settings shell for clinical staff (doctor, assistant).
class StaffPersonalSettingsScaffold extends StatefulWidget {
  const StaffPersonalSettingsScaffold({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
    required this.notificationRole,
    required this.accent,
    required this.heroTitle,
    this.subtitle,
    this.showPrivacy = true,
    this.leadingQuickActions = const [],
    this.trailingSections = const [],
  });

  final String currentRoute;
  final List<RoleNavDestination> destinations;
  final String profileRoute;
  final String notificationsRoute;
  final SettingsNotificationRole notificationRole;
  final Color accent;
  final String heroTitle;
  final String? subtitle;
  final bool showPrivacy;
  final List<SettingsQuickActionDef> leadingQuickActions;

  /// Extra sections appended after privacy (e.g. admin platform administration).
  final List<Widget> trailingSections;

  @override
  State<StaffPersonalSettingsScaffold> createState() =>
      _StaffPersonalSettingsScaffoldState();
}

class _StaffPersonalSettingsScaffoldState
    extends State<StaffPersonalSettingsScaffold> {
  final _appearanceKey = GlobalKey();
  final _notificationsKey = GlobalKey();
  final _privacyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations,
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: l10n.settings,
      subtitle: widget.subtitle ?? l10n.settingsSubtitle,
      body: AnimatedBuilder(
        animation: SettingsState.instance,
        builder: (context, _) {
          return PersonalSettingsBody(
            notificationRole: widget.notificationRole,
            accent: widget.accent,
            heroTitle: widget.heroTitle,
            profileRoute: widget.profileRoute,
            appearanceKey: _appearanceKey,
            notificationsKey: _notificationsKey,
            privacyKey: widget.showPrivacy ? _privacyKey : null,
            privacySection:
                widget.showPrivacy ? const PrivacySettingsSection() : null,
            leadingQuickActions: widget.leadingQuickActions,
            trailingSections: widget.trailingSections,
          );
        },
      ),
    );
  }
}
